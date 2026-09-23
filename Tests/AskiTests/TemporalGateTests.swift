import Testing

@testable import AskiMotionLab

@Suite struct TemporalGateTests {
    static func cell(
        _ stim: TemporalStimulus,
        _ cols: Int,
        baseChurn: Double,
        baseGMSD: Double,
        baseHaar: Double,
        _ pts: [(Float, Float, Double, Double, Double)],
        baselineAlpha: Float = 1,
        baselineTau: Float = 0
    ) -> GateCell {
        let baseline = CellMeasurement(
            alpha: baselineAlpha,
            tau: baselineTau,
            meanGlyphChurn: baseChurn,
            gmsd: baseGMSD,
            haarpsi: baseHaar
        )
        let points = pts.map {
            CellMeasurement(
                alpha: $0.0,
                tau: $0.1,
                meanGlyphChurn: $0.2,
                gmsd: $0.3,
                haarpsi: $0.4
            )
        }
        return GateCell(stimulus: stim, columns: cols, baseline: baseline, points: points)
    }

    static let goodPoint: (Float, Float, Double, Double, Double) = (0.6, 0.10, 0.07, 0.10, 0.90)

    static func fullGridPoints(
        overrides: [(Float, Float, Double, Double, Double)] = []
    ) -> [(Float, Float, Double, Double, Double)] {
        var points = TemporalGate.alphaGrid.flatMap { alpha in
            TemporalGate.tauGrid.map { tau in
                (alpha, tau, 0.10, 0.10, 0.90)
            }
        }

        for override in overrides {
            if let index = points.firstIndex(where: { $0.0 == override.0 && $0.1 == override.1 }) {
                points[index] = override
            } else {
                points.append(override)
            }
        }

        return points
    }

    static func fourGoodCells() -> [GateCell] {
        [
            cell(.s1, 64, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90, fullGridPoints(overrides: [goodPoint])),
            cell(.s1, 80, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90, fullGridPoints(overrides: [goodPoint])),
            cell(.s2, 64, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90, fullGridPoints(overrides: [goodPoint])),
            cell(.s2, 80, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90, fullGridPoints(overrides: [goodPoint])),
        ]
    }

    @Test func passWhenSharedAlphaSub1QualifiesAllFour() {
        let (verdict, shared) = TemporalGate.decide(cells: Self.fourGoodCells())
        #expect(verdict == .pass(alpha: 0.6, tau: 0.10))
        #expect(shared?.alpha == 0.6 && shared?.tau == 0.10)
    }

    @Test func killIncompleteGridWhenOnlySharedPointRowsAreProvided() {
        let cells = [
            Self.cell(.s1, 64, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90, [Self.goodPoint]),
            Self.cell(.s1, 80, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90, [Self.goodPoint]),
            Self.cell(.s2, 64, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90, [Self.goodPoint]),
            Self.cell(.s2, 80, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90, [Self.goodPoint]),
        ]

        let (verdict, shared) = TemporalGate.decide(cells: cells)

        Self.expectKill(verdict, contains: "incomplete", "grid")
        #expect(shared == nil)
    }

    @Test func killBaselineIdentityMismatch() {
        var cells = Self.fourGoodCells()
        cells[0] = Self.cell(
            .s1,
            64,
            baseChurn: 0.10,
            baseGMSD: 0.10,
            baseHaar: 0.90,
            Self.fullGridPoints(overrides: [Self.goodPoint]),
            baselineAlpha: 0.6,
            baselineTau: 0.10
        )

        let (verdict, shared) = TemporalGate.decide(cells: cells)

        Self.expectKill(verdict, contains: "baseline")
        #expect(shared == nil)
    }

    @Test func killIncompleteWhenInputIsEmpty() {
        let (verdict, shared) = TemporalGate.decide(cells: [])

        Self.expectKill(verdict, contains: "incomplete")
        #expect(shared == nil)
    }

