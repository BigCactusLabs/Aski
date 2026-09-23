@_spi(AskiResearch) import Aski
import simd

/// OKLab distance metrics evaluated by `palette-match-ablation`.
///
/// `oklabEuclidean` mirrors current production palette matching (CSS Color 4
/// `DeltaEOK`, a 3D Euclidean distance in resolved OKLab). `oklabHyAB` is a
/// HyAB-style OKLab variant — city-block lightness plus Euclidean chroma — that
/// the lab evaluates as a candidate. Published HyAB applications operate on
/// CIELAB; applying the same formula to OKLab is an Aski hypothesis.
public enum PaletteMatchPolicies {
    public static func oklabEuclidean(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        simd_length(a - b)
    }

    public static func oklabHyAB(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let deltaL = abs(a.x - b.x)
        let deltaAB = simd_length(SIMD2<Float>(a.y - b.y, a.z - b.z))
        return deltaL + deltaAB
    }

    public struct Selection: Equatable, Sendable {
        public let index: Int
        public let distance: Float
    }

    /// Returns the candidate index with the smallest distance under `metric`.
    /// Ties are broken by the lowest palette index (no metric-specific tie logic).
    public static func nearest(
        in candidates: [SIMD3<Float>],
        to source: SIMD3<Float>,
        using metric: (SIMD3<Float>, SIMD3<Float>) -> Float
    ) -> Selection {
        precondition(!candidates.isEmpty, "nearest(in:) requires at least one candidate")
        var bestIndex = 0
        var bestDistance = metric(source, candidates[0])
        for index in 1..<candidates.count {
            let distance = metric(source, candidates[index])
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return Selection(index: bestIndex, distance: bestDistance)
    }

    /// Lab-local resolver for `PaletteColor` → OKLab.
    /// Mirrors `Sources/Aski/ResolvedPalette.swift`, which is `internal` and
    /// cannot be reused here. Prefer this small duplicate over widening library
    /// API; if `PaletteColorSpace` grows a new public case, this resolver must
    /// be updated in lockstep (the `preconditionFailure` makes that a hard miss).
    public static func resolveToOKLab(_ color: PaletteColor) -> SIMD3<Float> {
        let linear = SIMD3<Float>(
            ColorConversion.sRGBDecode(color.components.x),
            ColorConversion.sRGBDecode(color.components.y),
            ColorConversion.sRGBDecode(color.components.z)
        )
        if color.colorSpace == .sRGB {
            return ColorConversion.linearSRGBToOKLAB(linear)
        }
        if color.colorSpace == .displayP3 {
            return ColorConversion.linearP3ToOKLAB(linear)
        }
        preconditionFailure("Unsupported PaletteColorSpace in AskiColorLab: update PaletteMatchPolicies.resolveToOKLab")
    }

    // MARK: - Helmlab MetricSpace (probe)

    /// Lab-local resolver for `PaletteColor` → Helmlab MetricSpace-Lab.
    /// Mirrors `resolveToOKLab`: PaletteColor encoded RGB → linear → XYZ →
    /// MetricSpace.
    public static func resolveToHelmlab(_ color: PaletteColor) -> SIMD3<Double> {
        let linear = SIMD3<Double>(
            Double(ColorConversion.sRGBDecode(color.components.x)),
            Double(ColorConversion.sRGBDecode(color.components.y)),
            Double(ColorConversion.sRGBDecode(color.components.z))
        )
        let xyz: SIMD3<Double>
        if color.colorSpace == .sRGB {
            xyz = ColorConversion.linearSRGBToXYZ(linear)
        } else if color.colorSpace == .displayP3 {
            xyz = ColorConversion.linearP3ToXYZ(linear)
        } else {
            preconditionFailure("Unsupported PaletteColorSpace in AskiColorLab: update PaletteMatchPolicies.resolveToHelmlab")
        }
        return HelmlabMetric.xyzToHelmlabMetric(xyz)
    }

    public static func helmlabEuclidean(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        HelmlabMetric.euclideanDistance(a, b)
    }

    public static func helmlabCompressed(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        HelmlabMetric.compressedDeltaE(a, b)
    }

    public struct DoubleSelection: Equatable, Sendable {
        public let index: Int
        public let distance: Double
    }

    /// Nearest under a Double Helmlab metric. Ties broken by lowest index.
    public static func nearestHelmlab(
        in candidates: [SIMD3<Double>],
        to source: SIMD3<Double>,
        using metric: (SIMD3<Double>, SIMD3<Double>) -> Double
    ) -> DoubleSelection {
        precondition(!candidates.isEmpty, "nearestHelmlab(in:) requires at least one candidate")
        var bestIndex = 0
        var bestDistance = metric(source, candidates[0])
        for index in 1..<candidates.count {
            let distance = metric(source, candidates[index])
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return DoubleSelection(index: bestIndex, distance: bestDistance)
    }
}
