import Testing
import simd
@_spi(AskiResearch) @testable import Aski

@Suite struct PaletteMatchingPolicyTests {
    @Test func oklabEuclideanReturnsClosestResolvedPaletteEntry() {
        let black = ResolvedPaletteColor(
            source: PaletteColor(SIMD3<Float>(0, 0, 0)),
            oklab: SIMD3<Float>(0, 0, 0)
        )
        let white = ResolvedPaletteColor(
            source: PaletteColor(SIMD3<Float>(1, 1, 1)),
            oklab: SIMD3<Float>(1, 0, 0)
        )
        let mid = ResolvedPaletteColor(
            source: PaletteColor(SIMD3<Float>(0.5, 0.5, 0.5)),
            oklab: SIMD3<Float>(0.5, 0, 0)
        )

        #expect(nearestPaletteMatch(SIMD3<Float>(0.95, 0.001, 0.001), palette: [black, white], policy: .oklabEuclidean) == white.oklab)
        #expect(nearestPaletteMatch(SIMD3<Float>(0.05, 0.001, 0.001), palette: [black, white], policy: .oklabEuclidean) == black.oklab)
        #expect(nearestPaletteMatch(SIMD3<Float>(0.5, 0, 0), palette: [black, mid, white], policy: .oklabEuclidean) == mid.oklab)
    }

    @Test func oklabHyABReturnsClosestResolvedPaletteEntry() {
        let black = ResolvedPaletteColor(
            source: PaletteColor(SIMD3<Float>(0, 0, 0)),
            oklab: SIMD3<Float>(0, 0, 0)
        )
        let white = ResolvedPaletteColor(
            source: PaletteColor(SIMD3<Float>(1, 1, 1)),
            oklab: SIMD3<Float>(1, 0, 0)
        )

        #expect(nearestPaletteMatch(SIMD3<Float>(0.95, 0.001, 0.001), palette: [black, white], policy: .oklabHyAB) == white.oklab)
        #expect(nearestPaletteMatch(SIMD3<Float>(0.05, 0.001, 0.001), palette: [black, white], policy: .oklabHyAB) == black.oklab)
    }

    /// Divergence-pin for HyAB vs Euclidean — ported from the lab fixture at
    /// `Tools/AskiColorLab/PaletteMatching/PaletteMatchFixtures.swift:77-101`.
    /// Source sits between a chroma-neighbor (index 4, yellow-olive) and a
    /// lightness-neighbor (index 5, light pink); Euclidean picks lightness,
    /// HyAB picks chroma. Catches a regression in the HyAB dispatch.
    @Test func oklabHyABDivergesFromEuclideanOnNearBisectorFixture() {
        let paletteColors: [PaletteColor] = [
            PaletteColor(SIMD3<Float>(0.20, 0.20, 0.20), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(0.85, 0.85, 0.85), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(0.95, 0.05, 0.05), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(0.40, 0.65, 0.40), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(0.55, 0.55, 0.20), colorSpace: .sRGB),  // chroma neighbor
            PaletteColor(SIMD3<Float>(0.85, 0.55, 0.55), colorSpace: .sRGB),  // lightness neighbor
        ]
        let resolved = paletteColors.map { color in
            ResolvedPaletteColor(source: color, oklab: paletteMatchingTestSRGBToOKLab(color.components))
        }
        let source = paletteMatchingTestSRGBToOKLab(SIMD3<Float>(0.46, 0.50, 0.80))

        let euclideanMatch = nearestPaletteMatch(source, palette: resolved, policy: .oklabEuclidean)
        let hyABMatch = nearestPaletteMatch(source, palette: resolved, policy: .oklabHyAB)

        #expect(euclideanMatch == resolved[5].oklab, "Euclidean should pick lightness neighbor (index 5)")
        #expect(hyABMatch == resolved[4].oklab, "HyAB should pick chroma neighbor (index 4)")
        #expect(euclideanMatch != hyABMatch, "Fixture must remain divergent")
    }

