import simd

/// Gamut mapping from OKLAB into a target linear RGB gamut (sRGB or Display P3).
///
/// Implements Björn Ottosson's recommended **adaptive L₀ straight-line projection**
/// from his gamut-clipping post: https://bottosson.github.io/posts/gamutclipping/
/// Quote: "I think a good default choice would be adaptive L0 with α=0.05".
///
/// The method projects an out-of-gamut OKLAB color in a straight line toward an
/// L-axis anchor point (L₀, 0, 0), where L₀ is chosen adaptively based on the
/// input luminance. The gamut-boundary intersection is found by 16-iteration
/// binary search along the projection line (~1.5e-5 precision in line parameter t).
/// Ottosson's published recipe uses Halley's method for constant-time convergence;
/// Phase 2 can substitute Halley's if benchmarks show binary search is a bottleneck.
public enum GamutMapping {

    /// Map an OKLAB color into sRGB gamut, returning linear sRGB (strictly 0..1 per channel).
    public static func adaptiveL0ToSRGB(_ oklab: SIMD3<Float>) -> SIMD3<Float> {
        let rgb = ColorConversion.oklabToLinearSRGB(oklab)
        // Fast path: already in gamut (±0.001 slack absorbs Float round-trip error).
        // Clamp so callers see a uniform [0, 1] post-condition regardless of path.
        if isInUnitRGBGamut(rgb) { return simd_clamp(rgb, SIMD3(0, 0, 0), SIMD3(1, 1, 1)) }
        return projectToSRGBGamut(oklab)
    }

    /// Map an OKLAB color into Display-P3 gamut, returning linear Display-P3.
    public static func adaptiveL0ToDisplayP3(_ oklab: SIMD3<Float>) -> SIMD3<Float> {
        let rgb = ColorConversion.oklabToLinearP3(oklab)
        if isInUnitRGBGamut(rgb) { return simd_clamp(rgb, SIMD3(0, 0, 0), SIMD3(1, 1, 1)) }
        return projectToDisplayP3Gamut(oklab)
    }

    /// Map an OKLAB color into sRGB gamut using CSS Color 4 Ray Trace,
    /// returning linear sRGB.
    ///
    /// Cross-checked in `AskiColorLab` against the pinned Color.js apps
    /// `9d4b9883` reference port at
    /// `Tools/AskiColorLab/GamutSweep/References/ReferenceRayTrace.swift`.
    public static func rayTraceToSRGB(_ oklab: SIMD3<Float>) -> SIMD3<Float> {
        rayTraceToRGBGamut(
            oklab,
            oklabToLinearRGB: ColorConversion.oklabToLinearSRGB,
            linearRGBToOKLab: ColorConversion.linearSRGBToOKLAB
        )
    }

    /// Map an OKLAB color into Display-P3 gamut using CSS Color 4 Ray Trace,
    /// returning linear Display-P3.
    ///
    /// Cross-checked in `AskiColorLab` against the pinned Color.js apps
    /// `9d4b9883` reference port at
    /// `Tools/AskiColorLab/GamutSweep/References/ReferenceRayTrace.swift`.
    public static func rayTraceToDisplayP3(_ oklab: SIMD3<Float>) -> SIMD3<Float> {
        rayTraceToRGBGamut(
            oklab,
            oklabToLinearRGB: ColorConversion.oklabToLinearP3,
            linearRGBToOKLab: ColorConversion.linearP3ToOKLAB
        )
    }

    private static func isInUnitRGBGamut(_ rgb: SIMD3<Float>) -> Bool {
        rgb.x >= -0.001 && rgb.x <= 1.001
            && rgb.y >= -0.001 && rgb.y <= 1.001
            && rgb.z >= -0.001 && rgb.z <= 1.001
    }

    private static func isStrictlyInUnitRGBGamut(_ rgb: SIMD3<Float>) -> Bool {
        rgb.x >= 0 && rgb.x <= 1
            && rgb.y >= 0 && rgb.y <= 1
            && rgb.z >= 0 && rgb.z <= 1
    }

    /// Projects `oklab` along a straight line toward (L₀, 0, 0) until the
    /// resulting linear sRGB is inside the unit cube. `internal` rather than
    /// `private` so `GamutMappingTests` can force the slow path directly
    /// (for the fixed-point / idempotence-on-boundary test).
    internal static func projectToSRGBGamut(_ oklab: SIMD3<Float>) -> SIMD3<Float> {
        projectToRGBGamut(oklab, toLinearRGB: ColorConversion.oklabToLinearSRGB)
    }

    internal static func projectToDisplayP3Gamut(_ oklab: SIMD3<Float>) -> SIMD3<Float> {
        projectToRGBGamut(oklab, toLinearRGB: ColorConversion.oklabToLinearP3)
    }

