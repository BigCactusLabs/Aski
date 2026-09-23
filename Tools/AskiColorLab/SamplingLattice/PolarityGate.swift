import AskiToolSupport
import CoreGraphics
import Foundation

@_spi(AskiResearch) import Aski

/// ASKI-60. What the `logPolar` shape query's ink convention costs, measured on
/// the REAL converter rather than on a lab re-implementation of it.
///
/// Production's shape term has histogrammed `1 − Rec.601 luma` since the first
/// log-polar commit, so it treats DARK source regions as ink. Its candidate
/// rasters, its tone pre-filter and its renderer all treat BRIGHT as ink. No
/// document in the repo ever decided that asymmetry. `ConventionAblation`
/// measured the two polarities through a lab sampler; this instrument measures
/// them through `ASCIIConverter.convert` itself, driven by the
/// `RenderingOptions.shapeQueryPolarity` knob, so the picks scored are the picks
/// the shipped matcher makes.
///
/// **What is held constant.** Everything except the knob: one converter
/// construction, one corpus walk, one scoring path
/// (`ConventionAblation.scoringRasters` — literally the same function the
/// convention ablation scores through), one oracle panel, exhaustive census.
/// The two arms differ in the polarity and in nothing else.
///
/// **The negative control is not optional.** The subject of this measurement is
/// an ink convention, so an oracle that moves with the convention would flatter
/// whichever arm shares its polarity. Every scored pair is re-scored with BOTH
/// planes negated; GMSD must reproduce within float noise and MAE must
/// reproduce to the same bound. If either moves materially the instrument is
/// polarity-coupled and the run is INVALID, not merely inconclusive.
enum PolarityGate {

    /// Oracles reported, MAE first: MAE is the house oracle (ASKI-27) and
    /// decides direction, GMSD is the convention-independent guard, SSIM and
    /// HaarPSI are reported and do not decide (SSIM's luminance term is
    /// polarity-coupled by construction).
    static let oracles: [SelectionCeiling.Oracle] = [.mae, .gmsd, .ssim, .haarPSI]

    /// Pre-registered decision thresholds. Written here, before the run, per the
    /// ASKI-60 addendum; changing them changes the gate, not the reporting.
    enum Rule {
        /// Relative MAE lift on `blocks`, both corpora, for CANDIDATE.
        static let requiredLiftPercent = 3.0
        /// Relative MAE regression on any other charset that vetoes CANDIDATE.
        static let regressionVetoPercent = 3.0
        /// The charset the promotion argument is about (the frozen preset's).
        static let decidingCharset = "blocks"
        /// Above this, a negated-plane rescore is a real move and the run is
        /// INVALID rather than float noise.
        static let negativeControlTolerance = 1e-6
        /// The pre-registered matrix. A run that measured less than this — one
        /// corpus, a subset of charsets, or a `--fixture-limit` smoke — reports
        /// numbers but is INVALID as a verdict, so a partial run can never be
        /// read as CANDIDATE.
        static let requiredCorpusCount = 2
        static let requiredCharsets = ["blocks", "standard", "braille"]
    }

    // MARK: - Rows

    struct ScoreRow: Sendable, Codable {
        let corpus: String
        let charset: String
        let polarity: String
        let oracle: String
        let cells: Int
        let glyphs: Int
        let mean: Double
    }

    /// One row per (corpus, charset, oracle): `direct` against `inverted`,
    /// signed so POSITIVE always means `direct` picked better.
    struct ComparisonRow: Sendable, Codable {
        let corpus: String
        let charset: String
        let oracle: String
        let cells: Int
        let invertedMean: Double
        let directMean: Double
        let improvementPercent: Double
        /// Share of cells where the two polarities chose different glyphs. Zero
        /// here would mean the knob never reached the picks.
        let differingPickPercent: Double
    }

    /// The mandatory negative control, per (corpus, charset, polarity).
    struct NegativeControlRow: Sendable, Codable {
        let corpus: String
        let charset: String
        let polarity: String
        let pairs: Int
        let maxAbsGMSDDelta: Double
        let maxAbsMAEDelta: Double
    }

    /// The tone pre-filter's reach on each charset (ASKI-60 mechanism check).
    ///
    /// `LogPolarKernel` prunes to `12 + round(density * 24)` brightness-nearest
    /// candidates and `ShapeMatching` takes `prefix(min(topK, count))`, so on a
    /// charset with fewer glyphs than `topK` the prune admits EVERY glyph and
    /// the shape term alone decides the pick. That is measured here rather than
    /// asserted, because it is the candidate explanation for why the polarity
    /// is a blocks-set effect.
    struct PoolSizeRow: Sendable, Codable {
        let charset: String
        let glyphs: Int
        /// `12 + round(density * 24)` at the resolved density.
        let topK: Int
        /// `min(topK, glyphs)` — what the pool actually holds.
        let poolSize: Int
        /// `false` means the pre-filter is a no-op and shape decides alone.
        let pruneBinds: Bool
    }

