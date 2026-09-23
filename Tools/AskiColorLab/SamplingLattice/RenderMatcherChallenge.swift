import AskiToolSupport
import Darwin
import Foundation
import simd

@_spi(AskiResearch) import Aski

/// One-shot ASKI-69 fixed-footprint matcher challenge.
///
/// This file is deliberately confined to AskiColorLab. The three challenger
/// selectors cannot be selected by a product caller, and no production default
/// observes them. The frozen rule lives in
/// `docs/Research/2026-09-04-aski69-render-space-matcher-rule.md`.
enum RenderMatcherChallenge {
    static let commandName = "render-matcher-challenge"
    static let csvFileName = "matcher-census.csv"
    static let examplesFileName = "examples.txt"
    static let summaryFileName = "summary.md"
    static let manifestFileName = "result.yaml"

    static let columns = 80
    static let oversample = 2
    static let footprint = 24
    static let candidateSupersample = 4
    static let memoryBudgetBytes = 1_048_576

    struct Corpus: Sendable {
        let name: String
        let relativeAssetsPath: String
        let expectedNativeSide: Int
    }

    static let corpora = [
        Corpus(
            name: "nasa-structure-v1",
            relativeAssetsPath: "docs/Research/Corpus/nasa-structure-v1/assets",
            expectedNativeSide: 2048
        ),
        Corpus(
            name: "nasa-steerable-v1",
            relativeAssetsPath: "docs/Research/Corpus/nasa-steerable-v1/assets",
            expectedNativeSide: 3072
        ),
    ]
    static let charsetNames = ["blocks", "standard"]

    enum Arm: String, CaseIterable, Sendable, Hashable {
        case production = "P"
        case aligned = "A"
        case shifted = "S1"
        case toneFill = "TF"

        var order: Int {
            switch self {
            case .production: return -1
            case .aligned: return 0
            case .shifted: return 1
            case .toneFill: return 2
            }
        }
    }

    struct ToneFillComponents: Equatable, Sendable {
        let tone: Double
        let fill: Double
        var total: Double { tone + fill }
    }

    struct Row: Sendable {
        let corpus: String
        let charset: String
        let arm: Arm
        let cells: Int
        let glyphs: Int
        let distinctGlyphs: Int
        let largestGlyphShare: Double
        let candidateChurnFraction: Double
        let meanMAE: Double
        let meanGMSD: Double
        let selectionWallSeconds: Double
        let timeRatioToProduction: Double
        let estimatedPeakSelectorBytes: Int
        let gitSHA: String
    }

    struct Example: Sendable {
        let corpus: String
        let charset: String
        let fixture: String
        let arm: Arm
        let lines: [String]
    }

    struct Comparison: Sendable {
        let corpus: String
        let charset: String
        let arm: Arm
        let maeImprovementPercent: Double
        let gmsdRegressionPercent: Double
        let timeRatio: Double
        let memoryBytes: Int
    }

    struct Assessment: Sendable {
        let verdict: String
        let objectiveCandidates: [Arm]
        let selectedTreatment: Arm?
        let selectedMeetsCostBudget: Bool
        let comparisons: [Comparison]
    }

    struct Report: Sendable {
        let rows: [Row]
        let examples: [Example]
        let assessment: Assessment
        let measurementWallSeconds: Double
        let processMaximumResidentBytes: UInt64
    }

    private struct CellInput: Sendable {
        let source: [Float]
        let queryLanes: [SIMD4<Float>]
        let queryTone: Float
        let productionIndex: Int
    }

    private struct Accumulator {
        var cells = 0
        var differingPicks = 0
        var mae = 0.0
        var gmsd = 0.0
        var selectionSeconds = 0.0
        var glyphUse: [Int]

        init(glyphs: Int) {
            glyphUse = [Int](repeating: 0, count: glyphs)
        }

        mutating func add(
            index: Int,
            productionIndex: Int,
            candidate: [Float],
            source: [Float]
        ) throws {
            let maeScore = alignedMAE(candidate, source)
            let gmsdScore = GMSD.gmsd(
                candidate, source, width: footprint, height: footprint)
            guard maeScore.isFinite, gmsdScore.isFinite else {
                throw ChallengeError.nonFiniteScore
            }
            cells += 1
            if index != productionIndex { differingPicks += 1 }
            mae += maeScore
            gmsd += gmsdScore
            glyphUse[index] += 1
        }
    }

