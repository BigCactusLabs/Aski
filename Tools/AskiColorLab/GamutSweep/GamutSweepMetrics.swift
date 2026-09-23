import Aski
import simd

public enum GamutSweepMetrics {

    /// CSS Color 4 §14.2 reference perceptual distance: Euclidean OKLab.
    public static func deltaEOK(
        source: SIMD3<Float>,
        mapped: SIMD3<Float>
    ) -> Float {
        simd_length(mapped - source)
    }

    /// Signed OkLCh hue rotation from `source` to `mapped`, normalized to
    /// `(-180, 180]` degrees, positive = counter-clockwise. Returns `0`
    /// when either side is achromatic (chroma < 1e-6) — hue is undefined.
    /// Use `chromaReductionPct` to distinguish "source was already
    /// achromatic" from "source had chroma but mapped to achromatic".
    public static func hueDeltaDegrees(
        source: SIMD3<Float>,
        mapped: SIMD3<Float>
    ) -> Float {
        let sourceC = sqrt(source.y * source.y + source.z * source.z)
        let mappedC = sqrt(mapped.y * mapped.y + mapped.z * mapped.z)
        guard sourceC >= 1e-6, mappedC >= 1e-6 else { return 0 }
        let sourceH = atan2(source.z, source.y) * 180 / .pi
        let mappedH = atan2(mapped.z, mapped.y) * 180 / .pi
        var delta = mappedH - sourceH
        while delta <= -180 { delta += 360 }
        while delta > 180 { delta -= 360 }
        return delta
    }

    public static func lightnessDelta(
        source: SIMD3<Float>,
        mapped: SIMD3<Float>
    ) -> Float {
        mapped.x - source.x
    }

    /// Precedence (spec §CSV Contract):
    ///   1. source_C < 1e-6 → 0       (no chroma to reduce)
    ///   2. mapped_C < 1e-6 → 100     (fully reduced to achromatic)
    ///   3. otherwise        → 100 * (1 - mapped_C / source_C)
    public static func chromaReductionPct(
        sourceC: Float,
        mappedC: Float
    ) -> Float {
        if sourceC < 1e-6 { return 0 }
        if mappedC < 1e-6 { return 100 }
        return 100 * (1 - mappedC / sourceC)
    }

    /// sRGB-style transfer encoding (sRGB and Display P3 share the curve),
    /// then per-channel clamp to `[0, 1]`. Matches Aski's existing
    /// `mapToDisplayColor` final-encode step.
    public static func encodedRGB(_ linearRGB: SIMD3<Float>) -> SIMD3<Float> {
        let encoded = SIMD3<Float>(
            ColorConversion.sRGBEncode(linearRGB.x),
            ColorConversion.sRGBEncode(linearRGB.y),
            ColorConversion.sRGBEncode(linearRGB.z)
        )
        return simd_clamp(encoded, SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 1, 1))
    }

    /// Re-implements `Aski.GamutMapping.isInUnitRGBGamut` lab-locally with the
    /// same ±0.001 slack — widening that internal symbol's visibility for one
    /// CSV column is not worth the public API surface area. The slack absorbs
    /// the round-trip float error of `OKLab → linear RGB → OKLab` and is the
    /// same predicate the production fast path uses; a strict-`[0,1]` predicate
    /// would flag the production fast path's own outputs as out-of-gamut at
    /// the boundary.
    public static func isSourceInTargetGamut(
        oklab: SIMD3<Float>,
        target: GamutSweepTarget
    ) -> Bool {
        let rgb = target.oklabToLinearRGB(oklab)
        return rgb.x >= -0.001 && rgb.x <= 1.001
            && rgb.y >= -0.001 && rgb.y <= 1.001
            && rgb.z >= -0.001 && rgb.z <= 1.001
    }

    /// Helper for callers assembling the CSV row.
    public static func chroma(of oklab: SIMD3<Float>) -> Float {
        sqrt(oklab.y * oklab.y + oklab.z * oklab.z)
    }
}
