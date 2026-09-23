import CoreGraphics
import Foundation
import Testing
@testable import Aski

@Suite struct SSIMValidation {

    @Test func mssimScoresIdenticalImagesNearOne() {
        let source = TestImages.horizontalGradient(width: 240, height: 160)
        let score = Self.computeMSSIM(source: source, rendered: source)

        #expect(abs(score - 1) < 1e-9, "MSSIM = \(score)")
    }

    @Test func mssimPenalizesLostHighFrequencyStructure() {
        let source = Self.checkerboard(width: 240, height: 160, squareSize: 12)
        let degraded = Self.solidGray(0.5, width: 240, height: 160)
        let score = Self.computeMSSIM(source: source, rendered: degraded)

        #expect(score < 0.2, "MSSIM = \(score)")
    }

    @Test func convertAndRenderBackPreservesHorizontalGradientStructure() {
        let source = TestImages.horizontalGradient(width: 400, height: 200)
        let grid = DefaultConverter().convert(source, columns: 80)
        let rendered = grid.renderImage(
            font: .system(size: 10),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )
        let score = Self.computeMSSIM(source: source, rendered: rendered)
        let blank = Self.solidGray(0, width: rendered.width, height: rendered.height)
        let blankScore = Self.computeMSSIM(source: source, rendered: blank)

        #expect(score >= 0.07, "MSSIM = \(score)")
        #expect(score > blankScore + 0.03, "MSSIM = \(score), blank MSSIM = \(blankScore)")
    }

    @Test func convertAndRenderBackPreservesDiagonalStructure() {
        let source = Self.diagonalGradient(width: 400, height: 240)
        let grid = DefaultConverter().convert(source, columns: 80)
        let rendered = grid.renderImage(
            font: .system(size: 10),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )
        let score = Self.computeMSSIM(source: source, rendered: rendered)
        let blank = Self.solidGray(0, width: rendered.width, height: rendered.height)
        let blankScore = Self.computeMSSIM(source: source, rendered: blank)

        #expect(score >= 0.07, "MSSIM = \(score)")
        #expect(score > blankScore + 0.03, "MSSIM = \(score), blank MSSIM = \(blankScore)")
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