    // MARK: - Pure selectors

    static func alignedMAE(_ candidate: [Float], _ source: [Float]) -> Double {
        guard candidate.count == source.count, !candidate.isEmpty else { return .nan }
        var sum = 0.0
        for index in candidate.indices {
            sum += Double(abs(candidate[index] - source[index]))
        }
        return sum / Double(candidate.count)
    }

    /// Candidate is translated within the fixed footprint. Samples outside the
    /// footprint are zero, as frozen in the rule.
    static func shiftedMAE(
        _ candidate: [Float],
        _ source: [Float],
        width: Int,
        height: Int,
        maximumShift: Int = 1
    ) -> Double {
        guard width > 0, height > 0, candidate.count == width * height,
            source.count == candidate.count, maximumShift >= 0
        else { return .nan }

        var best = Double.infinity
        for dy in (-maximumShift)...maximumShift {
            for dx in (-maximumShift)...maximumShift {
                var sum = 0.0
                for y in 0..<height {
                    let candidateY = y - dy
                    for x in 0..<width {
                        let candidateX = x - dx
                        let rendered: Float
                        if candidateX >= 0, candidateX < width,
                            candidateY >= 0, candidateY < height
                        {
                            rendered = candidate[candidateY * width + candidateX]
                        } else {
                            rendered = 0
                        }
                        sum += Double(abs(rendered - source[y * width + x]))
                    }
                }
                let score = sum / Double(candidate.count)
                if score < best { best = score }
            }
        }
        return best
    }

    static func toneFillComponents(
        _ candidate: [Float],
        _ source: [Float]
    ) -> ToneFillComponents {
        guard candidate.count == source.count, !candidate.isEmpty else {
            return ToneFillComponents(tone: .nan, fill: .nan)
        }
        let count = Double(candidate.count)
        var candidateSum = 0.0
        var sourceSum = 0.0
        for index in candidate.indices {
            candidateSum += Double(candidate[index])
            sourceSum += Double(source[index])
        }
        let candidateMean = candidateSum / count
        let sourceMean = sourceSum / count
        var fill = 0.0
        for index in candidate.indices {
            let candidateCentered = Double(candidate[index]) - candidateMean
            let sourceCentered = Double(source[index]) - sourceMean
            fill += abs(candidateCentered - sourceCentered)
        }
        return ToneFillComponents(
            tone: abs(candidateMean - sourceMean),
            fill: fill / count
        )
    }

