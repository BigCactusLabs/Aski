import Foundation
import simd

/// Lab-local Porter-Duff source-over composite policies. None of these are
/// promoted to public Aski API; cross-comparison is this lab's purpose and any
/// production renderer flip is a separate Slice 3 decision.
public enum LinearCompositePolicies {

    /// Canonical CSV order — spec §Policies "Policy identifiers written to CSV
    /// are exactly: encoded8bit, linear8bit, linearFloat".
    public static let canonicalOrder: [Identifier] = [
        .encoded8bit,
        .linear8bit,
        .linearFloat,
    ]

    public enum Identifier: String, CaseIterable, Sendable {
        case encoded8bit
        case linear8bit
        case linearFloat

        public var csvLabel: String { rawValue }
    }

    /// CSV-serialization-ready output for one (fixture, policy) row. All three
    /// policies converge to this shape after the spec §Policies §"CSV
    /// serialization is unpremultiplied throughout" projection.
    public struct PolicyOutput: Sendable, Equatable {
        public let mappedLinearRGB: SIMD3<Float>  // unpremultiplied linear unit floats
        public let mappedEncodedRGB: SIMD3<Float>  // unpremultiplied encoded byte/255
        public let mappedAlphaByte: Int  // 0...255

        public init(
            mappedLinearRGB: SIMD3<Float>,
            mappedEncodedRGB: SIMD3<Float>,
            mappedAlphaByte: Int
        ) {
            self.mappedLinearRGB = mappedLinearRGB
            self.mappedEncodedRGB = mappedEncodedRGB
            self.mappedAlphaByte = mappedAlphaByte
        }
    }

    /// Banker's rounding (`Float.rounded(.toNearestOrEven)`). Spec §Policies
    /// "Quantization convention".
    @inline(__always)
    static func roundEven(_ x: Float) -> Float {
        x.rounded(.toNearestOrEven)
    }

    @inline(__always)
    static func roundEven(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(roundEven(rgb.x), roundEven(rgb.y), roundEven(rgb.z))
    }

    /// Baseline. Spec §Policies (1): premultiply, source-over, all in encoded
    /// 8-bit. Round-half-to-even at every quantization step. Returns the
    /// CSV-ready unpremultiplied form per §"CSV serialization is
    /// unpremultiplied throughout".
    public static func encoded8bit(
        fgByte: SIMD3<Float>,
        fgAlphaByte: Int,
        bgByte: SIMD3<Float>,
        bgAlphaByte: Int,
        target: LinearCompositeSpaces.TargetGamut
    ) -> PolicyOutput {
        _ = target  // shared transfer; target only matters for the linear paths.

        let alphaSrc = Float(fgAlphaByte)
        let alphaBg = Float(bgAlphaByte)
        let pSrc = roundEven((alphaSrc / 255.0) * fgByte)
        let pBg = roundEven((alphaBg / 255.0) * bgByte)
        let pOut = roundEven(pSrc + pBg * ((255.0 - alphaSrc) / 255.0))
        let alphaOut = roundEven(alphaSrc + alphaBg * ((255.0 - alphaSrc) / 255.0))

        let alphaOutByte = Int(alphaOut)
        if alphaOutByte == 0 {
            return PolicyOutput(
                mappedLinearRGB: .zero,
                mappedEncodedRGB: .zero,
                mappedAlphaByte: 0
            )
        }
        let cCSVByte = roundEven(255.0 * pOut / alphaOut)
        let encodedUnit = cCSVByte / 255.0
        let linearUnit = LinearCompositeSpaces.transferDecode(encodedUnit)
        return PolicyOutput(
            mappedLinearRGB: linearUnit,
            mappedEncodedRGB: encodedUnit,
            mappedAlphaByte: alphaOutByte
        )
    }

    /// Spec §Policies (2): decode encoded bytes to linear, premultiply,
    /// composite, then unpremultiply / re-encode / quantize to 8-bit at the
    /// end. The path the renderer flip would adopt. Returns CSV-ready
    /// unpremultiplied form.
    public static func linear8bit(
        fgByte: SIMD3<Float>,
        fgAlphaByte: Int,
        bgByte: SIMD3<Float>,
        bgAlphaByte: Int,
        target: LinearCompositeSpaces.TargetGamut
    ) -> PolicyOutput {
        _ = target  // both gamuts share the sRGB transfer; per-gamut typing is informational.

        let cSrcLin = LinearCompositeSpaces.transferDecode(fgByte / 255.0)
        let cBgLin = LinearCompositeSpaces.transferDecode(bgByte / 255.0)
        let alphaSrcUnit = Float(fgAlphaByte) / 255.0
        let alphaBgUnit = Float(bgAlphaByte) / 255.0

        let pSrcLin = alphaSrcUnit * cSrcLin
        let pBgLin = alphaBgUnit * cBgLin
        let pOutLin = pSrcLin + pBgLin * (1.0 - alphaSrcUnit)
        let alphaOutUnit = alphaSrcUnit + alphaBgUnit * (1.0 - alphaSrcUnit)

        if alphaOutUnit <= 0 {
            return PolicyOutput(
                mappedLinearRGB: .zero,
                mappedEncodedRGB: .zero,
                mappedAlphaByte: 0
            )
        }
        let cOutLin = pOutLin / alphaOutUnit
        let cOutClamped = simd_clamp(cOutLin, SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 1, 1))
        let cOutEncoded = LinearCompositeSpaces.transferEncode(cOutClamped)
        // Spec §Policies §"unpremultiply, encode, re-premultiply to 8-bit storage":
        //   p_out_byte = round(255 · c_out_encoded_unit · α_out_unit);
        //   α_out_byte = round(255 · α_out_unit).
        let pOutByte = roundEven(255.0 * cOutEncoded * alphaOutUnit)
        let alphaOutByteFloat = roundEven(255.0 * alphaOutUnit)
        let alphaOutByte = Int(alphaOutByteFloat)

