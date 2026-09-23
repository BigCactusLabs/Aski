import Foundation

// MARK: - Frozen PASS/KILL gate for the ASTSK-43 inter-cell-smoothing screen

/// Mean oracle readings over one fixture pool. `m1` higher = better (seam
/// continuity), `gmsd` lower = better, `haarpsi` higher = better.
struct PoolMetrics: Sendable {
    let m1: Double
    let gmsd: Double
    let haarpsi: Double
}

/// One arm's pooled metrics (`baseline` = raw input, `treatment` = guided-filtered
/// input run through the same converter).
struct ArmMetrics: Sendable {
    let lineArt: PoolMetrics
    let naturals: PoolMetrics
}

enum InterCellVerdict: Equatable {
    case pass
    case kill(String)
    /// Dual-oracle disagreement → instrument failure, re-run (never pick a winner).
    case rerun(String)
}

/// The decision rule **frozen 2026-06-24 before any measurement**
/// (`docs/Research/2026-06-24-astsk43-inter-cell-smoothing.md`). Pure function of
/// the two arms' pooled metrics — no constant here is tuned to a result.
enum InterCellGate {
    /// M1 must lift by at least this much (absolute) AND `m1RelMargin` (relative),
    /// on the line-art pool, to count as non-flat.
    static let m1AbsMargin = 0.01
    static let m1RelMargin = 0.02
    /// GMSD/HaarPSI relative no-regress tolerance (0.5%) and oracle-sign deadband.
    static let regressTol = 0.005

    static func decide(baseline: ArmMetrics, treatment: ArmMetrics) -> InterCellVerdict {
        // 1. Instrument failure first: do the two oracles disagree on the sign of
        //    the quality change on either pool? (GMSD ↓ = better, HaarPSI ↑ = better.)
        for (b, t, name) in [
            (baseline.lineArt, treatment.lineArt, "line-art"),
            (baseline.naturals, treatment.naturals, "naturals"),
        ] where oraclesDisagree(b, t) {
            return .rerun("oracle disagreement on \(name): GMSD and HaarPSI disagree on sign")
        }

        // 2. Naturals washout (either oracle moving the wrong way > tolerance).
        if treatment.naturals.gmsd > baseline.naturals.gmsd * (1 + regressTol) {
            return .kill("naturals washout: GMSD \(pct(baseline.naturals.gmsd, treatment.naturals.gmsd)) (worse)")
        }
        if treatment.naturals.haarpsi < baseline.naturals.haarpsi * (1 - regressTol) {
            return .kill(
                "naturals washout: HaarPSI \(pct(baseline.naturals.haarpsi, treatment.naturals.haarpsi)) (worse)")
        }

        // 3. Flat M1 on line-art (the lever's whole point).
        let dM1 = treatment.lineArt.m1 - baseline.lineArt.m1
        let liftsM1 = dM1 >= m1AbsMargin && dM1 >= baseline.lineArt.m1 * m1RelMargin
        if !liftsM1 {
            return .kill("flat M1: line-art ΔM1=\(round4(dM1)) below the +\(m1AbsMargin)/\(pctOf(m1RelMargin)) margin")
        }

        // 4. M2 no-regress on line-art (naturals already covered above).
        if treatment.lineArt.gmsd > baseline.lineArt.gmsd * (1 + regressTol) {
            return .kill("line-art GMSD regress: \(pct(baseline.lineArt.gmsd, treatment.lineArt.gmsd)) (worse)")
        }
        // 5. HaarPSI agreement on line-art.
        if treatment.lineArt.haarpsi < baseline.lineArt.haarpsi * (1 - regressTol) {
            return .kill("line-art HaarPSI regress: \(pct(baseline.lineArt.haarpsi, treatment.lineArt.haarpsi)) (worse)")
        }
        return .pass
    }

    // MARK: - Internals

    private static func oraclesDisagree(_ b: PoolMetrics, _ t: PoolMetrics) -> Bool {
        let gmsdBetter = (b.gmsd - t.gmsd) / b.gmsd  // + = better
        let haarBetter = (t.haarpsi - b.haarpsi) / b.haarpsi  // + = better
        let gmsdSaysBetter = gmsdBetter > regressTol
        let gmsdSaysWorse = gmsdBetter < -regressTol
        let haarSaysBetter = haarBetter > regressTol
        let haarSaysWorse = haarBetter < -regressTol
        return (gmsdSaysBetter && haarSaysWorse) || (gmsdSaysWorse && haarSaysBetter)
    }

    private static func pct(_ base: Double, _ treat: Double) -> String {
        pctOf((treat - base) / base)
    }
    private static func pctOf(_ frac: Double) -> String {
        let s = frac >= 0 ? "+" : ""
        return "\(s)\((frac * 100 * 100).rounded() / 100)%"
    }
    private static func round4(_ v: Double) -> Double { (v * 10000).rounded() / 10000 }
}
