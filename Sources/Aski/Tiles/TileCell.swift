import simd

/// One cell of a `TileGrid`. Mirrors `ASCIICell` minus `character`. The
/// matching property names mean B-subsystem effects can read both grid
/// types polymorphically.
public struct TileCell: Sendable, Hashable {
    /// Display-ready color in the grid's `RenderColorSpace`, post-quantization
    /// and post-gamut-mapping. Channels are 0...1.
    public let displayColor: SIMD3<Float>

    /// Source alpha, preserved through the pipeline. 0...1. Renderers composite
    /// against `backgroundColor` (or `grout` in mosaic mode) at render time.
    public let alpha: Float

    /// Adjusted source OKLAB L: averaged source-pixel L after
    /// `RenderingOptions.brightness` and `.contrast`, pre-quantization.
    /// 0...1. Same semantics as `ASCIICell.brightness`.
    public let brightness: Float

    /// Per-cell mask coverage. White mask pixels produce `1`; black mask pixels
    /// produce `0`. Renderers multiply this into cell alpha except tile mosaic,
    /// where coverage gates the complete raster so grout fades with cells.
    public let coverage: Float

    public init(
        displayColor: SIMD3<Float>,
        alpha: Float,
        brightness: Float,
        coverage: Float = 1.0
    ) {
        self.displayColor = displayColor
        self.alpha = alpha
        self.brightness = brightness
        self.coverage = coverage
    }
}
