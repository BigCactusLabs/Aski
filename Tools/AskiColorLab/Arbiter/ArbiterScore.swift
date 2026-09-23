import AskiToolSupport
import Foundation

extension Arbiter {

    /// ASKI-56 §2.3 + §5.1, executed: ingest the human answers and/or the judge
    /// results, join them against `key.json`, apply the frozen gate, and emit
    /// `result.yaml` plus a Markdown readout.
    enum Score {

        /// α for the human verdict's one-sided binomial (§2.3).
        static let alpha = 0.05
        /// §2.3: "A verdict line is emitted only if decided n ≥ 30".
        static let minimumDecidedTrials = 30
        /// §5.1: "≥5 of 6 V pairs".
        static let validationGateThreshold = 5
        /// §5.2's standing bar, as a fraction.
        static let barFraction = 0.030
        /// Bootstrap draws for the JND75 band.
        static let bootstrapResamples = 2000
        /// The families the psychometric curve is fitted on (§2.3 + the M1
        /// erratum). C is the ladder; M is registered as calibration-adjacent by
        /// §2.1. V and D are excluded — V's margin is an order of magnitude
        /// beyond the ladder and would set the slope by leverage alone.
        static let calibrationFitFamilies: Set<Family> = [.calibration, .adversarial]
        /// The units the regressor and therefore the JND75 band are in. The
        /// §5.2 bar is a RATIO (`MAE_arm / MAE_baseline <= 0.97`), so the band
        /// has to be a ratio too or the comparison is a units error.
        static let calibrationUnits = "relative-mae-margin"

        enum GateStatus: String, Sendable, Codable, Equatable {
            case pass
            case fail
            case notEvaluated = "not-evaluated"
        }

        struct Input: Sendable {
            let key: KeyFile
            let humanAnswers: [String: Choice]
            let judgements: [Judge.PairJudgement]

            init(key: KeyFile, humanAnswers: [String: Choice], judgements: [Judge.PairJudgement]) {
                self.key = key
                self.humanAnswers = humanAnswers
                self.judgements = judgements
            }
        }

        /// Everything the readout and the manifest are rendered from.
        struct Report: Sendable {
            // §5.1
            let humanGate: GateStatus
            let humanValidationCorrect: Int
            let humanValidationTotal: Int
            let vlmGate: GateStatus
            let vlmValidationCorrect: Int
            let vlmValidationTotal: Int
            /// §5.1: on failure the VLM leg is reported invalid and the human
            /// leg stands alone. That is NOT a run failure.
            let vlmLegIsValid: Bool

            // §2.3 human verdict
            let humanDecidedN: Int
            let humanSuccesses: Int
            let humanTies: Int
            let humanTieRate: Double
            let humanUpperTailP: Double?
            /// `nil` below the pre-registered decided-n threshold.
            let humanVerdict: String?

            // §2.3 rater consistency (reported, never gated)
            let raterConsistency: Double?
            let raterRepeatCount: Int

            // §2.3 / AC#3 calibration
            let calibrationTrials: Int
            let calibrationUnits: String
            let calibrationFamilies: [String]
            let metricTies: Int
            let jnd75: ArbiterStatistics.JND75Band?
            let pse: Double?
            let barAssessment: ArbiterStatistics.BarAssessment?

            // Per-family behavior, including the D near-tie readout (§4).
            let familySplits: [String: FamilySplit]
            /// §4: the VLM leg's order-inconsistency rate on the D pairs is the
            /// deliverable, not a gate.
            let vlmOrderInconsistencyRate: [String: Double]

            /// §2.3's FAIL-FAST: a failed HUMAN gate fails the run.
            let exitCode: LabExitCode
        }

        struct FamilySplit: Sendable, Codable {
            let answered: Int
            let chosenLowerMAE: Int
            let ties: Int
        }

        // MARK: - Scoring