        if alphaOutByte == 0 {
            return PolicyOutput(
                mappedLinearRGB: .zero,
                mappedEncodedRGB: .zero,
                mappedAlphaByte: 0
            )
        }
        // CSV-serialization unpremultiplication per spec §Policies §"CSV
        // serialization is unpremultiplied throughout".
        let cCSVByte = roundEven(255.0 * pOutByte / alphaOutByteFloat)
        let encodedUnit = cCSVByte / 255.0
        let linearUnit = LinearCompositeSpaces.transferDecode(encodedUnit)
        return PolicyOutput(
            mappedLinearRGB: linearUnit,
            mappedEncodedRGB: encodedUnit,
            mappedAlphaByte: alphaOutByte
        )
    }

    /// Spec §Policies (3): same as `linear8bit` through the linear composite
    /// step. No quantization. Output is float, premultiplied, linear.
    /// CSV-ready form unpremultiplies per spec §"CSV serialization is
    /// unpremultiplied throughout".
    public static func linearFloat(
        fgByte: SIMD3<Float>,
        fgAlphaByte: Int,
        bgByte: SIMD3<Float>,
        bgAlphaByte: Int,
        target: LinearCompositeSpaces.TargetGamut
    ) -> PolicyOutput {
        _ = target

        let cSrcLin = LinearCompositeSpaces.transferDecode(fgByte / 255.0)
        let cBgLin = LinearCompositeSpaces.transferDecode(bgByte / 255.0)
        let alphaSrcUnit = Float(fgAlphaByte) / 255.0
        let alphaBgUnit = Float(bgAlphaByte) / 255.0

        let pSrcLin = alphaSrcUnit * cSrcLin
        let pBgLin = alphaBgUnit * cBgLin
        let pOutLin = pSrcLin + pBgLin * (1.0 - alphaSrcUnit)
        let alphaOutUnit = alphaSrcUnit + alphaBgUnit * (1.0 - alphaSrcUnit)

        // α_out_byte for linearFloat is the byte-projection of the float alpha.
        let alphaOutByteFloat = roundEven(255.0 * alphaOutUnit)
        let alphaOutByte = Int(alphaOutByteFloat)
        if alphaOutByte == 0 || alphaOutUnit <= 0 {
            return PolicyOutput(
                mappedLinearRGB: .zero,
                mappedEncodedRGB: .zero,
                mappedAlphaByte: 0
            )
        }
        // Native unpremultiplied linear (no clamp — spec §Policies (3) "Not
        // clamped. Native float values preserved").
        let cCSVLin = pOutLin / alphaOutUnit
        // mapped_encoded_rgb for linearFloat is the 8-bit-projected encoded
        // form (per spec §Policies §"For linearFloat: ... unpremultiplied
        // linear → encode → quantize to 8-bit → divide by 255").
        let cClamped = simd_clamp(cCSVLin, SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 1, 1))
        let cEncoded = LinearCompositeSpaces.transferEncode(cClamped)
        let cEncodedByte = roundEven(255.0 * cEncoded)
        let encodedUnit = cEncodedByte / 255.0
        return PolicyOutput(
            mappedLinearRGB: cCSVLin,
            mappedEncodedRGB: encodedUnit,
            mappedAlphaByte: alphaOutByte
        )
    }

    /// Dispatch by `Identifier`. Used by the command's row-assembly loop.
    public static func apply(
        policy: Identifier,
        fgByte: SIMD3<Float>,
        fgAlphaByte: Int,
        bgByte: SIMD3<Float>,
        bgAlphaByte: Int,
        target: LinearCompositeSpaces.TargetGamut
    ) -> PolicyOutput {
        switch policy {
        case .encoded8bit:
            return encoded8bit(
                fgByte: fgByte, fgAlphaByte: fgAlphaByte,
                bgByte: bgByte, bgAlphaByte: bgAlphaByte,
                target: target
            )
        case .linear8bit:
            return linear8bit(
                fgByte: fgByte, fgAlphaByte: fgAlphaByte,
                bgByte: bgByte, bgAlphaByte: bgAlphaByte,
                target: target
            )
        case .linearFloat:
            return linearFloat(
                fgByte: fgByte, fgAlphaByte: fgAlphaByte,
                bgByte: bgByte, bgAlphaByte: bgAlphaByte,
                target: target
            )
        }
    }
}