    @Test func killIncompleteWhenOnlyOneGoodCellIsProvided() {
        let cells = [
            Self.cell(.s1, 64, baseChurn: 0.10, baseGMSD: 0.10, baseHaar: 0.90, [Self.goodPoint])
        ]

        let (verdict, shared) = TemporalGate.decide(cells: cells)

        Self.expectKill(verdict, contains: "incomplete")
        #expect(shared == nil)
    }

    @Test func killOffGridPointInsteadOfPassing() {
        let offGridGood: (Float, Float, Double, Double, Double) = (0.5, 0.10, 0.07, 0.10, 0.90)
        let cells = TemporalStimulus.allCases.flatMap { stimulus in
            [64, 80].map {
                Self.cell(
                    stimulus,
                    $0,
                    baseChurn: 0.10,
                    baseGMSD: 0.10,
                    baseHaar: 0.90,
                    Self.fullGridPoints() + [offGridGood]
                )
            }
        }

        let (verdict, shared) = TemporalGate.decide(cells: cells)

        Self.expectKill(verdict, contains: "grid")
        #expect(shared == nil)
    }

    @Test func killDuplicateOperatingPointsWithinCell() {
        var cells = Self.fourGoodCells()
        cells[0] = Self.cell(
            .s1,
            64,
            baseChurn: 0.10,
            baseGMSD: 0.10,
            baseHaar: 0.90,
            Self.fullGridPoints(overrides: [Self.goodPoint]) + [Self.goodPoint]
        )

        let (verdict, shared) = TemporalGate.decide(cells: cells)

        Self.expectKill(verdict, contains: "duplicate")
        #expect(shared == nil)
    }

    @Test func killInertWhenNoChurnDropOnAStimulus() {
        let inert: (Float, Float, Double, Double, Double) = (0.6, 0.10, 0.10, 0.10, 0.90)
        let cells = [
            Self.cell(
                .s1,
                64,
                baseChurn: 0.10,
                baseGMSD: 0.10,
                baseHaar: 0.90,
                Self.fullGridPoints(overrides: [Self.goodPoint])
            ),
            Self.cell(
                .s1,
                80,
                baseChurn: 0.10,
                baseGMSD: 0.10,
                baseHaar: 0.90,
                Self.fullGridPoints(overrides: [Self.goodPoint])
            ),
            Self.cell(
                .s2,
                64,
                baseChurn: 0.10,
                baseGMSD: 0.10,
                baseHaar: 0.90,
                Self.fullGridPoints(overrides: [inert])
            ),
            Self.cell(
                .s2,
                80,
                baseChurn: 0.10,
                baseGMSD: 0.10,
                baseHaar: 0.90,
                Self.fullGridPoints(overrides: [inert])
            ),
        ]

        let (verdict, _) = TemporalGate.decide(cells: cells)

        if case .kill(let why) = verdict {
            #expect(why.contains("inert"))
        } else {
            Issue.record("expected inert KILL, got \(verdict)")
        }
    }

    @Test func killFreezeTrapWhenChurnDropAlwaysBustsFidelity() {
        let trap: (Float, Float, Double, Double, Double) = (0.6, 0.10, 0.07, 0.20, 0.90)
        let cells = TemporalStimulus.allCases.flatMap { stimulus in
            [64, 80].map {
                Self.cell(
                    stimulus,
                    $0,
                    baseChurn: 0.10,
                    baseGMSD: 0.10,
                    baseHaar: 0.90,
                    Self.fullGridPoints(overrides: [trap])
                )
            }
        }

        let (verdict, _) = TemporalGate.decide(cells: cells)

        if case .kill(let why) = verdict {
            #expect(why.contains("freeze"))
        } else {
            Issue.record("expected freeze-trap KILL, got \(verdict)")
        }
    }

