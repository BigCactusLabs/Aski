import Foundation

/// Validates the inputs and computes the output-slot bound. Returns `endSlot`
/// (also the projected output frame count). Throws before any allocation. Shared by
/// both operators and the test suite.
///
/// `endSlot` uses `ceil`, NOT `round`: the valid output slots are exactly
/// `{ k : k / t < sourceDuration }` = `{ k : k < sourceDuration * t }`, of which
/// there are `ceil(sourceDuration * t)`. `round` would truncate a clip whose
/// `sourceDuration * t` has a fractional part below 0.5 — e.g. a 0.2 s clip at
/// 12 fps (`2.4`) needs 3 output frames (slots 0, 1, 2), but `round(2.4) = 2` drops
/// the slot-2 content. Integer products (the spec's worked examples 6.0, 3.0) are
/// unaffected (`ceil == round` there). The PER-FRAME slot mapping stays `round=near`
/// (FFmpeg-faithful) — only this loop bound is `ceil`.
///
/// The `isFinite`/`>= 0` guard turns a NaN/∞ `sourceDuration` (e.g. an indefinite or
/// invalid `CMTime` whose `CMTimeGetSeconds` is NaN) into a thrown `ResampleError`.
/// The count bound is then checked **in `Double`** before any `Int(_:)` conversion:
/// a huge-but-finite duration (e.g. `1e300`) makes `sourceDuration * targetFPS`
/// exceed `Int.max`, and `Int(_:)` traps on that — the Double check throws
/// `resampledFrameCountExceeded` instead. Only a value already known to be within
/// `0...maxResampledFrames` is ever converted to `Int`.
func resamplePreflight(targetFPS: Int, sourceDuration: TimeInterval) throws -> Int {
    guard targetFPS >= 1, targetFPS <= maxTargetFPS else {
        throw ResampleError.invalidTargetFPS(targetFPS)
    }
    guard sourceDuration.isFinite, sourceDuration >= 0 else {
        throw ResampleError.invalidSourceDuration(sourceDuration)
    }
    let projectedDouble = (sourceDuration * Double(targetFPS)).rounded(.up)
    guard projectedDouble.isFinite, projectedDouble <= Double(maxResampledFrames) else {
        // Report a safe Int (never convert an out-of-Int-range Double).
        let reported =
            projectedDouble.isFinite && projectedDouble < Double(Int.max)
            ? Int(projectedDouble) : Int.max
        throw ResampleError.resampledFrameCountExceeded(projected: reported, limit: maxResampledFrames)
    }
    return max(1, Int(projectedDouble))
}

/// How a source frame's start time is derived. Video frames carry an absolute PTS;
/// GIF frames carry a per-frame interval (delay) the session accumulates. Both
/// closures are stateless and `@Sendable`; the actor owns the accumulation.
enum FrameTiming<F: Sendable>: Sendable {
    case absolute(@Sendable (F) -> Double)  // seconds; session normalizes by t0
    case interval(@Sendable (F) -> Double)  // per-frame delay; session sums to a start
}

