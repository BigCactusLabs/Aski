import Testing

@testable import AskiMotionLab

/// ASTSK-45 source-tether gate. Forks the ASTSK-41 §7 decision rule to a scalar-rho
/// operating point, reusing the churn/GMSD/HaarPSI triple screen, the three tolerance
/// constants, the four-cell validation discipline, and the §7.1 oracle-sign band verbatim.
@Suite struct SourceTetherGateTests {
    /// One (stimulus, column) cell: a per-frame-independent baseline plus points at each grid rho.
    static func cell(
        _ stim: TemporalStimulus,
        _ cols: Int,
        baseChurn: Double,
        baseGMSD: Double,
        baseHaar: Double,
        _ pts: [(Float, Double, Double, Double)],
        baselineRho: Float = SourceTetherGate.baselineRho
    ) -> SourceTetherCell {
        let baseline = SourceTetherMeasurement(
            rho: baselineRho,
            meanGlyphChurn: baseChurn,
            gmsd: baseGMSD,
            haarpsi: baseHaar
        )
        let points = pts.map {
            SourceTetherMeasurement(rho: $0.0, meanGlyphChurn: $0.1, gmsd: $0.2, haarpsi: $0.3)
        }
        return SourceTetherCell(stimulus: stim, columns: cols, baseline: baseline, points: points)
    }

    /// A single rho point that clears all three screens against the 0.10/0.10/0.90 baseline.
    static let goodPoint: (Float, Double, Double, Double) = (0.5, 0.07, 0.10, 0.90)

    /// The full frozen rho grid at a non-qualifying default, with per-rho overrides applied.
    static func fullGridPoints(
        overrides: [(Float, Double, Double, Double)] = []
    ) -> [(Float, Double, Double, Double)] {
        var points = SourceTetherGate.rhoGrid.map { rho in (rho, 0.10, 0.10, 0.90) }
        for override in overrides {
            if let index = points.firstIndex(where: { $0.0 == override.0 }) {
                points[index] = override
            } else {
                points.append(override)
            }
        }
        return points
    }

    static func fourGoodCells() -> [SourceTetherCell] {
        TemporalStimulus.allCases.flatMap { stimulus in
            [64, 80].map {
                cell(
                    stimulus, $0, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90,
                    fullGridPoints(overrides: [goodPoint]))
            }
        }
    }

    // MARK: - qualify triple

    @Test func qualifiesRequiresChurnDropAndGmsdAndHaarpsi() {
        let baseline = SourceTetherMeasurement(
            rho: SourceTetherGate.baselineRho, meanGlyphChurn: 0.10, gmsd: 0.10, haarpsi: 0.90)
        func point(_ churn: Double, _ gmsd: Double, _ haar: Double) -> SourceTetherMeasurement {
            SourceTetherMeasurement(rho: 0.5, meanGlyphChurn: churn, gmsd: gmsd, haarpsi: haar)
        }

        #expect(SourceTetherGate.qualifies(point(0.07, 0.10, 0.90), baseline: baseline))
        // Each screen, flipped one at a time, must reject.
        #expect(!SourceTetherGate.qualifies(point(0.09, 0.10, 0.90), baseline: baseline))  // churn
        #expect(!SourceTetherGate.qualifies(point(0.07, 0.11, 0.90), baseline: baseline))  // GMSD
        #expect(!SourceTetherGate.qualifies(point(0.07, 0.10, 0.80), baseline: baseline))  // HaarPSI
    }

    // MARK: - PASS

    @Test func passWhenSharedRhoQualifiesAllFour() {
        let (verdict, shared) = SourceTetherGate.decide(cells: Self.fourGoodCells())
        #expect(verdict == .pass(rho: 0.5))
        #expect(shared == 0.5)
    }

    // MARK: - KILL taxonomy

    @Test func killInertWhenNoChurnDropOnAStimulus() {
        let inert: (Float, Double, Double, Double) = (0.5, 0.10, 0.10, 0.90)
        let cells = [
            Self.cell(.s1, 64, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90, Self.fullGridPoints(overrides: [Self.goodPoint])),
            Self.cell(.s1, 80, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90, Self.fullGridPoints(overrides: [Self.goodPoint])),
            Self.cell(.s2, 64, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90, Self.fullGridPoints(overrides: [inert])),
            Self.cell(.s2, 80, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90, Self.fullGridPoints(overrides: [inert])),
        ]

        let (verdict, _) = SourceTetherGate.decide(cells: cells)
        Self.expectKill(verdict, contains: "inert")
    }

