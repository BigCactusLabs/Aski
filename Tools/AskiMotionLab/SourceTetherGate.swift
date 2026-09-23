/// One measured operating point in a (stimulus, column) cell for the ASTSK-45 source-tether
/// experiment: the mean over the N-frame sequence of glyph churn and source-fidelity oracles
/// at a single tolerance `rho`. The α×τ pair of `CellMeasurement` collapses to a scalar `rho`
/// because EMA is fixed off (α=1) — this is a 1-D experiment (spec §3, §5).
public struct SourceTetherMeasurement: Sendable {
    /// The source-tether tolerance. `SourceTetherGate.baselineRho` marks the per-frame-independent
    /// (no-tether) baseline; grid points carry a value from `SourceTetherGate.rhoGrid`.
    public let rho: Float
    public let meanGlyphChurn: Double
    public let meanAlphaChurn: Double
    public let gmsd: Double
    public let haarpsi: Double
    public let perFrameGMSD: [Double]
    public let meanDriftVsBaseline: Double

    public init(
        rho: Float,
        meanGlyphChurn: Double,
        meanAlphaChurn: Double = 0,
        gmsd: Double,
        haarpsi: Double,
        perFrameGMSD: [Double] = [],
        meanDriftVsBaseline: Double = .nan
    ) {
        self.rho = rho
        self.meanGlyphChurn = meanGlyphChurn
        self.meanAlphaChurn = meanAlphaChurn
        self.gmsd = gmsd
        self.haarpsi = haarpsi
        self.perFrameGMSD = perFrameGMSD
        self.meanDriftVsBaseline = meanDriftVsBaseline
    }
}

/// All measured rho points for one stimulus/column cell, plus its no-tether baseline.
public struct SourceTetherCell: Sendable {
    public let stimulus: TemporalStimulus
    public let columns: Int
    public let baseline: SourceTetherMeasurement
    public let points: [SourceTetherMeasurement]

    public init(
        stimulus: TemporalStimulus,
        columns: Int,
        baseline: SourceTetherMeasurement,
        points: [SourceTetherMeasurement]
    ) {
        self.stimulus = stimulus
        self.columns = columns
        self.baseline = baseline
        self.points = points
    }
}

public enum SourceTetherVerdict: Sendable, Equatable {
    case pass(rho: Float)
    case kill(String)
    case rerun(String)
}

/// Frozen ASTSK-45 §5 decision rule: the ASTSK-41 §7 gate forked to a scalar-rho operating point.
/// The churn/GMSD/HaarPSI `qualifies` screen, the three tolerance constants, the four-cell
/// validation discipline, and the §7.1 oracle-sign band are reused byte-for-byte from
/// `TemporalGate`; only the operating-point (α×τ → rho) and the EMA-specific "hysteresis-only
/// collapse" branch (absent here — α is fixed off) differ. Pure; no I/O.
public enum SourceTetherGate {
    /// Frozen rho grid (spec §4). EMA is fixed off (α=1), so this is the only swept parameter.
    public static let rhoGrid: [Float] = [0, 0.25, 0.5, 1.0, 2.0]
    /// Sentinel marking the per-frame-independent (no-tether) baseline; off the rho grid by design.
    public static let baselineRho: Float = -1

    // Reused verbatim from ASTSK-41 `TemporalGate`.
    public static let churnDropFactor = 0.80
    public static let gmsdTolerance = 1.02
    public static let haarpsiTolerance = 0.99

    static func reachesChurnDrop(_ p: SourceTetherMeasurement, baseline: SourceTetherMeasurement) -> Bool {
        p.meanGlyphChurn <= baseline.meanGlyphChurn * churnDropFactor
    }

    public static func qualifies(_ p: SourceTetherMeasurement, baseline: SourceTetherMeasurement) -> Bool {
        reachesChurnDrop(p, baseline: baseline)
            && p.gmsd <= baseline.gmsd * gmsdTolerance
            && p.haarpsi >= baseline.haarpsi * haarpsiTolerance
    }

