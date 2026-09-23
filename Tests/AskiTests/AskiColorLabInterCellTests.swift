import Foundation
import Testing
import AskiToolSupport
@testable import AskiColorLab

/// ASTSK-43 Unit 3 — the two pure units the inter-cell-smoothing screen is built
/// from: `GridComposite` (tile chosen glyphs into a rendered pixel image, so M1/M2
/// have a native-resolution grid with real seams to score) and `InterCellGate`
/// (the frozen PASS/KILL decision rule, encoded once before the run).
@Suite struct AskiColorLabGridCompositeTests {

    /// Per-character stub raster so the tiling logic is tested without CoreText.
    private func stub(_ ch: Character, cellPx: Int) -> [Float] {
        switch ch {
        case "A": return [Float](repeating: 1, count: cellPx * cellPx)
        case "B": return [Float](repeating: 0, count: cellPx * cellPx)
        case "C": return [Float](repeating: 0.5, count: cellPx * cellPx)
        case "D": return [Float](repeating: 0.25, count: cellPx * cellPx)
        default: return [Float](repeating: 0, count: cellPx * cellPx)
        }
    }

    @Test func tilesCellsAtCorrectOffsetsAndSize() {
        let chars: [[Character]] = [["A", "B"], ["C", "D"]]
        let cellPx = 2
        let out = GridComposite.compose(characters: chars, cellPx: cellPx) { stub($0, cellPx: cellPx) }
        #expect(out.width == 4 && out.height == 4)
        // Top-left pixel of each cell carries that cell's value.
        #expect(out.pixels[0 * 4 + 0] == 1)  // A at (0,0)
        #expect(out.pixels[0 * 4 + 2] == 0)  // B at (col 1 → x=2)
        #expect(out.pixels[2 * 4 + 0] == 0.5)  // C at (row 1 → y=2)
        #expect(out.pixels[2 * 4 + 2] == 0.25)  // D at (2,2)
    }

    @Test func preservesIntraCellOrientation() {
        // 'E' = ink in its top-left sub-pixel only; must land at the cell's top-left.
        let chars: [[Character]] = [["E"]]
        let cellPx = 2
        let out = GridComposite.compose(characters: chars, cellPx: cellPx) { _ in
            [1, 0, 0, 0]  // row-major 2×2: only (0,0) is ink
        }
        #expect(out.width == 2 && out.height == 2)
        #expect(out.pixels[0] == 1)
        #expect(out.pixels[1] == 0)
        #expect(out.pixels[2] == 0)
        #expect(out.pixels[3] == 0)
    }

    @Test func returnsEmptyForDegenerateGrid() {
        #expect(GridComposite.compose(characters: [], cellPx: 2) { _ in [] }.width == 0)
        // Ragged rows are rejected.
        let ragged: [[Character]] = [["A", "B"], ["C"]]
        #expect(GridComposite.compose(characters: ragged, cellPx: 2) { c in [Float](repeating: 0, count: 4) }.width == 0)
    }
}

@Suite struct AskiColorLabInterCellGateTests {

    private func metrics(m1: Double, gmsd: Double, haarpsi: Double) -> PoolMetrics {
        PoolMetrics(m1: m1, gmsd: gmsd, haarpsi: haarpsi)
    }

    /// Naturals that neither improve nor regress (used to isolate the line-art rule).
    private let flatNaturals = (
        base: PoolMetrics(m1: 0.4, gmsd: 0.10, haarpsi: 0.90),
        treat: PoolMetrics(m1: 0.40, gmsd: 0.10, haarpsi: 0.90)
    )

    @Test func cleanLiftPasses() {
        let base = ArmMetrics(lineArt: metrics(m1: 0.50, gmsd: 0.20, haarpsi: 0.80), naturals: flatNaturals.base)
        let treat = ArmMetrics(
            lineArt: metrics(m1: 0.56, gmsd: 0.199, haarpsi: 0.801), naturals: flatNaturals.treat)
        #expect(InterCellGate.decide(baseline: base, treatment: treat) == .pass)
    }

