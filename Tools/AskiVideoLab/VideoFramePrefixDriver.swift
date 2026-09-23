import Aski
import CoreMedia
import Foundation

/// Re-exposes a capped prefix of a decode stream as an `AsyncThrowingStream` so it
/// can feed a resampler operator (which takes `AsyncThrowingStream`). Mirrors
/// `CappedRenderDriver` minus the render: pulls at most `limit` frames via the
/// copy/advance/write-back `next(isolation:)` pattern (Swift-6 sending-safe).
actor VideoFramePrefixDriver {
    private var iterator: AsyncThrowingStream<ASCIIVideoFrame, Error>.AsyncIterator
    private var remaining: Int

    init(stream: AsyncThrowingStream<ASCIIVideoFrame, Error>, limit: Int) {
        self.iterator = stream.makeAsyncIterator()
        self.remaining = limit
    }

    func next() async throws -> ASCIIVideoFrame? {
        guard remaining > 0 else { return nil }
        var localIterator = iterator
        let frame = try await localIterator.next(isolation: #isolation)
        iterator = localIterator
        guard let frame else { return nil }
        remaining -= 1
        return frame
    }
}

/// Wraps `VideoFramePrefixDriver` as a stream for the resampler operators.
func prefixedVideoStream(
    _ source: AsyncThrowingStream<ASCIIVideoFrame, Error>,
    limit: Int
) -> AsyncThrowingStream<ASCIIVideoFrame, Error> {
    let driver = VideoFramePrefixDriver(stream: source, limit: limit)
    return AsyncThrowingStream(unfolding: { try await driver.next() })
}

/// Lab-level run errors surfaced through `VideoLabCLI`'s `do/catch`.
enum VideoLabRunError: Error, CustomStringConvertible {
    case cappedResampleNeedsFrameRate
    case uncappedGIFFrameCountExceedsLimit(count: Int, limit: Int)

    var description: String {
        switch self {
        case .cappedResampleNeedsFrameRate:
            "cannot bound the capped source span for --max-frames + --target-fps on this "
                + "source: its nominal frame rate is unavailable. Re-run without --max-frames, "
                + "or without --target-fps."
        case .uncappedGIFFrameCountExceedsLimit(let count, let limit):
            "GIF input has \(count) frames, exceeding the uncapped lab limit \(limit). "
                + "Re-run with --max-frames to process an explicit prefix."
        }
    }
}

/// The exact source span (seconds) for a `--max-frames N` capped MP4 prefix:
/// `min(trackDuration, N / nominalFrameRate)` — exact for CFR, a documented
/// approximation for capped VFR. THROWS when the nominal frame rate is unavailable
/// (`<= 0`) rather than falling back to the FULL track duration: that fallback would
/// make the resampler duplicate the last capped frame across the rest of the asset
/// (addendum §"Both operators take the source duration of the exact span fed in").
/// The exact capped-VFR path (reading the (N+1)th PTS) stays deferred (YAGNI).
func cappedVideoSourceSpan(
    trackDuration: TimeInterval,
    nominalFrameRate: Float,
    limit: Int
) throws -> TimeInterval {
    guard nominalFrameRate > 0 else { throw VideoLabRunError.cappedResampleNeedsFrameRate }
    return min(trackDuration, Double(limit) / Double(nominalFrameRate))
}
