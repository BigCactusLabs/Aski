import AskiToolSupport
import Foundation
import Testing

@testable import AskiColorLab

/// Guards ASKI-56 §2.3 + §5.1 as executed by `arbiter score`: the validation
/// gate's FAIL-FAST exit, tie exclusion, the pre-registered decided-n ≥ 30
/// threshold, the VLM leg's "invalid, human stands alone" disposition, and the
/// result manifest's field contract.
@Suite struct AskiColorLabArbiterScoreTests {

    private static func plan(seed: UInt64 = 4242) throws -> [Arbiter.Pair] {
        let sources = ArbiterTestSupport.sources()
        let plan = Arbiter.FamilyPlan()
        return try Arbiter.PairPlan.build(
            sources: sources,
            scores: ArbiterTestSupport.scoreTable(sources: sources, plan: plan),
            plan: plan,
            seed: seed)
    }

    /// The choice that names the arm with the lower MAE for `pair`.
    private static func correctChoice(_ pair: Arbiter.Pair) -> Arbiter.Choice {
        let lowerIsArmA = pair.metrics.signedDeltaMAE < 0
        return (lowerIsArmA == pair.leftIsArmA) ? .left : .right
    }

    private static func flipped(_ choice: Arbiter.Choice) -> Arbiter.Choice {
        choice == .left ? .right : .left
    }

    // MARK: - §5.1 validation gate

    /// The human leg missing the V pairs is an instrument failure, and the run
    /// exits `LabExitCode.failure`. Nothing downstream of a failed gate means
    /// anything, so it must not exit 0.
    @Test func aFailedHumanValidationGateFailsTheRunFast() throws {
        let pairs = try Self.plan()
        // Get 3 of the 6 V pairs wrong — below the ≥5 bar. Chosen by walking the
        // validation family, NOT by pair ID: the IDs are deliberately shuffled
        // so the family cannot be read off them (§3), and a test that keys on
        // "the first three IDs" would be leaning on the leak that shuffle exists
        // to close.
        let wrongIDs = Set(pairs.filter { $0.family == .validation }.prefix(3).map(\.id))
        #expect(wrongIDs.count == 3)
        var answers: [String: Arbiter.Choice] = [:]
        for pair in pairs {
            let choice = Self.correctChoice(pair)
            answers[pair.id] = wrongIDs.contains(pair.id) ? Self.flipped(choice) : choice
        }

        let report = try Arbiter.Score.score(
            .init(key: .init(seed: 4242, pairs: pairs), humanAnswers: answers, judgements: []))
        #expect(report.humanGate == .fail)
        #expect(report.humanValidationCorrect == 3)
        #expect(report.exitCode == LabExitCode.failure)
    }

    /// Five of six is the frozen bar — a huge-margin screen at n = 6, accepted
    /// at p ≈ 0.11 because it is screening the instrument, not the arms.
    @Test func fiveOfSixValidationPairsPassesTheHumanGate() throws {
        let pairs = try Self.plan()
        var answers: [String: Arbiter.Choice] = [:]
        var wrongApplied = false
        for pair in pairs {
            let choice = Self.correctChoice(pair)
            if pair.family == .validation && !wrongApplied {
                wrongApplied = true
                answers[pair.id] = Self.flipped(choice)
            } else {
                answers[pair.id] = choice
            }
        }
        let report = try Arbiter.Score.score(
            .init(key: .init(seed: 4242, pairs: pairs), humanAnswers: answers, judgements: []))
        #expect(report.humanValidationCorrect == 5)
        #expect(report.humanGate == .pass)
        #expect(report.exitCode == LabExitCode.success)
    }

    /// With no human answers the gate is not evaluated — a VLM-only run is
    /// legal and must not be reported as a failed human gate.
    @Test func anAbsentHumanLegLeavesTheGateUnevaluated() throws {
        let pairs = try Self.plan()
        let report = try Arbiter.Score.score(
            .init(key: .init(seed: 4242, pairs: pairs), humanAnswers: [:], judgements: []))
        #expect(report.humanGate == .notEvaluated)
        #expect(report.exitCode == LabExitCode.success)
    }