        static func score(_ input: Input) throws -> Report {
            // A key that fails to yield pairs (unknown arm, newer protocol)
            // must fail the run loudly — an empty pair list would score as a
            // plausible not-evaluated report with exit 0.
            let pairs = try input.key.pairs()
            let byID = Dictionary(uniqueKeysWithValues: pairs.map { ($0.id, $0) })
            let judgementsByID = Dictionary(
                input.judgements.map { ($0.pairID, $0) }, uniquingKeysWith: { first, _ in first })

            // --- §5.1 validation gate -------------------------------------
            let validationPairs = pairs.filter { $0.family == .validation && $0.repeatOf == nil }
            // The correct answer on a V pair is F, and F is the lower-MAE arm by
            // a huge margin — every one of the five oracles agrees. So "answered
            // F" and "answered the lower-MAE side" are the same predicate here,
            // and reading it off the arm name is what makes the gate honest if a
            // future V family ever changes arms.
            func namesFloor(_ pair: Pair, _ choice: Choice) -> Bool {
                pair.arm(for: choice)?.name == "F"
            }

            var humanValidationCorrect = 0
            var answeredValidation = 0
            for pair in validationPairs {
                guard let choice = input.humanAnswers[pair.id] else { continue }
                answeredValidation += 1
                if namesFloor(pair, choice) { humanValidationCorrect += 1 }
            }
            let humanGate: GateStatus
            if answeredValidation == 0 {
                humanGate = .notEvaluated
            } else {
                humanGate = humanValidationCorrect >= validationGateThreshold ? .pass : .fail
            }

            var vlmValidationCorrect = 0
            var judgedValidation = 0
            for pair in validationPairs {
                guard let judgement = judgementsByID[pair.id] else { continue }
                judgedValidation += 1
                let choice: Choice? =
                    judgement.decision == .left
                    ? .left : (judgement.decision == .right ? .right : nil)
                if let choice, namesFloor(pair, choice) { vlmValidationCorrect += 1 }
            }
            let vlmGate: GateStatus =
                judgedValidation == 0
                ? .notEvaluated
                : (vlmValidationCorrect >= validationGateThreshold ? .pass : .fail)

            // --- §2.3 human verdict ---------------------------------------
            // Decided = non-tie, non-repeat. Repeats measure the rater, not the
            // arms, so counting them would double-count six of the sources and
            // inflate n past what the design supports.
            var decided = 0
            var successes = 0
            var ties = 0
            var metricTies = 0
            var answeredUnique = 0
            var familyTotals: [String: (answered: Int, lower: Int, ties: Int)] = [:]
            var calibrationTrials: [ArbiterStatistics.CalibrationTrial] = []

            for pair in pairs where pair.repeatOf == nil {
                guard let choice = input.humanAnswers[pair.id] else { continue }
                answeredUnique += 1
                var entry = familyTotals[pair.family.rawValue] ?? (0, 0, 0)
                entry.answered += 1
                if choice == .tie {
                    ties += 1
                    entry.ties += 1
                    familyTotals[pair.family.rawValue] = entry
                    continue
                }
                familyTotals[pair.family.rawValue] = entry

                // An exact MAE tie has no lower-MAE side, so there is no right
                // answer to score against. Counting it as a binomial failure
                // invents a wrong answer, and feeding it to the fit adds a
                // `y = 0` point at margin 0 that drags the curve down at the
                // origin — precisely where JND75 is read.
                guard let lower = pair.lowerMAESide else {
                    metricTies += 1
                    continue
                }
                decided += 1
                let choseLower = lower == choice
                if choseLower {
                    successes += 1
                    entry.lower += 1
                    familyTotals[pair.family.rawValue] = entry
                }

                // §2.3's calibration set is the ladder. M is registered by §2.1
                // as calibration-adjacent — it exists to probe where MAE is
                // blind — so it belongs. V and D do NOT: the V pairs sit an
                // order of magnitude beyond the ladder's largest rung, which
                // makes six trials the highest-leverage points in the whole
                // regression and lets them set the slope on their own.
                guard calibrationFitFamilies.contains(pair.family) else { continue }
                let margin = pair.metrics.relativeMarginMAE
                if margin.isFinite {
                    calibrationTrials.append(
                        .init(
                            sourceKey: pair.source.key, relativeMarginMAE: margin,
                            choseLowerMAESide: choseLower))
                }
            }

            let upperTail: Double? =
                decided > 0
                ? ArbiterStatistics.binomialUpperTail(successes: successes, trials: decided) : nil
            var verdict: String?
            if decided >= minimumDecidedTrials, let upperTail {
                verdict =
                    upperTail < alpha
                    ? "the rater prefers the lower-MAE side (p = \(formatted(upperTail)), n = \(decided))"
                    : "no detectable preference for the lower-MAE side (p = \(formatted(upperTail)), n = \(decided))"
            }

            // --- §2.3 rater consistency ------------------------------------
            let repeats = pairs.filter { $0.repeatOf != nil }
            var agreed = 0
            var comparable = 0
            for repeated in repeats {
                guard
                    let originID = repeated.repeatOf,
                    let origin = byID[originID],
                    let repeatChoice = input.humanAnswers[repeated.id],
                    let originChoice = input.humanAnswers[originID]
                else { continue }
                comparable += 1
                // Agreement is on the ARM, not the side: the repeat is
                // re-randomized, so a consistent rater flips sides.
                if repeated.arm(for: repeatChoice) == origin.arm(for: originChoice) { agreed += 1 }
            }
            let consistency = comparable > 0 ? Double(agreed) / Double(comparable) : nil

            // --- §2.3 calibration (AC#3) -----------------------------------
            let band = ArbiterStatistics.jnd75Band(
                trials: calibrationTrials, seed: input.key.seed, resamples: bootstrapResamples)
            let fit = ArbiterStatistics.fitLogistic(
                x: calibrationTrials.map(\.relativeMarginMAE),
                y: calibrationTrials.map { $0.choseLowerMAESide ? 1.0 : 0.0 })
            let pse = fit.flatMap { ArbiterStatistics.level($0, probability: 0.5) }
            let assessment = band.map {
                ArbiterStatistics.assessBar(
                    band: (low: $0.low, high: $0.high), barFraction: barFraction)
            }

            // --- §4 D-family VLM order inconsistency -----------------------
            var inconsistency: [String: Double] = [:]
            for family in Family.allCases {
                let inFamily = pairs.filter { $0.family == family && $0.repeatOf == nil }
                // A pair where BOTH orders have no majority is a pair the judge
                // never actually answered. Counting it as "the orders agreed"
                // makes an all-invalid run look perfectly order-consistent, so
                // it leaves the denominator entirely.
                // BOTH order-majorities must exist. A pair where one order has
                // no majority is a PARTIAL answer, not a disagreement: counting
                // it as inconsistent conflates "the judge contradicted itself"
                // with "the judge failed to answer", and those call for opposite
                // responses. A pair with neither is not an answer at all.
                let judged = inFamily.compactMap { judgementsByID[$0.id] }.filter {
                    $0.orderMajority(.leftFirst) != nil && $0.orderMajority(.rightFirst) != nil
                }
                guard !judged.isEmpty else { continue }
                let disagreeing = judged.filter {
                    $0.orderMajority(.leftFirst) != $0.orderMajority(.rightFirst)
                }
                inconsistency[family.rawValue] = Double(disagreeing.count) / Double(judged.count)
            }

            return Report(
                humanGate: humanGate,
                humanValidationCorrect: humanValidationCorrect,
                humanValidationTotal: validationPairs.count,
                vlmGate: vlmGate,
                vlmValidationCorrect: vlmValidationCorrect,
                vlmValidationTotal: validationPairs.count,
                vlmLegIsValid: vlmGate == .pass,
                humanDecidedN: decided,
                humanSuccesses: successes,
                humanTies: ties,
                humanTieRate: answeredUnique > 0 ? Double(ties) / Double(answeredUnique) : 0,
                humanUpperTailP: upperTail,
                humanVerdict: verdict,
                raterConsistency: consistency,
                raterRepeatCount: comparable,
                calibrationTrials: calibrationTrials.count,
                calibrationUnits: Self.calibrationUnits,
                calibrationFamilies: Family.allCases.filter { calibrationFitFamilies.contains($0) }
                    .map(\.rawValue),
                metricTies: metricTies,
                jnd75: band,
                pse: pse,
                barAssessment: assessment,
                familySplits: familyTotals.mapValues {
                    FamilySplit(answered: $0.answered, chosenLowerMAE: $0.lower, ties: $0.ties)
                },
                vlmOrderInconsistencyRate: inconsistency,
                exitCode: humanGate == .fail ? .failure : .success)
        }

