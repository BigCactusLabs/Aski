import Foundation

/// Pure-data resampling report. `achievedFPS == Double(requestedFPS)` for MP4
/// (CMTime is exact); for GIF it is the centisecond-quantized effective rate
/// `100 / round(100 / requestedFPS)` (e.g. requested 60 -> achieved 50).
public struct ResampleReport: Sendable {
    public let requestedFPS: Int
    public let achievedFPS: Double
    /// Frames pulled from the decoder (after any `--max-frames` cap).
    public let sourceFrameCount: Int
    /// Frames emitted to the encoder.
    public let outputFrameCount: Int
    /// Source frames dropped (not emitted) on a collision.
    public let droppedCount: Int
    /// Extra emissions beyond one-per-distinct-source-frame (duplicates on a gap).
    public let duplicatedCount: Int

    /// Pure-data carrier: every field is stored verbatim and validated nowhere
    /// (ASKI-35 classification — correctly permissive). `achievedFPS` is only
    /// ever formatted for display; nothing derives geometry, an allocation or
    /// an integer conversion from it, and the rate that DOES drive the pipeline
    /// (`targetFPS`) is validated up front by `resamplePreflight`. A report is
    /// also a record of what happened, so a caller reconstructing one from a
    /// log must be able to store an odd measured value unchanged.
    public init(
        requestedFPS: Int,
        achievedFPS: Double,
        sourceFrameCount: Int,
        outputFrameCount: Int,
        droppedCount: Int,
        duplicatedCount: Int
    ) {
        self.requestedFPS = requestedFPS
        self.achievedFPS = achievedFPS
        self.sourceFrameCount = sourceFrameCount
        self.outputFrameCount = outputFrameCount
        self.droppedCount = droppedCount
        self.duplicatedCount = duplicatedCount
    }
}

/// Inclusive ceiling on `targetFPS`. 240 covers every realistic target.
public let maxTargetFPS = 240

/// Inclusive ceiling on the OUTPUT frame count. `maxTargetFPS` bounds the rate and
/// `--max-frames` bounds the SOURCE, but neither bounds duplication: a 2-frame GIF
/// with multi-second delays resampled up expands without limit. 36_000 ≈ 10 min at
/// 60 fps — generous for real clips, OOM-proof.
public let maxResampledFrames = 36_000

/// Thrown before any allocation: an out-of-range rate, a non-finite/negative source
/// duration, or a projected OUTPUT frame count that would exceed
/// `maxResampledFrames` (bound-before-allocate, ASTSK-15).
public enum ResampleError: Error, CustomStringConvertible {
    case invalidTargetFPS(Int)
    case invalidSourceDuration(TimeInterval)
    case resampledFrameCountExceeded(projected: Int, limit: Int)

    public var description: String {
        switch self {
        case .invalidTargetFPS(let fps):
            "target fps \(fps) is out of range (expected 1...\(maxTargetFPS))"
        case .invalidSourceDuration(let duration):
            "source duration \(duration) is not a finite, non-negative number of seconds"
        case .resampledFrameCountExceeded(let projected, let limit):
            "projected resampled frame count \(projected) exceeds the limit \(limit)"
        }
    }
}

/// Public, `Sendable` stats handle the caller passes in and reads AFTER consuming
/// the stream. An `actor` (not closure-captured counters) so it stays
/// Swift-6-diagnostic-clean and matches `CappedRenderDriver`. Reads are public; the
/// single mutator `commit` is **module-internal**, so only `ResampleSession` (same
/// module) can write — an external caller reads the tallies but never overwrites
/// them.
public actor ResampleStats {
    public private(set) var sourceFrameCount = 0
    public private(set) var outputFrameCount = 0
    public private(set) var droppedCount = 0
    public private(set) var duplicatedCount = 0

    public init() {}

    /// `internal` (no `public`): called once by `ResampleSession` at stream end. The
    /// session accumulates plain local counters and flushes here — one cross-actor
    /// hop, no per-frame overhead.
    func commit(source: Int, output: Int, dropped: Int, duplicated: Int) {
        sourceFrameCount = source
        outputFrameCount = output
        droppedCount = dropped
        duplicatedCount = duplicated
    }
}