    /// Addendum item 5: the shipped renderer scored against the source, so the
    /// lab scoring path can be checked for SIGN agreement with what a viewer
    /// actually sees. Not a second verdict — an existence proof.
    struct RenderArmRow: Sendable, Codable {
        let corpus: String
        let fixture: String
        let polarity: String
        let renderedWidth: Int
        let renderedHeight: Int
        let sourceWidth: Int
        let sourceHeight: Int
        let mae: Double
        let gmsd: Double
        let png: String
    }

    /// One evaluated clause of the pre-registered rule.
    struct Clause: Sendable, Codable {
        let name: String
        let passed: Bool
        let detail: String
    }

    /// The four outcomes the ASKI-60 addendum pre-registers, decided by
    /// ``verdict(comparisons:negativeControl:)`` before any number was seen.
    ///
    /// `invalid` is never a result about the treatment — it says the instrument
    /// could not be trusted (the negative control moved, or an arm is missing)
    /// and the run must be re-instrumented. `inconclusive` and `candidate` both
    /// route to the ASKI-56 arbiter, because the 3.0% bar sits inside the JND75
    /// band; `kill` does not.
    enum Verdict: String, Sendable, Codable {
        case candidate = "CANDIDATE-FOR-PROMOTION"
        case inconclusive = "INCONCLUSIVE"
        case kill = "KILL"
        case invalid = "INVALID"
    }

    struct Report: Sendable, Codable {
        let gitSHA: String
        let columns: Int
        let oversample: Int
        let footprint: Int
        let cellWidth: Int
        let cellHeight: Int
        let fixtures: [String]
        /// Non-nil marks a SMOKE run: the corpus was truncated, so the verdict
        /// describes a fixture subset and is not the pre-registered regime.
        let fixtureLimit: Int?
        let poolSizes: [PoolSizeRow]
        let scores: [ScoreRow]
        let comparisons: [ComparisonRow]
        let negativeControl: [NegativeControlRow]
        let clauses: [Clause]
        let verdict: Verdict
        /// The clause that decided the verdict, named so the result is readable
        /// without re-deriving the rule.
        let decidingClause: String
        let renderArm: [RenderArmRow]
        let renderArmNote: String?
    }

    // MARK: - Run

