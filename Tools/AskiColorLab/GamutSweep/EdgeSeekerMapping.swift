import Aski
import simd

/// Ardov 2023 EdgeSeeker. Per-target-gamut cusp construction is mandatory:
/// the sRGB cusp at any given hue sits at lower chroma than the P3 cusp, so
/// porting a P3-tuned cusp LUT to sRGB rows would produce incorrect `edge_C`
/// values and the sRGB EdgeSeeker evidence would be invalid.
///
/// Two early-exit guards (lightness ceiling/floor, returning achromatic at
/// the source hue), then chroma is clamped to `min(source_C, edge_C)` along
/// the constant-`L` constant-`h` line in OkLCh. In-gamut sources are
/// preserved by the natural `min(source_C, edge_C)`; no separate in-gamut
/// guard is needed.
///
/// **Algorithm:** for each of 360 hue buckets and 64 L samples, perform
/// 16-iteration interval bisection in OkLCh chroma along the constant-(L, h)
/// line until the strict `[0, 1]` boundary in target linear RGB is bracketed
/// to within `~1.5e-5`. This is the "interval bisection over a per-hue cusp
/// approximation" the spec calls for, and matches the structure of Ardov's
/// published JS (and Color.js's `edge-seeker.js`) where the polyline LUT IS
/// the cusp approximation. Runtime is a polyline lookup; the bisection cost
/// is paid once at module load via Swift's lazy `static let`.
///
/// **Sendable:** `static let forSRGB` / `static let forDisplayP3` are global
/// immutable values, so Swift 6 strict concurrency requires `Sendable`. We
/// keep the conformance trivial by storing only the `GamutSweepTarget` enum
/// (Sendable) and a `CuspLUT` of arrays-of-floats (Sendable), and by
/// switching on the enum inside `map(_:)` rather than storing closures.
///
/// Algorithm family from [Ardov's gamut-mapping playground](https://lab.ardov.me/gamut-mapping)
/// and [Color.js `makeEdgeSeeker`](https://github.com/color-js/apps/blob/9d4b9883a2ad4a6f73875f666d2d531c6b4248f6/gamut-mapping/edge-seeker/makeEdgeSeeker.js)
/// at commit `9d4b9883`.
/// The pinned Color.js cusp + curvature LUT is ported in-repo at
/// `Tools/AskiColorLab/GamutSweep/References/ReferenceEdgeSeeker.swift` and
/// cross-checks this implementation in Swift Testing.
///
/// **Algorithmic divergence vs Color.js (by design, not a bug):** Color.js
/// stores one cusp point + curvature per hue across 400 slices with line+arc
/// interpolation; Aski stores 64 edge-chroma samples per hue across 360 slices
/// with bilinear interpolation. Both produce min(source_C, edge_C) along the
/// constant-(L, h) line. Cross-validated structurally (boundary cases,
/// monotonicity, fixture-level mapped_C agreement) - not bit-exactly. Per-
/// fixture mapped_C agreement is guarded by the in-repo Color.js reference
/// cross-check suite.
public struct EdgeSeekerMapping: Sendable {

    public static let forSRGB = EdgeSeekerMapping(target: .sRGB)
    public static let forDisplayP3 = EdgeSeekerMapping(target: .displayP3)

    private let target: GamutSweepTarget
    private let cuspLUT: CuspLUT

    private init(target: GamutSweepTarget) {
        self.target = target
        self.cuspLUT = CuspLUT.build(target: target)
    }

    public func map(oklab: SIMD3<Float>) -> SIMD3<Float> {
        let L = oklab.x
        let a = oklab.y
        let b = oklab.z
        let sourceC = sqrt(a * a + b * b)
        let hRad = atan2(b, a)

        // Lightness ceiling: achromatic at source hue → (1, 0, h) → linear RGB.
        if L >= 1 {
            return oklabToLinear(SIMD3<Float>(1, 0, 0))
        }
        // Lightness floor: achromatic at source hue → (0, 0, h) → linear RGB.
        if L <= 0 {
            return oklabToLinear(SIMD3<Float>(0, 0, 0))
        }

        let edgeC = cuspLUT.maxChroma(forL: L, hueRadians: hRad)
        let mappedC = min(sourceC, edgeC)
        let cosH = sourceC > 1e-12 ? a / sourceC : cos(hRad)
        let sinH = sourceC > 1e-12 ? b / sourceC : sin(hRad)
        let mappedLab = SIMD3<Float>(L, mappedC * cosH, mappedC * sinH)
        return simd_clamp(
            oklabToLinear(mappedLab),
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(1, 1, 1)
        )
    }

    /// OKLab → target linear RGB. Inlined switch (rather than a stored
    /// closure) so the enclosing struct can remain `Sendable` under Swift 6
    /// strict concurrency.
    private func oklabToLinear(_ lab: SIMD3<Float>) -> SIMD3<Float> {
        switch target {
        case .sRGB: return ColorConversion.oklabToLinearSRGB(lab)
        case .displayP3: return ColorConversion.oklabToLinearP3(lab)
        }
    }
}

