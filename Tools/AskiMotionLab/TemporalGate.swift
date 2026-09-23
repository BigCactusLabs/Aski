/// One measured operating point in a (stimulus, column) cell: the mean over the
/// N-frame sequence of glyph churn and source-fidelity oracles.
public struct CellMeasurement: Sendable {
    public let alpha: Float
    public let tau: Float
    public let meanGlyphChurn: Double
    public let meanAlphaChurn: Double
    public let gmsd: Double
    public let haarpsi: Double
    public let perFrameGMSD: [Double]
    public let meanDriftVsBaseline: Double

    public init(
        alpha: Float,
        tau: Float,
        meanGlyphChurn: Double,
        meanAlphaChurn: Double = 0,
        gmsd: Double,
        haarpsi: Double,
        perFrameGMSD: [Double] = [],
        meanDriftVsBaseline: Double = .nan
    ) {
        self.alpha = alpha
        self.tau = tau
        self.meanGlyphChurn = meanGlyphChurn
        self.meanAlphaChurn = meanAlphaChurn
        self.gmsd = gmsd
        self.haarpsi = haarpsi
        self.perFrameGMSD = perFrameGMSD
        self.meanDriftVsBaseline = meanDriftVsBaseline
    }
}

/// All measured alpha/tau points for one stimulus/column cell.
public struct GateCell: Sendable {
    public let stimulus: TemporalStimulus
    public let columns: Int
    public let baseline: CellMeasurement
    public let points: [CellMeasurement]

    public init(stimulus: TemporalStimulus, columns: Int, baseline: CellMeasurement, points: [CellMeasurement]) {
        self.stimulus = stimulus
        self.columns = columns
        self.baseline = baseline
        self.points = points
    }
}

public enum TemporalVerdict: Sendable, Equatable {
    case pass(alpha: Float, tau: Float)
    case kill(String)
    case rerun(String)
}

/// Frozen ASTSK-41 §7 decision rule. Pure; no I/O.
public enum TemporalGate {
    public static let alphaGrid: [Float] = [1.0, 0.6, 0.35, 0.2]
    public static let tauGrid: [Float] = [0, 0.05, 0.10, 0.20]
    public static let churnDropFactor = 0.80
    public static let gmsdTolerance = 1.02
    public static let haarpsiTolerance = 0.99

    static func reachesChurnDrop(_ p: CellMeasurement, baseline: CellMeasurement) -> Bool {
        p.meanGlyphChurn <= baseline.meanGlyphChurn * churnDropFactor
    }

    public static func qualifies(_ p: CellMeasurement, baseline: CellMeasurement) -> Bool {
        reachesChurnDrop(p, baseline: baseline)
            && p.gmsd <= baseline.gmsd * gmsdTolerance
            && p.haarpsi >= baseline.haarpsi * haarpsiTolerance
    }