    /// A failed VLM gate does NOT fail the run: §5.1 says the VLM leg is
    /// reported invalid and the human leg stands alone.
    @Test func aFailedVLMGateInvalidatesThatLegWithoutFailingTheRun() throws {
        let pairs = try Self.plan()
        let answers = Dictionary(
            uniqueKeysWithValues: pairs.map { ($0.id, Self.correctChoice($0)) })
        // Every V pair decided for the WRONG side.
        let judgements = pairs.filter { $0.family == .validation }.map { pair in
            Arbiter.Judge.PairJudgement(
                pairID: pair.id,
                calls: [],
                decision: Self.correctChoice(pair) == .left ? .right : .left)
        }
        let report = try Arbiter.Score.score(
            .init(key: .init(seed: 4242, pairs: pairs), humanAnswers: answers, judgements: judgements))
        #expect(report.vlmGate == .fail)
        #expect(report.vlmLegIsValid == false)
        #expect(report.humanGate == .pass)
        #expect(report.exitCode == LabExitCode.success)
    }

    // MARK: - Ties and the decided-n threshold

    /// Ties are allowed, excluded from n, and reported as a rate. Repeats are
    /// excluded from n too — they measure the rater, not the arms.
    @Test func tiesAndRepeatsAreExcludedFromTheVerdictDenominator() throws {
        let pairs = try Self.plan()
        var answers: [String: Arbiter.Choice] = [:]
        var tied = 0
        for pair in pairs {
            if pair.repeatOf == nil && tied < 8 && pair.family == .calibration {
                answers[pair.id] = .tie
                tied += 1
            } else {
                answers[pair.id] = Self.correctChoice(pair)
            }
        }
        let uniqueCount = pairs.filter { $0.repeatOf == nil }.count
        let report = try Arbiter.Score.score(
            .init(key: .init(seed: 4242, pairs: pairs), humanAnswers: answers, judgements: []))

        #expect(report.humanDecidedN == uniqueCount - 8)
        #expect(abs(report.humanTieRate - Double(8) / Double(uniqueCount)) < 1e-12)
        #expect(report.humanDecidedN < pairs.count)
    }

    /// Below 30 decided trials no verdict line is emitted — pre-registered, so
    /// the readout cannot be talked into a verdict after the fact.
    @Test func noVerdictLineIsEmittedBelowThirtyDecidedTrials() throws {
        let pairs = try Self.plan()
        var thin: [String: Arbiter.Choice] = [:]
        for pair in pairs.prefix(20) { thin[pair.id] = Self.correctChoice(pair) }
        // Keep the V pairs answered so the gate still passes.
        for pair in pairs where pair.family == .validation {
            thin[pair.id] = Self.correctChoice(pair)
        }
        let thinReport = try Arbiter.Score.score(
            .init(key: .init(seed: 4242, pairs: pairs), humanAnswers: thin, judgements: []))
        #expect(thinReport.humanDecidedN < 30)
        #expect(thinReport.humanVerdict == nil)
        #expect(thinReport.humanUpperTailP != nil, "the split and its p must still be reported")

        let full = Dictionary(uniqueKeysWithValues: pairs.map { ($0.id, Self.correctChoice($0)) })
        let fullReport = try Arbiter.Score.score(
            .init(key: .init(seed: 4242, pairs: pairs), humanAnswers: full, judgements: []))
        #expect(fullReport.humanDecidedN >= 30)
        #expect(fullReport.humanVerdict != nil)
    }

    /// Rater consistency is the agreement rate on the five R repeats, reported
    /// and never gated. Agreement is on the ARM chosen, not the side — the
    /// repeat is re-randomized, so a consistent rater flips sides.
    @Test func raterConsistencyIsMeasuredOnArmsNotSides() throws {
        let pairs = try Self.plan()
        let byID = Dictionary(uniqueKeysWithValues: pairs.map { ($0.id, $0) })
        var answers: [String: Arbiter.Choice] = [:]
        for pair in pairs { answers[pair.id] = Self.correctChoice(pair) }
        let report = try Arbiter.Score.score(
            .init(key: .init(seed: 4242, pairs: pairs), humanAnswers: answers, judgements: []))
        #expect(report.raterConsistency == 1.0)

        // Flip one repeat's answer: consistency drops to 4/5.
        let firstRepeat = try #require(pairs.first { $0.family == .repeats })
        _ = try #require(firstRepeat.repeatOf.flatMap { byID[$0] })
        answers[firstRepeat.id] = Self.flipped(Self.correctChoice(firstRepeat))
        let dropped = try Arbiter.Score.score(
            .init(key: .init(seed: 4242, pairs: pairs), humanAnswers: answers, judgements: []))
        #expect(abs((dropped.raterConsistency ?? 0) - 0.8) < 1e-12)
    }

