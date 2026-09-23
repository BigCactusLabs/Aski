import Testing
import simd
@testable import Aski

@Suite struct ResolvedPaletteTests {
    @Test func passThroughResolvesWithoutColors() {
        let resolved = ResolvedPalette(content: .passThrough)

        #expect(resolved.isPassThrough)
        #expect(resolved.colors.isEmpty)
    }

    @Test func srgbPaletteColorResolvesThroughOKLABPath() {
        let color = PaletteColor(SIMD3<Float>(0.5, 0, 0), colorSpace: .sRGB)
        let resolved = ResolvedPalette(content: .fixed([color]))
        let expected = ColorConversion.linearSRGBToOKLAB(
            SIMD3<Float>(
                ColorConversion.sRGBDecode(0.5),
                ColorConversion.sRGBDecode(0),
                ColorConversion.sRGBDecode(0)
            ))

        #expect(resolved.colors.count == 1)
        #expect(simd_length(resolved.colors[0].oklab - expected) < 1e-6)
        #expect(resolved.colors[0].source == color)
    }

    @Test func displayP3PaletteColorUsesP3Matrix() {
        let color = PaletteColor(SIMD3<Float>(1, 0, 0), colorSpace: .displayP3)
        let resolved = ResolvedPalette(content: .fixed([color]))
        let expected = ColorConversion.linearP3ToOKLAB(
            SIMD3<Float>(
                ColorConversion.sRGBDecode(1),
                ColorConversion.sRGBDecode(0),
                ColorConversion.sRGBDecode(0)
            ))

        #expect(simd_length(resolved.colors[0].oklab - expected) < 1e-6)
    }

    @Test func oklabInitializerPreservesSyntheticPaletteValues() {
        let oklabColors = [
            SIMD3<Float>(0.1, 0.2, 0.3),
            SIMD3<Float>(0.7, -0.1, 0.05),
        ]
        let resolved = ResolvedPalette(oklabColors: oklabColors)

        #expect(!resolved.isPassThrough)
        #expect(resolved.colors.count == oklabColors.count)
        #expect(resolved.colors.map(\.oklab) == oklabColors)
        #expect(resolved.colors.allSatisfy { $0.source == nil })
    }

    #if !SWT_NO_EXIT_TESTS
        @Test func emptyOKLABInitializerFailsPrecondition() async {
            await #expect(processExitsWith: .failure) {
                _ = ResolvedPalette(oklabColors: [])
            }
        }
    #endif

    @Test func ansi16ResolvedValuesMatchOKLABConversion() {
        let literals: [SIMD3<Float>] = [
            SIMD3(0.00, 0.00, 0.00),
            SIMD3(0.50, 0.00, 0.00),
            SIMD3(0.00, 0.50, 0.00),
            SIMD3(0.50, 0.50, 0.00),
            SIMD3(0.00, 0.00, 0.50),
            SIMD3(0.50, 0.00, 0.50),
            SIMD3(0.00, 0.50, 0.50),
            SIMD3(0.75, 0.75, 0.75),
            SIMD3(0.50, 0.50, 0.50),
            SIMD3(1.00, 0.00, 0.00),
            SIMD3(0.00, 1.00, 0.00),
            SIMD3(1.00, 1.00, 0.00),
            SIMD3(0.00, 0.00, 1.00),
            SIMD3(1.00, 0.00, 1.00),
            SIMD3(0.00, 1.00, 1.00),
            SIMD3(1.00, 1.00, 1.00),
        ]
        let resolved = ResolvedPalette(content: BuiltInPalette.ansi16.content)

        #expect(resolved.colors.count == literals.count)
        for index in literals.indices {
            let encoded = literals[index]
            let expected = ColorConversion.linearSRGBToOKLAB(
                SIMD3<Float>(
                    ColorConversion.sRGBDecode(encoded.x),
                    ColorConversion.sRGBDecode(encoded.y),
                    ColorConversion.sRGBDecode(encoded.z)
                ))
            #expect(simd_length(resolved.colors[index].oklab - expected) < 1e-6)
        }
    }
}