/// Per-hue, per-L edge-chroma table. For each of 360 hue buckets, stores 64
/// edge-chroma samples — one per L value uniformly spaced in `[0, 1]`. Each
/// entry is the maximum chroma at that (L, h) for which `OkLCh(L, C, h)`
/// converts to a strict-`[0, 1]` target linear RGB.
///
/// Construction: 16-iteration interval bisection per (h, L) sample. Runtime
/// lookup is bilinear interpolation across (hue bucket, L index).
struct CuspLUT: Sendable {
    static let hueBucketCount: Int = 360
    static let lSampleCount: Int = 64
    static let bisectionIterations: Int = 16

    /// One inner array per hue bucket; each contains `lSampleCount` edge
    /// chromas. Index `i` corresponds to `L = i / (lSampleCount - 1)`.
    let edgeChromasByHue: [[Float]]

    func maxChroma(forL L: Float, hueRadians: Float) -> Float {
        let degrees = (hueRadians * 180 / .pi).truncatingRemainder(dividingBy: 360)
        let normalized = degrees < 0 ? degrees + 360 : degrees
        let lowerHue = Int(normalized.rounded(.down)) % Self.hueBucketCount
        let upperHue = (lowerHue + 1) % Self.hueBucketCount
        let hueFrac = normalized - Float(lowerHue)
        let lowerC = interpolateL(L: L, line: edgeChromasByHue[lowerHue])
        let upperC = interpolateL(L: L, line: edgeChromasByHue[upperHue])
        return lowerC * (1 - hueFrac) + upperC * hueFrac
    }

    private func interpolateL(L: Float, line: [Float]) -> Float {
        let clamped = max(0, min(1, L))
        let exact = clamped * Float(Self.lSampleCount - 1)
        let lowerIdx = min(Self.lSampleCount - 2, Int(exact))
        let frac = exact - Float(lowerIdx)
        return line[lowerIdx] * (1 - frac) + line[lowerIdx + 1] * frac
    }

    static func build(target: GamutSweepTarget) -> CuspLUT {
        var allHues: [[Float]] = []
        allHues.reserveCapacity(hueBucketCount)
        for hueBucket in 0..<hueBucketCount {
            let hRad = Float(hueBucket) * .pi / 180
            let cosH = cos(hRad)
            let sinH = sin(hRad)
            var line: [Float] = []
            line.reserveCapacity(lSampleCount)
            for lIndex in 0..<lSampleCount {
                let L = Float(lIndex) / Float(lSampleCount - 1)
                line.append(
                    edgeChroma(
                        L: L, cosH: cosH, sinH: sinH, target: target
                    ))
            }
            allHues.append(line)
        }
        return CuspLUT(edgeChromasByHue: allHues)
    }

    /// Interval bisection in OkLCh chroma along constant-`(L, h)` line.
    ///
    /// Invariant maintained across iterations: `low` is the highest chroma
    /// known to map inside the strict `[0, 1]` target linear-RGB cube; `high`
    /// is the lowest chroma known to map outside. Initialized with `low = 0`
    /// (the achromatic L-axis is in-gamut for any L ∈ [0, 1] by construction)
    /// and `high` doubled outward from `1.0` until out-of-gamut. After 16
    /// iterations, `high - low < initial_high × 2^-16 ≈ 1.5e-5`.
    private static func edgeChroma(
        L: Float, cosH: Float, sinH: Float, target: GamutSweepTarget
    ) -> Float {
        var low: Float = 0
        var high: Float = 1.0
        // Some hue/L combinations have wider-than-unit chroma reach in OKLab
        // (e.g. saturated yellows in Display P3 sit near OkLCh chroma 0.35,
        // but at low L the edge moves further out). Expand `high` until it
        // is provably out-of-gamut. A safety cap of 64 prevents infinite
        // expansion on numerical edge cases.
        while isInUnitCube(oklabToLinear(L: L, a: high * cosH, b: high * sinH, target: target)) {
            high *= 2
            if high > 64 { break }
        }
        for _ in 0..<bisectionIterations {
            let mid = (low + high) * 0.5
            if isInUnitCube(oklabToLinear(L: L, a: mid * cosH, b: mid * sinH, target: target)) {
                low = mid
            } else {
                high = mid
            }
        }
        return low
    }

    private static func oklabToLinear(
        L: Float, a: Float, b: Float, target: GamutSweepTarget
    ) -> SIMD3<Float> {
        let lab = SIMD3<Float>(L, a, b)
        switch target {
        case .sRGB: return ColorConversion.oklabToLinearSRGB(lab)
        case .displayP3: return ColorConversion.oklabToLinearP3(lab)
        }
    }

    private static func isInUnitCube(_ rgb: SIMD3<Float>) -> Bool {
        rgb.x >= 0 && rgb.x <= 1
            && rgb.y >= 0 && rgb.y <= 1
            && rgb.z >= 0 && rgb.z <= 1
    }
}