    public static func decide(cells: [GateCell]) -> (verdict: TemporalVerdict, sharedPoint: (alpha: Float, tau: Float)?) {
        let validation = validateDecisiveInput(cells)
        if let failure = validation.failure {
            return (failure, nil)
        }
        let decisiveCells = expectedCellKeys.compactMap { validation.cellsByKey[$0] }

        for stimulus in TemporalStimulus.allCases {
            let stimulusCells = decisiveCells.filter { $0.stimulus == stimulus }

            let reachesDrop = stimulusCells.contains { cell in
                cell.points.contains { reachesChurnDrop($0, baseline: cell.baseline) }
            }
            if !reachesDrop {
                return (.kill("inert prior: no alpha/tau point reaches the 20% churn drop on \(stimulus.rawValue)"), nil)
            }
        }

        struct Candidate {
            let point: OperatingPoint
            var cellsQualified: Int
            var churnDrop: Double
        }

        var candidates: [OperatingPoint: Candidate] = [:]
        var anyAlphaSub1Qualifies = false
        var anyAlpha1Qualifies = false

        for cell in decisiveCells {
            for point in cell.points where qualifies(point, baseline: cell.baseline) {
                guard let operatingPoint = OperatingPoint(point) else {
                    return (
                        .kill(
                            "off-grid operating point: alpha=\(point.alpha), tau=\(point.tau) in \(cell.stimulus.rawValue)/\(cell.columns)"
                        ),
                        nil
                    )
                }

                if operatingPoint.alpha >= 1 {
                    anyAlpha1Qualifies = true
                    continue
                }

                anyAlphaSub1Qualifies = true
                let drop =
                    (cell.baseline.meanGlyphChurn - point.meanGlyphChurn)
                    / max(cell.baseline.meanGlyphChurn, .leastNonzeroMagnitude)

                if var candidate = candidates[operatingPoint] {
                    candidate.cellsQualified += 1
                    candidate.churnDrop += drop
                    candidates[operatingPoint] = candidate
                } else {
                    candidates[operatingPoint] = Candidate(
                        point: operatingPoint,
                        cellsQualified: 1,
                        churnDrop: drop
                    )
                }
            }
        }

        guard anyAlphaSub1Qualifies else {
            if anyAlpha1Qualifies {
                return (.kill("hysteresis-only collapse: only alpha=1 points qualify; EMA contributes nothing"), nil)
            }
            return (.kill("freeze-trap: every alpha/tau point reaching the churn drop busts GMSD/HaarPSI"), nil)
        }

        let shared = candidates.values.max {
            if $0.cellsQualified != $1.cellsQualified {
                return $0.cellsQualified < $1.cellsQualified
            }
            if $0.churnDrop != $1.churnDrop {
                return $0.churnDrop < $1.churnDrop
            }
            if $0.point.alphaIndex != $1.point.alphaIndex {
                return $0.point.alphaIndex > $1.point.alphaIndex
            }
            return $0.point.tauIndex > $1.point.tauIndex
        }!
        let sharedPoint = (alpha: shared.point.alpha, tau: shared.point.tau)

        // Oracle-sign agreement at the shared point, per spec §7.1 (re-instrument).
        // Each oracle's fidelity change counts as "meaningful" only when it exceeds
        // that oracle's pre-registered equivalence bound — its own §7 qualify tolerance
        // (the SESOI), derived from the already-frozen constants, not a new parameter.
        // A change within the bound is "fidelity held", not disagreement. RERUN fires
        // only when BOTH oracles move beyond band AND their signs differ.
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
                    sharedPoint
                )
            }
        }

        guard shared.cellsQualified == expectedCellKeys.count else {
            return (
                .kill(
                    "non-robust: best alpha<1 point (alpha=\(shared.point.alpha), tau=\(shared.point.tau)) qualifies in \(shared.cellsQualified)/\(expectedCellKeys.count) cells"
                ),
                sharedPoint
            )
        }

        return (.pass(alpha: shared.point.alpha, tau: shared.point.tau), sharedPoint)
    }

    private struct CellKey: Hashable {
        let stimulus: TemporalStimulus
        let columns: Int
    }

    private struct OperatingPoint: Hashable {
        let alpha: Float
        let tau: Float
        let alphaIndex: Int
        let tauIndex: Int

        init(alpha: Float, tau: Float, alphaIndex: Int, tauIndex: Int) {
            self.alpha = alpha
            self.tau = tau
            self.alphaIndex = alphaIndex
            self.tauIndex = tauIndex
        }

        init?(_ measurement: CellMeasurement) {
            guard
                let alphaIndex = alphaGrid.firstIndex(of: measurement.alpha),
                let tauIndex = tauGrid.firstIndex(of: measurement.tau)
            else {
                return nil
            }

            self.init(
                alpha: measurement.alpha,
                tau: measurement.tau,
                alphaIndex: alphaIndex,
                tauIndex: tauIndex
            )
        }

        func matches(_ measurement: CellMeasurement) -> Bool {
            measurement.alpha == alpha && measurement.tau == tau
        }
    }

    private static let expectedCellKeys = [
        CellKey(stimulus: .s1, columns: 64),
        CellKey(stimulus: .s1, columns: 80),
        CellKey(stimulus: .s2, columns: 64),
        CellKey(stimulus: .s2, columns: 80),
    ]

    private static let expectedCellKeySet = Set(expectedCellKeys)

    private static let expectedOperatingPoints = alphaGrid.enumerated().flatMap { alphaIndex, alpha in
        tauGrid.enumerated().map { tauIndex, tau in
            OperatingPoint(alpha: alpha, tau: tau, alphaIndex: alphaIndex, tauIndex: tauIndex)
        }
    }

    private static let expectedOperatingPointSet = Set(expectedOperatingPoints)

    private static func validateDecisiveInput(_ cells: [GateCell]) -> (
        failure: TemporalVerdict?,
        cellsByKey: [CellKey: GateCell]
    ) {
        guard !cells.isEmpty else {
            return (.kill("incomplete decisive input: expected four stimulus/column cells"), [:])
        }

        var cellsByKey: [CellKey: GateCell] = [:]
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
            guard cell.baseline.alpha == 1, cell.baseline.tau == 0 else {
                return (
                    .kill(
                        "baseline identity mismatch: expected alpha=1, tau=0 in \(cell.stimulus.rawValue)/\(cell.columns)"
                    ),
                    cellsByKey
                )
            }

            var seenPoints = Set<OperatingPoint>()
            for point in cell.points {
                guard let operatingPoint = OperatingPoint(point) else {
                    return (
                        .kill(
                            "off-grid operating point: alpha=\(point.alpha), tau=\(point.tau) in \(cell.stimulus.rawValue)/\(cell.columns)"
                        ),
                        cellsByKey
                    )
                }
                guard seenPoints.insert(operatingPoint).inserted else {
                    return (
                        .kill(
                            "duplicate operating point: alpha=\(point.alpha), tau=\(point.tau) in \(cell.stimulus.rawValue)/\(cell.columns)"
                        ),
                        cellsByKey
                    )
                }
            }
            guard seenPoints == expectedOperatingPointSet else {
                let missing = expectedOperatingPoints.filter { !seenPoints.contains($0) }
                let missingLabel = missing.first.map { "alpha=\($0.alpha), tau=\($0.tau)" } ?? "unknown point"
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