        // MARK: - Answer ingestion

        /// Parse `answers.csv`. Strict on the vocabulary and on unknown pair IDs
        /// — a typo'd ID that scored as a silent drop would shrink `n` without
        /// anyone noticing. A blank choice is an unanswered row, which the
        /// shipped template is entirely made of, so it is skipped rather than
        /// rejected.
        static func parseAnswers(csv: String, known: Set<String>) throws -> [String: Choice] {
            var out: [String: Choice] = [:]
            for (offset, rawLine) in csv.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
            {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
                if offset == 0, line.lowercased().hasPrefix("pairid") { continue }
                let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard fields.count >= 2 else {
                    throw ArbiterError.malformedAnswer(row: offset + 1, value: line)
                }
                let id = fields[0]
                let raw = fields[1]
                if raw.isEmpty { continue }
                guard known.contains(id) else { throw ArbiterError.unknownPairID(id) }
                guard let choice = Choice(rawValue: raw) else {
                    throw ArbiterError.malformedAnswer(row: offset + 1, value: raw)
                }
                // A rater who answered one pair twice has given two answers.
                // Silently keeping the last one drops the other, and at n = 40 a
                // single dropped trial can move the verdict.
                guard out[id] == nil else { throw ArbiterError.duplicateAnswer(id) }
                out[id] = choice
            }
            return out
        }

