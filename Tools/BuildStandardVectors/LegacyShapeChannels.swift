import CoreGraphics
import CoreText
import Foundation

/// Generator-only support for the retired v3 structure-channel block.
///
/// Production no longer loads these channels, but the checked-in v3 binaries
/// retain them as historical artifacts. Keeping the original math here makes
/// `just regen-vectors` byte-stable without carrying the killed experiment in
/// the Aski library target.
enum LegacyShapeChannels {
    static let footprint = 24
    static let orientationBins = 8

    static func rasterize(_ character: Character, font: CTFont, size: Int) -> [Float] {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard
            let context = CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else { return [Float](repeating: 0, count: size * size) }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let string = NSAttributedString(
            string: String(character),
            attributes: [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1),
            ] as [NSAttributedString.Key: Any]
        )
        let line = CTLineCreateWithAttributedString(string)
        let bounds = CTLineGetImageBounds(line, context)
        context.textPosition = CGPoint(
            x: (CGFloat(size) - bounds.width) / 2 - bounds.origin.x,
            y: (CGFloat(size) - bounds.height) / 2 - bounds.origin.y
        )
        CTLineDraw(line, context)

        guard let data = context.data else {
            return [Float](repeating: 0, count: size * size)
        }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        return (0..<(size * size)).map { Float(bytes[$0]) / 255.0 }
    }

    static func orientationHistogram(_ source: [Float], width: Int, height: Int) -> [Float] {
        var histogram = [Double](repeating: 0, count: orientationBins)
        guard width > 0, height > 0, source.count == width * height else {
            return [Float](repeating: 0, count: orientationBins)
        }
        @inline(__always) func at(_ x: Int, _ y: Int) -> Double {
            let clampedX = min(max(x, 0), width - 1)
            let clampedY = min(max(y, 0), height - 1)
            return Double(source[clampedY * width + clampedX])
        }
        let binWidth = Double.pi / Double(orientationBins)
        for y in 0..<height {
            for x in 0..<width {
                let topLeft = at(x - 1, y - 1)
                let topCenter = at(x, y - 1)
                let topRight = at(x + 1, y - 1)
                let middleLeft = at(x - 1, y)
                let middleRight = at(x + 1, y)
                let bottomLeft = at(x - 1, y + 1)
                let bottomCenter = at(x, y + 1)
                let bottomRight = at(x + 1, y + 1)
                let gx = (topRight + middleRight + bottomRight) - (topLeft + middleLeft + bottomLeft)
                let gy = (bottomLeft + bottomCenter + bottomRight) - (topLeft + topCenter + topRight)
                let energy = gx * gx + gy * gy
                guard energy > 0 else { continue }
                var theta = atan2(gy, gx)
                if theta < 0 { theta += Double.pi }
                if theta >= Double.pi { theta -= Double.pi }
                let bin = min(orientationBins - 1, max(0, Int(theta / binWidth)))
                histogram[bin] += energy
            }
        }
        let total = histogram.reduce(0, +)
        guard total > 0 else { return [Float](repeating: 0, count: orientationBins) }
        return histogram.map { Float($0 / total) }
    }

    static func radialPeak(_ source: [Float], width: Int, height: Int) -> Float {
        Float(radialAutocorrelationPeak(radialProfile(source, width: width, height: height)))
    }

    private static func radialProfile(_ source: [Float], width: Int, height: Int) -> [Double] {
        guard width > 0, height > 0, source.count == width * height else { return [] }
        let centerX = Double(width - 1) / 2.0
        let centerY = Double(height - 1) / 2.0
        let maxRadius = Int((min(Double(width), Double(height)) / 2.0).rounded(.down))
        guard maxRadius >= 1 else { return [] }
        var sums = [Double](repeating: 0, count: maxRadius + 1)
        var counts = [Int](repeating: 0, count: maxRadius + 1)
        for y in 0..<height {
            for x in 0..<width {
                let dx = Double(x) - centerX
                let dy = Double(y) - centerY
                let radius = Int((dx * dx + dy * dy).squareRoot().rounded())
                guard radius <= maxRadius else { continue }
                sums[radius] += Double(source[y * width + x])
                counts[radius] += 1
            }
        }
        var profile: [Double] = []
        profile.reserveCapacity(maxRadius + 1)
        for radius in 0...maxRadius where counts[radius] > 0 {
            profile.append(sums[radius] / Double(counts[radius]))
        }
        return profile
    }

    private static func radialAutocorrelationPeak(_ profile: [Double]) -> Double {
        let count = profile.count
        guard count >= 4 else { return 0 }
        let mean = profile.reduce(0, +) / Double(count)
        var variance = 0.0
        for value in profile {
            let delta = value - mean
            variance += delta * delta
        }
        guard variance > 1e-12 else { return 0 }
        let maxLag = count / 2
        guard maxLag >= 2 else { return 0 }
        var peak = 0.0
        for lag in 2...maxLag {
            var covariance = 0.0
            for index in 0..<(count - lag) {
                covariance += (profile[index] - mean) * (profile[index + lag] - mean)
            }
            peak = max(peak, covariance / variance)
        }
        return peak
    }
}
