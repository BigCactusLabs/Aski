import simd

extension TilePalette {
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
            let samples = Self.makeColorSamples(
                pixels: pixels,
                width: pixelWidth,
                height: pixelHeight,
                colorSpace: colorSpace
            )
            guard !samples.isEmpty else { return .passThrough }
            let wu = WuQuantizer(samples: samples).palette(maxColors: maxColors)
            oklabColors = KMeansRefinement.refine(palette: wu, samples: samples)
            if oklabColors.isEmpty {
                return .passThrough
            }
        case .fixedOKLAB(let colors):
            oklabColors = colors
        }
        return ResolvedPalette(oklabColors: oklabColors)
    }

    /// Four payload floats in one vector instead of SIMD3 plus a separately
    /// aligned alpha field. The accessors copy lanes; no color math changes.
    /// Package-visible only for stage benchmarks; no public API or global cache.
    package struct ColorSample: Sendable {
        private let packed: SIMD4<Float>

        init(oklab: SIMD3<Float>, alpha: Float) {
            packed = SIMD4(oklab.x, oklab.y, oklab.z, alpha)
        }

        var oklab: SIMD3<Float> { SIMD3(packed.x, packed.y, packed.z) }
        var alpha: Float { packed.w }
    }

    /// Prepare once for both quantizers. Preserve row-major order, skip alpha
    /// zero, unpremultiply before decoding, and retain alpha as a weight.
    /// Capacity is bounded by the source pixel count and owned by this call.
    package static func makeColorSamples(
        pixels: [UInt8],
        width: Int,
        height: Int,
        colorSpace: RenderColorSpace
    ) -> [ColorSample] {
        let pixelCount = width * height
        var firstVisible = 0
        while firstVisible < pixelCount && pixels[firstVisible * 4 + 3] == 0 {
            firstVisible += 1
        }
        // Avoid reserving an image-sized buffer when no color signal exists.
        guard firstVisible < pixelCount else { return [] }
        var samples: [ColorSample] = []
        samples.reserveCapacity(pixelCount - firstVisible)
        for i in firstVisible..<pixelCount {
            let offset = i * 4
            let alpha = Float(pixels[offset + 3]) / 255
            if alpha == 0 { continue }

            let red = min(Float(pixels[offset + 0]) / 255 / alpha, 1)
            let green = min(Float(pixels[offset + 1]) / 255 / alpha, 1)
            let blue = min(Float(pixels[offset + 2]) / 255 / alpha, 1)
            let linear = SIMD3<Float>(
                ColorConversion.sRGBDecode(red),
                ColorConversion.sRGBDecode(green),
                ColorConversion.sRGBDecode(blue)
            )
            let oklab: SIMD3<Float>
            switch colorSpace {
            case .sRGB: oklab = ColorConversion.linearSRGBToOKLAB(linear)
            case .displayP3: oklab = ColorConversion.linearP3ToOKLAB(linear)
            }
            samples.append(ColorSample(oklab: oklab, alpha: alpha))
        }
        return samples
    }
}
