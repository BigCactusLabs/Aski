import Testing
import Foundation
import simd
@testable import Aski

@Suite struct ColorConversionTests {
    @Test func sRGBWhiteToOKLAB() {
        // Per Ottosson: linear-sRGB (1,1,1) → OKLAB (1.0, 0, 0) within ~1e-4
        let oklab = ColorConversion.linearSRGBToOKLAB(SIMD3(1, 1, 1))
        #expect(abs(oklab.x - 1.0) < 0.001)
        #expect(abs(oklab.y) < 0.001)
        #expect(abs(oklab.z) < 0.001)
    }

    @Test func sRGBBlackToOKLAB() {
        let oklab = ColorConversion.linearSRGBToOKLAB(SIMD3(0, 0, 0))
        #expect(abs(oklab.x) < 0.001)
    }

    @Test func sRGBRoundTripIdentity() {
        let samples: [SIMD3<Float>] = [
            SIMD3(0.5, 0.5, 0.5),
            SIMD3(0.8, 0.2, 0.1),
            SIMD3(0.1, 0.6, 0.9),
            SIMD3(1.0, 0.0, 0.5),
        ]
        for rgb in samples {
            let oklab = ColorConversion.linearSRGBToOKLAB(rgb)
            let back = ColorConversion.oklabToLinearSRGB(oklab)
            let delta = simd_length(back - rgb)
            #expect(delta < 1.0 / 255.0, "round-trip failed for \(rgb), delta=\(delta)")
        }
    }

    @Test func sRGBTransferRoundTrip() {
        // Exercise both sides of the piecewise split (threshold 0.04045 encoded /
        // 0.0031308 linear) plus the endpoints, since a typo in either constant
        // silently breaks gamma handling for entire ranges of input.
        let samples: [Float] = [0.0, 0.001, 0.0031308, 0.04045, 0.5, 0.9, 1.0]
        for encoded in samples {
            let linear = ColorConversion.sRGBDecode(encoded)
            let back = ColorConversion.sRGBEncode(linear)
            #expect(abs(back - encoded) < 1e-5, "transfer round-trip failed for \(encoded), back=\(back)")
        }
    }

    @Test func p3WhiteToOKLAB() {
        // Display P3 white is the same physical color as sRGB white (both D65).
        // Linear-P3 (1,1,1) → OKLAB L=1, a=b=0. Asserting all three channels
        // catches row-swap bugs that would leave L near 1 but wreck chromaticity.
        let oklab = ColorConversion.linearP3ToOKLAB(SIMD3(1, 1, 1))
        #expect(abs(oklab.x - 1.0) < 0.002)
        #expect(abs(oklab.y) < 0.002)
        #expect(abs(oklab.z) < 0.002)
    }

    @Test func p3WiderGamutThanSRGB() {
        // A saturated P3 red (outside sRGB gamut) should have higher |a| than
        // saturated sRGB red converted through the sRGB path.
        let p3Red = ColorConversion.linearP3ToOKLAB(SIMD3(1, 0, 0))
        let srgbRed = ColorConversion.linearSRGBToOKLAB(SIMD3(1, 0, 0))
        #expect(p3Red.y > srgbRed.y)  // larger a-channel for more saturated red
    }

    @Test func linearP3ToOKLABMatchesCSSReferencePrimaries() {
        // Pinned against CSS Color 4 / Color.js OKLab's Display-P3 fused matrix.
        let samples: [(rgb: SIMD3<Float>, expected: SIMD3<Float>)] = [
            (
                SIMD3(1, 0, 0),
                SIMD3(0.648574070, 0.262041753, 0.145001931)
            ),
            (
                SIMD3(0, 1, 0),
                SIMD3(0.848829289, -0.304240527, 0.207967431)
            ),
            (
                SIMD3(0, 0, 1),
                SIMD3(0.466360537, -0.033487149, -0.321415991)
            ),
        ]

        for sample in samples {
            let actual = ColorConversion.linearP3ToOKLAB(sample.rgb)
            let delta = simd_length(actual - sample.expected)
            #expect(delta < 2e-5, "P3 OKLab reference mismatch for \(sample.rgb), got \(actual), delta=\(delta)")
        }
    }

    @Test func oklabToLinearP3MatchesCSSReferenceInverse() {
        let p3BlueOKLab = SIMD3<Float>(0.466360537, -0.033487149, -0.321415991)

        let actual = ColorConversion.oklabToLinearP3(p3BlueOKLab)
        let expected = SIMD3<Float>(0, 0, 1)
        let delta = simd_length(actual - expected)

        #expect(delta < 2e-4, "P3 inverse reference mismatch, got \(actual), delta=\(delta)")
    }

    @Test func p3RoundTripIdentity() {
        let samples: [SIMD3<Float>] = [
            SIMD3(0.5, 0.5, 0.5),
            SIMD3(1.0, 0.0, 0.0),
            SIMD3(0.0, 1.0, 0.0),
            SIMD3(0.2, 0.6, 0.9),
        ]
        for rgb in samples {
            let oklab = ColorConversion.linearP3ToOKLAB(rgb)
            let back = ColorConversion.oklabToLinearP3(oklab)
            let delta = simd_length(back - rgb)
            #expect(delta < 1.0 / 255.0, "P3 round-trip failed for \(rgb), delta=\(delta)")
        }
    }

