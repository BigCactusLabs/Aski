import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Batch-encodes rendered frames as an animated GIF via `CGImageDestination`,
/// with per-frame delays + an explicit loop count, returning a pure-data report.
/// The library NEVER prints — callers decide what to surface from the report.
///
/// Promoted + extended from `Tools/AskiMotionLab/GIFExporter.swift`. Asymmetric
/// with `ASCIIVideoEncoder`'s streaming `write` BY DESIGN: GIFs are short loops,
/// and `CGImageDestination` accumulates then finalizes, so batch is the right
/// shape (roadmap "batch first").
public struct ASCIIGIFEncoder: Sendable {
    public init() {}

    /// `loopCount` is REQUIRED (no default) so callers consciously choose
    /// preserve-source vs infinite (0) vs once (1).
    ///
    /// Input contract:
    /// - empty `frames` -> throws `.noFrames` (ImageIO can't finalize 0 images).
    /// - delay that is non-finite (NaN/inf) or <= 0 -> normalized to 0.1s; 0 is
    ///   never written (a written 0/neg/NaN round-trips as UnclampedDelayTime 0).
    /// - valid sub-floor delays (0 < d < 0.02s) are written RAW and counted into
    ///   `subFloorDelayCount`.
    @discardableResult
    public func write(_ frames: [RenderedGIFFrame], loopCount: Int, to url: URL) throws -> GIFEncodeReport {
        guard !frames.isEmpty else { throw GIFEncodeError.noFrames }
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.gif.identifier as CFString,
                frames.count,
                nil
            )
        else {
            throw GIFEncodeError.cannotCreateDestination(url.path)
        }

        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loopCount]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        var subFloorDelayCount = 0
        var minDelay = Double.greatestFiniteMagnitude
        for frame in frames {
            let delay = Self.normalizedDelay(frame.delay)
            if delay < 0.02 { subFloorDelayCount += 1 }
            minDelay = min(minDelay, delay)
            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
            ]
            CGImageDestinationAddImage(destination, frame.image, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw GIFEncodeError.cannotFinalize(url.path)
        }
        return GIFEncodeReport(
            framesWritten: frames.count,
            loopCount: loopCount,
            subFloorDelayCount: subFloorDelayCount,
            minDelay: minDelay
        )
    }

    /// Non-finite or non-positive delays normalize to the documented 0.1s default;
    /// valid sub-floor delays (0 < d < 0.02s) pass through RAW (intent preserved).
    static func normalizedDelay(_ delay: TimeInterval) -> TimeInterval {
        guard delay.isFinite, delay > 0 else { return 0.1 }
        return delay
    }
}
