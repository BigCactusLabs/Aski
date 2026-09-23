import simd

public struct ASCIICell: Sendable, Hashable {
    /// The selected character for this cell.
    public let character: Character

    /// Display-ready color in the grid's `RenderColorSpace`, already palette-matched
    /// and gamut-mapped. Channels are 0...1 (r, g, b).
    public let displayColor: SIMD3<Float>

    /// Source alpha, preserved through the pipeline. 0...1.
    /// Renderers composite against the caller-supplied background at render time.
    public let alpha: Float

    /// Adjusted source OKLAB L — the cell's averaged source-pixel L after
    /// `RenderingOptions.brightness` and `.contrast` adjustments. This is the L
    /// used for brightness-based matching (logPolar top-K, dotMatrix nearest-
    /// brightness pick) and palette lookup. 0...1.
    ///
    /// - Note: Describes the *source* (post-adjustment), not the L embedded in
    ///   `displayColor`. With a non-trivial palette these diverge — e.g., with
    ///   `BuiltInPalette.monochrome`, every `displayColor` is white, but
    ///   `brightness` still tracks the source pixel luminance.
    ///
    /// - Note: At default `RenderingOptions` (brightness=0, contrast=0) this
    ///   equals the pre-A1 raw source L bit-identically.
    public let brightness: Float

    /// Per-cell mask coverage. White mask pixels produce `1`; black mask pixels
    /// produce `0`. Renderers multiply this into cell alpha.
    public let coverage: Float

    public init(
        character: Character,
        displayColor: SIMD3<Float>,
        alpha: Float,
        brightness: Float,
        coverage: Float = 1.0
    ) {
        self.character = character
        self.displayColor = displayColor
        self.alpha = alpha
        self.brightness = brightness
        self.coverage = coverage
    }
}