    static func run(
        columns: Int,
        oversample: Int,
        footprint: Int,
        cellWidth: Int,
        cellHeight: Int,
        charsetNames: [String],
        corpora: [String],
        polarities: [ShapeQueryPolarity],
        fixtureLimit: Int?,
        gitSHA: String,
        renderArm: Bool,
        renderArmDirectory: URL?
    ) throws -> Report {
        var scores: [ScoreRow] = []
        var poolSizes: [PoolSizeRow] = []
        var renderArmRows: [RenderArmRow] = []
        var comparisons: [ComparisonRow] = []
        var negativeControl: [NegativeControlRow] = []
        var fixtureIDs: [String] = []

        for corpus in corpora {
            var fixtures = try SteerableBattery.naturals(corpusDirectory: corpus)
            if let fixtureLimit { fixtures = Array(fixtures.prefix(max(1, fixtureLimit))) }
            let corpusName = SelectionCeiling.corpusLabel(corpus)
            for fixture in fixtures where !fixtureIDs.contains(fixture.id) {
                fixtureIDs.append(fixture.id)
            }

            for charsetName in charsetNames {
                let characterSet = try SelectionCeiling.characterSet(named: charsetName)
                let glyphs = characterSet.characters
                try SelectionCeiling.assertUniqueGlyphs(glyphs, charset: charsetName)
                if !poolSizes.contains(where: { $0.charset == charsetName }) {
                    poolSizes.append(poolSizeRow(charset: charsetName, glyphs: glyphs.count))
                }
                let rasters = ConventionAblation.scoringRasters(
                    glyphs: glyphs, cellWidth: cellWidth, cellHeight: cellHeight,
                    footprint: footprint)

                // Per-polarity accumulators, plus the per-cell pick sequence so
                // the two arms can be compared cell for cell afterwards.
                var means: [ShapeQueryPolarity: [SelectionCeiling.Oracle: ConventionAblation.Accumulator]] = [:]
                var picks: [ShapeQueryPolarity: [Int]] = [:]
                var control: [ShapeQueryPolarity: (pairs: Int, gmsd: Double, mae: Double)] = [:]

                for polarity in polarities {
                    var options = RenderingOptions.default
                    options.shapeQueryPolarity = polarity
                    let converter = ASCIIConverter(
                        characterSet: characterSet,
                        palette: BuiltInPalette.monochrome,
                        options: options,
                        colorSpace: .sRGB,
                        oversample: oversample
                    )
                    var accumulators = Dictionary(
                        uniqueKeysWithValues: oracles.map { ($0, ConventionAblation.Accumulator()) })
                    var pickSequence: [Int] = []
                    var controlPairs = 0
                    var maxGMSD = 0.0
                    var maxMAE = 0.0

                    for fixture in fixtures {
                        let grid = converter.convert(fixture.image, columns: columns)
                        guard grid.rows > 0, grid.columns > 0,
                            let geometry = converter.samplingGeometry(
                                fixture.image, columns: columns),
                            geometry.rows == grid.rows, geometry.columns == grid.columns
                        else { continue }

                        for row in 0..<grid.rows {
                            for col in 0..<grid.columns {
                                guard
                                    let block = SampledSource.lumaBlock(
                                        fixture, cellRow: row, cellCol: col, geometry: geometry),
                                    block.width >= 2, block.height >= 2,
                                    let index = glyphs.firstIndex(
                                        of: grid.cells[row][col].character)
                                else { continue }

                                let source = LumaResample.resample(
                                    block.luma, srcWidth: block.width, srcHeight: block.height,
                                    dstWidth: footprint, dstHeight: footprint)
                                let candidate = rasters[index]
                                pickSequence.append(index)
                                var scored: [SelectionCeiling.Oracle: Double] = [:]
                                for oracle in oracles {
                                    let value = oracle.score(candidate, source, footprint: footprint)
                                    scored[oracle] = value
                                    accumulators[oracle]!.add(value)
                                }

                                // Negative control on the SAME pair, both planes
                                // negated. Scored on every cell rather than a
                                // sample: a control that only looks at some pairs
                                // cannot rule out a polarity coupling in the rest.
                                let negatedCandidate = candidate.map { 1 - $0 }
                                let negatedSource = source.map { 1 - $0 }
                                let negatedGMSD = SelectionCeiling.Oracle.gmsd.score(
                                    negatedCandidate, negatedSource, footprint: footprint)
                                let negatedMAE = SelectionCeiling.Oracle.mae.score(
                                    negatedCandidate, negatedSource, footprint: footprint)
                                maxGMSD = max(maxGMSD, abs((scored[.gmsd] ?? 0) - negatedGMSD))
                                maxMAE = max(maxMAE, abs((scored[.mae] ?? 0) - negatedMAE))
                                controlPairs += 1
                            }
                        }
                    }

                    means[polarity] = accumulators
                    picks[polarity] = pickSequence
                    control[polarity] = (controlPairs, maxGMSD, maxMAE)

                    for oracle in oracles {
                        scores.append(
                            ScoreRow(
                                corpus: corpusName, charset: charsetName,
                                polarity: label(polarity), oracle: oracle.rawValue,
                                cells: accumulators[oracle]!.count, glyphs: glyphs.count,
                                mean: accumulators[oracle]!.mean))
                    }
                    negativeControl.append(
                        NegativeControlRow(
                            corpus: corpusName, charset: charsetName,
                            polarity: label(polarity), pairs: controlPairs,
                            maxAbsGMSDDelta: maxGMSD, maxAbsMAEDelta: maxMAE))
                }

                // The comparison only exists when both arms ran.
                guard let inverted = means[.inverted], let direct = means[.direct],
                    let invertedPicks = picks[.inverted], let directPicks = picks[.direct],
                    invertedPicks.count == directPicks.count, !invertedPicks.isEmpty
                else { continue }
                var differing = 0
                for (lhs, rhs) in zip(invertedPicks, directPicks) where lhs != rhs { differing += 1 }
                let differingPercent = Double(differing) / Double(invertedPicks.count) * 100

                for oracle in oracles {
                    comparisons.append(
                        ComparisonRow(
                            corpus: corpusName, charset: charsetName, oracle: oracle.rawValue,
                            cells: inverted[oracle]!.count,
                            invertedMean: inverted[oracle]!.mean,
                            directMean: direct[oracle]!.mean,
                            improvementPercent: ConventionAblation.improvement(
                                baseline: inverted[oracle]!.mean, arm: direct[oracle]!.mean,
                                polarity: oracle.polarity),
                            differingPickPercent: differingPercent))
                }
            }
        }

        if renderArm, let renderArmDirectory {
            renderArmRows = try runRenderArm(
                corpora: corpora, polarities: polarities, fixtureLimit: fixtureLimit,
                outputDirectory: renderArmDirectory)
        }

        let clauses = evaluate(
            comparisons: comparisons, negativeControl: negativeControl,
            polarities: polarities, fixtureLimit: fixtureLimit)
        let decision = verdict(comparisons: comparisons, clauses: clauses)

        return Report(
            gitSHA: gitSHA, columns: columns, oversample: oversample, footprint: footprint,
            cellWidth: cellWidth, cellHeight: cellHeight, fixtures: fixtureIDs,
            fixtureLimit: fixtureLimit, poolSizes: poolSizes, scores: scores,
            comparisons: comparisons, negativeControl: negativeControl,
            clauses: clauses, verdict: decision.verdict,
            decidingClause: decision.decidingClause,
            renderArm: renderArmRows,
            renderArmNote: renderArm && renderArmDirectory == nil
                ? "--render-arm needs --output-dir: the arm's evidence is the PNGs it writes."
                : nil)
    }