    public static func decide(cells: [SourceTetherCell]) -> (verdict: SourceTetherVerdict, sharedRho: Float?) {
        let validation = validateDecisiveInput(cells)
        if let failure = validation.failure {
            return (failure, nil)
        }
        let decisiveCells = expectedCellKeys.compactMap { validation.cellsByKey[$0] }

        // Inert: each stimulus must have at least one rho reaching the 20% churn drop.
        for stimulus in TemporalStimulus.allCases {
            let stimulusCells = decisiveCells.filter { $0.stimulus == stimulus }
            let reachesDrop = stimulusCells.contains { cell in
                cell.points.contains { reachesChurnDrop($0, baseline: cell.baseline) }
            }
            if !reachesDrop {
                return (.kill("inert tether: no rho reaches the 20% churn drop on \(stimulus.rawValue)"), nil)
            }
        }

        struct Candidate {
            let point: OperatingPoint
            var cellsQualified: Int
            var churnDrop: Double
        }

        var candidates: [OperatingPoint: Candidate] = [:]
        var anyQualifies = false

        for cell in decisiveCells {
            for point in cell.points where qualifies(point, baseline: cell.baseline) {
                guard let operatingPoint = OperatingPoint(point) else {
                    return (
                        .kill("off-grid operating point: rho=\(point.rho) in \(cell.stimulus.rawValue)/\(cell.columns)"),
                        nil
                    )
                }

                anyQualifies = true
                let drop =
                    (cell.baseline.meanGlyphChurn - point.meanGlyphChurn)
                    / max(cell.baseline.meanGlyphChurn, .leastNonzeroMagnitude)

                if var candidate = candidates[operatingPoint] {
                    candidate.cellsQualified += 1
                    candidate.churnDrop += drop
                    candidates[operatingPoint] = candidate
                } else {
                    candidates[operatingPoint] = Candidate(point: operatingPoint, cellsQualified: 1, churnDrop: drop)
                }
            }
        }

        // Every rho that reaches the churn drop busts GMSD/HaarPSI — the washout / freeze-trap
        // death path (spec §5, §7 taxonomy 2). With EMA off there is no hysteresis-only variant.
        guard anyQualifies else {
            return (.kill("freeze-trap: every rho reaching the churn drop busts GMSD/HaarPSI"), nil)
        }

        // Shared rho = qualifying in the most cells; ties → larger summed churn drop (spec §5).
        // A residual tie (equal cells AND equal drop, measure-zero) breaks toward the smaller rho
        // — the more conservative hold tolerance — purely for determinism.
        let shared = candidates.values.max {
            if $0.cellsQualified != $1.cellsQualified {
                return $0.cellsQualified < $1.cellsQualified
            }
            if $0.churnDrop != $1.churnDrop {
                return $0.churnDrop < $1.churnDrop
            }
            return $0.point.rhoIndex > $1.point.rhoIndex
        }!
        let sharedRho = shared.point.rho

        // Oracle-sign agreement at the shared point, per spec §7.1 (re-instrument), inherited
        // as-is. Each oracle's change counts as "meaningful" only beyond its pre-registered
        // equivalence bound (its own qualify tolerance, the SESOI). RERUN fires only when BOTH
        // oracles move beyond band AND their signs disagree.
        for cell in decisiveCells {
            guard let point = cell.points.first(where: { shared.point.matches($0) }) else {
                continue
            }

            let gmsdDelta = cell.baseline.gmsd - point.gmsd
            let haarpsiDelta = point.haarpsi - cell.baseline.haarpsi
            let gmsdBand = cell.baseline.gmsd * (gmsdTolerance - 1)
            let haarpsiBand = cell.baseline.haarpsi * (1 - haarpsiTolerance)
            if abs(gmsdDelta) > gmsdBand,
                abs(haarpsiDelta) > haarpsiBand,
                (gmsdDelta > 0) != (haarpsiDelta > 0)
            {
                return (
                    .rerun(
                        "oracle disagreement at shared point in \(cell.stimulus.rawValue)/\(cell.columns): GMSD and HaarPSI disagree on fidelity sign beyond the equivalence bound"
                    ),
                    sharedRho
                )
            }
        }

        guard shared.cellsQualified == expectedCellKeys.count else {
            return (
                .kill(
                    "non-robust: best rho (rho=\(shared.point.rho)) qualifies in \(shared.cellsQualified)/\(expectedCellKeys.count) cells"
                ),
                sharedRho
            )
        }

        return (.pass(rho: shared.point.rho), sharedRho)
    }

