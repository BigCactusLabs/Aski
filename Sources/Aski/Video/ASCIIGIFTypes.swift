import CoreGraphics
import Foundation

/// A converted GIF frame: an `ASCIIGrid` plus its per-frame delay.
///
/// Mirrors `ASCIIVideoFrame`: `CGImage`-free and fully `Sendable`. `delay` is the
/// UNCLAMPED GIF delay in seconds — reading the clamped value silently floors
/// fast GIFs to 0.1s (C2b addendum §Evidence).
public struct ASCIIGIFFrame: Sendable {
    public let grid: ASCIIGrid
    public let delay: TimeInterval
    /// `delay` is stored verbatim — intentionally permissive (ASKI-35). This is
    /// a carrier for the raw decoded value; the rule for a non-finite or
    /// non-positive delay is stated once downstream, at
    /// `ASCIIGIFEncoder.normalizedDelay` (write time): it becomes 0.1s, while a
    /// valid sub-floor delay passes through raw. Re-checking here would make
    /// the same input fail in two ways. The resampler's derived output slot is
    /// separately bounded in `ResampleSession.slot(of:)`.
    public init(grid: ASCIIGrid, delay: TimeInterval) {
        self.grid = grid
        self.delay = delay
    }
}

/// A rendered GIF frame ready to encode: a `CGImage` plus its per-frame delay.
/// `CGImage` is `@unchecked Sendable` per Apple (thread-safe for reads), as in C2a.
public struct RenderedGIFFrame: Sendable {
    public let image: CGImage
    public let delay: TimeInterval
    /// `delay` is stored verbatim, same contract as `ASCIIGIFFrame.init`
    /// (ASKI-35): the single stated rule for an out-of-domain delay is
    /// `ASCIIGIFEncoder.normalizedDelay`, which this type feeds directly.
    public init(image: CGImage, delay: TimeInterval) {
        self.image = image
        self.delay = delay
    }
}

/// Container-level GIF metadata.
///
/// `loopCount` carries NON-obvious semantics (verified on the target SDK,
/// addendum §Verification): `1` = play once (absent Netscape extension),
/// `0` = infinite, `N` = a finite number of plays.
public struct GIFContainerInfo: Sendable {
    /// Count-only container metadata. Does not include per-frame delays.
    public struct Header: Sendable {
        public let frameCount: Int
        public let loopCount: Int
        public let canvasSize: CGSize

        public init(frameCount: Int, loopCount: Int, canvasSize: CGSize) {
            self.frameCount = frameCount
            self.loopCount = loopCount
            self.canvasSize = canvasSize
        }
    }

    public let frameCount: Int
    public let loopCount: Int
    public let canvasSize: CGSize
    /// Per-frame UNCLAMPED delays in seconds (one per frame, in order).
    public let frameDelays: [TimeInterval]
    /// Sum of `frameDelays` — the exact source span for fps resampling.
    public var totalDuration: TimeInterval { frameDelays.reduce(0, +) }

    public init(frameCount: Int, loopCount: Int, canvasSize: CGSize, frameDelays: [TimeInterval]) {
        self.frameCount = frameCount
        self.loopCount = loopCount
        self.canvasSize = canvasSize
        self.frameDelays = frameDelays
    }
}

/// Pure-data report returned by `ASCIIGIFEncoder.write`. The library NEVER prints;
/// callers decide what to surface (e.g. the sub-floor browser-portability note).
public struct GIFEncodeReport: Sendable {
    public let framesWritten: Int
    public let loopCount: Int
    /// Frames whose written delay is < 0.02s (the reliable browser floor).
    public let subFloorDelayCount: Int
    /// Defined only for non-empty input (empty throws `.noFrames` first).
    public let minDelay: TimeInterval
    /// fps-resampling report; `nil` when the GIF was not resampled. Defaulted so
    /// `ASCIIGIFEncoder.write` (which knows nothing of resampling) is unchanged.
    public let resample: ResampleReport?

    public init(
        framesWritten: Int,
        loopCount: Int,
        subFloorDelayCount: Int,
        minDelay: TimeInterval,
        resample: ResampleReport? = nil
    ) {
        self.framesWritten = framesWritten
        self.loopCount = loopCount
        self.subFloorDelayCount = subFloorDelayCount
        self.minDelay = minDelay
        self.resample = resample
    }
}

/// Errors thrown by `ASCIIGIFEncoder.write`.
public enum GIFEncodeError: Error, CustomStringConvertible {
    /// Empty frame array — `CGImageDestinationFinalize` returns false for 0 images.
    case noFrames
    case cannotCreateDestination(String)
    case cannotFinalize(String)

    public var description: String {
        switch self {
        case .noFrames:
            "cannot encode a GIF with zero frames"
        case .cannotCreateDestination(let path):
            "could not create GIF destination '\(path)'"
        case .cannotFinalize(let path):
            "could not finalize GIF '\(path)'"
        }
    }
}

/// Errors thrown by `ASCIIGIFDecoder`.
public enum GIFDecodeError: Error, CustomStringConvertible {
    case cannotOpenSource(String)
    case noFrames
    case frameDecodeFailed(Int)
    case frameCountExceedsLimit(count: Int, limit: Int)

    public var description: String {
        switch self {
        case .cannotOpenSource(let path):
            "could not open GIF source '\(path)'"
        case .noFrames:
            "GIF source contains no frames"
        case .frameDecodeFailed(let index):
            "could not decode GIF frame at index \(index)"
        case .frameCountExceedsLimit(let count, let limit):
            "GIF source contains \(count) frames, exceeding the maximum frame count \(limit)"
        }
    }
}
