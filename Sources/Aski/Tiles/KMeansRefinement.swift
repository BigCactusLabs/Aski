import simd

package enum KMeansRefinement {

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

        return refine(
            palette: palette,
            samples: TilePalette.makeColorSamples(pixels: pixels, width: width, height: height, colorSpace: colorSpace)
        )
    }

    /// Shared-sample entry point. The samples are not mutated or retained;
    /// cluster order, strict-distance ties, and accumulation order are unchanged.
    package static func refine(palette: [SIMD3<Float>], samples: [TilePalette.ColorSample]) -> [SIMD3<Float>] {
        guard !palette.isEmpty else { return [] }
        var centers = palette

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

}
