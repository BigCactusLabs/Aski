import Testing
import simd
@testable import Aski

@Suite struct KMeansRefinementTests {

    private static func solidColor(
        _ rgba: (UInt8, UInt8, UInt8, UInt8),
        width: Int,
        height: Int
    ) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            pixels[i * 4 + 0] = rgba.0
            pixels[i * 4 + 1] = rgba.1
            pixels[i * 4 + 2] = rgba.2
            pixels[i * 4 + 3] = rgba.3
        }
        return pixels
    }

    @Test func deterministic() {
        let pixels = WuQuantizationTestsFixture.fourQuadrants(width: 32, height: 32)
        let wu = WuQuantizer(pixels: pixels, width: 32, height: 32, colorSpace: .sRGB)
            .palette(maxColors: 4)
        let r1 = KMeansRefinement.refine(
            palette: wu,
            pixels: pixels,
            width: 32,
            height: 32,
            colorSpace: .sRGB
        )
        let r2 = KMeansRefinement.refine(
            palette: wu,
            pixels: pixels,
            width: 32,
            height: 32,
            colorSpace: .sRGB
        )
        #expect(r1.count == r2.count)
        for (a, b) in zip(r1, r2) {
            #expect(simd_length(a - b) < 1e-6)
        }
    }

    @Test func emptyPaletteReturnsEmpty() {
        let pixels = Self.solidColor((128, 128, 128, 255), width: 8, height: 8)
        let result = KMeansRefinement.refine(
            palette: [],
            pixels: pixels,
            width: 8,
            height: 8,
            colorSpace: .sRGB
        )
        #expect(result.isEmpty)
    }

    @Test func singleColorImageProducesNoNaN() {
        let pixels = Self.solidColor((128, 128, 128, 255), width: 16, height: 16)
        let mid = ColorConversion.linearSRGBToOKLAB(
            SIMD3<Float>(
                ColorConversion.sRGBDecode(Float(128) / 255),
                ColorConversion.sRGBDecode(Float(128) / 255),
                ColorConversion.sRGBDecode(Float(128) / 255)
            ))
        let result = KMeansRefinement.refine(
            palette: [mid, mid],
            pixels: pixels,
            width: 16,
            height: 16,
            colorSpace: .sRGB
        )
        for center in result {
            #expect(!center.x.isNaN && !center.y.isNaN && !center.z.isNaN)
        }
        #expect(!result.isEmpty)
    }

    @Test func refinedPaletteHasEqualOrLowerOKLABMSE() {
        let pixels = WuQuantizationTestsFixture.fourQuadrants(width: 64, height: 64)
        let wu = WuQuantizer(pixels: pixels, width: 64, height: 64, colorSpace: .sRGB)
            .palette(maxColors: 4)
        let refined = KMeansRefinement.refine(
            palette: wu,
            pixels: pixels,
            width: 64,
            height: 64,
            colorSpace: .sRGB
        )
        let mseWu = Self.mse(palette: wu, pixels: pixels, width: 64, height: 64)
        let mseRefined = Self.mse(palette: refined, pixels: pixels, width: 64, height: 64)
        #expect(mseRefined <= mseWu + 1e-6)
    }

    private static func mse(
        palette: [SIMD3<Float>],
        pixels: [UInt8],
        width: Int,
        height: Int
    ) -> Float {
        guard !palette.isEmpty else { return .infinity }

        var sum: Float = 0
        var weight: Float = 0
        for i in 0..<(width * height) {
            let offset = i * 4
            let alpha = Float(pixels[offset + 3]) / 255
            if alpha == 0 { continue }

            let red = min(Float(pixels[offset + 0]) / 255 / alpha, 1)
            let green = min(Float(pixels[offset + 1]) / 255 / alpha, 1)
            let blue = min(Float(pixels[offset + 2]) / 255 / alpha, 1)
            let lab = ColorConversion.linearSRGBToOKLAB(
                SIMD3(
                    ColorConversion.sRGBDecode(red),
                    ColorConversion.sRGBDecode(green),
                    ColorConversion.sRGBDecode(blue)
                ))

            var nearest: Float = .infinity
            for center in palette {
                nearest = min(nearest, simd_length_squared(center - lab))
            }
            sum += alpha * nearest
            weight += alpha
        }

        return weight > 0 ? sum / weight : 0
    }
}

internal enum WuQuantizationTestsFixture {
    static func fourQuadrants(width: Int, height: Int) -> [UInt8] {
        precondition(width % 2 == 0 && height % 2 == 0)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let half = width / 2
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let topLeft = y < height / 2 && x < half
                let topRight = y < height / 2 && x >= half
                let bottomLeft = y >= height / 2 && x < half
                if topLeft {
                    pixels[offset + 0] = 255
                } else if topRight {
                    pixels[offset + 1] = 255
                } else if bottomLeft {
                    pixels[offset + 2] = 255
                } else {
                    pixels[offset + 0] = 255
                    pixels[offset + 1] = 255
                    pixels[offset + 2] = 255
                }
                pixels[offset + 3] = 255
            }
        }
        return pixels
    }
}