    @Test func killHysteresisOnlyWhenOnlyAlpha1Qualifies() {
        let hystOnly: (Float, Float, Double, Double, Double) = (1.0, 0.10, 0.07, 0.10, 0.90)
        let emaFail: (Float, Float, Double, Double, Double) = (0.6, 0.10, 0.07, 0.20, 0.90)
        let cells = TemporalStimulus.allCases.flatMap { stimulus in
            [64, 80].map {
                Self.cell(
                    stimulus,
                    $0,
                    baseChurn: 0.10,
                    baseGMSD: 0.10,
                    baseHaar: 0.90,
                    Self.fullGridPoints(overrides: [hystOnly, emaFail])
                )
            }
        }

        let (verdict, _) = TemporalGate.decide(cells: cells)

        if case .kill(let why) = verdict {
            #expect(why.contains("hysteresis"))
        } else {
            Issue.record("expected hysteresis-only KILL, got \(verdict)")
        }
    }

    @Test func killNonRobustWhenAlphaSub1QualifiesButNotAllFour() {
        var cells = Self.fourGoodCells()
        cells[3] = Self.cell(
            .s2,
            80,
            baseChurn: 0.10,
            baseGMSD: 0.10,
            baseHaar: 0.90,
            Self.fullGridPoints(overrides: [(0.6, 0.10, 0.07, 0.10, 0.80)])
        )

        let (verdict, _) = TemporalGate.decide(cells: cells)

        if case .kill(let why) = verdict {
            #expect(why.contains("robust"))
        } else {
            Issue.record("expected non-robust KILL, got \(verdict)")
        }
    }

    // Spec §7.1 re-instrument: a sub-band sign disagreement (the run-1 s1/80
    // noise-floor case) is "fidelity held", not instrument failure. With baseline
    // GMSD 0.10 / HaarPSI 0.90 the equivalence bounds are ±0.002 (GMSD ×0.02) and
    // ±0.009 (HaarPSI ×0.01); here GMSD improves +0.001 and HaarPSI dips −0.003 —
    // opposite signs, both within band — so the gate must NOT RERUN and instead
    // reaches its substantive verdict (PASS, since the point qualifies in all four).
    // Under the old absolute 1e-4 deadband this combination would have RERUN'd.
    @Test func noRerunWhenSubBandSignDisagreementHeldAtSharedPoint() {
        let cells = TemporalStimulus.allCases.flatMap { stimulus in
            [64, 80].map {
                Self.cell(
                    stimulus,
                    $0,
                    baseChurn: 0.10,
                    baseGMSD: 0.10,
                    baseHaar: 0.90,
                    Self.fullGridPoints(overrides: [(0.6, 0.10, 0.07, 0.099, 0.897)])
                )
            }
        }

        let (verdict, shared) = TemporalGate.decide(cells: cells)

        #expect(verdict == .pass(alpha: 0.6, tau: 0.10))
        #expect(shared?.alpha == 0.6 && shared?.tau == 0.10)
    }

    // An above-band sign disagreement IS a genuine instrument failure and still
    // RERUNs — and does so before the non-robust KILL. The cell[3] deltas (GMSD
    // +0.02 vs ±0.002 band, HaarPSI −0.10 vs ±0.009 band) are well beyond band.
    @Test func rerunOracleDisagreementBeforeNonRobustKill() {
        var cells = Self.fourGoodCells()
        cells[3] = Self.cell(
            .s2,
            80,
            baseChurn: 0.10,
            baseGMSD: 0.10,
            baseHaar: 0.90,
            Self.fullGridPoints(overrides: [(0.6, 0.10, 0.07, 0.08, 0.80)])
        )

        let (verdict, shared) = TemporalGate.decide(cells: cells)

        if case .rerun(let why) = verdict {
            #expect(why.contains("oracle"))
            #expect(shared?.alpha == 0.6 && shared?.tau == 0.10)
        } else {
            Issue.record("expected oracle RERUN before non-robust KILL, got \(verdict)")
        }
    }

    private static func expectKill(_ verdict: TemporalVerdict, contains needles: String...) {
        if case .kill(let why) = verdict {
            for needle in needles {
                #expect(why.contains(needle))
            }
        } else {
            Issue.record("expected KILL containing \(needles), got \(verdict)")
        }
    }
}
