import Foundation
import simd

/// Helmlab **MetricSpace** color-difference space — the color-difference half
/// of the Helmlab two-space family. Ported as an experimental, opt-in
/// palette-matching distance. Port design recorded in the private development
/// archive.
///
/// 72-parameter analytic XYZ → MetricSpace-Lab pipeline. The pipeline runs in
/// `Double`: the reference JS port attributes ~0.6 STRESS drift to `Float`
/// accumulation across stages, so `Double` lets us validate tighter against the
/// Python reference (3-decimal forward match; near-epsilon round-trip).
///
/// Params and per-stage formulas are transcribed verbatim from the pinned
/// reference data file and `metric.py`; provenance below. This mirrors the
/// inlined fused matrices in `ColorConversion.swift`.
///
/// The transcription fixes the trained viewing condition to the v21 default
/// (surround = 0.5, `neutral_correction = false`): every surround (`*_S`)
/// parameter is `0` in v21 so those terms vanish, and the gray-axis neutral
/// correction is display-only (it degrades the trained metric ~5 STRESS) and is
/// off by default — so neither is ported. The `-28.2°` rigid `(a, b)` display
/// rotation IS applied, matching the reference's default `MetricSpace()`
/// (a pure isometry, so all distances are invariant to it).
///
/// SPI, not public SDK API (see plan § Visibility & API surface). The public
/// surface for Helmlab is the two `PaletteMatchingPolicy` cases only.
@_spi(AskiResearch) public enum HelmlabMetric {

    /// Provenance for the transcribed parameters. The v21 reconciliation
    /// (spec § Provenance STOP GATE): the PyPI `metric_params.json` carries no
    /// embedded version string and its README staledly labels the file "v20b",
    /// but every param is byte-identical to Color.js PR #722's block explicitly
    /// labeled "Core parameters (v21, 72 params)" — so the pinned source ships
    /// v21. `sourceSHA` is that Color.js merge commit (the demonstrable v21
    /// anchor); the params themselves were transcribed from the PyPI wheel.
    @_spi(AskiResearch) public enum Provenance {
        public static let pypiVersion = "0.14.0"
        public static let sourceSHA = "2500556fe44db9aed76395296197aa262008c63d"  // color-js/color.js#722 merge (v21 anchor)
        public static let helmlabRepoSHA = "4778cf3467b8b6ec2e9fea0154acee808a23358f"  // Grkmyldz148/helmlab main
        public static let declaredParamVersion = "v21"
        public static let transcriptionDate = "2026-06-07"
    }
}

extension HelmlabMetric {
    /// Inlined MetricSpace parameters, transcribed from `metric_params.json`
    /// (PyPI helmlab 0.14.0, v21 — see `Provenance`). Constant names mirror the
    /// JSON keys exactly so a future maintainer can diff them against the source.
    ///
    /// Omitted because they are `0.0` in the v21 set and therefore drop out of
    /// every stage: `dist_nl`, `dist_sat`, `dist_linear`, the eight
    /// `dist_{sl,sc}_h{cos,sin}{1,2}` hue-modulation terms, all eleven surround
    /// (`*_S`) terms, and `L_S_offset`. (Re-add them here if a future param
    /// version makes them non-zero; the reference-vector test will catch drift.)
    enum Params {
        // Core (24): M1, gamma, M2, H-K base
        static let M1 = simd_double3x3(rows: [
            SIMD3<Double>(0.7212986433113499, 0.45344826541531813, -0.19288975751942616),
            SIMD3<Double>(-0.788211869495579, 1.795241376757236, 0.0876172451181785),
            SIMD3<Double>(-0.0917700599912156, 0.45765588659459255, 1.2922045513917677),
        ])
        static let gamma = SIMD3<Double>(0.47229813098762524, 0.5149184096354483, 0.5113233386366979)
        static let M2 = simd_double3x3(rows: [
            SIMD3<Double>(-0.26355622180094096, 0.4168322883703174, 0.4926763141656403),
            SIMD3<Double>(1.8897570508777322, -3.1212232034205774, 1.0421666921060384),
            SIMD3<Double>(0.3585108617962056, 1.7694028193790368, -1.4120626067695372),
        ])
        static let hk_weight = 0.2676231133101982
        static let hk_power = 0.8934892185255707
        static let hk_hue_mod = 0.7173169828841472

        // Cubic L correction (+ hue-dependent term, v8)
        static let L_corr_p1 = 0.5385456675962418
        static let L_corr_p2 = 0.12508858146241716
        static let L_corr_p3 = 0.6768950256217603
        static let Lh_cos1 = -0.4963251525324449
        static let Lh_sin1 = -0.09564696283240552

