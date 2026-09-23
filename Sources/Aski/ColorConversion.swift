import simd
import CoreGraphics

/// Color space conversion utilities. All matrices are pre-multiplied (fused) so
/// we never detour through gamma-encoded sRGB for wide-gamut inputs.
///
/// References:
/// - Björn Ottosson — OKLAB: https://bottosson.github.io/posts/oklab/
/// - CSS Color 4 §17 sample code: https://www.w3.org/TR/css-color-4/#color-conversion-code
public enum ColorConversion {
    private static let cgSRGBColorSpace =
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static let cgDisplayP3ColorSpace =
        CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

    // MARK: - Fused linear RGB → LMS matrices
    //
    // Fused through the CSS Color 4 / Color.js OKLab XYZ → LMS basis.
    // For linear-P3 we compose (linear-P3 → XYZ(D65)) × (XYZ → LMS) offline.
    // The prior P3 matrix used Ottosson's older XYZ → LMS basis; keeping both
    // target gamuts on the same basis avoids sRGB/P3 OKLab drift.

    internal static let FUSED_LINEAR_SRGB_TO_LMS = simd_float3x3(rows: [
        SIMD3<Float>(0.4122214708, 0.5363325363, 0.0514459929),
        SIMD3<Float>(0.2119034982, 0.6806995451, 0.1073969566),
        SIMD3<Float>(0.0883024619, 0.2817188376, 0.6299787005),
    ])

    internal static let LMS_PRIME_TO_OKLAB = simd_float3x3(rows: [
        SIMD3<Float>(0.2104542553, 0.7936177850, -0.0040720468),
        SIMD3<Float>(1.9779984951, -2.4285922050, 0.4505937099),
        SIMD3<Float>(0.0259040371, 0.7827717662, -0.8086757660),
    ])

    private static let OKLAB_TO_LMS_PRIME = simd_float3x3(rows: [
        SIMD3<Float>(1.0, 0.3963377774, 0.2158037573),
        SIMD3<Float>(1.0, -0.1055613458, -0.0638541728),
        SIMD3<Float>(1.0, -0.0894841775, -1.2914855480),
    ])

    private static let LMS_TO_LINEAR_SRGB = simd_float3x3(rows: [
        SIMD3<Float>(4.0767416621, -3.3077115913, 0.2309699292),
        SIMD3<Float>(-1.2684380046, 2.6097574011, -0.3413193965),
        SIMD3<Float>(-0.0041960863, -0.7034186147, 1.7076147010),
    ])

    // Linear Display-P3 → LMS, computed as (P3→XYZ(D65)) × (XYZ→LMS) offline.
    // Using CSS Color 4 §17 P3→XYZ and CSS/Color.js OKLab XYZ→LMS.
    internal static let FUSED_LINEAR_P3_TO_LMS = simd_float3x3(rows: [
        SIMD3<Float>(0.4813798527, 0.4621183710, 0.0565017762),
        SIMD3<Float>(0.2288319418, 0.6532168194, 0.1179512388),
        SIMD3<Float>(0.0839457523, 0.2241652710, 0.6918889767),
    ])

    private static let LMS_TO_LINEAR_P3 = simd_inverse(FUSED_LINEAR_P3_TO_LMS)

    // MARK: - Linear RGB → XYZ (D65), Double precision
    //
    // Standard CSS Color 4 §17 matrices. Used by the Helmlab MetricSpace port,
    // which runs in Double to validate tightly against the Python reference
    // (see HelmlabMetric.swift). `oklabToLinearSRGB` ∘ `linearSRGBToXYZ`
    // composes to a gamut-invariant OKLab → XYZ(D65).

    private static let LINEAR_SRGB_TO_XYZ_D65 = simd_double3x3(rows: [
        SIMD3<Double>(0.41239079926595934, 0.357584339383878, 0.1804807884018343),
        SIMD3<Double>(0.21263900587151027, 0.715168678767756, 0.07219231536073371),
        SIMD3<Double>(0.01933081871559182, 0.11919477979462598, 0.9505321522496607),
    ])

    private static let LINEAR_P3_TO_XYZ_D65 = simd_double3x3(rows: [
        SIMD3<Double>(0.4865709486482162, 0.26566769316909306, 0.1982172852343625),
        SIMD3<Double>(0.2289745640697488, 0.6917385218365064, 0.079286914093745),
        SIMD3<Double>(0.0, 0.04511338185890264, 1.043944368900976),
    ])

    /// Linear sRGB (gamma-decoded, may be out of 0...1) → CIE XYZ (D65).
    /// SPI, not public SDK API — only the Helmlab port (in-module) and the
    /// research lab/tests (`@_spi(AskiResearch) import`) consume it.
    @_spi(AskiResearch) public static func linearSRGBToXYZ(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        LINEAR_SRGB_TO_XYZ_D65 * rgb
    }

    /// Linear Display-P3 (gamma-decoded, may be out of 0...1) → CIE XYZ (D65). SPI (see above).
    @_spi(AskiResearch) public static func linearP3ToXYZ(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        LINEAR_P3_TO_XYZ_D65 * rgb
    }