    /// The tone pre-filter's reach, read off the kernel's own rule rather than
    /// restated: `LogPolarKernel` computes `topK = 12 + Int((density * 24)
    /// .rounded())` and `ShapeMatching` prunes with `prefix(min(topK, count))`.
    /// Measured at the converter's resolved default options, which is the regime
    /// every arm of this gate runs under.
    static func poolSizeRow(charset: String, glyphs: Int) -> PoolSizeRow {
        // `RenderingOptions.default.density` is 0 and finite, so resolution is
        // the identity here; reading the public default keeps this Tools-side.
        let density = RenderingOptions.default.density
        let topK = 12 + Int((density * 24).rounded())
        return PoolSizeRow(
            charset: charset, glyphs: glyphs, topK: topK,
            poolSize: min(topK, glyphs), pruneBinds: glyphs > topK)
    }

    static func label(_ polarity: ShapeQueryPolarity) -> String {
        switch polarity {
        case .inverted: return "inverted"
        case .direct: return "direct"
        }
    }

    static func parse(_ raw: String) -> ShapeQueryPolarity? {
        switch raw {
        case "inverted": return .inverted
        case "direct": return .direct
        default: return nil
        }
    }

    // MARK: - Decision rule

    /// The pre-registered outcome, decided from the MAE and GMSD comparison
    /// rows and the negative-control clause. Written before any Phase B number
    /// was seen (ASKI-60 addendum, "Decisions taken after Phase A review") and
    /// evaluated in this order:
    ///
    /// 1. The negative control failing, or an arm missing, is INVALID — the run
    ///    is not evidence about the treatment and has to be re-instrumented.
    /// 2. KILL iff `direct` is WORSE than `inverted` on blocks MAE on either
    ///    corpus, OR any non-blocks charset regresses by more than 3.0% MAE on
    ///    either corpus.
    /// 3. CANDIDATE iff blocks MAE lift exceeds 3.0% on BOTH corpora, GMSD
    ///    agrees with MAE in sign on both, and no non-blocks charset regresses.
    /// 4. INCONCLUSIVE otherwise: `direct` wins blocks on both corpora but the
    ///    lift is inside the bar on one, or GMSD disagrees with MAE in sign.
    ///
    /// A non-finite blocks lift (degenerate baseline) cannot show `direct` to be
    /// worse and cannot clear the bar, so it lands in INCONCLUSIVE rather than
    /// inventing a fifth outcome.
    static func verdict(
        comparisons: [ComparisonRow], clauses: [Clause]
    ) -> (verdict: Verdict, decidingClause: String) {
        func clausePassed(_ name: String) -> Bool {
            clauses.first { $0.name.hasPrefix(name) }?.passed ?? false
        }
        guard clausePassed("negative control") else {
            return (.invalid, "negative control")
        }
        guard clausePassed("both arms measured") else {
            return (.invalid, "both arms measured")
        }
        guard clausePassed("full matrix measured") else {
            return (.invalid, "full matrix measured")
        }

        let blocksMAE = comparisons.filter {
            $0.charset == Rule.decidingCharset && $0.oracle == SelectionCeiling.Oracle.mae.rawValue
        }
        guard !blocksMAE.isEmpty else {
            return (.invalid, "blocks MAE rows present")
        }

        // 2. KILL — `direct` actually loses on the deciding charset, or the
        //    treatment breaks a charset it was not aimed at.
        if let worse = blocksMAE.first(where: { $0.improvementPercent.isFinite && $0.improvementPercent < 0 }) {
            return (
                .kill,
                "direct is worse than inverted on blocks MAE (\(worse.corpus): "
                    + "\(ConventionAblation.trimmed(worse.improvementPercent))%)"
            )
        }
        if !clausePassed("no other charset regresses") {
            return (.kill, "no other charset regresses > \(Rule.regressionVetoPercent)% MAE")
        }

        // 3/4. Both remaining outcomes route to the arbiter; they differ in
        //      whether the pre-registered bar was cleared with the guard agreeing.
        let liftPassed = clausePassed("blocks MAE lift")
        let signAgrees = clausePassed("GMSD agrees with MAE in sign")
        if liftPassed && signAgrees {
            return (.candidate, "all clauses passed")
        }
        if !signAgrees {
            return (.inconclusive, "GMSD agrees with MAE in sign on blocks, both corpora")
        }
        return (
            .inconclusive,
            "blocks MAE lift > \(Rule.requiredLiftPercent)% on both corpora"
        )
    }

