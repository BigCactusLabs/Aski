import Foundation

// MARK: - Shared log-polar cell sampling (ASKI-26)

/// One log-polar sampling function, called by BOTH the query side and the
/// candidate side of the ASKI-26 ablation arms.
///
/// The shipped matcher does not do this. `ShapeContext.histogram60` inscribes a
/// single disc in the *shorter* axis of whatever raster it is handed, and the
/// two sides are handed differently-shaped rasters: the query side gets the raw
/// anisotropic cell (a 1:2 block admits ~39% of its pixels to the disc), the
/// candidate side gets a 64×64 square (~79%). The supports are mismatched, so
/// the two histograms are not comparable in the way the matcher assumes. Every
/// arm built on this type samples both sides with the same function, the same
/// configuration, and the same cell geometry, which is the property the source
/// paper (Xu, Zhang & Wong, *Structure-based ASCII Art*, ACM TOG 29(4),
/// SIGGRAPH 2010) states and the shipped path does not have.
///
/// Two supports are offered so the convention itself can be ablated:
///
/// - ``Support/singleDisc`` — one 5×12 log-polar window centred on the cell,
///   radius = half the shorter side. This is the *current* convention,
///   reproduced here on the anisotropic rect so the ablation has a like-for-like
///   baseline. Ink outside the inscribed disc is discarded, which is why a
///   baseline-hugging glyph such as `_` can land an all-zero descriptor.
/// - ``Support/tiled(stride:)`` — the paper's construction: a stride-2 grid of
///   log-polar windows over the true anisotropic cell, each window 5 radial ×
///   12 angular with radius = half the shorter cell side, concatenated. For a
///   `Tw × Th` cell that is `(Tw/stride) × (Th/stride)` windows, i.e. the
///   paper's `N = (Tw/2)(Th/2)`; a 12×24 cell gives 72 windows and a 4320-D
///   descriptor. Position is preserved by construction: the same ink at a
///   different place in the cell falls in a different window.
///
/// Normalization is **global L1 over the concatenated vector**, not per-window.
/// Per-window normalization would rescale every window to unit mass and throw
/// away exactly the information the tiling was added to keep — where the ink
/// is, and how much of it is there. Global L1 keeps the shipped convention's
/// scale invariance (`ShapeContext` L1-normalizes too) while leaving the
/// between-window mass ratios intact.
public enum LogPolarCellSampling {

    /// 5 radial log-bins × 12 angular bins, matching `ShapeContext.dimension`.
    public static let radialBins = 5
    public static let angularBins = 12
    public static let binsPerWindow = radialBins * angularBins

    /// The paper applies a 7×7 Gaussian pre-blur to both sides before sampling.
    /// Kernel radius is fixed at 3 (7 taps); sigma is the caller's choice.
    public static let blurKernelRadius = 3

    /// The sigma this unit records for its blurred arms. σ = 1.2 sits in the
    /// middle of the 1.0–1.5 band a 7-tap kernel supports: at σ = 1.0 the
    /// outer taps are already near zero (the kernel is effectively 5×5), and
    /// past σ ≈ 1.5 the kernel is truncated hard enough that its discrete mass
    /// no longer approximates the continuous Gaussian. Recorded as a named
    /// constant so an arm cannot silently be re-run at a different blur.
    public static let defaultBlurSigma: Float = 1.2

    public struct Configuration: Sendable, Equatable {
        public enum Support: Sendable, Equatable {
            /// One window centred on the cell — the shipped convention.
            case singleDisc
            /// Stride-`stride` grid of windows over the cell — the paper's.
            case tiled(stride: Int)
        }

        public var support: Support
        /// `nil` disables the pre-blur. Applied identically to both sides.
        public var blurSigma: Float?

        public init(support: Support, blurSigma: Float? = nil) {
            self.support = support
            self.blurSigma = blurSigma
        }

        /// The shipped convention, on whatever rect it is handed.
        public static let singleDisc = Configuration(support: .singleDisc)
        /// The paper's construction, with its 7×7 pre-blur.
        public static let tiledAISS = Configuration(
            support: .tiled(stride: 2), blurSigma: defaultBlurSigma)
        /// The paper's construction with the pre-blur removed — the ablation
        /// that says how much of the tiling's effect is the blur.
        public static let tiledAISSNoBlur = Configuration(support: .tiled(stride: 2))
    }

    /// Window grid for a cell, as (columns, rows). Empty when the cell is too
    /// small to hold one window at this stride.
    public static func windowGrid(width: Int, height: Int, stride: Int) -> (
        columns: Int, rows: Int
    ) {
        guard stride > 0 else { return (0, 0) }
        return (max(0, width / stride), max(0, height / stride))
    }

    /// Descriptor length for a cell under a configuration. `0` means the cell
    /// cannot be sampled at all under that configuration.
    public static func dimension(width: Int, height: Int, configuration: Configuration) -> Int {
        switch configuration.support {
        case .singleDisc:
            return min(width, height) > 1 ? binsPerWindow : 0
        case .tiled(let stride):
            let grid = windowGrid(width: width, height: height, stride: stride)
            return grid.columns * grid.rows * binsPerWindow
        }
    }