        // MARK: - Artifacts

        /// `result.yaml` in the cross-lab shared schema, so the run drops
        /// straight into `docs/Research/Results/` and the registry accepts it.
        static func resultYAML(
            report: Report,
            date: String,
            gitSHA: String,
            seed: UInt64,
            command: String,
            outputs: [String],
            protocolVersion: String = Arbiter.protocolVersion
        ) -> String {
            var lines = ["---"]
            lines.append("schema_version: \"1\"")
            lines.append("date: \(date)")
            lines.append("aski_git_sha: \(gitSHA)")
            lines.append("runner: AskiColorLab")
            lines.append("command: \(quoted(command))")
            lines.append("run_seed: \"\(seed)\"")
            lines.append("provenance:")
            lines.append(
                "  - \(quoted("Frozen protocol: \(Arbiter.protocolNote(for: protocolVersion)) (v\(protocolVersion), committed before any vote)"))"
            )
            lines.append(
                "  - \(quoted("Human leg is the arbiter; the VLM leg is a pre-screen and tie-breaker and counts only after the section 5.1 gate"))"
            )
            lines.append(
                "  - \(quoted("Blinded: identity lives only in key.json; the rater submits answers before opening it"))"
            )
            lines.append("datasets:")
            lines.append("  - docs/Research/Corpus/nasa-steerable-v1")
            lines.append("  - docs/Research/Corpus/nasa-structure-v1")
            lines.append("outputs:")
            for output in outputs { lines.append("  - \(output)") }
            lines.append("calibration_units: \(quoted(report.calibrationUnits))")
            let fitFamilies = report.calibrationFamilies.joined(separator: "+")
            lines.append("calibration_families: \(quoted(fitFamilies))")
            if let band = report.jnd75 {
                lines.append("jnd75_contains_point_estimate: \(band.containsPointEstimate)")
            }
            lines.append("summary: \(quoted(summaryLine(report)))")
            lines.append("---")
            return lines.joined(separator: "\n") + "\n"
        }

        static func summaryLine(_ report: Report) -> String {
            var parts: [String] = []
            parts.append(
                "Instrument validation gate (section 5.1): human \(report.humanGate.rawValue) at \(report.humanValidationCorrect)/\(report.humanValidationTotal), VLM \(report.vlmGate.rawValue) at \(report.vlmValidationCorrect)/\(report.vlmValidationTotal)."
            )
            if let verdict = report.humanVerdict {
                parts.append("Human leg: \(verdict).")
            } else {
                parts.append(
                    "Human leg: \(report.humanSuccesses)/\(report.humanDecidedN) decided, below the pre-registered decided-n threshold of \(minimumDecidedTrials), so no verdict line is emitted."
                )
            }
            if let band = report.jnd75, let assessment = report.barAssessment {
                parts.append(
                    "JND75 band \(formatted(band.low)) to \(formatted(band.high)) relative MAE margin, fitted on families \(report.calibrationFamilies.joined(separator: " + ")); the 3.0 percent bar is \(assessment.rawValue)."
                )
            } else {
                parts.append("JND75 was not estimable from this run's calibration trials.")
            }
            return parts.joined(separator: " ")
        }