        // Hue-dependent chroma scaling (4 harmonics)
        static let cs_cos1 = -0.195370576218515
        static let cs_sin1 = 0.5330819227283227
        static let cs_cos2 = 0.08863325582067766
        static let cs_sin2 = 0.9365540137751136
        static let cs_cos3 = 0.13789738139719568
        static let cs_sin3 = 0.061650260197979936
        static let cs_cos4 = 0.0641970862504494
        static let cs_sin4 = -0.027401052793571013

        // L-dependent chroma scaling
        static let lc1 = -1.5239477450767043
        static let lc2 = -1.751157310240011

        // Enhanced H-K harmonics
        static let hk_sin1 = 0.6915224124600773
        static let hk_cos2 = 0.48647127559605596
        static let hk_sin2 = 0.9853124591201782

        // Hue correction (4 harmonics)
        static let hue_cos1 = -0.02833024015436984
        static let hue_sin1 = -0.21131429516166544
        static let hue_cos2 = 0.2189784817615645
        static let hue_sin2 = -0.06871898981942523
        static let hue_cos3 = 0.005506053349515315
        static let hue_sin3 = -0.0641329861299175
        static let hue_cos4 = -0.053592461436994296
        static let hue_sin4 = -0.00954137464208059

        // Hue×Lightness chroma interaction
        static let hlc_cos1 = -0.43576378069144767
        static let hlc_sin1 = 1.060094063845983
        static let hlc_cos2 = 0.47931193034584496
        static let hlc_sin2 = -0.2622579649434462

        // Hue-dependent lightness scaling
        static let hl_cos1 = 0.13610794232685908
        static let hl_sin1 = 0.1168702235362288
        static let hl_cos2 = -0.01617739641422492
        static let hl_sin2 = 0.038145638815030566

        // Nonlinear chroma power
        static let cp_cos1 = -0.09900209889026965
        static let cp_sin1 = 0.059635520647228726
        static let cp_cos2 = -0.013586499967803128
        static let cp_sin2 = 0.2253393118474472

        // Adaptive dark-L compression (hue-dependent coefficient)
        static let lp_dark = -0.029053748937210654
        static let lp_dark_hcos = 1.3346761652952872
        static let lp_dark_hsin = -0.1698908144723919

        // Distance-stage params (used by compressedDeltaE — Task 4)
        static let dist_power = 1.9737081170404969
        static let dist_wC = 3.966003089807536
        static let dist_compress = 52.473130649294724
        static let dist_post_power = 0.47897301074925214
        static let dist_sl = -0.9155125151657894
        static let dist_sc = 2.9268353744941558

        // Display alignment: rigid (a,b) rotation. Pure isometry → distances
        // are exactly invariant; applied to match the reference's default.
        static let display_phi_deg = -28.2
    }

    // Precomputed inverse matrices (Python uses np.linalg.inv; simd_inverse on a
    // well-conditioned Double 3×3 is accurate to ~1e-15, validated by the
    // round-trip test). Single source of truth = Params.M1 / Params.M2.
    fileprivate static let M1Inv = simd_inverse(Params.M1)
    fileprivate static let M2Inv = simd_inverse(Params.M2)

    fileprivate static let displayPhiRad = Params.display_phi_deg * Double.pi / 180.0
    fileprivate static let abRotCos = cos(displayPhiRad)
    fileprivate static let abRotSin = sin(displayPhiRad)
}

// MARK: - Forward transform (XYZ(D65) → MetricSpace-Lab)

