import Aski
import Foundation
import simd

public enum LinearCompositeMetrics {

    /// Bundle of the three metric values for one row.
    public struct Result: Sendable, Equatable {
        public let deltaEOK: Float
        public let encodedRGBDistance: Float
        public let maxChannelAbsDiff: Float
    }

    /// Spec §CSV Contract: `simd_length(mapped_oklab − ground_truth_oklab)`.
    /// OKLab is produced by converting the row's `mapped_linear_rgb` directly
    /// via the target gamut's `linear → OKLab` transform.
    public static func deltaEOK(
        mappedOKLab: SIMD3<Float>,
        groundTruthOKLab: SIMD3<Float>
    ) -> Float {
        simd_length(mappedOKLab - groundTruthOKLab)
    }

    /// Spec §CSV Contract: `simd_length` on unit-float byte space.
    public static func encodedRGBDistance(
        mapped: SIMD3<Float>,
        groundTruth: SIMD3<Float>
    ) -> Float {
        simd_length(mapped - groundTruth)
    }

    /// Spec §CSV Contract: per-channel absolute difference, max.
    public static func maxChannelAbsDiff(
        mapped: SIMD3<Float>,
        groundTruth: SIMD3<Float>
    ) -> Float {
        let diff = abs(mapped - groundTruth)
        return max(diff.x, max(diff.y, diff.z))
    }

    /// Row-level convenience. Applies the spec's zero-alpha convention: if
    /// either side has `alpha_byte == 0`, all three metrics are zero.
    public static func compute(
        mappedLinearRGB: SIMD3<Float>,
        mappedEncodedRGB: SIMD3<Float>,
        mappedAlphaByte: Int,
        groundTruthLinearRGB: SIMD3<Float>,
        groundTruthEncodedRGB: SIMD3<Float>,
        groundTruthAlphaByte: Int,
        target: LinearCompositeSpaces.TargetGamut
    ) -> Result {
        if mappedAlphaByte == 0 || groundTruthAlphaByte == 0 {
            return Result(deltaEOK: 0, encodedRGBDistance: 0, maxChannelAbsDiff: 0)
        }
        let mappedOKLab = target.linearRGBToOKLab(mappedLinearRGB)
        let truthOKLab = target.linearRGBToOKLab(groundTruthLinearRGB)
        return Result(
            deltaEOK: deltaEOK(mappedOKLab: mappedOKLab, groundTruthOKLab: truthOKLab),
            encodedRGBDistance: encodedRGBDistance(mapped: mappedEncodedRGB, groundTruth: groundTruthEncodedRGB),
            maxChannelAbsDiff: maxChannelAbsDiff(mapped: mappedEncodedRGB, groundTruth: groundTruthEncodedRGB)
        )
    }
}
