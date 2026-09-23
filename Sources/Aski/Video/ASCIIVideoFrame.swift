import CoreGraphics
import CoreMedia

/// A converted video frame: an `ASCIIGrid` plus its source presentation time.
///
/// `CMTime` is `Sendable`; `ASCIIGrid` is `Sendable`. The decoder yields only
/// this type across isolation — the non-Sendable `CVPixelBuffer` it was built
/// from never escapes the decoder's serial executor.
public struct ASCIIVideoFrame: Sendable {
    public let grid: ASCIIGrid
    /// Source presentation timestamp — timing is preserved (no fps resampling).
    public let time: CMTime

    public init(grid: ASCIIGrid, time: CMTime) {
        self.grid = grid
        self.time = time
    }
}

public extension ASCIIVideoFrame {
    /// Returns the frame with `pattern` applied to its grid at the frame's own
    /// presentation time, keeping the timestamp. A `nil` pattern is the identity,
    /// so render paths can pass an optional pattern straight through. Feeding
    /// each frame its own PTS makes the overlay's global phase advance coherently
    /// across frames by construction (AC#2). See `ASCIIGrid.applyingOngoingPattern`.
    func applyingOngoingPattern(_ pattern: OngoingPattern?) -> ASCIIVideoFrame {
        guard let pattern else { return self }
        pattern.validate()
        return ASCIIVideoFrame(
            grid: grid.applyingOngoingPattern(pattern, at: time.seconds),
            time: time
        )
    }
}

/// A rendered frame ready to encode: a `CGImage` plus its presentation time.
///
/// `CGImage` is `Sendable` (CoreGraphics value type, thread-safe for reads).
/// `CMTime` is `Sendable`.
public struct RenderedVideoFrame: Sendable {
    public let image: CGImage
    public let time: CMTime

    public init(image: CGImage, time: CMTime) {
        self.image = image
        self.time = time
    }
}
