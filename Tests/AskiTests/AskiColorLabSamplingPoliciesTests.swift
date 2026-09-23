import Foundation
import Testing
import simd
@testable import Aski
@testable import AskiColorLab

@Suite struct AskiColorLabSamplingPoliciesTests {
    @Test func fixtureSetHasStableOrderingAndIDs() {
        let fixtures = SamplingFixtures.all
        #expect(fixtures.count >= 7)
        #expect(fixtures.map(\.id).first == "2x2_opaque_primaries")
        let ids = Set(fixtures.map(\.id))
        #expect(ids.count == fixtures.count)
    }

    @Test func everyFixturePixelCountMatchesDeclaredSize() {
        for fixture in SamplingFixtures.all {
            let expected = fixture.width * fixture.height * 4
            #expect(fixture.pixels.count == expected, "\(fixture.id) has wrong byte count")
        }
    }

    @Test func encodedAverageLegacyLabSamplerMatchesLibraryOnAllFixtures() {
        for fixture in SamplingFixtures.all {
            let lab = SamplingPolicies.encodedAverageLegacy(
                pixels: fixture.pixels,
                width: fixture.width,
                height: fixture.height
            )
            let expectedDisplay = expectedDisplayColor(
                fromLabLinearRGB: lab.linearRGB,
                colorSpace: fixture.colorSpace
            )

            let context = ConversionContext(
                pixels: fixture.pixels,
                pixelWidth: fixture.width,
                pixelHeight: fixture.height,
                cellWidth: fixture.width,
                cellHeight: fixture.height,
                columns: 1,
                rows: 1,
                palette: .passThrough,
                options: ResolvedRenderingOptions(.default),
                colorSpace: fixture.colorSpace,
                colorSampling: .encodedAverageLegacy,
                paletteMatching: .oklabEuclidean,
                gamutMapping: .clip
            )
            let stats = context.cellStats(at: CellCoord(column: 0, row: 0))

            #expect(simd_length(stats.displayColor - expectedDisplay) < 1e-5, "fixture \(fixture.id) displayColor drift: lab=\(expectedDisplay) lib=\(stats.displayColor)")
            #expect(abs(stats.alpha - lab.alpha) < 1e-6, "fixture \(fixture.id) alpha drift")
        }
    }

    @Test func linearLightAverageLabSamplerMatchesLibraryOnAllFixtures() {
        for fixture in SamplingFixtures.all {
            let lab = SamplingPolicies.linearLightAverage(
                pixels: fixture.pixels,
                width: fixture.width,
                height: fixture.height
            )
            let expectedDisplay = expectedDisplayColor(
                fromLabLinearRGB: lab.linearRGB,
                colorSpace: fixture.colorSpace
            )

            let context = ConversionContext(
                pixels: fixture.pixels,
                pixelWidth: fixture.width,
                pixelHeight: fixture.height,
                cellWidth: fixture.width,
                cellHeight: fixture.height,
                columns: 1,
                rows: 1,
                palette: .passThrough,
                options: ResolvedRenderingOptions(.default),
                colorSpace: fixture.colorSpace,
                colorSampling: .linearLightAverage,
                paletteMatching: .oklabEuclidean,
                gamutMapping: .clip
            )
            let stats = context.cellStats(at: CellCoord(column: 0, row: 0))

            #expect(simd_length(stats.displayColor - expectedDisplay) < 1e-5, "fixture \(fixture.id) displayColor drift: lab=\(expectedDisplay) lib=\(stats.displayColor)")
            #expect(abs(stats.alpha - lab.alpha) < 1e-6, "fixture \(fixture.id) alpha drift")
        }
    }

    /// Replays the library's pass-through + clip pipeline against the lab
    /// sampler's `linearRGB`. Both the lab and the library use the same
    /// `ColorConversion` primitives, so they must produce equal `displayColor`
    /// up to float precision.
    private func expectedDisplayColor(
        fromLabLinearRGB linearRGB: SIMD3<Float>,
        colorSpace: RenderColorSpace
    ) -> SIMD3<Float> {
        let oklab: SIMD3<Float>
        switch colorSpace {
        case .sRGB: oklab = ColorConversion.linearSRGBToOKLAB(linearRGB)
        case .displayP3: oklab = ColorConversion.linearP3ToOKLAB(linearRGB)
        }
        let adjustedL = simd_clamp(oklab.x, 0, 1)
        let query = SIMD3<Float>(adjustedL, oklab.y, oklab.z)
        let linearOut: SIMD3<Float>
        switch colorSpace {
        case .sRGB: linearOut = ColorConversion.oklabToLinearSRGB(query)
        case .displayP3: linearOut = ColorConversion.oklabToLinearP3(query)
        }
        return simd_clamp(
            SIMD3<Float>(
                ColorConversion.sRGBEncode(linearOut.x),
                ColorConversion.sRGBEncode(linearOut.y),
                ColorConversion.sRGBEncode(linearOut.z)
            ),
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(1, 1, 1)
        )
    }

    @Test func linearLightAverageAllTransparentReturnsZeroLinearRGBAndZeroAlpha() {
        let pixels = [UInt8](repeating: 0, count: 16)  // 2x2 all-zero RGBA8
        let lab = SamplingPolicies.linearLightAverage(pixels: pixels, width: 2, height: 2)
        #expect(lab.linearRGB == SIMD3<Float>(0, 0, 0))
        #expect(lab.alpha == 0)
    }
}
