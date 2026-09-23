import Testing
import simd
@testable import Aski

@Suite struct GamutMappingTests {

    @Test func inGamutIsIdempotent() {
        // Mid-gray linear sRGB round-trips through OKLAB and back to itself —
        // the fast path returns the clamped round-trip.
        let oklab = ColorConversion.linearSRGBToOKLAB(SIMD3<Float>(0.5, 0.5, 0.5))
        let mapped = GamutMapping.adaptiveL0ToSRGB(oklab)
        let original = ColorConversion.oklabToLinearSRGB(oklab)
        let delta = simd_length(mapped - original)
        #expect(delta < 0.005)
    }

    @Test func outOfGamutProducesInGamutOutput() {
        // High-chroma OKLAB that `oklabToLinearSRGB` sends outside [0, 1].
        // Projection must return channels strictly in [0, 1] after final clamp.
        let outOfGamut = SIMD3<Float>(0.7, 0.3, 0.2)
        let mapped = GamutMapping.adaptiveL0ToSRGB(outOfGamut)
        #expect(mapped.x >= 0 && mapped.x <= 1)
        #expect(mapped.y >= 0 && mapped.y <= 1)
        #expect(mapped.z >= 0 && mapped.z <= 1)
    }

    @Test func achromaticOutOfGamutClampsToRange() {
        // L=1.5 with zero chroma maps to (3.375, 3.375, 3.375) in linear sRGB
        // (every LMS→RGB row sums to 1 by D65 calibration). The projection's
        // C<1e-6 short-circuit must clamp to (1, 1, 1) instead of running the
        // binary search (which has no meaningful answer for zero-chroma input).
        let superWhite = SIMD3<Float>(1.5, 0, 0)
        let mapped = GamutMapping.adaptiveL0ToSRGB(superWhite)
        #expect(abs(mapped.x - 1) < 0.001)
        #expect(abs(mapped.y - 1) < 0.001)
        #expect(abs(mapped.z - 1) < 0.001)
    }

    @Test func projectionIsIdempotentOnBoundary() {
        // Projecting an out-of-gamut input lands on the gamut boundary. Feeding
        // that boundary point back through `projectToSRGBGamut` directly — bypassing
        // the public fast-path short-circuit that would trivially pass — must
        // return approximately the same point. A projection is a fixed-point
        // operation on its target set; the binary search must recognize in-gamut
        // test points and converge t → 1.
        let outOfGamut = SIMD3<Float>(0.7, 0.3, 0.2)
        let boundary = GamutMapping.projectToSRGBGamut(outOfGamut)
        let boundaryOKLAB = ColorConversion.linearSRGBToOKLAB(boundary)
        let reprojected = GamutMapping.projectToSRGBGamut(boundaryOKLAB)
        let delta = simd_length(reprojected - boundary)
        #expect(delta < 0.01)
    }

    @Test func displayP3MappingPreservesP3Primary() {
        let p3RedOKLAB = ColorConversion.linearP3ToOKLAB(SIMD3<Float>(1, 0, 0))
        let mapped = GamutMapping.adaptiveL0ToDisplayP3(p3RedOKLAB)

        #expect(abs(mapped.x - 1) < 0.005)
        #expect(abs(mapped.y) < 0.005)
        #expect(abs(mapped.z) < 0.005)
    }

    @Test func clipPolicyClampsEncodedOutputChannels() {
        let superWhite = mapToDisplayColor(
            for: SIMD3<Float>(1.5, 0, 0),
            colorSpace: .sRGB,
            policy: .clip
        )
        #expect(abs(superWhite.x - 1) < 0.001)
        #expect(abs(superWhite.y - 1) < 0.001)
        #expect(abs(superWhite.z - 1) < 0.001)

        let belowBlack = mapToDisplayColor(
            for: SIMD3<Float>(-0.2, 0, 0),
            colorSpace: .sRGB,
            policy: .clip
        )
        #expect(abs(belowBlack.x) < 0.001)
        #expect(abs(belowBlack.y) < 0.001)
        #expect(abs(belowBlack.z) < 0.001)
    }

    @Test func rayTraceInGamutChromaticPassesThroughUntouched() {
        let hueRadians = Float(90) * .pi / 180
        let oklab = SIMD3<Float>(
            0.5,
            0.1 * cos(hueRadians),
            0.1 * sin(hueRadians)
        )
        let mapped = GamutMapping.rayTraceToSRGB(oklab)
        let direct = ColorConversion.oklabToLinearSRGB(oklab)

        #expect(mapped.x == direct.x)
        #expect(mapped.y == direct.y)
        #expect(mapped.z == direct.z)
    }