extension HelmlabMetric {
    /// Forward transform: CIE XYZ (D65) → MetricSpace-Lab coordinates.
    /// Faithful port of `helmlab.spaces.metric.MetricSpace.from_XYZ` with the
    /// bundled v21 params, surround = 0.5, `apply_neutral = false`, and the
    /// default `-28.2°` display rotation. The Task 3 reference-vector test
    /// (≥3 decimals) is the contract.
    @_spi(AskiResearch) public static func xyzToHelmlabMetric(_ xyz: SIMD3<Double>) -> SIMD3<Double> {
        // 1. XYZ → LMS
        let lms = Params.M1 * xyz
        // 2. Signed power compression (per channel, exactly invertible)
        let lmsC = SIMD3<Double>(
            signedPow(lms.x, Params.gamma.x),
            signedPow(lms.y, Params.gamma.y),
            signedPow(lms.z, Params.gamma.z)
        )
        // 3. LMS_c → Lab_raw
        let lab = Params.M2 * lmsC
        var L = lab.x
        var a = lab.y
        var b = lab.z

        // 3.5. Hue correction (rotate chromatic plane by δ(h))
        (a, b) = applyHueCorrection(a, b)
        let h0 = atan2(b, a)

        // 3.7. Embedded H-K: chroma-dependent lightness, uses post-correction C
        let cRaw = (a * a + b * b).squareRoot()
        let hkBoost =
            Params.hk_weight
            * pow(cRaw, min(max(Params.hk_power, 0.01), 10.0))
            * hkHueFactor(h0)
        L += hkBoost

        // 4. Cubic L correction (with hue-dependent term)
        L = lCorrect(L, h0)

        // 4.5. Dark-L compression (hue-dependent coefficient)
        L = darkLCompress(L, h0)

        // 5. Hue-dependent chroma scaling
        let cs = chromaScale(h0)
        a *= cs
        b *= cs

        // 5.5. Nonlinear chroma power
        let cPre = (a * a + b * b).squareRoot()
        let cNew = cPre > 0 ? pow(cPre, chromaPower(h0)) : 0
        a = cNew * cos(h0)
        b = cNew * sin(h0)

        // 6. L-dependent chroma scaling
        let t = lChromaScale(L)
        a *= t
        b *= t

        // 6.5. Hue×Lightness chroma interaction
        let hlc = hlcScale(h0, L)
        a *= hlc
        b *= hlc

        // 8. Hue-dependent lightness scaling
        L *= hueLightnessScale(h0)

        // 11. Rigid (a, b) display rotation (isometry; distances invariant)
        let aRot = a * abRotCos - b * abRotSin
        let bRot = a * abRotSin + b * abRotCos
        return SIMD3<Double>(L, aRot, bRot)
    }
}

// MARK: - Analytic inverse (MetricSpace-Lab → XYZ(D65))

extension HelmlabMetric {
    /// Analytic inverse: MetricSpace-Lab → CIE XYZ (D65). Each forward stage
    /// inverted in reverse order (Newton iteration for hue correction, dark-L,
    /// and cubic-L). Validated by the Task 3 round-trip test (<1e-9).
    @_spi(AskiResearch) public static func helmlabMetricToXYZ(_ lab: SIMD3<Double>) -> SIMD3<Double> {
        // 11. Undo rigid rotation
        var a = lab.y * abRotCos + lab.z * abRotSin
        var b = -lab.y * abRotSin + lab.z * abRotCos

        // 8. Undo hue-dependent lightness scaling → L1 (= L before hl scaling)
        var l1 = lab.x / hueLightnessScale(atan2(b, a))

        // 6.5. Undo hue×lightness chroma interaction (uses L1)
        let hlc = hlcScale(atan2(b, a), l1)
        a /= hlc
        b /= hlc

        // 6. Undo L-dependent chroma scaling (uses L1)
        let t = lChromaScale(l1)
        a /= t
        b /= t

        // 5.5. Undo nonlinear chroma power
        let hCp = atan2(b, a)
        let cPost = (a * a + b * b).squareRoot()
        let cOrig = cPost > 0 ? pow(cPost, 1.0 / chromaPower(hCp)) : 0
        a = cOrig * cos(hCp)
        b = cOrig * sin(hCp)

        // 5. Undo hue-dependent chroma scaling → a_raw, b_raw
        let cs = chromaScale(atan2(b, a))
        a /= cs
        b /= cs

        // 4.5. Undo dark-L compression
        l1 = darkLCompressInv(l1, atan2(b, a))

        // 4. Undo cubic L correction → L_raw
        var lRaw = lCorrectInv(l1, atan2(b, a))

        // 3.7. Undo embedded H-K
        let cRaw = (a * a + b * b).squareRoot()
        let hkBoost =
            Params.hk_weight
            * pow(cRaw, min(max(Params.hk_power, 0.01), 10.0))
            * hkHueFactor(atan2(b, a))
        lRaw -= hkBoost

        // 3.5. Undo hue correction
        (a, b) = undoHueCorrection(a, b)

        // 3. Lab_raw → LMS_c
        let lmsC = M2Inv * SIMD3<Double>(lRaw, a, b)
        // 2. Undo power compression (sign-preserving)
        let lms = SIMD3<Double>(
            signedPow(lmsC.x, 1.0 / Params.gamma.x),
            signedPow(lmsC.y, 1.0 / Params.gamma.y),
            signedPow(lmsC.z, 1.0 / Params.gamma.z)
        )
        // 1. LMS → XYZ
        return M1Inv * lms
    }
}

// MARK: - Per-stage helpers (transcribed from metric.py)