    static func fixedFootprintPick(
        arm: Arm,
        source: [Float],
        rasters: [[Float]],
        width: Int,
        height: Int
    ) -> Int {
        precondition(arm != .production)
        var bestIndex = 0
        var bestScore = Double.infinity
        for index in rasters.indices {
            let score: Double
            switch arm {
            case .aligned:
                score = alignedMAE(rasters[index], source)
            case .shifted:
                score = shiftedMAE(
                    rasters[index], source, width: width, height: height)
            case .toneFill:
                score = toneFillComponents(rasters[index], source).total
            case .production:
                preconditionFailure("production does not use the render-space selector")
            }
            // Strict comparison supplies the frozen lower-index tie-break.
            if score < bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return bestIndex
    }

    // MARK: - Measurement

    static func evaluate(gitSHA: String) throws -> Report {
        let wallStart = DispatchTime.now().uptimeNanoseconds
        var rows: [Row] = []
        var examples: [Example] = []

        for corpus in corpora {
            let corpusPath = resolvePackagePath(corpus.relativeAssetsPath)
            let fixtures = try SteerableBattery.naturals(corpusDirectory: corpusPath)
            guard fixtures.count == 3 else {
                throw ChallengeError.fixtureCount(corpus: corpus.name, actual: fixtures.count)
            }
            for fixture in fixtures
            where fixture.width != corpus.expectedNativeSide
                || fixture.height != corpus.expectedNativeSide
            {
                throw ChallengeError.fixtureGeometry(
                    corpus: corpus.name,
                    fixture: fixture.id,
                    width: fixture.width,
                    height: fixture.height
                )
            }

            for charsetName in charsetNames {
                let characterSet = try SelectionCeiling.characterSet(named: charsetName)
                let glyphs = characterSet.characters
                try SelectionCeiling.assertUniqueGlyphs(glyphs, charset: charsetName)
                let rasters = glyphs.map {
                    GlyphCellRaster.luma(
                        character: $0,
                        width: footprint,
                        height: footprint,
                        supersample: candidateSupersample,
                        boundsCentred: false
                    )
                }
                guard rasters.allSatisfy({ $0.count == footprint * footprint }) else {
                    throw ChallengeError.invalidRaster(charset: charsetName)
                }

                let converter = ASCIIConverter(
                    characterSet: characterSet,
                    palette: BuiltInPalette.monochrome,
                    options: .default,
                    colorSpace: .sRGB,
                    oversample: oversample
                )
                var accumulators = Dictionary(
                    uniqueKeysWithValues: Arm.allCases.map {
                        ($0, Accumulator(glyphs: glyphs.count))
                    })

                for (fixtureIndex, fixture) in fixtures.enumerated() {
                    guard
                        let queries = converter.cellQueryDescriptors(
                            fixture.image, columns: columns),
                        queries.supportsShapeDescriptor,
                        let geometry = converter.samplingGeometry(
                            fixture.image, columns: columns),
                        geometry.rows == queries.rows,
                        geometry.columns == queries.columns,
                        geometry.droppedX == 0,
                        geometry.droppedY == 0,
                        queries.rows > 0,
                        queries.columns > 0
                    else {
                        throw ChallengeError.invalidLattice(
                            corpus: corpus.name, fixture: fixture.id, charset: charsetName)
                    }

                    var inputs: [CellInput] = []
                    inputs.reserveCapacity(queries.rows * queries.columns)
                    for row in 0..<queries.rows {
                        for column in 0..<queries.columns {
                            guard
                                let block = SampledSource.lumaBlock(
                                    fixture,
                                    cellRow: row,
                                    cellCol: column,
                                    geometry: geometry
                                ),
                                block.width >= 2,
                                block.height >= 2,
                                let productionIndex = glyphs.firstIndex(
                                    of: queries.grid.cells[row][column].character)
                            else {
                                throw ChallengeError.missingCell(
                                    corpus: corpus.name,
                                    fixture: fixture.id,
                                    charset: charsetName,
                                    row: row,
                                    column: column
                                )
                            }
                            inputs.append(
                                CellInput(
                                    source: LumaResample.resample(
                                        block.luma,
                                        srcWidth: block.width,
                                        srcHeight: block.height,
                                        dstWidth: footprint,
                                        dstHeight: footprint
                                    ),
                                    queryLanes: queries.lanes(row: row, column: column),
                                    queryTone: queries.adjustedL(row: row, column: column),
                                    productionIndex: productionIndex
                                ))
                        }
                    }
                    guard inputs.count == queries.rows * queries.columns else {
                        throw ChallengeError.partialCensus(
                            corpus: corpus.name, fixture: fixture.id, charset: charsetName)
                    }

                    for arm in Arm.allCases {
                        let started = DispatchTime.now().uptimeNanoseconds
                        let picks: [Int]
                        switch arm {
                        case .production:
                            picks = inputs.map { input in
                                SelectionCeiling.poolWidthPick(
                                    queryLanes: input.queryLanes,
                                    adjustedL: input.queryTone,
                                    candidateLanes: characterSet.shapeVectorLanes,
                                    brightnessValues: characterSet.brightnessValues,
                                    topK: SelectionCeiling.productionPoolWidth
                                )
                            }
                        case .aligned, .shifted, .toneFill:
                            picks = inputs.map { input in
                                fixedFootprintPick(
                                    arm: arm,
                                    source: input.source,
                                    rasters: rasters,
                                    width: footprint,
                                    height: footprint
                                )
                            }
                        }
                        let seconds =
                            Double(
                                DispatchTime.now().uptimeNanoseconds - started) / 1e9
                        accumulators[arm]!.selectionSeconds += seconds

                        if arm == .production {
                            for (input, pick) in zip(inputs, picks)
                            where pick != input.productionIndex {
                                throw ChallengeError.productionDiverged(
                                    corpus: corpus.name,
                                    fixture: fixture.id,
                                    charset: charsetName,
                                    recovered: glyphs[pick],
                                    rendered: glyphs[input.productionIndex]
                                )
                            }
                        }
                        for (input, pick) in zip(inputs, picks) {
                            try accumulators[arm]!.add(
                                index: pick,
                                productionIndex: input.productionIndex,
                                candidate: rasters[pick],
                                source: input.source
                            )
                        }

                        if fixtureIndex == 0 {
                            examples.append(
                                Example(
                                    corpus: corpus.name,
                                    charset: charsetName,
                                    fixture: fixture.id,
                                    arm: arm,
                                    lines: gridLines(
                                        picks: picks,
                                        glyphs: glyphs,
                                        rows: queries.rows,
                                        columns: queries.columns
                                    )
                                ))
                        }
                    }
                }

                guard let production = accumulators[.production], production.cells > 0 else {
                    throw ChallengeError.partialCensus(
                        corpus: corpus.name, fixture: "all", charset: charsetName)
                }
                for arm in Arm.allCases {
                    guard let accumulator = accumulators[arm], accumulator.cells == production.cells
                    else {
                        throw ChallengeError.partialCensus(
                            corpus: corpus.name, fixture: "all", charset: charsetName)
                    }
                    let distinct = accumulator.glyphUse.count(where: { $0 > 0 })
                    let largest = accumulator.glyphUse.max() ?? 0
                    rows.append(
                        Row(
                            corpus: corpus.name,
                            charset: charsetName,
                            arm: arm,
                            cells: accumulator.cells,
                            glyphs: glyphs.count,
                            distinctGlyphs: distinct,
                            largestGlyphShare: Double(largest) / Double(accumulator.cells),
                            candidateChurnFraction:
                                Double(accumulator.differingPicks) / Double(accumulator.cells),
                            meanMAE: accumulator.mae / Double(accumulator.cells),
                            meanGMSD: accumulator.gmsd / Double(accumulator.cells),
                            selectionWallSeconds: accumulator.selectionSeconds,
                            timeRatioToProduction:
                                accumulator.selectionSeconds / production.selectionSeconds,
                            estimatedPeakSelectorBytes: estimatedPeakSelectorBytes(
                                glyphs: glyphs.count, cells: accumulator.cells),
                            gitSHA: gitSHA
                        ))
                }
            }
        }

        let assessment = assess(rows)
        let wallSeconds = Double(DispatchTime.now().uptimeNanoseconds - wallStart) / 1e9
        return Report(
            rows: rows,
            examples: examples,
            assessment: assessment,
            measurementWallSeconds: wallSeconds,
            processMaximumResidentBytes: maximumResidentBytes()
        )
    }

    private static func gridLines(
        picks: [Int], glyphs: [Character], rows: Int, columns: Int
    ) -> [String] {
        guard picks.count == rows * columns else { return [] }
        return (0..<rows).map { row in
            String(picks[(row * columns)..<((row + 1) * columns)].map { glyphs[$0] })
        }
    }

    static func estimatedPeakSelectorBytes(glyphs: Int, cells: Int) -> Int {
        let rasterBank = glyphs * footprint * footprint * MemoryLayout<Float>.stride
        let sourceFootprint = footprint * footprint * MemoryLayout<Float>.stride
        let pickGrid = cells * MemoryLayout<Int>.stride
        return rasterBank + sourceFootprint + pickGrid
    }

    // MARK: - Mechanical decision rule

    static func assess(_ rows: [Row]) -> Assessment {
        var comparisons: [Comparison] = []
        var objectiveCandidates: [Arm] = []
        var memoryViableCandidates: [Arm] = []

        for arm in Arm.allCases where arm != .production {
            let armRows = rows.filter { $0.arm == arm }
            var hasAllRegimes = armRows.count == corpora.count * charsetNames.count
            var blocksPass = true
            var standardPass = true
            var gmsdPass = true
            var censusPass = true
            var memoryPass = true

            for row in armRows {
                guard
                    let production = rows.first(where: {
                        $0.corpus == row.corpus && $0.charset == row.charset
                            && $0.arm == .production
                    }),
                    production.meanMAE > 0,
                    production.meanGMSD > 0
                else {
                    hasAllRegimes = false
                    continue
                }
                let maeImprovement =
                    (production.meanMAE - row.meanMAE) / production.meanMAE * 100
                let gmsdRegression =
                    (row.meanGMSD - production.meanGMSD) / production.meanGMSD * 100
                comparisons.append(
                    Comparison(
                        corpus: row.corpus,
                        charset: row.charset,
                        arm: arm,
                        maeImprovementPercent: maeImprovement,
                        gmsdRegressionPercent: gmsdRegression,
                        timeRatio: row.timeRatioToProduction,
                        memoryBytes: row.estimatedPeakSelectorBytes
                    ))
                if row.charset == "blocks" {
                    blocksPass = blocksPass && maeImprovement >= 5.0
                } else if row.charset == "standard" {
                    standardPass = standardPass && maeImprovement >= -1.0
                }
                gmsdPass = gmsdPass && gmsdRegression <= 1.0
                censusPass =
                    censusPass && row.cells == production.cells
                    && row.candidateChurnFraction > 0
                memoryPass =
                    memoryPass
                    && row.estimatedPeakSelectorBytes <= memoryBudgetBytes
            }

            if hasAllRegimes, blocksPass, standardPass, gmsdPass, censusPass {
                objectiveCandidates.append(arm)
                if memoryPass { memoryViableCandidates.append(arm) }
            }
        }

        let selected = preferredTreatment(
            objectiveCandidates: memoryViableCandidates, comparisons: comparisons)
        let costPass: Bool =
            selected.map { arm in
                comparisons.filter { $0.arm == arm }.allSatisfy { comparison in
                    let budget = comparison.charset == "blocks" ? 4.0 : 12.0
                    return comparison.timeRatio <= budget
                }
            } ?? false
        let verdict =
            objectiveCandidates.isEmpty || memoryViableCandidates.isEmpty
            ? "KILL"
            : "HOLD - PERCEPTUAL DISPOSITION OPEN"
        return Assessment(
            verdict: verdict,
            objectiveCandidates: objectiveCandidates,
            selectedTreatment: selected,
            selectedMeetsCostBudget: costPass,
            comparisons: comparisons
        )
    }

    private static func preferredTreatment(
        objectiveCandidates: [Arm], comparisons: [Comparison]
    ) -> Arm? {
        guard !objectiveCandidates.isEmpty else { return nil }
        let means = Dictionary(
            uniqueKeysWithValues: objectiveCandidates.map { arm in
                let gains = comparisons.filter { $0.arm == arm && $0.charset == "blocks" }
                    .map(\.maeImprovementPercent)
                return (arm, gains.reduce(0, +) / Double(gains.count))
            })
        let best = objectiveCandidates.max {
            means[$0, default: -.infinity]
                < means[$1, default: -.infinity]
        }!
        let nearBest = objectiveCandidates.filter {
            means[best, default: -.infinity] - means[$0, default: -.infinity] < 1.0
        }
        return nearBest.min(by: { $0.order < $1.order })
    }

    // MARK: - Artifacts

    static func run(
        outputDirectory: String,
        gitSHAOverride: String?,
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void
    ) -> LabExitCode {
        let gitSHA = GitSHA.resolve(override: gitSHAOverride)
        do {
            let report = try evaluate(gitSHA: gitSHA)
            let output = URL(fileURLWithPath: outputDirectory)
            try FileManager.default.createDirectory(
                at: output, withIntermediateDirectories: true)
            try (csv(report.rows) + "\n").write(
                to: output.appendingPathComponent(csvFileName),
                atomically: true,
                encoding: .utf8
            )
            try (examplesText(report.examples) + "\n").write(
                to: output.appendingPathComponent(examplesFileName),
                atomically: true,
                encoding: .utf8
            )
            try (markdown(report) + "\n").write(
                to: output.appendingPathComponent(summaryFileName),
                atomically: true,
                encoding: .utf8
            )
            try
                (manifest(
                    report,
                    gitSHA: gitSHA,
                    outputDirectory: outputDirectory,
                    gitSHAOverride: gitSHAOverride
                ) + "\n").write(
                    to: output.appendingPathComponent(manifestFileName),
                    atomically: true,
                    encoding: .utf8
                )
            standardOutput("ASKI-69 render matcher challenge: \(report.assessment.verdict)\n")
            if let treatment = report.assessment.selectedTreatment {
                standardOutput("selected treatment: \(treatment.rawValue)\n")
            }
            return .success
        } catch let error as ChallengeError {
            standardError("error: \(error.description)\n")
            return .failure
        } catch {
            standardError("error: \(error)\n")
            return .ioError
        }
    }

    static func csv(_ rows: [Row]) -> String {
        var lines = [
            "corpus,charset,arm,cells,glyphs,distinct_glyphs,largest_glyph_share,candidate_churn,mean_mae,mean_gmsd,selection_wall_seconds,time_ratio_to_p,estimated_peak_selector_bytes,git_sha"
        ]
        for row in rows {
            lines.append(
                [
                    row.corpus,
                    row.charset,
                    row.arm.rawValue,
                    String(row.cells),
                    String(row.glyphs),
                    String(row.distinctGlyphs),
                    format(row.largestGlyphShare, digits: 8),
                    format(row.candidateChurnFraction, digits: 8),
                    format(row.meanMAE, digits: 8),
                    format(row.meanGMSD, digits: 8),
                    format(row.selectionWallSeconds, digits: 6),
                    format(row.timeRatioToProduction, digits: 4),
                    String(row.estimatedPeakSelectorBytes),
                    row.gitSHA,
                ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func examplesText(_ examples: [Example]) -> String {
        var lines = [
            "ASKI-69 first-fixture character grids",
            "Each arm uses the same 24x24 Courier renderer-faithful glyph masks.",
        ]
        for example in examples {
            lines.append("")
            lines.append(
                "=== \(example.corpus) / \(example.charset) / \(example.fixture) / \(example.arm.rawValue) ==="
            )
            lines.append(contentsOf: example.lines)
        }
        return lines.joined(separator: "\n")
    }

    static func markdown(_ report: Report) -> String {
        var lines = [
            "# ASKI-69 render-space matcher challenge",
            "",
            "Verdict: **\(report.assessment.verdict)**",
            "",
            "The frozen MAE and GMSD rule was applied separately to `blocks` and `standard` on both corpora. Generated metric grids are not perceptual votes. If an objective candidate exists, its human and pinned-VLM disposition remains open under a new ASKI-62-compatible treatment.",
            "",
            "## Regime census",
            "",
            "corpus | charset | arm | cells | glyphs used | largest share | churn | MAE | GMSD | seconds | ratio P | selector bytes",
            "--- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---:",
        ]
        for row in report.rows {
            lines.append(
                "\(row.corpus) | \(row.charset) | \(row.arm.rawValue) | \(row.cells) | \(row.distinctGlyphs)/\(row.glyphs) | \(percent(row.largestGlyphShare)) | \(percent(row.candidateChurnFraction)) | \(format(row.meanMAE, digits: 6)) | \(format(row.meanGMSD, digits: 6)) | \(format(row.selectionWallSeconds, digits: 4)) | \(format(row.timeRatioToProduction, digits: 2))x | \(row.estimatedPeakSelectorBytes)"
            )
        }

        lines += [
            "",
            "## Frozen-rule comparisons",
            "",
            "corpus | charset | arm | MAE improve | GMSD regress | time / P | memory",
            "--- | --- | --- | ---: | ---: | ---: | ---:",
        ]
        for comparison in report.assessment.comparisons {
            lines.append(
                "\(comparison.corpus) | \(comparison.charset) | \(comparison.arm.rawValue) | \(format(comparison.maeImprovementPercent, digits: 2))% | \(format(comparison.gmsdRegressionPercent, digits: 2))% | \(format(comparison.timeRatio, digits: 2))x | \(comparison.memoryBytes)"
            )
        }
        let candidates = report.assessment.objectiveCandidates.map(\.rawValue).joined(separator: ", ")
        lines += [
            "",
            "## Decision",
            "",
            "- Objective candidates: \(candidates.isEmpty ? "none" : candidates).",
            "- Selected arbiter treatment: \(report.assessment.selectedTreatment?.rawValue ?? "none").",
            "- Selected treatment meets the frozen time and memory cost budgets: \(report.assessment.selectedMeetsCostBudget ? "yes" : "no").",
            "- Measurement wall time: \(format(report.measurementWallSeconds, digits: 3)) seconds.",
            "- Process maximum resident size: \(report.processMaximumResidentBytes) bytes. This is descriptive; the per-row selector estimate is the memory gate.",
            "",
            "## Complexity boundary",
            "",
            "- Production source files changed: 0.",
            "- Public APIs or defaults added: 0.",
            "- Permanent production matcher paths added: 0.",
            "- Research selectors added: 3, contained in `AskiColorLab`.",
            "- A replacement task with a negative production-complexity budget is created only after PROMOTE. HOLD or KILL creates no production option.",
        ]
        return lines.joined(separator: "\n")
    }

    static func manifest(
        _ report: Report,
        gitSHA: String,
        outputDirectory: String,
        gitSHAOverride: String?
    ) -> String {
        let command = reproductionCommand(
            outputDirectory: outputDirectory, gitSHAOverride: gitSHAOverride)
        return [
            "---",
            "schema_version: \"1\"",
            "date: 2026-09-04",
            "aski_git_sha: \"\(yamlEscaped(gitSHA))\"",
            "runner: \"AskiColorLab\"",
            "command: \"\(yamlEscaped(command))\"",
            "provenance:",
            "  - \"Frozen rule: docs/Research/2026-09-04-aski69-render-space-matcher-rule.md; committed before this command ran\"",
            "  - \"Release build; exact converter sampling lattice; exhaustive stride 1 census\"",
            "  - \"Metric examples are not human or VLM votes\"",
            "datasets:",
            "  - docs/Research/Corpus/nasa-structure-v1",
            "  - docs/Research/Corpus/nasa-steerable-v1",
            "outputs:",
            "  - \(csvFileName)",
            "  - \(examplesFileName)",
            "  - \(summaryFileName)",
            "summary: \"ASKI-69 frozen render-space matcher challenge. Verdict: \(yamlEscaped(report.assessment.verdict)).\"",
            "---",
        ].joined(separator: "\n")
    }

    static func reproductionCommand(
        outputDirectory: String,
        gitSHAOverride: String?
    ) -> String {
        var command =
            "xcrun swift run -c release AskiColorLab render-matcher-challenge --output-dir \(outputDirectory)"
        if let gitSHAOverride { command += " --aski-git-sha \(gitSHAOverride)" }
        return command
    }

    private static func format(_ value: Double, digits: Int) -> String {
        String(format: "%.*f", digits, value)
    }

    private static func percent(_ fraction: Double) -> String {
        format(fraction * 100, digits: 2) + "%"
    }

    private static func yamlEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func resolvePackagePath(_ relativePath: String) -> String {
        var current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while current.path != "/" {
            if FileManager.default.fileExists(
                atPath: current.appendingPathComponent("Package.swift").path)
            {
                return current.appendingPathComponent(relativePath).path
            }
            current.deleteLastPathComponent()
        }
        return relativePath
    }

    private static func maximumResidentBytes() -> UInt64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return UInt64(max(0, usage.ru_maxrss))
    }
}

enum ChallengeError: Error, CustomStringConvertible {
    case fixtureCount(corpus: String, actual: Int)
    case fixtureGeometry(corpus: String, fixture: String, width: Int, height: Int)
    case invalidRaster(charset: String)
    case invalidLattice(corpus: String, fixture: String, charset: String)
    case missingCell(corpus: String, fixture: String, charset: String, row: Int, column: Int)
    case partialCensus(corpus: String, fixture: String, charset: String)
    case productionDiverged(
        corpus: String, fixture: String, charset: String, recovered: Character, rendered: Character)
    case nonFiniteScore

    var description: String {
        switch self {
        case .fixtureCount(let corpus, let actual):
            return "\(corpus) must contain exactly 3 fixtures, found \(actual)"
        case .fixtureGeometry(let corpus, let fixture, let width, let height):
            return "\(corpus)/\(fixture) has unfrozen geometry \(width)x\(height)"
        case .invalidRaster(let charset):
            return "\(charset) candidate raster bank is incomplete"
        case .invalidLattice(let corpus, let fixture, let charset):
            return "\(corpus)/\(fixture)/\(charset) did not resolve the frozen exact lattice"
        case .missingCell(let corpus, let fixture, let charset, let row, let column):
            return "missing cell \(row),\(column) in \(corpus)/\(fixture)/\(charset)"
        case .partialCensus(let corpus, let fixture, let charset):
            return "partial census in \(corpus)/\(fixture)/\(charset)"
        case .productionDiverged(
            let corpus, let fixture, let charset, let recovered, let rendered):
            return "P diverged in \(corpus)/\(fixture)/\(charset): recovered '\(recovered)', converter rendered '\(rendered)'"
        case .nonFiniteScore:
            return "a selector or oracle produced a non-finite score"
        }
    }
}