    /// Built-in palette regression — per addendum §5, ansi16 must produce zero
    /// divergence under HyAB vs Euclidean. Source queries are the lab's
    /// synthetic_srgb ablation sources (the exact inputs that validated zero
    /// built-in divergence on regen).
    @Test func ansi16BuiltInProducesIdenticalMatchesUnderBothPolicies() {
        let palette = ResolvedPalette(content: BuiltInPalette.ansi16.content)
        for source in paletteMatchingTestBuiltInSourceQueries() {
            let euclidean = nearestPaletteMatch(source, palette: palette.colors, policy: .oklabEuclidean)
            let hyAB = nearestPaletteMatch(source, palette: palette.colors, policy: .oklabHyAB)
            #expect(euclidean == hyAB, "ansi16: HyAB diverged from Euclidean on OKLab \(source)")
        }
    }

    @Test func monochromeBuiltInProducesIdenticalMatchesUnderBothPolicies() {
        let palette = ResolvedPalette(content: BuiltInPalette.monochrome.content)
        for source in paletteMatchingTestBuiltInSourceQueries() {
            let euclidean = nearestPaletteMatch(source, palette: palette.colors, policy: .oklabEuclidean)
            let hyAB = nearestPaletteMatch(source, palette: palette.colors, policy: .oklabHyAB)
            #expect(euclidean == hyAB, "monochrome: HyAB diverged from Euclidean on OKLab \(source)")
        }
    }

    @Test func helmlabPoliciesReportNeedsHelmlab() {
        #expect(PaletteMatchingPolicy.helmlabEuclidean.needsHelmlab)
        #expect(PaletteMatchingPolicy.helmlabCompressed.needsHelmlab)
        #expect(!PaletteMatchingPolicy.oklabEuclidean.needsHelmlab)
        #expect(!PaletteMatchingPolicy.oklabHyAB.needsHelmlab)
    }

    @Test func helmlabPoliciesRecoverExactPaletteEntry() {
        func resolved(_ rgb: SIMD3<Float>) -> ResolvedPaletteColor {
            let linearD = SIMD3<Double>(
                Double(ColorConversion.sRGBDecode(rgb.x)),
                Double(ColorConversion.sRGBDecode(rgb.y)),
                Double(ColorConversion.sRGBDecode(rgb.z))
            )
            let linearF = SIMD3<Float>(
                ColorConversion.sRGBDecode(rgb.x),
                ColorConversion.sRGBDecode(rgb.y),
                ColorConversion.sRGBDecode(rgb.z)
            )
            return ResolvedPaletteColor(
                source: PaletteColor(rgb, colorSpace: .sRGB),
                oklab: ColorConversion.linearSRGBToOKLAB(linearF),
                helmlab: HelmlabMetric.xyzToHelmlabMetric(ColorConversion.linearSRGBToXYZ(linearD))
            )
        }
        let black = resolved(SIMD3(0, 0, 0))
        let red = resolved(SIMD3(1, 0, 0))
        let palette = [black, red]
        // Query == red's OKLab → must select red under both Helmlab policies.
        for policy in [PaletteMatchingPolicy.helmlabEuclidean, .helmlabCompressed] {
            #expect(nearestPaletteMatch(red.oklab, palette: palette, policy: policy) == red.oklab)
        }
    }
}

private func paletteMatchingTestSRGBToOKLab(_ encoded: SIMD3<Float>) -> SIMD3<Float> {
    ColorConversion.linearSRGBToOKLAB(
        SIMD3<Float>(
            ColorConversion.sRGBDecode(encoded.x),
            ColorConversion.sRGBDecode(encoded.y),
            ColorConversion.sRGBDecode(encoded.z)
        )
    )
}

private func paletteMatchingTestBuiltInSourceQueries() -> [SIMD3<Float>] {
    [
        paletteMatchingTestSRGBToOKLab(SIMD3<Float>(0.20, 0.20, 0.20)),
        paletteMatchingTestSRGBToOKLab(SIMD3<Float>(0.50, 0.50, 0.50)),
        paletteMatchingTestSRGBToOKLab(SIMD3<Float>(0.30, 0.05, 0.05)),
        paletteMatchingTestSRGBToOKLab(SIMD3<Float>(0.65, 0.65, 0.65)),
        paletteMatchingTestSRGBToOKLab(SIMD3<Float>(0.46, 0.50, 0.80)),
    ]
}