    private static func projectToRGBGamut(
        _ oklab: SIMD3<Float>,
        toLinearRGB: (SIMD3<Float>) -> SIMD3<Float>
    ) -> SIMD3<Float> {
        let L = oklab.x
        let a = oklab.y
        let b = oklab.z
        let C = (a * a + b * b).squareRoot()
        if C < 1e-6 { return simd_clamp(toLinearRGB(oklab), SIMD3(0, 0, 0), SIMD3(1, 1, 1)) }

        // Adaptive anchor: L₀ blends toward 0.5 as chroma grows, α controls how fast.
        let alpha: Float = 0.05
        let L0 = 0.5 + alpha * (L - 0.5)

        // Line in OKLAB from (L₀, 0, 0) through (L, a, b). Parameter t ∈ [0, 1]:
        //   at t=0: anchor point (L₀, 0, 0)
        //   at t=1: original (L, a, b)
        // 16 iterations → t precision ~2^-16 ≈ 1.5e-5, well under perceptual JND.
        var low: Float = 0
        var high: Float = 1
        for _ in 0..<16 {
            let mid = (low + high) * 0.5
            let testOKLAB = SIMD3<Float>(
                L0 + mid * (L - L0),
                mid * a,
                mid * b
            )
            let testRGB = toLinearRGB(testOKLAB)
            if isInUnitRGBGamut(testRGB) {
                low = mid
            } else {
                high = mid
            }
        }
        let finalOKLAB = SIMD3<Float>(
            L0 + low * (L - L0),
            low * a,
            low * b
        )
        return simd_clamp(
            toLinearRGB(finalOKLAB),
            SIMD3(0, 0, 0),
            SIMD3(1, 1, 1)
        )
    }

    private static func rayTraceToRGBGamut(
        _ oklab: SIMD3<Float>,
        oklabToLinearRGB: (SIMD3<Float>) -> SIMD3<Float>,
        linearRGBToOKLab: (SIMD3<Float>) -> SIMD3<Float>
    ) -> SIMD3<Float> {
        let initialLinearRGB = oklabToLinearRGB(oklab)
        if isStrictlyInUnitRGBGamut(initialLinearRGB) {
            return initialLinearRGB
        }
        if oklab.x >= 1 { return SIMD3<Float>(1, 1, 1) }
        if oklab.x <= 0 { return SIMD3<Float>(0, 0, 0) }

        let sourceL = oklab.x
        let sourceA = oklab.y
        let sourceB = oklab.z
        let sourceHRad = atan2(sourceB, sourceA)
        let cosH = cos(sourceHRad)
        let sinH = sin(sourceHRad)

        var anchor = oklabToLinearRGB(SIMD3<Float>(sourceL, 0, 0))
        var mapColor = initialLinearRGB
        var last = initialLinearRGB

        let strictlyInsideEpsilon: Float = 1e-6

        for i in 0..<4 {
            if i > 0 {
                let currentLab = linearRGBToOKLab(mapColor)
                let currentA = currentLab.y
                let currentB = currentLab.z
                let currentC = sqrt(currentA * currentA + currentB * currentB)
                let correctedLab = SIMD3<Float>(sourceL, currentC * cosH, currentC * sinH)
                mapColor = oklabToLinearRGB(correctedLab)
            }

            let intersection = rayTraceBoxIntersection(from: anchor, through: mapColor)

            if i > 0
                && mapColor.x > strictlyInsideEpsilon && mapColor.x < 1 - strictlyInsideEpsilon
                && mapColor.y > strictlyInsideEpsilon && mapColor.y < 1 - strictlyInsideEpsilon
                && mapColor.z > strictlyInsideEpsilon && mapColor.z < 1 - strictlyInsideEpsilon
            {
                anchor = mapColor
            }

            mapColor = intersection
            last = intersection
        }

        return simd_clamp(last, SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 1, 1))
    }

    internal static func rayTraceBoxIntersection(
        from anchor: SIMD3<Float>,
        through mapColor: SIMD3<Float>
    ) -> SIMD3<Float> {
        let direction = mapColor - anchor
        var bestT: Float = .infinity

        for axis in 0..<3 {
            let originComp: Float
            let dirComp: Float
            switch axis {
            case 0:
                originComp = anchor.x
                dirComp = direction.x
            case 1:
                originComp = anchor.y
                dirComp = direction.y
            default:
                originComp = anchor.z
                dirComp = direction.z
            }
            guard abs(dirComp) > 1e-12 else { continue }

            let tZero = (0 - originComp) / dirComp
            let tOne = (1 - originComp) / dirComp
            if tZero > 0 && tZero < bestT { bestT = tZero }
            if tOne > 0 && tOne < bestT { bestT = tOne }
        }

        guard bestT.isFinite else { return mapColor }
        return anchor + direction * bestT
    }
}
