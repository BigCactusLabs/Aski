@_spi(AskiResearch) @testable import Aski  // internal: ResolvedPalette(content:needsHelmlab:) + .helmlab; SPI: HelmlabMetric
import Testing
import simd

@Suite struct ResolvedPaletteHelmlabTests {
    @Test func helmlabFieldIsNilWhenNotNeeded() {
        let resolved = ResolvedPalette(content: BuiltInPalette.ansi16.content, needsHelmlab: false)
        #expect(resolved.colors.allSatisfy { $0.helmlab == nil })
    }

    @Test func helmlabFieldIsPopulatedWhenNeeded() {
        let resolved = ResolvedPalette(content: BuiltInPalette.ansi16.content, needsHelmlab: true)
        #expect(resolved.colors.allSatisfy { $0.helmlab != nil })
        // Sanity: a known entry's Helmlab matches the direct transform.
        let first = resolved.colors[0]
        if let helmlab = first.helmlab, let source = first.source {
            let linear = SIMD3<Double>(
                Double(ColorConversion.sRGBDecode(source.components.x)),
                Double(ColorConversion.sRGBDecode(source.components.y)),
                Double(ColorConversion.sRGBDecode(source.components.z))
            )
            let expected = HelmlabMetric.xyzToHelmlabMetric(ColorConversion.linearSRGBToXYZ(linear))
            #expect(simd_length(helmlab - expected) < 1e-9)
        }
    }

    @Test func oklabColorsInitLeavesHelmlabNil() {
        let resolved = ResolvedPalette(oklabColors: [SIMD3<Float>(0.5, 0, 0)])
        #expect(resolved.colors[0].helmlab == nil)
    }
}
