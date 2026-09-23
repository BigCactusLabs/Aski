import CoreGraphics

/// Conversion-time raster mask options. The mask image is stretched to the
/// output grid's exact cell extent; callers that need aspect-fit or aspect-fill
/// placement should pre-render that placement into `image`.
public struct MaskOptions: Sendable {
    /// Raster mask image. White pixels are inside the mask; black pixels are
    /// outside. The image is stretched to the output grid's exact
    /// `columns x rows` cell extent during conversion.
    public let image: CGImage
    /// Content rendered behind cells where coverage is below 1.
    public let fallback: MaskFallback
    /// Raster color rendered behind active glyphs or tiles. A nil, zero-alpha,
    /// or non-finite-alpha value has no raster effect.
    public let groundColor: CGColor?
    /// When true, grayscale luminance is preserved as continuous coverage.
    /// When false, luminance is thresholded at 0.5 before optional inversion.
    public let softEdges: Bool
    /// Flips coverage after hard-edge thresholding.
    public let invert: Bool

    public init(
        image: CGImage,
        fallback: MaskFallback = .transparent,
        groundColor: CGColor? = nil,
        softEdges: Bool = true,
        invert: Bool = false
    ) {
        self.image = image
        self.fallback = fallback
        self.groundColor = groundColor
        self.softEdges = softEdges
        self.invert = invert
    }
}