extension HelmlabMetric {
    /// Sign-preserving power: `sign(x) · |x|^g`. Handles out-of-gamut negative
    /// LMS exactly (matches numpy `np.sign(x) * np.abs(x) ** g`), so a slightly
    /// out-of-gamut query never produces `NaN` in the power stage.
    @inline(__always)
    fileprivate static func signedPow(_ x: Double, _ g: Double) -> Double {
        copysign(pow(abs(x), g), x)
    }

    /// δ(h): Fourier hue rotation (up to 4th harmonic).
    fileprivate static func hueDelta(_ h: Double) -> Double {
        Params.hue_cos1 * cos(h) + Params.hue_sin1 * sin(h)
            + Params.hue_cos2 * cos(2 * h) + Params.hue_sin2 * sin(2 * h)
            + Params.hue_cos3 * cos(3 * h) + Params.hue_sin3 * sin(3 * h)
            + Params.hue_cos4 * cos(4 * h) + Params.hue_sin4 * sin(4 * h)
    }

    /// d/dh of δ(h), for the inverse Newton iteration.
    fileprivate static func hueDeltaDeriv(_ h: Double) -> Double {
        -Params.hue_cos1 * sin(h) + Params.hue_sin1 * cos(h)
            - 2 * Params.hue_cos2 * sin(2 * h) + 2 * Params.hue_sin2 * cos(2 * h)
            - 3 * Params.hue_cos3 * sin(3 * h) + 3 * Params.hue_sin3 * cos(3 * h)
            - 4 * Params.hue_cos4 * sin(4 * h) + 4 * Params.hue_sin4 * cos(4 * h)
    }

    fileprivate static func applyHueCorrection(_ a: Double, _ b: Double) -> (Double, Double) {
        let h = atan2(b, a)
        let hNew = h + hueDelta(h)
        let c = (a * a + b * b).squareRoot()
        return (c * cos(hNew), c * sin(hNew))
    }

    fileprivate static func undoHueCorrection(_ a: Double, _ b: Double) -> (Double, Double) {
        let hOut = atan2(b, a)
        let c = (a * a + b * b).squareRoot()
        var hRaw = hOut
        for _ in 0..<8 {
            let f = hRaw + hueDelta(hRaw) - hOut
            var fp = 1 + hueDeltaDeriv(hRaw)
            if abs(fp) < 1e-10 { fp = 1 }
            hRaw -= f / fp
        }
        return (c * cos(hRaw), c * sin(hRaw))
    }

    fileprivate static func hkHueFactor(_ h: Double) -> Double {
        1 + Params.hk_hue_mod * cos(h) + Params.hk_sin1 * sin(h)
            + Params.hk_cos2 * cos(2 * h) + Params.hk_sin2 * sin(2 * h)
    }

    fileprivate static func chromaScale(_ h: Double) -> Double {
        exp(
            Params.cs_cos1 * cos(h) + Params.cs_sin1 * sin(h)
                + Params.cs_cos2 * cos(2 * h) + Params.cs_sin2 * sin(2 * h)
                + Params.cs_cos3 * cos(3 * h) + Params.cs_sin3 * sin(3 * h)
                + Params.cs_cos4 * cos(4 * h) + Params.cs_sin4 * sin(4 * h))
    }

    fileprivate static func lChromaScale(_ L: Double) -> Double {
        let dL = L - 0.5
        let arg = Params.lc1 * dL + Params.lc2 * dL * dL
        return exp(min(max(arg, -30.0), 30.0))
    }

    fileprivate static func hlcScale(_ h: Double, _ L: Double) -> Double {
        let hueFactor =
            Params.hlc_cos1 * cos(h) + Params.hlc_sin1 * sin(h)
            + Params.hlc_cos2 * cos(2 * h) + Params.hlc_sin2 * sin(2 * h)
        let arg = (L - 0.5) * hueFactor
        return exp(min(max(arg, -30.0), 30.0))
    }

    fileprivate static func hueLightnessScale(_ h: Double) -> Double {
        exp(
            Params.hl_cos1 * cos(h) + Params.hl_sin1 * sin(h)
                + Params.hl_cos2 * cos(2 * h) + Params.hl_sin2 * sin(2 * h))
    }

    fileprivate static func chromaPower(_ h: Double) -> Double {
        1 + Params.cp_cos1 * cos(h) + Params.cp_sin1 * sin(h)
            + Params.cp_cos2 * cos(2 * h) + Params.cp_sin2 * sin(2 * h)
    }

    fileprivate static func darkLCoeff(_ h: Double) -> Double {
        Params.lp_dark + Params.lp_dark_hcos * cos(h) + Params.lp_dark_hsin * sin(h)
    }

