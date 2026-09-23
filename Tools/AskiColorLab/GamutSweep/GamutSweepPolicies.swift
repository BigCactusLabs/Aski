import Aski
import simd

/// Lab-local gamut-mapping algorithms evaluated by `gamut-sweep`. None of these
/// are promoted to `GamutMappingPolicy` cases; cross-comparison is the lab's
/// purpose and any production promotion is a separate Slice 4 decision.
public enum GamutSweepPolicies {

    /// Canonical CSV order — `adaptiveL0` first, then `clip`, then the three
    /// CSS Color 4 candidates.
    public static let canonicalOrder: [Identifier] = [
        .adaptiveL0,
        .clip,
        .localMINDE,
        .rayTrace,
        .edgeSeeker,
    ]

    public enum Identifier: String, CaseIterable, Sendable {
        case adaptiveL0
        case clip
        case localMINDE
        case rayTrace
        case edgeSeeker

        public var csvLabel: String { rawValue }
    }

    /// Map `oklab` into the target gamut and return final-clamped linear RGB
    /// strictly in `[0, 1]` per channel.
    public static func map(
        oklab: SIMD3<Float>,
        target: GamutSweepTarget,
        policy: Identifier
    ) -> SIMD3<Float> {
        switch policy {
        case .adaptiveL0: return adaptiveL0(oklab: oklab, target: target)
        case .clip: return clip(oklab: oklab, target: target)
        case .localMINDE: return localMINDE(oklab: oklab, target: target)
        case .rayTrace: return rayTrace(oklab: oklab, target: target)
        case .edgeSeeker:
            switch target {
            case .sRGB: return EdgeSeekerMapping.forSRGB.map(oklab: oklab)
            case .displayP3: return EdgeSeekerMapping.forDisplayP3.map(oklab: oklab)
            }
        }
    }

    /// Production baseline. Direct call into existing public `GamutMapping`
    /// functions. No re-implementation; the CSV records this as the reference.
    public static func adaptiveL0(
        oklab: SIMD3<Float>,
        target: GamutSweepTarget
    ) -> SIMD3<Float> {
        switch target {
        case .sRGB: return GamutMapping.adaptiveL0ToSRGB(oklab)
        case .displayP3: return GamutMapping.adaptiveL0ToDisplayP3(oklab)
        }
    }

    /// Production Ray Trace policy. The lab delegates to shipped behavior so
    /// `gamut-sweep` cannot drift from the opt-in or default production path.
    public static func rayTrace(
        oklab: SIMD3<Float>,
        target: GamutSweepTarget
    ) -> SIMD3<Float> {
        switch target {
        case .sRGB: return GamutMapping.rayTraceToSRGB(oklab)
        case .displayP3: return GamutMapping.rayTraceToDisplayP3(oklab)
        }
    }

    /// Encoded-clip behaviour. Matches `GamutMappingPolicy.clip` semantics
    /// without depending on `Aski.CellSampling.mapToDisplayColor` internals.
    /// Returns final-clamped linear RGB; the encoded-clip step is handled by
    /// `GamutSweepMetrics.encodedRGB` at row-assembly time.
    public static func clip(
        oklab: SIMD3<Float>,
        target: GamutSweepTarget
    ) -> SIMD3<Float> {
        let linearRGB = target.oklabToLinearRGB(oklab)
        return simd_clamp(linearRGB, SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 1, 1))
    }

    /// CSS Color 4 §14.2.2 Local MINDE.
    ///
    /// Three early-exit guards (matching `rayTrace`'s structure), then a
    /// 20-iteration binary search over chroma. The candidate at chroma `C` is
    /// `OkLCh(L, C, h) → OKLab → linear RGB → channel-clipped`; the candidate
    /// passes when `ΔEOK` between the intended OKLab and the clipped round
    /// trip is below `0.02`. Invariant maintained: `low` passes, `high` fails.
    /// Returns the channel-clipped candidate at `low` — NOT at `mid` or `high`
    /// — so localMINDE evidence is comparable to CSS Color 4 reference
    /// implementations.
    public static func localMINDE(
        oklab: SIMD3<Float>,
        target: GamutSweepTarget
    ) -> SIMD3<Float> {
        let oklabToLinear = target.oklabToLinearRGB
        let linearToOklab = target.linearRGBToOKLab

        // In-gamut guard (strict [0, 1], not Aski's ±0.001 production slack).
        let initialLinearRGB = oklabToLinear(oklab)
        if isStrictlyInUnitCube(initialLinearRGB) {
            return initialLinearRGB
        }
        // Lightness ceiling.
        if oklab.x >= 1 {
            return SIMD3<Float>(1, 1, 1)
        }
        // Lightness floor.
        if oklab.x <= 0 {
            return SIMD3<Float>(0, 0, 0)
        }

        let L = oklab.x
        let a = oklab.y
        let b = oklab.z
        let sourceC = sqrt(a * a + b * b)
        let hRad = atan2(b, a)
        let cosH = cos(hRad)
        let sinH = sin(hRad)

        // `low` is the highest chroma so far known to pass the JND predicate.
        // `high` is the lowest chroma so far known to fail. C = 0 is always
        // a passing candidate (achromatic gray channel-clips trivially). The
        // source chroma is, by virtue of falling through the in-gamut guard,
        // a failing candidate.
        var low: Float = 0
        var high: Float = sourceC

        let jndThreshold: Float = 0.02

        // 20 iterations bring high - low below sourceC × 1e-6, well under any
        // perceptual threshold and matching CSS Color 4 reference behaviour.
        for _ in 0..<20 {
            let mid = (low + high) * 0.5
            let intendedOKLab = SIMD3<Float>(L, mid * cosH, mid * sinH)
            let intendedLinearRGB = oklabToLinear(intendedOKLab)
            let clippedLinearRGB = simd_clamp(
                intendedLinearRGB,
                SIMD3<Float>(0, 0, 0),
                SIMD3<Float>(1, 1, 1)
            )
            let roundTripOKLab = linearToOklab(clippedLinearRGB)
            let deltaEOK = simd_length(roundTripOKLab - intendedOKLab)
            if deltaEOK < jndThreshold {
                low = mid
            } else {
                high = mid
            }
        }

        // Return the channel-clipped candidate at `low` — the highest chroma
        // whose clipping distortion is within JND. NOT at `mid` or `high`.
        let finalOKLab = SIMD3<Float>(L, low * cosH, low * sinH)
        return simd_clamp(
            oklabToLinear(finalOKLab),
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(1, 1, 1)
        )
    }

    /// Strict `[0, 1]` per channel — for the in-gamut / lightness guards used
    /// by `localMINDE` and `rayTrace`. The CSV's `source_in_target_gamut`
    /// column uses Aski's ±0.001 predicate instead (see GamutSweepMetrics).
    static func isStrictlyInUnitCube(_ rgb: SIMD3<Float>) -> Bool {
        rgb.x >= 0 && rgb.x <= 1
            && rgb.y >= 0 && rgb.y <= 1
            && rgb.z >= 0 && rgb.z <= 1
    }
}