    /// The rule exactly as pre-registered in the ASKI-60 addendum, evaluated
    /// clause by clause so a failure names itself instead of collapsing into a
    /// single boolean.
    static func evaluate(
        comparisons: [ComparisonRow],
        negativeControl: [NegativeControlRow],
        polarities: [ShapeQueryPolarity],
        fixtureLimit: Int? = nil
    ) -> [Clause] {
        var clauses: [Clause] = []

        // Clause -1: the full pre-registered matrix was measured. Every required
        // charset needs an MAE row with cells on every corpus, blocks needs a
        // GMSD row on every corpus, at least `requiredCorpusCount` corpora ran,
        // and no fixture limit was applied. Anything less is a smoke run.
        let corpora = Set(comparisons.map(\.corpus))
        var missing: [String] = []
        if corpora.count < Rule.requiredCorpusCount {
            missing.append("\(corpora.count) of \(Rule.requiredCorpusCount) corpora")
        }
        for corpus in corpora.sorted() {
            for charset in Rule.requiredCharsets {
                let hasMAE = comparisons.contains {
                    $0.corpus == corpus && $0.charset == charset
                        && $0.oracle == SelectionCeiling.Oracle.mae.rawValue && $0.cells > 0
                }
                if !hasMAE { missing.append("\(corpus)/\(charset) MAE") }
            }
            let hasGMSD = comparisons.contains {
                $0.corpus == corpus && $0.charset == Rule.decidingCharset
                    && $0.oracle == SelectionCeiling.Oracle.gmsd.rawValue && $0.cells > 0
            }
            if !hasGMSD { missing.append("\(corpus)/\(Rule.decidingCharset) GMSD") }
        }
        if let fixtureLimit { missing.append("fixture-limit \(fixtureLimit) (smoke run)") }
        clauses.append(
            Clause(
                name: "full matrix measured", passed: missing.isEmpty,
                detail: missing.isEmpty
                    ? "\(corpora.count) corpora × \(Rule.requiredCharsets.joined(separator: ",")) × MAE+GMSD, no fixture limit"
                    : "missing: " + missing.joined(separator: "; ")))

        // Clause 0: both arms present. A one-polarity run reports numbers but
        // cannot reach a verdict, and saying so is the honest output.
        let bothArms = polarities.contains(.inverted) && polarities.contains(.direct)
        clauses.append(
            Clause(
                name: "both arms measured", passed: bothArms,
                detail: bothArms
                    ? "inverted and direct both ran"
                    : "only " + polarities.map(label).joined(separator: ", ")
                        + " ran; the rule needs both"))

        // Clause 1: blocks MAE lift > 3.0% on BOTH corpora.
        let blocksMAE = comparisons.filter {
            $0.charset == Rule.decidingCharset && $0.oracle == SelectionCeiling.Oracle.mae.rawValue
        }
        let liftPassed =
            !blocksMAE.isEmpty && blocksMAE.allSatisfy { $0.improvementPercent > Rule.requiredLiftPercent }
        clauses.append(
            Clause(
                name: "blocks MAE lift > \(Rule.requiredLiftPercent)% on both corpora",
                passed: liftPassed,
                detail: blocksMAE.isEmpty
                    ? "no blocks MAE rows"
                    : blocksMAE.map { "\($0.corpus): \(ConventionAblation.trimmed($0.improvementPercent))%" }
                        .joined(separator: ", ")))

        // Clause 2: GMSD agrees in sign with MAE on BOTH corpora for blocks.
        let blocksGMSD = comparisons.filter {
            $0.charset == Rule.decidingCharset && $0.oracle == SelectionCeiling.Oracle.gmsd.rawValue
        }
        var signAgrees = !blocksGMSD.isEmpty && !blocksMAE.isEmpty
        for gmsdRow in blocksGMSD {
            guard let maeRow = blocksMAE.first(where: { $0.corpus == gmsdRow.corpus }),
                gmsdRow.improvementPercent.isFinite, maeRow.improvementPercent.isFinite,
                (gmsdRow.improvementPercent > 0) == (maeRow.improvementPercent > 0)
            else {
                signAgrees = false
                continue
            }
        }
        clauses.append(
            Clause(
                name: "GMSD agrees with MAE in sign on blocks, both corpora",
                passed: signAgrees,
                detail: blocksGMSD.map {
                    "\($0.corpus): GMSD \(ConventionAblation.trimmed($0.improvementPercent))%"
                }.joined(separator: ", ")))

        // Clause 3: no OTHER charset regresses by more than 3.0% MAE anywhere.
        let otherMAE = comparisons.filter {
            $0.charset != Rule.decidingCharset && $0.oracle == SelectionCeiling.Oracle.mae.rawValue
        }
        let regressions = otherMAE.filter {
            $0.improvementPercent.isFinite && $0.improvementPercent < -Rule.regressionVetoPercent
        }
        clauses.append(
            Clause(
                name: "no other charset regresses > \(Rule.regressionVetoPercent)% MAE",
                passed: regressions.isEmpty,
                detail: regressions.isEmpty
                    ? "worst non-blocks MAE move: "
                        + (otherMAE.map(\.improvementPercent).filter(\.isFinite).min().map {
                            ConventionAblation.trimmed($0) + "%"
                        } ?? "n/a")
                    : regressions.map {
                        "\($0.corpus)/\($0.charset): \(ConventionAblation.trimmed($0.improvementPercent))%"
                    }.joined(separator: ", ")))

        // Clause 4: the negative control. A failure here invalidates the run.
        let worstGMSD = negativeControl.map(\.maxAbsGMSDDelta).max() ?? 0
        let worstMAE = negativeControl.map(\.maxAbsMAEDelta).max() ?? 0
        let controlHolds =
            !negativeControl.isEmpty && worstGMSD <= Rule.negativeControlTolerance
            && worstMAE <= Rule.negativeControlTolerance
        clauses.append(
            Clause(
                name: "negative control", passed: controlHolds,
                detail: negativeControl.isEmpty
                    ? "no pairs scored"
                    : "max |ΔGMSD| \(ConventionAblation.trimmed(worstGMSD)), max |ΔMAE| "
                        + "\(ConventionAblation.trimmed(worstMAE)) over "
                        + "\(negativeControl.reduce(0) { $0 + $1.pairs }) pairs "
                        + "(tolerance \(Rule.negativeControlTolerance))"))

        return clauses
    }

