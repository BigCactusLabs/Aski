import Foundation

/// 60-D log-polar shape-context histogram (5 radial log-bins × 12 angular bins),
/// computed at the image center. Output is L1-normalized so it sums to 1; if no
/// pixel is above the inclusion threshold, returns all zeros.
///
/// Shared by `LogPolarKernel` (per-cell, at convert time), `RasterizedCharacterSet`
/// (per-glyph, when building runtime character sets), and `BuildStandardVectors`
/// (per-glyph, when building the bundled `.bin` files). Centralized to prevent
/// silent drift between in-module copies.
package enum ShapeContext {
    /// Bin count = radial × angular = 5 × 12 = 60.
    package static let dimension: Int = 60

    package static func histogram60(
        _ pixels: [Float],
        width: Int,
        height: Int
    ) -> [Float] {
        var histogram = [Float](repeating: 0, count: dimension)
        let minDimension = min(width, height)
        guard minDimension > 1 else { return histogram }
        let centerX = Float(width) / 2
        let centerY = Float(height) / 2
        let maxRadius = Float(minDimension) / 2
        let logSpan = logf(Float(minDimension))
        guard maxRadius.isFinite, maxRadius > 0, logSpan.isFinite, logSpan > 0 else { return histogram }

        for y in 0..<height {
            for x in 0..<width {
                let weight = pixels[y * width + x]
                if weight < 0.05 { continue }
                let dx = Float(x) - centerX
                let dy = Float(y) - centerY
                let radius = (dx * dx + dy * dy).squareRoot()
                if radius < 0.5 || radius > maxRadius { continue }
                let logRadius = logf(radius / maxRadius)
                let radialPosition = (logRadius + logSpan) / logSpan * 5
                guard radialPosition.isFinite else { continue }
                let radialBin = min(4, max(0, Int(radialPosition)))
                var theta = atan2f(dy, dx)
                if theta < 0 { theta += 2 * .pi }
                // `theta` is atan2f of finite grid coordinates, normalized to
                // `[0, 2π)`; that named angular bound puts this in `[0, 12)`.
                let angularPosition = theta / (2 * .pi) * 12
                let angleBin = min(11, Int(angularPosition))
                histogram[radialBin * 12 + angleBin] += weight
            }
        }
        let total = histogram.reduce(0, +)
        if total > 0 {
            for index in 0..<dimension { histogram[index] /= total }
        }
        return histogram
    }

    /// Geometry for one fixed cell footprint. A conversion owns one immutable
    /// value; each histogram owns its own accumulator. Nothing is cached globally.
    /// The scalar entry point above remains the per-glyph path and parity control.
    package struct Footprint: Sendable {
        package let width: Int
        package let height: Int
        // One byte per footprint pixel; 255 means outside the admitted disc.
        // Keep raster order: grouping by bin would change Float addition order.
        private let bins: [UInt8]

        /// Logical bin payload only; excludes Array headers and allocator rounding.
        package var storageByteCount: Int { bins.count }

        package init(width: Int, height: Int) {
            self.width = width
            self.height = height
            let minDimension = min(width, height)
            guard minDimension > 1 else {
                bins = []
                return
            }
            let centerX = Float(width) / 2
            let centerY = Float(height) / 2
            let maxRadius = Float(minDimension) / 2
            let logSpan = logf(Float(minDimension))
            guard maxRadius.isFinite, maxRadius > 0, logSpan.isFinite, logSpan > 0 else {
                bins = []
                return
            }
            let count = width.multipliedReportingOverflow(by: height)
            precondition(!count.overflow, "ShapeContext footprint pixel count must fit Int")
            var bins = [UInt8](repeating: 255, count: count.partialValue)
            for y in 0..<height {
                for x in 0..<width {
                    let dx = Float(x) - centerX
                    let dy = Float(y) - centerY
                    let radius = (dx * dx + dy * dy).squareRoot()
                    if radius < 0.5 || radius > maxRadius { continue }
                    let logRadius = logf(radius / maxRadius)
                    let radialPosition = (logRadius + logSpan) / logSpan * 5
                    guard radialPosition.isFinite else { continue }
                    let radialBin = min(4, max(0, Int(radialPosition)))
                    var theta = atan2f(dy, dx)
                    if theta < 0 { theta += 2 * .pi }
                    let angularPosition = theta / (2 * .pi) * 12
                    let angleBin = min(11, Int(angularPosition))
                    bins[y * width + x] = UInt8(radialBin * 12 + angleBin)
                }
            }
            self.bins = bins
        }

        package func histogram60(_ pixels: [Float]) -> [Float] {
            var histogram = [Float](repeating: 0, count: ShapeContext.dimension)
            // Degenerate footprints intentionally require no pixel storage,
            // matching the scalar entry point's early return.
            for index in bins.indices {
                let bin = bins[index]
                if bin == 255 { continue }
                let weight = pixels[index]
                if weight < 0.05 { continue }
                histogram[Int(bin)] += weight
            }
            let total = histogram.reduce(0, +)
            if total > 0 {
                for index in 0..<ShapeContext.dimension { histogram[index] /= total }
            }
            return histogram
        }
    }
}
