import CoreGraphics
import CryptoKit
import Foundation
import Testing
@testable import Aski

/// TEMPORARY attribution measurements. Do not commit as a correctness oracle:
/// the remapped arm deliberately reproduces the old Generic RGB interpretation.
@Suite struct SSIMAttributionProbe {
    @Test(arguments: ["horizontal", "diagonal"])
    func fullColorToneAttribution(fixture: String) throws {
        let source = fixture == "horizontal"
            ? TestImages.horizontalGradient(width: 400, height: 200)
            : Self.diagonalGradient(width: 400, height: 240)
        let grid = DefaultConverter().convert(source, columns: 80)
        let remapped = try Self.genericRGBToSRGB(grid)
        let originalImage = Self.render(grid)
        let remappedImage = Self.render(remapped)
        let blank = Self.solidGray(0, width: originalImage.width, height: originalImage.height)
        let blankScore = Self.computeMSSIM(source: source, rendered: blank)
        let row: [String: Any] = [
            "probe": "ASKI3-SSIM-attribution",
            "fixture": fixture,
            "source_sha256": try Self.rawSHA256(source),
            "blank_score": blankScore,
            "blank_sha256": try Self.rawSHA256(blank),
            "original": try Self.measure(source: source, rendered: originalImage),
            "generic_rgb_to_srgb": try Self.measure(source: source, rendered: remappedImage),
        ]
        let json = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        print(String(decoding: json, as: UTF8.self))
    }

    /// Decode the legacy Generic RGB meaning into encoded sRGB independently of
    /// production color helpers. Only displayColor changes; every other cell and
    /// grid field is retained, and the default converter's sRGB tag is unchanged.
    private static func genericRGBToSRGB(_ grid: ASCIIGrid) throws -> ASCIIGrid {
        let destination = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let cells = try grid.cells.map { row in
            try row.map { cell in
                let generic = CGColor(
                    red: CGFloat(cell.displayColor.x), green: CGFloat(cell.displayColor.y),
                    blue: CGFloat(cell.displayColor.z), alpha: 1)
                let converted = try #require(generic.converted(to: destination, intent: .defaultIntent, options: nil))
                let components = try #require(converted.components)
                return ASCIICell(
                    character: cell.character,
                    displayColor: SIMD3(Float(components[0]), Float(components[1]), Float(components[2])),
                    alpha: cell.alpha, brightness: cell.brightness, coverage: cell.coverage)
            }
        }
        return ASCIIGrid(
            cells: cells, colorSpace: grid.colorSpace, composition: grid.composition,
            maskFallback: grid.maskFallback, maskGroundColor: grid.maskGroundColor,
            maskUsesHardEdges: grid.maskUsesHardEdges)
    }

    private static func render(_ grid: ASCIIGrid) -> CGImage {
        grid.renderImage(
            font: .system(size: 10), backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1), scale: 1)
    }

    private static func measure(source: CGImage, rendered: CGImage) throws -> [String: Any] {
        [
            "score": computeMSSIM(source: source, rendered: rendered),
            "raw_sha256": try rawSHA256(rendered),
            "width": rendered.width,
            "height": rendered.height,
            "bytes_per_row": rendered.bytesPerRow,
            "bits_per_component": rendered.bitsPerComponent,
            "bits_per_pixel": rendered.bitsPerPixel,
            "bitmap_info": rendered.bitmapInfo.rawValue,
            "color_space": rendered.colorSpace?.name.map { $0 as String } ?? "nil",
        ]
    }

    /// Hash actual CGImage backing bytes, including row padding, without PNG or
    /// display/profile conversion. Layout fields accompany the hash in each row.
    private static func rawSHA256(_ image: CGImage) throws -> String {
        let provider = try #require(image.dataProvider)
        let bytes = try #require(provider.data)
        return SHA256.hash(data: bytes as Data).map { String(format: "%02x", $0) }.joined()
    }

    /// Local-window mean SSIM on luminance, using Wang et al.-style constants:
    /// 11x11 Gaussian window, sigma 1.5, K1 0.01, K2 0.03, data range 1.0.
    private static func computeMSSIM(source: CGImage, rendered: CGImage) -> Double {
        let refSize = 128
        let a = downsampleLuminance(source, target: refSize)
        let b = downsampleLuminance(rendered, target: refSize)
        let kernel = gaussianKernel(radius: 5, sigma: 1.5)
        let c1 = 0.01 * 0.01
        let c2 = 0.03 * 0.03

        var total = 0.0
        var windows = 0
        for y in 5..<(refSize - 5) {
            for x in 5..<(refSize - 5) {
                var meanA = 0.0
                var meanB = 0.0
                for ky in -5...5 {
                    for kx in -5...5 {
                        let weight = kernel[ky + 5][kx + 5]
                        let index = (y + ky) * refSize + x + kx
                        meanA += weight * a[index]
                        meanB += weight * b[index]
                    }
                }

                var varA = 0.0
                var varB = 0.0
                var cov = 0.0
                for ky in -5...5 {
                    for kx in -5...5 {
                        let weight = kernel[ky + 5][kx + 5]
                        let index = (y + ky) * refSize + x + kx
                        let da = a[index] - meanA
                        let db = b[index] - meanB
                        varA += weight * da * da
                        varB += weight * db * db
                        cov += weight * da * db
                    }
                }

                total +=
                    ((2 * meanA * meanB + c1) * (2 * cov + c2))
                    / ((meanA * meanA + meanB * meanB + c1) * (varA + varB + c2))
                windows += 1
            }
        }

        return total / Double(windows)
    }

    private static func downsampleLuminance(_ image: CGImage, target: Int) -> [Double] {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(
            data: nil,
            width: target,
            height: target,
            bitsPerComponent: 8,
            bytesPerRow: target,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: target, height: target))
        guard let data = context.data else { return [] }

        let bytes = data.assumingMemoryBound(to: UInt8.self)
        return (0..<(target * target)).map { Double(bytes[$0]) / 255.0 }
    }

    private static func gaussianKernel(radius: Int, sigma: Double) -> [[Double]] {
        let size = radius * 2 + 1
        var kernel = Array(repeating: Array(repeating: 0.0, count: size), count: size)
        var sum = 0.0
        for y in -radius...radius {
            for x in -radius...radius {
                let value = exp(-Double(x * x + y * y) / (2 * sigma * sigma))
                kernel[y + radius][x + radius] = value
                sum += value
            }
        }

        for y in 0..<size {
            for x in 0..<size {
                kernel[y][x] /= sum
            }
        }
        return kernel
    }

    private static func diagonalGradient(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        for y in 0..<height {
            for x in 0..<width {
                let t = CGFloat(x + y) / CGFloat(width + height - 2)
                context.setFillColor(red: t, green: t, blue: t, alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }

        return context.makeImage()!
    }

    private static func checkerboard(width: Int, height: Int, squareSize: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        for y in 0..<height {
            for x in 0..<width {
                let isLight = ((x / squareSize) + (y / squareSize)).isMultiple(of: 2)
                let value: CGFloat = isLight ? 1 : 0
                context.setFillColor(red: value, green: value, blue: value, alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }

        return context.makeImage()!
    }

    private static func solidGray(_ value: CGFloat, width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        context.setFillColor(red: value, green: value, blue: value, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