    @Test func rayTraceLightnessGuardsReturnWhiteAndBlack() {
        let white = GamutMapping.rayTraceToSRGB(SIMD3<Float>(1.044, 0, 0))
        #expect(abs(white.x - 1) < 0.005)
        #expect(abs(white.y - 1) < 0.005)
        #expect(abs(white.z - 1) < 0.005)

        let black = GamutMapping.rayTraceToDisplayP3(SIMD3<Float>(0, 0.1, 0))
        #expect(abs(black.x) < 0.005)
        #expect(abs(black.y) < 0.005)
        #expect(abs(black.z) < 0.005)
    }

    @Test func rayTraceOutOfGamutReturnsInGamutForBothTargets() {
        let deepMagenta = oklabFromOkLCh(L: 0.5, C: 0.8, hueDegrees: 315)
        let srgb = GamutMapping.rayTraceToSRGB(deepMagenta)
        let p3 = GamutMapping.rayTraceToDisplayP3(deepMagenta)

        for component in [srgb.x, srgb.y, srgb.z, p3.x, p3.y, p3.z] {
            #expect(component >= 0)
            #expect(component <= 1)
            #expect(component.isFinite)
        }
    }

    @Test func rayTraceDiffersFromClipAndPreservesLightnessOnCyanPeak() {
        let cyanPeak = oklabFromOkLCh(L: 0.75, C: 0.4, hueDegrees: 195)
        let rayTrace = GamutMapping.rayTraceToSRGB(cyanPeak)
        let clip = simd_clamp(
            ColorConversion.oklabToLinearSRGB(cyanPeak),
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(1, 1, 1)
        )

        #expect(simd_length(rayTrace - clip) > 0.01)
        let mappedOKLab = ColorConversion.linearSRGBToOKLAB(rayTrace)
        #expect(abs(mappedOKLab.x - 0.75) < 0.05)
    }

    @Test func rayTraceOutOfGamutLandsOnCubeFace() {
        let yellow = oklabFromOkLCh(L: 0.95, C: 0.8, hueDegrees: 105)
        let mapped = GamutMapping.rayTraceToSRGB(yellow)
        let epsilon: Float = 1e-3
        let touchesFace =
            mapped.x <= epsilon || mapped.x >= 1 - epsilon
            || mapped.y <= epsilon || mapped.y >= 1 - epsilon
            || mapped.z <= epsilon || mapped.z >= 1 - epsilon

        #expect(touchesFace)
    }

    @Test func rayTraceDegenerateRayIntersectionReturnsThroughColor() {
        let through = SIMD3<Float>(0.25, 0.5, 0.75)
        let mapped = GamutMapping.rayTraceBoxIntersection(from: through, through: through)

        #expect(mapped.x == through.x)
        #expect(mapped.y == through.y)
        #expect(mapped.z == through.z)
    }

    @Test func mapToDisplayColorRoutesRayTraceForSRGBAndDisplayP3() {
        let oklab = oklabFromOkLCh(L: 0.75, C: 0.4, hueDegrees: 195)

        let srgb = mapToDisplayColor(for: oklab, colorSpace: .sRGB, policy: .rayTrace)
        let expectedSRGB = encodedDisplayRGB(GamutMapping.rayTraceToSRGB(oklab))
        #expect(simd_length(srgb - expectedSRGB) < 1e-6)

        let p3 = mapToDisplayColor(for: oklab, colorSpace: .displayP3, policy: .rayTrace)
        let expectedP3 = encodedDisplayRGB(GamutMapping.rayTraceToDisplayP3(oklab))
        #expect(simd_length(p3 - expectedP3) < 1e-6)
    }
}

private func oklabFromOkLCh(L: Float, C: Float, hueDegrees: Float) -> SIMD3<Float> {
    let hueRadians = hueDegrees * .pi / 180
    return SIMD3<Float>(
        L,
        C * cos(hueRadians),
        C * sin(hueRadians)
    )
}

private func encodedDisplayRGB(_ linearRGB: SIMD3<Float>) -> SIMD3<Float> {
    simd_clamp(
        SIMD3(
            ColorConversion.sRGBEncode(linearRGB.x),
            ColorConversion.sRGBEncode(linearRGB.y),
            ColorConversion.sRGBEncode(linearRGB.z)
        ),
        SIMD3<Float>(0, 0, 0),
        SIMD3<Float>(1, 1, 1)
    )
}