        /// The Markdown readout — the human-facing half of `score`.
        static func readout(
            _ report: Report,
            protocolVersion: String = Arbiter.protocolVersion
        ) -> String {
            var lines = ["# ASKI-56 perceptual arbiter — readout", ""]
            lines.append(
                "Protocol: `\(Arbiter.protocolNote(for: protocolVersion))` (v\(protocolVersion), frozen)."
            )
            lines.append("")
            lines.append("## Validation gate (section 5.1)")
            lines.append("")
            lines.append(
                "- Human leg: **\(report.humanGate.rawValue)** — \(report.humanValidationCorrect)/\(report.humanValidationTotal) V pairs answered F (bar: \(validationGateThreshold))."
            )
            lines.append(
                "- VLM leg: **\(report.vlmGate.rawValue)** — \(report.vlmValidationCorrect)/\(report.vlmValidationTotal) V pairs decided F under the both-orders rule."
            )
            if !report.vlmLegIsValid {
                lines.append(
                    "- The VLM leg is reported **invalid**; the human leg stands alone (section 5.1).")
            }
            lines.append("")
            lines.append("## Human leg")
            lines.append("")
            lines.append(
                "- Split: \(report.humanSuccesses)/\(report.humanDecidedN) chose the lower-MAE side (decided n = \(report.humanDecidedN))."
            )
            if let p = report.humanUpperTailP {
                lines.append(
                    "- Exact one-sided binomial p = \(formatted(p)) at alpha = \(formatted(alpha)).")
            }
            lines.append("- Tie rate: \(formatted(report.humanTieRate)) (\(report.humanTies) ties).")
            if let verdict = report.humanVerdict {
                lines.append("- Verdict: \(verdict).")
            } else {
                lines.append(
                    "- No verdict line: decided n = \(report.humanDecidedN) is below the pre-registered decided-n threshold of \(minimumDecidedTrials); the split and p above are the whole readout."
                )
            }
            if let consistency = report.raterConsistency {
                lines.append(
                    "- Rater consistency on \(report.raterRepeatCount) repeats: \(formatted(consistency)) (reported, never gated)."
                )
            }
            lines.append("")
            lines.append("## Calibration (AC#3)")
            lines.append("")
            lines.append(
                "- Fitted on \(report.calibrationTrials) trials from families \(report.calibrationFamilies.joined(separator: " + ")); V and D are excluded (see the protocol's pre-run errata)."
            )
            lines.append(
                "- Regressor units: `\(report.calibrationUnits)` — the fractional improvement `1 - MAE_better / MAE_worse`, which is the same quantity the section 5.2 bar is written in."
            )
            if report.metricTies > 0 {
                lines.append(
                    "- Exact MAE ties among the answered pairs: \(report.metricTies), excluded from both the binomial and the fit (there is no lower-MAE side to score against)."
                )
            }
            if let band = report.jnd75 {
                lines.append(
                    "- JND75 band: \(formatted(band.low)) ... \(formatted(band.high)) relative MAE margin (point \(formatted(band.point))), bootstrapped by SOURCE IMAGE over \(band.usableResamples)/\(band.requestedResamples) usable resamples."
                )
                if !band.containsPointEstimate {
                    lines.append(
                        "- **WARNING: the bootstrap interval does not contain the full-data point estimate.** That is bootstrap bias, and it is a reason to distrust this fit rather than to widen the band."
                    )
                }
            } else {
                lines.append("- JND75: not estimable from \(report.calibrationTrials) trials.")
            }
            if let pse = report.pse {
                lines.append("- PSE: \(formatted(pse)) relative MAE margin.")
            }
            if let assessment = report.barAssessment {
                lines.append("- Section 5.2 disposition of the 3.0 percent bar: **\(assessment.rawValue)**.")
            }
            lines.append("")
            lines.append("## Per-family splits")
            lines.append("")
            lines.append("family | answered | chose lower MAE | ties")
            lines.append("--- | --- | --- | ---")
            for family in Family.allCases {
                guard let split = report.familySplits[family.rawValue] else { continue }
                lines.append(
                    "\(family.rawValue) | \(split.answered) | \(split.chosenLowerMAE) | \(split.ties)")
            }
            if !report.vlmOrderInconsistencyRate.isEmpty {
                lines.append("")
                lines.append("## VLM order-inconsistency rate (section 4, recorded not gated)")
                lines.append("")
                for family in Family.allCases {
                    guard let rate = report.vlmOrderInconsistencyRate[family.rawValue] else {
                        continue
                    }
                    lines.append("- \(family.rawValue): \(formatted(rate))")
                }
            }
            return lines.joined(separator: "\n") + "\n"
        }

        private static func quoted(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\"", with: "'") + "\""
        }

        static func formatted(_ value: Double) -> String {
            value.isFinite ? String(format: "%.4f", value) : "nan"
        }
    }
}