    @Test func ansi16PinnedOKLABRegression() {
        // Silent-drift gate for the cube-root primitive in linearSRGBToOKLAB.
        //
        // Inputs: every color declared in BuiltInPalette.ansi16. Reading from
        // the canonical palette (instead of retyping literals) means a future
        // change to the palette declaration flows through this test naturally
        // rather than silently bypassing it.
        //
        // Reference: composes ColorConversion.sRGBDecode (transfer), the
        // internal FUSED_LINEAR_SRGB_TO_LMS matrix, a Float64 cube root via
        // Foundation/Darwin, and the internal LMS_PRIME_TO_OKLAB matrix. The
        // reference does NOT call linearSRGBToOKLAB — it's an independent
        // path, so a buggy production swap cannot bless its own output.
        //
        // The cuberoot-accuracy lab (PR #14) established that darwin_cbrtf is
        // bit-exact to Float(cbrt(Double(x))) across the LMS sweep, so this
        // test passes iff the production cube root is the Float64-correctly-
        // rounded value. Future regressions caught: a swap to vvcbrtf (lab
        // showed up to 2 ULP drift) or a regression to the sign*pow idiom.
        //
        // Swap rationale recorded in the private development archive.

        guard let ansi16Colors = BuiltInPalette.ansi16.content.colors else {
            Issue.record("BuiltInPalette.ansi16 is not a .fixed palette; test is stale.")
            return
        }
        #expect(ansi16Colors.count == 16, "BuiltInPalette.ansi16 declared \(ansi16Colors.count) colors, expected 16")

        for (index, paletteColor) in ansi16Colors.enumerated() {
            #expect(paletteColor.colorSpace == .sRGB, "ANSI16[\(index)] color space changed; test assumes sRGB.")

            let linear = SIMD3<Float>(
                ColorConversion.sRGBDecode(paletteColor.components.x),
                ColorConversion.sRGBDecode(paletteColor.components.y),
                ColorConversion.sRGBDecode(paletteColor.components.z)
            )

            // Reference path: Float64 cube root between the production matrices.
            let lms = ColorConversion.FUSED_LINEAR_SRGB_TO_LMS * linear
            let lmsPrime = SIMD3<Float>(
                Float(cbrt(Double(lms.x))),
                Float(cbrt(Double(lms.y))),
                Float(cbrt(Double(lms.z)))
            )
            let expected = ColorConversion.LMS_PRIME_TO_OKLAB * lmsPrime

            // Production path:
            let actual = ColorConversion.linearSRGBToOKLAB(linear)

            #expect(
                actual.x.bitPattern == expected.x.bitPattern
                    && actual.y.bitPattern == expected.y.bitPattern
                    && actual.z.bitPattern == expected.z.bitPattern,
                """
                ANSI16[\(index)] sRGB \(paletteColor.components) OKLAB cbrt drift:
                  actual   L=\(actual.x.bitPattern) a=\(actual.y.bitPattern) b=\(actual.z.bitPattern)
                  expected L=\(expected.x.bitPattern) a=\(expected.y.bitPattern) b=\(expected.z.bitPattern)
                """
            )
        }
    }

    @Test func p3PrimariesPinnedOKLABRegression() {
        // Silent-drift gate for the cube-root primitive in linearP3ToOKLAB.
        // Counterpart to ansi16PinnedOKLABRegression for the P3 conversion path.
        //
        // Inputs: the four P3 mathematical-anchor primaries. There is no
        // P3-equivalent of BuiltInPalette.ansi16 in production code, so the
        // inputs are hardcoded — but the REFERENCE is still computed
        // independently of linearP3ToOKLAB, which is the point.
        //
        // The existing linearP3ToOKLABMatchesCSSReferencePrimaries uses a
        // < 2e-5 tolerance against CSS Color 4 reference values; the cube-
        // root error after the matrix multiply is ~5e-7 worst-case, well
        // under that bound, so it cannot detect a cube-root regression on
        // its own. This test closes that gap.

        let p3Inputs: [(name: String, rgb: SIMD3<Float>)] = [
            ("red", SIMD3(1, 0, 0)),
            ("green", SIMD3(0, 1, 0)),
            ("blue", SIMD3(0, 0, 1)),
            ("white", SIMD3(1, 1, 1)),
        ]

        for (name, rgb) in p3Inputs {
            // Inputs are already-linear P3; linearP3ToOKLAB does not transfer-decode.

            // Reference path: Float64 cube root between the production matrices.
            let lms = ColorConversion.FUSED_LINEAR_P3_TO_LMS * rgb
            let lmsPrime = SIMD3<Float>(
                Float(cbrt(Double(lms.x))),
                Float(cbrt(Double(lms.y))),
                Float(cbrt(Double(lms.z)))
            )
            let expected = ColorConversion.LMS_PRIME_TO_OKLAB * lmsPrime

            // Production path:
            let actual = ColorConversion.linearP3ToOKLAB(rgb)

            #expect(
                actual.x.bitPattern == expected.x.bitPattern
                    && actual.y.bitPattern == expected.y.bitPattern
                    && actual.z.bitPattern == expected.z.bitPattern,
                """
                P3 \(name) \(rgb) OKLAB cbrt drift:
                  actual   L=\(actual.x.bitPattern) a=\(actual.y.bitPattern) b=\(actual.z.bitPattern)
                  expected L=\(expected.x.bitPattern) a=\(expected.y.bitPattern) b=\(expected.z.bitPattern)
                """
            )
        }
    }
}