    // MARK: - Real-renderer arm

    /// Addendum item 5. Renders the picked grid through the SHIPPED
    /// `ImageRenderer` and scores it against the source, once per corpus and
    /// polarity, so the lab's cell-wise scoring path can be checked for SIGN
    /// agreement with the image a viewer actually gets.
    ///
    /// Deliberately NOT the frozen preset. Scoring is on luma, so the preset's
    /// duotone palette cannot affect the answer; using a plain converter with
    /// white ink on a black ground keeps the arm a statement about the renderer
    /// rather than about one palette. Blocks at 76 columns is kept because that
    /// is the shipping column count the preset froze.
    ///
    /// The rendered image is resampled to the SOURCE geometry with the same
    /// area-weighted `LumaResample` every other instrument uses, so the two
    /// planes are compared at the resolution the source actually carries.
    static let renderArmColumns = 76
    static let renderArmCharset = "blocks"
    static let renderArmFontSize: CGFloat = 12
    static let renderArmScale: CGFloat = 1

    static func runRenderArm(
        corpora: [String],
        polarities: [ShapeQueryPolarity],
        fixtureLimit: Int?,
        outputDirectory: URL
    ) throws -> [RenderArmRow] {
        let directory = outputDirectory.appendingPathComponent("render-arm")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let characterSet = try SelectionCeiling.characterSet(named: renderArmCharset)
        var rows: [RenderArmRow] = []

        for corpus in corpora {
            let fixtures = try SteerableBattery.naturals(corpusDirectory: corpus)
            // One fixture per corpus, the loader's first in deterministic
            // filename order — an existence proof needs one image, not a census.
            guard let fixture = fixtures.first else { continue }
            let corpusName = SelectionCeiling.corpusLabel(corpus)

            for polarity in polarities {
                var options = RenderingOptions.default
                options.shapeQueryPolarity = polarity
                let converter = ASCIIConverter(
                    characterSet: characterSet,
                    palette: BuiltInPalette.monochrome,
                    options: options,
                    colorSpace: .sRGB,
                    oversample: 2
                )
                let grid = converter.convert(fixture.image, columns: renderArmColumns)
                let rendered = grid.renderImage(
                    font: .courierPrime(size: renderArmFontSize),
                    backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                    scale: renderArmScale,
                    preserveSourceAspect: true
                )
                guard let renderedLuma = luma(of: rendered) else { continue }

                let filename =
                    "render_\(corpusName)_\(fixture.id)_\(label(polarity)).png"
                try DemoImageIO.writePNG(
                    rendered, to: directory.appendingPathComponent(filename).path)

                let resampled = LumaResample.resample(
                    renderedLuma.values,
                    srcWidth: renderedLuma.width, srcHeight: renderedLuma.height,
                    dstWidth: fixture.width, dstHeight: fixture.height)
                var maeTotal = 0.0
                for index in resampled.indices {
                    maeTotal += Double(abs(resampled[index] - fixture.luma[index]))
                }
                rows.append(
                    RenderArmRow(
                        corpus: corpusName, fixture: fixture.id, polarity: label(polarity),
                        renderedWidth: renderedLuma.width, renderedHeight: renderedLuma.height,
                        sourceWidth: fixture.width, sourceHeight: fixture.height,
                        mae: maeTotal / Double(resampled.count),
                        gmsd: GMSD.gmsd(
                            resampled, fixture.luma,
                            width: fixture.width, height: fixture.height),
                        png: "render-arm/" + filename))
            }
        }
        return rows
    }

