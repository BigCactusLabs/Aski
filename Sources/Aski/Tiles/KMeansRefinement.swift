import simd

internal enum KMeansRefinement {

    static let maxIterations = 5
    static let convergenceThreshold: Float = 0.001

    /// Refine `palette` (initial cluster centers in OKLAB) against the same
    /// premultiplied RGBA `pixels` Wu used. Returns up to `palette.count`
    /// converged centroids. Empty clusters are dropped at the end of each
    /// iteration.
    static func refine(
        palette: [SIMD3<Float>],
        pixels: [UInt8],
        width: Int,
        height: Int,
        colorSpace: RenderColorSpace
    ) -> [SIMD3<Float>] {
        guard !palette.isEmpty else { return [] }

        var centers = palette
        let samples = makeSamples(
            pixels: pixels,
            width: width,
            height: height,
            colorSpace: colorSpace
        )

        for _ in 0..<maxIterations {
            var sums = [SIMD3<Float>](repeating: .zero, count: centers.count)
            var weights = [Float](repeating: 0, count: centers.count)

            for sample in samples {
                var nearestIndex = 0
                var nearestDistance = Float.infinity
                for (index, center) in centers.enumerated() {
                    let distance = simd_length_squared(center - sample.oklab)
                    if distance < nearestDistance {
                        nearestDistance = distance
                        nearestIndex = index
                    }
                }

                sums[nearestIndex] += sample.alpha * sample.oklab
                weights[nearestIndex] += sample.alpha
            }

            var newCenters: [SIMD3<Float>] = []
            newCenters.reserveCapacity(centers.count)
            for (index, weight) in weights.enumerated() where weight > 0 {
                newCenters.append(sums[index] / weight)
            }
            if newCenters.isEmpty { return [] }

            if newCenters.count == centers.count {
                var maxMove: Float = 0
                for (oldCenter, newCenter) in zip(centers, newCenters) {
                    maxMove = max(maxMove, simd_length(oldCenter - newCenter))
                }
                centers = newCenters
                if maxMove < Self.convergenceThreshold { break }
            } else {
                centers = newCenters
            }
        }

        return centers
    }

    private static func makeSamples(
        pixels: [UInt8],
        width: Int,
        height: Int,
        colorSpace: RenderColorSpace
    ) -> [Sample] {
        var samples: [Sample] = []
        samples.reserveCapacity(width * height)
        for i in 0..<(width * height) {
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
            samples.append(Sample(oklab: oklab, alpha: alpha))
        }
        return samples
    }

    private struct Sample {
        let oklab: SIMD3<Float>
        let alpha: Float
    }
}