    /// Samples `pixels` (row-major, `width × height`, ink in [0,1]).
    ///
    /// The returned vector is L1-normalized over its whole length, or all-zero
    /// when no pixel cleared the inclusion threshold inside any window.
    public static func descriptor(
        _ pixels: [Float], width: Int, height: Int, configuration: Configuration
    ) -> [Float] {
        let dimension = dimension(width: width, height: height, configuration: configuration)
        guard dimension > 0, pixels.count == width * height else {
            return [Float](repeating: 0, count: max(0, dimension))
        }

        let source: [Float]
        if let sigma = configuration.blurSigma, sigma > 0 {
            source = gaussianBlur(pixels, width: width, height: height, sigma: sigma)
        } else {
            source = pixels
        }

        // Radius = half the SHORTER cell side, for both supports. Under
        // `tiled` that makes neighbouring windows overlap heavily, which is
        // what gives the concatenation its positional resolution.
        let radius = Float(min(width, height)) / 2
        guard radius > 0 else { return [Float](repeating: 0, count: dimension) }

        var histogram = [Float](repeating: 0, count: dimension)
        switch configuration.support {
        case .singleDisc:
            accumulate(
                source, width: width, height: height,
                centerX: Float(width) / 2, centerY: Float(height) / 2, radius: radius,
                into: &histogram, offset: 0)
        case .tiled(let stride):
            let grid = windowGrid(width: width, height: height, stride: stride)
            var offset = 0
            for row in 0..<grid.rows {
                for column in 0..<grid.columns {
                    // Window centres sit at the middle of each stride-sized
                    // step, so the grid covers the cell symmetrically.
                    let centerX = (Float(column * stride) + Float(stride) / 2)
                    let centerY = (Float(row * stride) + Float(stride) / 2)
                    accumulate(
                        source, width: width, height: height,
                        centerX: centerX, centerY: centerY, radius: radius,
                        into: &histogram, offset: offset)
                    offset += binsPerWindow
                }
            }
        }

        let total = histogram.reduce(0, +)
        if total > 0 {
            for index in 0..<dimension { histogram[index] /= total }
        }
        return histogram
    }

    /// One 5×12 log-polar window, written into `histogram[offset...]`.
    ///
    /// The bin math is `ShapeContext.histogram60`'s, verbatim apart from the
    /// centre and radius being parameters instead of derived from the raster:
    /// same 0.05 inclusion threshold, same `r < 0.5` inner cutoff, same
    /// `logSpan = log(2 × radius)` radial scale. Keeping it identical is the
    /// point — a difference between an arm and the shipped path must be the
    /// support, not an incidental change of binning.
    private static func accumulate(
        _ pixels: [Float], width: Int, height: Int,
        centerX: Float, centerY: Float, radius: Float,
        into histogram: inout [Float], offset: Int
    ) {
        let logSpan = logf(2 * radius)
        guard radius.isFinite, radius > 0, logSpan.isFinite, logSpan > 0 else { return }

        // Only the disc can contribute, so bound the scan to its bounding box
        // rather than walking the whole cell once per window.
        let minX = max(0, Int((centerX - radius).rounded(.down)))
        let maxX = min(width - 1, Int((centerX + radius).rounded(.up)))
        let minY = max(0, Int((centerY - radius).rounded(.down)))
        let maxY = min(height - 1, Int((centerY + radius).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return }

        for y in minY...maxY {
            for x in minX...maxX {
                let weight = pixels[y * width + x]
                if weight < 0.05 { continue }
                let dx = Float(x) - centerX
                let dy = Float(y) - centerY
                let r = (dx * dx + dy * dy).squareRoot()
                if r < 0.5 || r > radius { continue }
                let radialPosition = (logf(r / radius) + logSpan) / logSpan * Float(radialBins)
                guard radialPosition.isFinite else { continue }
                let radialBin = min(radialBins - 1, max(0, Int(radialPosition)))
                var theta = atan2f(dy, dx)
                if theta < 0 { theta += 2 * .pi }
                let angularPosition = theta / (2 * .pi) * Float(angularBins)
                let angleBin = min(angularBins - 1, Int(angularPosition))
                histogram[offset + radialBin * angularBins + angleBin] += weight
            }
        }
    }

    /// Separable 7×7 Gaussian with clamp-to-edge borders. Clamping (rather than
    /// zero padding) keeps a glyph that touches a cell edge from being darkened
    /// by the blur, which would show up as a tone difference the arm did not
    /// intend to introduce.
    public static func gaussianBlur(
        _ pixels: [Float], width: Int, height: Int, sigma: Float
    ) -> [Float] {
        guard width > 0, height > 0, pixels.count == width * height, sigma > 0 else {
            return pixels
        }
        let radius = blurKernelRadius
        var kernel = [Float](repeating: 0, count: 2 * radius + 1)
        var sum: Float = 0
        for i in -radius...radius {
            let value = expf(-Float(i * i) / (2 * sigma * sigma))
            kernel[i + radius] = value
            sum += value
        }
        for i in 0..<kernel.count { kernel[i] /= sum }

        var horizontal = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var acc: Float = 0
                for k in -radius...radius {
                    let sx = min(width - 1, max(0, x + k))
                    acc += pixels[y * width + sx] * kernel[k + radius]
                }
                horizontal[y * width + x] = acc
            }
        }
        var blurred = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var acc: Float = 0
                for k in -radius...radius {
                    let sy = min(height - 1, max(0, y + k))
                    acc += horizontal[sy * width + x] * kernel[k + radius]
                }
                blurred[y * width + x] = acc
            }
        }
        return blurred
    }
}