    /// Rec.601 luma of a `CGImage`, drawn once into an sRGB RGBA context — the
    /// same weights `LogPolarKernel.baseInkField` uses, so the render arm and
    /// the census agree on what "luma" means.
    static func luma(of image: CGImage) -> (values: [Float], width: Int, height: Int)? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard
            let context = buffer.withUnsafeMutableBytes({ raw -> CGContext? in
                CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            })
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var values = [Float](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let offset = index * 4
            values[index] =
                0.299 * Float(buffer[offset]) / 255
                + 0.587 * Float(buffer[offset + 1]) / 255
                + 0.114 * Float(buffer[offset + 2]) / 255
        }
        return (values, width, height)
    }

    // MARK: - Output

    static let scoresCSVHeader = "corpus,charset,polarity,oracle,cells,glyphs,mean"

    static func scoresCSV(_ rows: [ScoreRow]) -> String {
        var lines = [scoresCSVHeader]
        for row in rows {
            lines.append(
                [
                    row.corpus, row.charset, row.polarity, row.oracle, String(row.cells),
                    String(row.glyphs), ConventionAblation.trimmed(row.mean),
                ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func format(_ report: Report, reproduce: String) -> String {
        var lines = ["# Shape-query polarity gate (ASKI-60)"]
        lines.append("")
        lines.append("Provenance: `\(report.gitSHA)`.")
        lines.append(
            "Regime: columns \(report.columns), oversample \(report.oversample), footprint "
                + "\(report.footprint), sampling cell \(report.cellWidth)x\(report.cellHeight), "
                + "exhaustive census.")
        lines.append("Fixtures: \(report.fixtures.joined(separator: ", ")).")
        if let limit = report.fixtureLimit {
            lines.append("")
            lines.append(
                "**SMOKE RUN — NOT QUOTABLE.** `--fixture-limit \(limit)` truncated each corpus, so "
                    + "every number and the verdict below describe a fixture subset, not the "
                    + "pre-registered regime.")
        }
        lines.append("")
        lines.append("## Reproduce")
        lines.append("")
        lines.append("```")
        lines.append(reproduce)
        lines.append("```")
        lines.append("")
        lines.append("## How to read this")
        lines.append("")
        lines.append(
            "- **MAE decides direction (ASKI-27).** It is printed first everywhere. GMSD is the"
        )
        lines.append(
            "  convention-independent GUARD: Prewitt kernels are zero-mean, so a global negation of"
        )
        lines.append(
            "  both planes leaves gradient magnitudes untouched and GMSD cannot be flattered by the"
        )
        lines.append("  ink convention under test. SSIM and HaarPSI are reported and do NOT decide —")
        lines.append("  SSIM's luminance term is polarity-coupled by construction.")
        lines.append(
            "- **`improvement%` is signed so POSITIVE means `direct` picked better**, whichever way"
        )
        lines.append("  the oracle points.")
        lines.append(
            "- **A CANDIDATE verdict does not flip the default.** Standing rule ASKI-56: default"
        )
        lines.append(
            "  promotion requires an `AskiColorLab arbiter score` sitting, in a follow-up PR."
        )
        lines.append(
            "- **The four outcomes are pre-registered.** KILL: `direct` is worse on blocks MAE on"
        )
        lines.append(
            "  either corpus, or a non-blocks charset regresses > 3.0% MAE. CANDIDATE: blocks MAE"
        )
        lines.append(
            "  lift > 3.0% on BOTH corpora with GMSD agreeing in sign and no regression."
        )
        lines.append(
            "  INCONCLUSIVE: `direct` wins blocks on both but inside the bar, or GMSD disagrees —"
        )
        lines.append(
            "  it routes to the arbiter just as CANDIDATE does, because the bar sits inside the"
        )
        lines.append(
            "  ASKI-56 JND75 band. INVALID: the negative control moved, or an arm is missing —"
        )
        lines.append("  a re-instrument, never a result about the treatment.")

        lines.append("")
        lines.append("## Tone pre-filter reach (mechanism check)")
        lines.append(
            "`LogPolarKernel` prunes to `topK = 12 + round(density*24)` brightness-nearest"
        )
        lines.append(
            "candidates and `ShapeMatching` takes `prefix(min(topK, count))`. Where `pruneBinds` is"
        )
        lines.append(
            "`false` the pool holds EVERY glyph, the tone term selects nothing, and the shape term"
        )
        lines.append("decides the pick alone.")
        lines.append("charset | glyphs | topK | poolSize | pruneBinds")
        for row in report.poolSizes {
            lines.append(
                "\(row.charset) | \(row.glyphs) | \(row.topK) | \(row.poolSize) | \(row.pruneBinds)"
            )
        }

        lines.append("")
        lines.append("## Oracle means per arm")
        lines.append("corpus | charset | polarity | oracle | cells | mean")
        for row in ordered(report.scores, oracle: \.oracle) {
            lines.append(
                "\(row.corpus) | \(row.charset) | \(row.polarity) | \(row.oracle) | \(row.cells) | "
                    + String(format: "%.5f", row.mean))
        }

        lines.append("")
        lines.append("## direct vs inverted (positive = direct picked better)")
        lines.append("corpus | charset | oracle | cells | inverted | direct | improve% | differPicks%")
        for row in ordered(report.comparisons, oracle: \.oracle) {
            lines.append(
                String(
                    format: "%@ | %@ | %@ | %d | %.5f | %.5f | %.2f | %.1f",
                    row.corpus, row.charset, row.oracle, row.cells, row.invertedMean,
                    row.directMean, row.improvementPercent, row.differingPickPercent))
        }

        lines.append("")
        lines.append("## Negative control (both planes negated)")
        lines.append("corpus | charset | polarity | pairs | max|ΔGMSD| | max|ΔMAE|")
        for row in report.negativeControl {
            lines.append(
                "\(row.corpus) | \(row.charset) | \(row.polarity) | \(row.pairs) | "
                    + "\(ConventionAblation.trimmed(row.maxAbsGMSDDelta)) | "
                    + "\(ConventionAblation.trimmed(row.maxAbsMAEDelta))")
        }

        lines.append("")
        lines.append("## Pre-registered decision rule")
        lines.append("clause | result | detail")
        for clause in report.clauses {
            lines.append("\(clause.name) | \(clause.passed ? "PASS" : "FAIL") | \(clause.detail)")
        }
        lines.append("")
        lines.append("**Verdict: \(report.verdict.rawValue).**")
        lines.append("")
        lines.append("Deciding clause: \(report.decidingClause).")
        let failed = report.clauses.filter { !$0.passed }.map(\.name)
        if !failed.isEmpty {
            lines.append("")
            lines.append("Failing clause(s): \(failed.joined(separator: "; ")).")
        }

        if !report.renderArm.isEmpty {
            lines.append("")
            lines.append("## Real-renderer arm (sign agreement, not a second verdict)")
            lines.append(
                "One fixture per corpus rendered through the shipped `ImageRenderer` (blocks, "
                    + "\(renderArmColumns) columns, white ink on black), area-weighted down to the "
                    + "source geometry and scored against the source luma. What matters is whether "
                    + "the SIGN of the polarity difference matches the cell-wise census above."
            )
            lines.append("corpus | fixture | polarity | rendered | source | MAE | GMSD")
            for row in report.renderArm {
                lines.append(
                    String(
                        format: "%@ | %@ | %@ | %dx%d | %dx%d | %.5f | %.5f",
                        row.corpus, row.fixture, row.polarity, row.renderedWidth,
                        row.renderedHeight, row.sourceWidth, row.sourceHeight, row.mae, row.gmsd))
            }
        }
        if let note = report.renderArmNote {
            lines.append("")
            lines.append("## Real-renderer arm")
            lines.append("")
            lines.append(note)
        }
        return lines.joined(separator: "\n")
    }

    /// MAE-first ordering, stable within the emission order otherwise — the same
    /// rule `ConventionAblation` prints under.
    private static func ordered<Row>(_ rows: [Row], oracle: KeyPath<Row, String>) -> [Row] {
        let rank = Dictionary(
            uniqueKeysWithValues: oracles.enumerated().map { ($1.rawValue, $0) })
        return rows.enumerated()
            .sorted {
                let a = rank[$0.element[keyPath: oracle]] ?? Int.max
                let b = rank[$1.element[keyPath: oracle]] ?? Int.max
                return a == b ? $0.offset < $1.offset : a < b
            }
            .map(\.element)
    }
}