/// Internal generic selection core. Confines the source iterator + counters to an
/// actor (the copy/advance/write-back `next(isolation:)` pattern of
/// `CappedRenderDriver`). Holds at most two source frames (current + one
/// lookahead). Runs FFmpeg-faithful `round=near` drop/duplicate selection and
/// `commit`s plain local tallies to the injected `ResampleStats` once at stream end.
actor ResampleSession<F: Sendable> {
    private var iterator: AsyncThrowingStream<F, Error>.AsyncIterator
    private let timing: FrameTiming<F>
    private let retime: @Sendable (F, Int) -> F
    private let targetFPS: Double
    private let endSlot: Int
    private let stats: ResampleStats

    // Selection state.
    private var currentSlot = 0
    private var held: F?
    private var heldEmitted = false
    private var lookahead: F?
    private var lookaheadStart = 0.0
    private var sourceExhausted = false
    private var firstAbsolute: Double?  // t0 for .absolute normalization
    private var nextIntervalStart = 0.0  // running sum for .interval mode

    // Local tallies, flushed once at the end.
    private var sourceCount = 0
    private var outputCount = 0
    private var droppedCount = 0
    private var duplicatedCount = 0
    private var committed = false

    init(
        source: AsyncThrowingStream<F, Error>,
        timing: FrameTiming<F>,
        retime: @escaping @Sendable (F, Int) -> F,
        targetFPS: Int,
        endSlot: Int,
        stats: ResampleStats
    ) {
        self.iterator = source.makeAsyncIterator()
        self.timing = timing
        self.retime = retime
        self.targetFPS = Double(targetFPS)
        self.endSlot = endSlot
        self.stats = stats
    }

    /// Pull-based: one output frame per call; `nil` ends the stream (and flushes
    /// stats exactly once). The unfolding closure captures only this actor.
    func next() async throws -> F? {
        if currentSlot >= endSlot {
            await commitOnce()
            return nil
        }
        try Task.checkCancellation()
        let k = currentSlot

        // Advance through every source frame whose slot <= k, keeping the last.
        while true {
            try await fillLookahead()
            guard let frame = lookahead, slot(of: lookaheadStart) <= k else { break }
            if held != nil, !heldEmitted { droppedCount += 1 }  // superseded before emission
            held = frame
            heldEmitted = false
            lookahead = nil
        }

        guard let frame = held else {
            // No source frame reached slot k (only if the first frame's slot > 0,
            // which normalization prevents). Treat as end.
            await commitOnce()
            return nil
        }

        if heldEmitted {
            duplicatedCount += 1
        } else {
            heldEmitted = true
        }
        let out = retime(frame, k)
        outputCount += 1
        currentSlot += 1
        // Backstop (preflight already bounds endSlot <= maxResampledFrames).
        if outputCount > maxResampledFrames {
            throw ResampleError.resampledFrameCountExceeded(projected: outputCount, limit: maxResampledFrames)
        }
        return out
    }

    /// Pulls one source frame into `lookahead` if empty, computing its start.
    /// Copy/advance/write-back keeps the non-Sendable iterator pinned to this actor
    /// across the suspension (plain `next()` trips `sending` under strict 6).
    private func fillLookahead() async throws {
        guard lookahead == nil, !sourceExhausted else { return }
        var localIterator = iterator
        let pulled = try await localIterator.next(isolation: #isolation)
        iterator = localIterator
        guard let frame = pulled else { sourceExhausted = true; return }
        sourceCount += 1
        switch timing {
        case .absolute(let project):
            let absolute = project(frame)
            if firstAbsolute == nil { firstAbsolute = absolute }
            lookaheadStart = absolute - (firstAbsolute ?? absolute)
        case .interval(let project):
            lookaheadStart = nextIntervalStart
            nextIntervalStart += project(frame)
        }
        lookahead = frame
    }

    /// The output slot a source frame starts in, with the derived conversion
    /// BOUNDED (ASKI-35, following the ASKI-17 derived-geometry rule).
    ///
    /// `start` comes from caller data the operators deliberately do not
    /// validate per frame: a GIF frame's raw `delay` (accumulated here) or a
    /// video frame's PTS. `preflight` bounds the declared `sourceDuration`, not
    /// the individual frames, so a non-finite or astronomically large value
    /// reached the unchecked `Int(_:)` and trapped. Clamping the derived slot
    /// into `-1...endSlot` keeps the existing selection semantics for every
    /// in-range start and degrades the rest: a start at or past `endSlot` is
    /// simply never selected (the schedule ends), and a start before zero is
    /// held and superseded exactly as a small negative start already was.
    private func slot(of start: Double) -> Int {
        let scaled = (start * targetFPS).rounded(.toNearestOrAwayFromZero)
        guard scaled.isFinite else { return scaled < 0 ? -1 : endSlot }
        return Int(Swift.max(-1, Swift.min(Double(endSlot), scaled)))
    }

    private func commitOnce() async {
        guard !committed else { return }
        committed = true
        await stats.commit(
            source: sourceCount, output: outputCount,
            dropped: droppedCount, duplicated: duplicatedCount
        )
    }
}