    @Test func killFreezeTrapWhenChurnDropAlwaysBustsFidelity() {
        let trap: (Float, Double, Double, Double) = (0.5, 0.07, 0.20, 0.90)  // churn down, GMSD busts
        let cells = TemporalStimulus.allCases.flatMap { stimulus in
            [64, 80].map {
                Self.cell(stimulus, $0, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90, Self.fullGridPoints(overrides: [trap]))
            }
        }

        let (verdict, _) = SourceTetherGate.decide(cells: cells)
        Self.expectKill(verdict, contains: "freeze")
    }

    @Test func killNonRobustWhenRhoQualifiesButNotAllFour() {
        var cells = Self.fourGoodCells()
        // s2/80: good churn+GMSD but HaarPSI busts within-band on GMSD (no sign disagreement),
        // so no RERUN — the point fails to qualify and the shared rho lands 3/4.
        cells[3] = Self.cell(
            .s2, 80, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90,
            Self.fullGridPoints(overrides: [(0.5, 0.07, 0.10, 0.80)]))

        let (verdict, _) = SourceTetherGate.decide(cells: cells)
        Self.expectKill(verdict, contains: "robust")
    }

    // MARK: - reused validation discipline

    @Test func killIncompleteWhenInputIsEmpty() {
        let (verdict, shared) = SourceTetherGate.decide(cells: [])
        Self.expectKill(verdict, contains: "incomplete")
        #expect(shared == nil)
    }

    @Test func killIncompleteGridWhenPointsMissing() {
        let cells = TemporalStimulus.allCases.flatMap { stimulus in
            [64, 80].map {
                Self.cell(stimulus, $0, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90, [Self.goodPoint])
            }
        }
        let (verdict, _) = SourceTetherGate.decide(cells: cells)
        Self.expectKill(verdict, contains: "grid")
    }

    @Test func killBaselineIdentityMismatch() {
        var cells = Self.fourGoodCells()
        cells[0] = Self.cell(
            .s1, 64, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90,
            Self.fullGridPoints(overrides: [Self.goodPoint]), baselineRho: 0.5)
        let (verdict, _) = SourceTetherGate.decide(cells: cells)
        Self.expectKill(verdict, contains: "baseline")
    }

    // MARK: - inherited §7.1 oracle-sign band

    @Test func noRerunWhenSubBandSignDisagreementHeldAtSharedPoint() {
        // GMSD +0.001 (band ±0.002) and HaarPSI −0.003 (band ±0.009): opposite signs but both
        // within band → "fidelity held", not disagreement → substantive PASS.
        let cells = TemporalStimulus.allCases.flatMap { stimulus in
            [64, 80].map {
                Self.cell(stimulus, $0, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90, Self.fullGridPoints(overrides: [(0.5, 0.07, 0.099, 0.897)]))
            }
        }
        let (verdict, shared) = SourceTetherGate.decide(cells: cells)
        #expect(verdict == .pass(rho: 0.5))
        #expect(shared == 0.5)
    }

    @Test func rerunOracleDisagreementBeforeNonRobustKill() {
        // s2/80: GMSD +0.02 and HaarPSI −0.10, both beyond band, opposite signs → RERUN,
        // and it fires before the non-robust KILL.
        var cells = Self.fourGoodCells()
        cells[3] = Self.cell(
            .s2, 80, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90,
            Self.fullGridPoints(overrides: [(0.5, 0.07, 0.08, 0.80)]))
        let (verdict, shared) = SourceTetherGate.decide(cells: cells)
        if case .rerun(let why) = verdict {
            #expect(why.contains("oracle"))
            #expect(shared == 0.5)
        } else {
            Issue.record("expected oracle RERUN before non-robust KILL, got \(verdict)")
        }
    }

    private static func expectKill(_ verdict: SourceTetherVerdict, contains needles: String...) {
        if case .kill(let why) = verdict {
            for needle in needles {
                #expect(why.contains(needle))
            }
        } else {
            Issue.record("expected KILL containing \(needles), got \(verdict)")
        }
    }
}