    @Test func flatM1Kills() {
        // ΔM1 = 0.005 < the 0.01 absolute margin.
        let base = ArmMetrics(lineArt: metrics(m1: 0.50, gmsd: 0.20, haarpsi: 0.80), naturals: flatNaturals.base)
        let treat = ArmMetrics(
            lineArt: metrics(m1: 0.505, gmsd: 0.199, haarpsi: 0.801), naturals: flatNaturals.treat)
        let v = InterCellGate.decide(baseline: base, treatment: treat)
        guard case .kill(let why) = v else { Issue.record("expected KILL, got \(v)"); return }
        #expect(why.lowercased().contains("m1"))
    }

    @Test func naturalsWashoutKills() {
        // M1 lifts on line-art, but naturals GMSD regresses > 0.5%.
        let base = ArmMetrics(lineArt: metrics(m1: 0.50, gmsd: 0.20, haarpsi: 0.80), naturals: flatNaturals.base)
        let treat = ArmMetrics(
            lineArt: metrics(m1: 0.56, gmsd: 0.199, haarpsi: 0.801),
            naturals: metrics(m1: 0.40, gmsd: 0.105, haarpsi: 0.90))  // GMSD 0.10→0.105 = +5%
        let v = InterCellGate.decide(baseline: base, treatment: treat)
        guard case .kill(let why) = v else { Issue.record("expected KILL, got \(v)"); return }
        #expect(why.lowercased().contains("natural"))
    }

    @Test func oracleDisagreementTriggersRerun() {
        // Line-art GMSD says much better, HaarPSI says much worse → instrument failure.
        let base = ArmMetrics(lineArt: metrics(m1: 0.50, gmsd: 0.20, haarpsi: 0.80), naturals: flatNaturals.base)
        let treat = ArmMetrics(
            lineArt: metrics(m1: 0.56, gmsd: 0.18, haarpsi: 0.74),  // GMSD −10%, HaarPSI −7.5%
            naturals: flatNaturals.treat)
        let v = InterCellGate.decide(baseline: base, treatment: treat)
        guard case .rerun = v else { Issue.record("expected RERUN, got \(v)"); return }
    }

    /// Regression anchor for the screen's fail-loud guard. The frozen gate cannot
    /// defend itself against an empty pool: if a pool is dropped entirely, its
    /// `pooledMean` is all-NaN, and every washout comparison here is `NaN < x` /
    /// `NaN > x` — all false — so the gate falls through to a line-art-only verdict
    /// instead of failing. `InterCellSmoothingScreen.run` therefore throws on any
    /// unscored fixture rather than feed the gate a partial battery.
    @Test func nanNaturalsSlipPastWashoutSoTheScreenMustFailLoud() {
        let nan = PoolMetrics(m1: .nan, gmsd: .nan, haarpsi: .nan)
        let base = ArmMetrics(lineArt: metrics(m1: 0.50, gmsd: 0.20, haarpsi: 0.80), naturals: nan)
        let treat = ArmMetrics(
            lineArt: metrics(m1: 0.56, gmsd: 0.199, haarpsi: 0.801), naturals: nan)
        // NaN naturals trip neither the rerun (oracle-disagreement) nor the washout
        // KILLs, so the verdict is decided by line-art alone — the exact hazard the
        // screen-level guard prevents by refusing a partial battery.
        #expect(InterCellGate.decide(baseline: base, treatment: treat) == .pass)
    }

    @Test func lineArtM2RegressKillsEvenWithM1Lift() {
        // M1 lifts, naturals fine, oracles agree (both worse on line-art GMSD/HaarPSI
        // within deadband for HaarPSI) → line-art M2 regress is a KILL, not a PASS.
        let base = ArmMetrics(lineArt: metrics(m1: 0.50, gmsd: 0.20, haarpsi: 0.80), naturals: flatNaturals.base)
        let treat = ArmMetrics(
            lineArt: metrics(m1: 0.56, gmsd: 0.21, haarpsi: 0.799),  // GMSD +5%, HaarPSI ~flat
            naturals: flatNaturals.treat)
        let v = InterCellGate.decide(baseline: base, treatment: treat)
        guard case .kill(let why) = v else { Issue.record("expected KILL, got \(v)"); return }
        #expect(why.lowercased().contains("gmsd") || why.lowercased().contains("line-art"))
    }
}
