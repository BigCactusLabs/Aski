import simd

internal extension TilePalette {
    /// Resolve this palette strategy to a concrete OKLAB palette.
    /// - For `.adaptive`: runs Wu's algorithm + k-means refinement on the
    ///   premultiplied RGBA source pixels.
    /// - For `.fixedOKLAB`: returns the precomputed colors verbatim.
    func resolved(
        pixels: [UInt8],
        pixelWidth: Int,
        pixelHeight: Int,
        colorSpace: RenderColorSpace
    ) -> ResolvedPalette {
        let oklabColors: [SIMD3<Float>]
        switch strategy {
        case .adaptive(let maxColors):
            let wu = WuQuantizer(
                pixels: pixels,
                width: pixelWidth,
                height: pixelHeight,
                colorSpace: colorSpace
            ).palette(maxColors: maxColors)
            oklabColors = KMeansRefinement.refine(
                palette: wu,
                pixels: pixels,
                width: pixelWidth,
                height: pixelHeight,
                colorSpace: colorSpace
            )
            if oklabColors.isEmpty {
                return .passThrough
            }
        case .fixedOKLAB(let colors):
            oklabColors = colors
        }
        return ResolvedPalette(oklabColors: oklabColors)
    }
}
