import Testing
import simd
@testable import Aski

@Suite struct ColorSamplingPolicyTests {
    @Test func linearLightAverageOpaqueBytesMatchDirectDecodeExactly() {
        let pixels: [UInt8] = [17, 93, 241, 255]
        let context = ConversionContext(
            pixels: pixels,
            pixelWidth: 1,
            pixelHeight: 1,
            cellWidth: 1,
            cellHeight: 1,
            columns: 1,
            rows: 1,
            palette: .passThrough,
            options: ResolvedRenderingOptions(.default),
            colorSpace: .sRGB,
            colorSampling: .linearLightAverage
        )

        let source = context.cellSourceStats(at: CellCoord(column: 0, row: 0))
        let expected = ColorConversion.linearSRGBToOKLAB(
            SIMD3<Float>(
                ColorConversion.sRGBDecode(Float(pixels[0]) / 255),
                ColorConversion.sRGBDecode(Float(pixels[1]) / 255),
                ColorConversion.sRGBDecode(Float(pixels[2]) / 255)
            ))

        #expect(source.oklab == expected)
        #expect(source.alpha == 1)
    }

    @Test func encodedAverageLegacyMatchesCurrentAlphaSkipping() {
        let pixels: [UInt8] = [
            0, 0, 0, 255,
            128, 128, 128, 128,
        ]
        let context = ConversionContext(
            pixels: pixels,
            pixelWidth: 2,
            pixelHeight: 1,
            cellWidth: 2,
            cellHeight: 1,
            columns: 1,
            rows: 1,
            palette: .passThrough,
            options: ResolvedRenderingOptions(.default),
            colorSpace: .sRGB,
            colorSampling: .encodedAverageLegacy
        )

        let stats = context.cellStats(at: CellCoord(column: 0, row: 0))
        let expectedLinear = SIMD3<Float>(
            ColorConversion.sRGBDecode(0.5),
            ColorConversion.sRGBDecode(0.5),
            ColorConversion.sRGBDecode(0.5)
        )
        let expectedOKLAB = ColorConversion.linearSRGBToOKLAB(expectedLinear)
        let expectedAlpha = (Float(255) / 255 + Float(128) / 255) / 2

        #expect(abs(stats.rawL - expectedOKLAB.x) < 1e-5)
        #expect(abs(stats.alpha - expectedAlpha) < 1e-6)
    }

    @Test func linearLightAverageWeightsUnpremultipliedSamplesByAlpha() {
        let pixels: [UInt8] = [
            0, 0, 0, 255,
            128, 128, 128, 128,
        ]
        let context = ConversionContext(
            pixels: pixels,
            pixelWidth: 2,
            pixelHeight: 1,
            cellWidth: 2,
            cellHeight: 1,
            columns: 1,
            rows: 1,
            palette: .passThrough,
            options: ResolvedRenderingOptions(.default),
            colorSpace: .sRGB,
            colorSampling: .linearLightAverage
        )

        let stats = context.cellStats(at: CellCoord(column: 0, row: 0))
        let halfAlpha = Float(128) / 255
        let expectedChannel = halfAlpha / (1 + halfAlpha)
        let expectedOKLAB = ColorConversion.linearSRGBToOKLAB(
            SIMD3<Float>(
                expectedChannel,
                expectedChannel,
                expectedChannel
            ))
        let legacyOKLAB = ColorConversion.linearSRGBToOKLAB(
            SIMD3<Float>(
                ColorConversion.sRGBDecode(0.5),
                ColorConversion.sRGBDecode(0.5),
                ColorConversion.sRGBDecode(0.5)
            ))

        #expect(abs(stats.rawL - expectedOKLAB.x) < 1e-5)
        #expect(abs(stats.rawL - legacyOKLAB.x) > 0.02)
    }

    @Test func linearLightAverageAllTransparentSamplesProduceZeroAlphaAndBlack() {
        let pixels: [UInt8] = [
            0, 0, 0, 0,
            0, 0, 0, 0,
        ]
        let context = ConversionContext(
            pixels: pixels,
            pixelWidth: 2,
            pixelHeight: 1,
            cellWidth: 2,
            cellHeight: 1,
            columns: 1,
            rows: 1,
            palette: .passThrough,
            options: ResolvedRenderingOptions(.default),
            colorSpace: .sRGB,
            colorSampling: .linearLightAverage
        )

        let stats = context.cellStats(at: CellCoord(column: 0, row: 0))

        #expect(stats.alpha == 0)
        #expect(abs(stats.rawL) < 1e-6)
        #expect(abs(stats.adjustedL) < 1e-6)
    }
}