    /// Linear sRGB (0..1, already gamma-decoded) → OKLAB.
    public static func linearSRGBToOKLAB(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        let lms = FUSED_LINEAR_SRGB_TO_LMS * rgb
        // cbrt handles negative LMS natively (IEEE 754 odd-degree-root sign
        // preservation). See cuberoot-accuracy lab evidence:
        // Tools/AskiColorLab/CuberootAccuracy/ and PR #14.
        let lmsPrime = SIMD3<Float>(
            cbrt(lms.x),
            cbrt(lms.y),
            cbrt(lms.z)
        )
        return LMS_PRIME_TO_OKLAB * lmsPrime
    }

    /// Linear Display-P3 (0..1, already gamma-decoded) → OKLAB.
    public static func linearP3ToOKLAB(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        let lms = FUSED_LINEAR_P3_TO_LMS * rgb
        // cbrt handles negative LMS natively. See linearSRGBToOKLAB.
        let lmsPrime = SIMD3<Float>(
            cbrt(lms.x),
            cbrt(lms.y),
            cbrt(lms.z)
        )
        return LMS_PRIME_TO_OKLAB * lmsPrime
    }

    /// OKLAB → linear sRGB (not yet gamma-encoded; may be out of 0..1 gamut).
    public static func oklabToLinearSRGB(_ oklab: SIMD3<Float>) -> SIMD3<Float> {
        let lmsPrime = OKLAB_TO_LMS_PRIME * oklab
        let lms = SIMD3<Float>(
            lmsPrime.x * lmsPrime.x * lmsPrime.x,
            lmsPrime.y * lmsPrime.y * lmsPrime.y,
            lmsPrime.z * lmsPrime.z * lmsPrime.z
        )
        return LMS_TO_LINEAR_SRGB * lms
    }

    /// OKLAB → linear Display-P3 (not yet transfer-encoded; may be out of 0..1 gamut).
    public static func oklabToLinearP3(_ oklab: SIMD3<Float>) -> SIMD3<Float> {
        let lmsPrime = OKLAB_TO_LMS_PRIME * oklab
        let lms = SIMD3<Float>(
            lmsPrime.x * lmsPrime.x * lmsPrime.x,
            lmsPrime.y * lmsPrime.y * lmsPrime.y,
            lmsPrime.z * lmsPrime.z * lmsPrime.z
        )
        return LMS_TO_LINEAR_P3 * lms
    }

    /// sRGB transfer function (gamma encode). Input: linear 0..1. Output: encoded 0..1.
    public static func sRGBEncode(_ x: Float) -> Float {
        x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1.0 / 2.4) - 0.055
    }

    /// sRGB inverse transfer function (gamma decode). Input: encoded 0..1. Output: linear 0..1.
    public static func sRGBDecode(_ x: Float) -> Float {
        x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }

    /// Convert a `CGColor` to OKLAB. The color is first converted to sRGB if
    /// it isn't already in sRGB or Display-P3, then sRGB-decoded to linear and
    /// matrixed to OKLAB. CMYK/indexed/unknown color spaces fall through via
    /// `CGColor.converted(to:intent:options:)`. If conversion fails, returns
    /// OKLAB black (caller's responsibility per spec §4).
    public static func cgColorToOKLAB(_ color: CGColor) -> SIMD3<Float> {
        // Fast path: sRGB or P3 input - read components directly.
        if let colorSpace = color.colorSpace {
            if colorSpace == cgSRGBColorSpace
                || colorSpace.name == CGColorSpace.sRGB
                || colorSpace.name == CGColorSpace.linearSRGB
            {
                guard let encoded = rgbTriple(from: color.components) else {
                    return SIMD3<Float>(0, 0, 0)
                }
                let linear =
                    colorSpace.name == CGColorSpace.linearSRGB
                    ? encoded
                    : SIMD3<Float>(
                        sRGBDecode(encoded.x), sRGBDecode(encoded.y), sRGBDecode(encoded.z))
                return linearSRGBToOKLAB(linear)
            }
            if colorSpace == cgDisplayP3ColorSpace || colorSpace.name == CGColorSpace.displayP3 {
                guard let encoded = rgbTriple(from: color.components) else {
                    return SIMD3<Float>(0, 0, 0)
                }
                let linear = SIMD3<Float>(
                    sRGBDecode(encoded.x), sRGBDecode(encoded.y), sRGBDecode(encoded.z))
                return linearP3ToOKLAB(linear)
            }
        }

        guard let converted = color.converted(to: cgSRGBColorSpace, intent: .perceptual, options: nil),
            let encoded = rgbTriple(from: converted.components)
        else {
            return SIMD3<Float>(0, 0, 0)
        }
        let linear = SIMD3<Float>(
            sRGBDecode(encoded.x), sRGBDecode(encoded.y), sRGBDecode(encoded.z))
        return linearSRGBToOKLAB(linear)
    }

    /// The leading RGB triple of a `CGColor` component list, or `nil` when the
    /// list is missing or carries fewer than three components. Every branch of
    /// `cgColorToOKLAB` reads components through here, so the fast paths cannot
    /// disagree with the `converted(to:)` path about whether the count is
    /// trustworthy — a short list degenerates to OKLAB black, never a trap.
    static func rgbTriple(from components: [CGFloat]?) -> SIMD3<Float>? {
        guard let components, components.count >= 3 else { return nil }
        return SIMD3<Float>(Float(components[0]), Float(components[1]), Float(components[2]))
    }
}
