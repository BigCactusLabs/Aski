import CoreMedia
import Foundation

/// The centisecond-quantized per-frame delay for a GIF target rate. `>= 1 cs`
/// (GIF cannot store 0). e.g. 60 -> 2 cs, 30 -> 3 cs, 24 -> 4 cs, 15 -> 7 cs.
/// `public` so callers (the lab, the app) can predict the quantization.
///
/// The divisor is clamped to `>= 1`: this is a non-throwing predictor an external
/// caller may hand an unchecked user-entered rate, and `targetFPS == 0` would make
/// `100.0 / 0` non-finite, trapping the `Int(_:)` conversion. A non-positive rate
/// is treated as 1 fps (100 cs) — the slowest sane delay — so the helper never
/// crashes; the conversion paths still reject invalid rates up front via
/// `resamplePreflight`. Valid rates (`1...maxTargetFPS`) are unaffected.
public func gifDelayCentiseconds(targetFPS: Int) -> Int {
    max(1, Int((100.0 / Double(max(1, targetFPS))).rounded(.toNearestOrAwayFromZero)))
}

/// The effective rate a GIF actually plays after centisecond quantization.
/// e.g. requested 60 -> achieved 50.0 (2 cs); requested 24 -> 25.0 (4 cs).
/// `public` so the lab can fill `ResampleReport.achievedFPS` without re-deriving it.
public func gifAchievedFPS(targetFPS: Int) -> Double {
    100.0 / Double(gifDelayCentiseconds(targetFPS: targetFPS))
}

/// Video resampling operator — exact `CMTime` CFR retiming. Drop/duplicate by
/// nearest slot; output frame `k` gets `CMTime(value: k, timescale: targetFPS)`.
/// `sourceDuration` is the span of the EXACT frames fed in (uncapped = the track
/// time range; capped = the first-N span). Throws synchronously on an invalid rate
/// or a projected count over `maxResampledFrames`. The caller reads `stats` after
/// the stream ends.
public func resampledVideoFrames(
    _ source: AsyncThrowingStream<ASCIIVideoFrame, Error>,
    targetFPS: Int,
    sourceDuration: TimeInterval,
    into stats: ResampleStats
) throws -> AsyncThrowingStream<ASCIIVideoFrame, Error> {
    let endSlot = try resamplePreflight(targetFPS: targetFPS, sourceDuration: sourceDuration)
    let session = ResampleSession<ASCIIVideoFrame>(
        source: source,
        timing: .absolute { CMTimeGetSeconds($0.time) },
        retime: { frame, k in
            ASCIIVideoFrame(grid: frame.grid, time: CMTime(value: Int64(k), timescale: Int32(targetFPS)))
        },
        targetFPS: targetFPS,
        endSlot: endSlot,
        stats: stats
    )
    return AsyncThrowingStream(unfolding: { try await session.next() })
}

/// GIF resampling operator — quantized uniform-delay retiming. Drop/duplicate by
/// nearest slot; every output frame gets the centisecond-quantized uniform delay.
/// `sourceDuration` is the sum of the delays of the EXACT frames fed in.
public func resampledGIFFrames(
    _ source: AsyncThrowingStream<ASCIIGIFFrame, Error>,
    targetFPS: Int,
    sourceDuration: TimeInterval,
    into stats: ResampleStats
) throws -> AsyncThrowingStream<ASCIIGIFFrame, Error> {
    let endSlot = try resamplePreflight(targetFPS: targetFPS, sourceDuration: sourceDuration)
    let uniformDelay = Double(gifDelayCentiseconds(targetFPS: targetFPS)) / 100.0
    let session = ResampleSession<ASCIIGIFFrame>(
        source: source,
        timing: .interval { $0.delay },
        retime: { frame, _ in ASCIIGIFFrame(grid: frame.grid, delay: uniformDelay) },
        targetFPS: targetFPS,
        endSlot: endSlot,
        stats: stats
    )
    return AsyncThrowingStream(unfolding: { try await session.next() })
}