    fileprivate static func darkLCompress(_ L: Double, _ h: Double) -> Double {
        let coeff = darkLCoeff(h)
        let oml = max(0.0, 1.0 - L)
        let g = coeff * L * oml * oml
        return L * exp(min(max(g, -30.0), 30.0))
    }

    fileprivate static func darkLCompressInv(_ lNew: Double, _ h: Double) -> Double {
        let coeff = darkLCoeff(h)
        var L = lNew
        for _ in 0..<12 {
            let oml = max(0.0, 1.0 - L)
            let g = coeff * L * oml * oml
            let eg = exp(min(max(g, -30.0), 30.0))
            let f = L * eg - lNew
            let gp = coeff * oml * (1.0 - 3.0 * L)  // g'(L); 0 for L≥1
            var fp = eg * (1.0 + L * gp)
            if abs(fp) < 1e-10 { fp = 1 }
            L -= f / fp
        }
        return L
    }

    fileprivate static func lCorrect(_ lRaw: Double, _ h: Double) -> Double {
        let t = lRaw * (1.0 - lRaw)
        let lh = Params.Lh_cos1 * cos(h) + Params.Lh_sin1 * sin(h)
        return lRaw + Params.L_corr_p1 * t + Params.L_corr_p2 * t * (0.5 - lRaw)
            + Params.L_corr_p3 * t * t + t * lh
    }

    fileprivate static func lCorrectInv(_ l1: Double, _ h: Double) -> Double {
        let lh = Params.Lh_cos1 * cos(h) + Params.Lh_sin1 * sin(h)
        var L = l1
        for _ in 0..<15 {
            let t = L * (1.0 - L)
            let dt = 1.0 - 2.0 * L
            let f =
                L + Params.L_corr_p1 * t + Params.L_corr_p2 * t * (0.5 - L)
                + Params.L_corr_p3 * t * t + t * lh - l1
            var dfdL =
                1.0 + (Params.L_corr_p1 + lh) * dt
                + Params.L_corr_p2 * (dt * (0.5 - L) - t)
                + Params.L_corr_p3 * 2.0 * t * dt
            if abs(dfdL) < 1e-10 { dfdL = 1 }
            L -= f / dfdL
        }
        return L
    }
}

// MARK: - Distances (over MetricSpace-Lab)

extension HelmlabMetric {
    /// Plain Euclidean distance over MetricSpace-Lab. Monotonic at all
    /// distances → preferred for ranking distant palette candidates. No
    /// distance params. Matches the reference's plain-Euclidean fallback
    /// (`np.sqrt(np.sum((c1 - c2)**2))`).
    @_spi(AskiResearch) public static func euclideanDistance(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        simd_length(a - b)
    }

    /// Trained Minkowski + monotonic-compression ΔE. Faithful port of the v21
    /// branch of `MetricSpace._distance_pair` (the one `MetricSpace.distance`
    /// reaches via `from_XYZ(apply_neutral=False)`). For v21 the active terms
    /// are: pair-weighted SL/SC (`dist_sl`, `dist_sc`; the hue-modulation terms
    /// are all 0), the Minkowski exponent `dist_power`, monotonic compression
    /// `dist_compress` (v12 form; `dist_linear`/`dist_nl` are 0), and the
    /// post-compress power `dist_post_power`. Best STRESS on small diffs;
    /// saturates near ~0.15 for very dissimilar pairs. Not monotonic in squared
    /// form — callers compute the full distance per candidate.
    @_spi(AskiResearch) public static func compressedDeltaE(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let d = a - b
        var dL2 = d.x * d.x
        var dab2 = d.y * d.y + d.z * d.z

        // Pair-dependent SL/SC weighting (hue-modulation terms are 0 in v21).
        let lAvg = (a.x + b.x) * 0.5
        let sl = 1.0 + Params.dist_sl * (lAvg - 0.5) * (lAvg - 0.5)
        dL2 /= sl * sl

        let c1 = (a.y * a.y + a.z * a.z).squareRoot()
        let c2 = (b.y * b.y + b.z * b.z).squareRoot()
        let cAvg = (c1 + c2) * 0.5
        let sc = 1.0 + Params.dist_sc * cAvg
        dab2 /= sc * sc

        // Minkowski combine.
        let sumSq = dL2 + Params.dist_wC * dab2
        var de = pow(sumSq, Params.dist_power / 2.0)

        // v12 monotonic compression (always positive, no ceiling issues).
        de = de / (1.0 + Params.dist_compress * de)

        // v14b post-compress power.
        return pow(de, Params.dist_post_power)
    }
}