    // MARK: - Answer ingestion

    /// `answers.csv` round-trips the template, rejects an unknown choice, and
    /// rejects a pair ID the key does not know.
    @Test func answerCSVIngestionIsStrict() throws {
        let pairs = try Self.plan()
        let known = Set(pairs.map(\.id))
        let parsed = try Arbiter.Score.parseAnswers(
            csv: "pairID,choice\npair-001,L\npair-002,R\npair-003,tie\n", known: known)
        #expect(parsed["pair-001"] == .left)
        #expect(parsed["pair-002"] == .right)
        #expect(parsed["pair-003"] == .tie)

        #expect(throws: ArbiterError.self) {
            try Arbiter.Score.parseAnswers(
                csv: "pairID,choice\npair-001,maybe\n", known: known)
        }
        #expect(throws: ArbiterError.self) {
            try Arbiter.Score.parseAnswers(
                csv: "pairID,choice\npair-999,L\n", known: known)
        }
        // An unanswered row is skipped, not an error — the template ships blank.
        #expect(
            try Arbiter.Score.parseAnswers(csv: "pairID,choice\npair-001,\n", known: known)
                .isEmpty)
    }

    // MARK: - result.yaml / manifest schema

    /// The result manifest carries the cross-lab shared schema fields, so the
    /// run drops into `docs/Research/Results/` and the registry accepts it.
    @Test func resultYAMLCarriesTheSharedResultSchemaFields() throws {
        let pairs = try Self.plan()
        let answers = Dictionary(
            uniqueKeysWithValues: pairs.map { ($0.id, Self.correctChoice($0)) })
        let report = try Arbiter.Score.score(
            .init(key: .init(seed: 4242, pairs: pairs), humanAnswers: answers, judgements: []))
        let yaml = Arbiter.Score.resultYAML(
            report: report,
            date: "2026-08-25",
            gitSHA: "abc1234",
            seed: 4242,
            command: "AskiColorLab arbiter score --output-dir <dir>",
            outputs: ["result.yaml", "readout.md"])

        #expect(yaml.hasPrefix("---\n"))
        #expect(yaml.hasSuffix("---\n"))
        for key in [
            "schema_version:", "date:", "aski_git_sha:", "provenance:", "outputs:",
            "runner:", "command:", "run_seed:", "datasets:", "summary:",
        ] {
            #expect(yaml.contains(key), "result.yaml is missing '\(key)'")
        }
        #expect(yaml.contains("runner: AskiColorLab"))
        #expect(yaml.contains("2026-09-04-aski62-arbiter-v2-protocol.md"))
        #expect(!yaml.contains("<date-executed>"), "an unresolved placeholder would fail the registry")
    }

    /// The Markdown readout is the human-facing half. It must name the gate
    /// outcome and never print a verdict line the threshold forbids.
    @Test func markdownReadoutReportsTheGateAndRespectsTheThreshold() throws {
        let pairs = try Self.plan()
        var thin: [String: Arbiter.Choice] = [:]
        for pair in pairs where pair.family == .validation { thin[pair.id] = Self.correctChoice(pair) }
        let report = try Arbiter.Score.score(
            .init(key: .init(seed: 4242, pairs: pairs), humanAnswers: thin, judgements: []))
        let markdown = Arbiter.Score.readout(report)

        #expect(markdown.contains("Validation gate"))
        #expect(markdown.contains("decided n"))
        #expect(!markdown.contains("VERDICT:"), "a verdict was printed below the decided-n threshold")
        #expect(markdown.contains("below the pre-registered decided-n"))
    }
}