    private struct CellKey: Hashable {
        let stimulus: TemporalStimulus
        let columns: Int
    }

    private struct OperatingPoint: Hashable {
        let rho: Float
        let rhoIndex: Int

        init(rho: Float, rhoIndex: Int) {
            self.rho = rho
            self.rhoIndex = rhoIndex
        }

        init?(_ measurement: SourceTetherMeasurement) {
            guard let rhoIndex = rhoGrid.firstIndex(of: measurement.rho) else {
                return nil
            }
            self.init(rho: measurement.rho, rhoIndex: rhoIndex)
        }

        func matches(_ measurement: SourceTetherMeasurement) -> Bool {
            measurement.rho == rho
        }
    }

    private static let expectedCellKeys = [
        CellKey(stimulus: .s1, columns: 64),
        CellKey(stimulus: .s1, columns: 80),
        CellKey(stimulus: .s2, columns: 64),
        CellKey(stimulus: .s2, columns: 80),
    ]

    private static let expectedCellKeySet = Set(expectedCellKeys)

    private static let expectedOperatingPoints = rhoGrid.enumerated().map { rhoIndex, rho in
        OperatingPoint(rho: rho, rhoIndex: rhoIndex)
    }

    private static let expectedOperatingPointSet = Set(expectedOperatingPoints)

    private static func validateDecisiveInput(_ cells: [SourceTetherCell]) -> (
        failure: SourceTetherVerdict?,
        cellsByKey: [CellKey: SourceTetherCell]
    ) {
        guard !cells.isEmpty else {
            return (.kill("incomplete decisive input: expected four stimulus/column cells"), [:])
        }

        var cellsByKey: [CellKey: SourceTetherCell] = [:]
        for cell in cells {
            let cellKey = CellKey(stimulus: cell.stimulus, columns: cell.columns)
            guard expectedCellKeySet.contains(cellKey) else {
                return (
                    .kill("non-decisive input: unexpected cell \(cell.stimulus.rawValue)/\(cell.columns)"),
                    cellsByKey
                )
            }
            guard cellsByKey[cellKey] == nil else {
                return (
                    .kill("non-decisive input: duplicate cell \(cell.stimulus.rawValue)/\(cell.columns)"),
                    cellsByKey
                )
            }
            guard cell.baseline.rho == baselineRho else {
                return (
                    .kill(
                        "baseline identity mismatch: expected no-tether baseline in \(cell.stimulus.rawValue)/\(cell.columns)"
                    ),
                    cellsByKey
                )
            }

            var seenPoints = Set<OperatingPoint>()
            for point in cell.points {
                guard let operatingPoint = OperatingPoint(point) else {
                    return (
                        .kill(
                            "off-grid operating point: rho=\(point.rho) in \(cell.stimulus.rawValue)/\(cell.columns)"
                        ),
                        cellsByKey
                    )
                }
                guard seenPoints.insert(operatingPoint).inserted else {
                    return (
                        .kill(
                            "duplicate operating point: rho=\(point.rho) in \(cell.stimulus.rawValue)/\(cell.columns)"
                        ),
                        cellsByKey
                    )
                }
            }
            guard seenPoints == expectedOperatingPointSet else {
                let missing = expectedOperatingPoints.filter { !seenPoints.contains($0) }
                let missingLabel = missing.first.map { "rho=\($0.rho)" } ?? "unknown point"
                return (
                    .kill("incomplete grid: missing \(missingLabel) in \(cell.stimulus.rawValue)/\(cell.columns)"),
                    cellsByKey
                )
            }

            cellsByKey[cellKey] = cell
        }

        let missing = expectedCellKeys.filter { cellsByKey[$0] == nil }
        guard missing.isEmpty else {
            let labels = missing.map { "\($0.stimulus.rawValue)/\($0.columns)" }.joined(separator: ", ")
            return (.kill("incomplete decisive input: missing \(labels)"), cellsByKey)
        }

        return (nil, cellsByKey)
    }
}
