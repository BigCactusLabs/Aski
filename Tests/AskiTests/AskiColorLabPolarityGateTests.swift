import Testing

@_spi(AskiResearch) @testable import Aski
@testable import AskiColorLab

/// The ASKI-60 decision rule was pre-registered before Phase B measured
/// anything, so it is tested on synthetic rows rather than on corpus output:
/// these cases pin what each verdict MEANS, independently of what the corpus
/// turned out to say. If a later edit moves a boundary, one of these fails.
@Suite struct AskiColorLabPolarityGateTests {

    private static let mae = "mae"
    private static let gmsd = "gmsd"

    private static func comparison(
        corpus: String, charset: String, oracle: String, improvement: Double
    ) -> PolarityGate.ComparisonRow {
        PolarityGate.ComparisonRow(
            corpus: corpus, charset: charset, oracle: oracle, cells: 100,
            invertedMean: 0.5, directMean: 0.4, improvementPercent: improvement,
            differingPickPercent: 50)
    }

    /// A full comparison set: blocks MAE + GMSD on both corpora at the given
    /// lifts, plus one non-blocks charset at `otherMAE`.
    private static func rows(
        blocksMAE: (Double, Double),
        blocksGMSD: (Double, Double),
        otherMAE: Double = 1.0
    ) -> [PolarityGate.ComparisonRow] {
        [
            comparison(corpus: "a", charset: "blocks", oracle: mae, improvement: blocksMAE.0),
            comparison(corpus: "b", charset: "blocks", oracle: mae, improvement: blocksMAE.1),
            comparison(corpus: "a", charset: "blocks", oracle: gmsd, improvement: blocksGMSD.0),
            comparison(corpus: "b", charset: "blocks", oracle: gmsd, improvement: blocksGMSD.1),
            comparison(corpus: "a", charset: "standard", oracle: mae, improvement: otherMAE),
            comparison(corpus: "b", charset: "standard", oracle: mae, improvement: otherMAE),
            comparison(corpus: "a", charset: "braille", oracle: mae, improvement: otherMAE),
            comparison(corpus: "b", charset: "braille", oracle: mae, improvement: otherMAE),
        ]
    }

    private static func control(gmsdDelta: Double, maeDelta: Double)
        -> [PolarityGate.NegativeControlRow]
    {
        [
            PolarityGate.NegativeControlRow(
                corpus: "a", charset: "blocks", polarity: "inverted", pairs: 100,
                maxAbsGMSDDelta: gmsdDelta, maxAbsMAEDelta: maeDelta)
        ]
    }

    private static func decide(
        _ comparisons: [PolarityGate.ComparisonRow],
        control negativeControl: [PolarityGate.NegativeControlRow] = control(
            gmsdDelta: 1e-9, maeDelta: 1e-9),
        polarities: [ShapeQueryPolarity] = [.inverted, .direct]
    ) -> (verdict: PolarityGate.Verdict, decidingClause: String) {
        let clauses = PolarityGate.evaluate(
            comparisons: comparisons, negativeControl: negativeControl, polarities: polarities)
        return PolarityGate.verdict(comparisons: comparisons, clauses: clauses)
    }

    @Test func clearLiftWithAgreeingGuardIsCandidate() {
        let outcome = Self.decide(Self.rows(blocksMAE: (8, 6), blocksGMSD: (5, 4)))
        #expect(outcome.verdict == .candidate)
    }

    /// KILL clause 1: `direct` actually loses on the deciding charset. One
    /// corpus is enough — a treatment that hurts somewhere is not promotable.
    @Test func blocksRegressionOnEitherCorpusIsKill() {
        let outcome = Self.decide(Self.rows(blocksMAE: (8, -0.5), blocksGMSD: (5, 4)))
        #expect(outcome.verdict == .kill)
        #expect(outcome.decidingClause.contains("worse than inverted on blocks MAE"))
    }

    /// KILL clause 2: collateral damage on a charset the treatment was not
    /// aimed at vetoes promotion outright, even with a clean blocks lift.
    @Test func nonBlocksRegressionBeyondTheVetoIsKill() {
        let outcome = Self.decide(
            Self.rows(blocksMAE: (8, 6), blocksGMSD: (5, 4), otherMAE: -4))
        #expect(outcome.verdict == .kill)
        #expect(outcome.decidingClause.contains("no other charset regresses"))
    }

    /// A regression inside the veto is tolerated — the bar is 3.0%, not zero.
    @Test func nonBlocksRegressionInsideTheVetoStillCandidate() {
        let outcome = Self.decide(
            Self.rows(blocksMAE: (8, 6), blocksGMSD: (5, 4), otherMAE: -2.5))
        #expect(outcome.verdict == .candidate)
    }

    /// `direct` wins on both corpora but one lift sits inside the bar.
    @Test func winInsideTheBarIsInconclusive() {
        let outcome = Self.decide(Self.rows(blocksMAE: (8, 1.5), blocksGMSD: (5, 4)))
        #expect(outcome.verdict == .inconclusive)
        #expect(outcome.decidingClause.contains("blocks MAE lift"))
    }

    /// The guard dissenting is a different failure from a small lift, and it
    /// names itself: MAE says better, GMSD says worse.
    @Test func guardDisagreeingInSignIsInconclusive() {
        let outcome = Self.decide(Self.rows(blocksMAE: (8, 6), blocksGMSD: (5, -4)))
        #expect(outcome.verdict == .inconclusive)
        #expect(outcome.decidingClause.contains("GMSD agrees with MAE in sign"))
    }

    /// The exact bar: 3.0% does NOT clear it, anything above does.
    @Test func theBarIsStrictlyGreaterThanThreePercent() {
        #expect(Self.decide(Self.rows(blocksMAE: (3.0, 8), blocksGMSD: (5, 4))).verdict == .inconclusive)
        #expect(Self.decide(Self.rows(blocksMAE: (3.001, 8), blocksGMSD: (5, 4))).verdict == .candidate)
    }

    /// A moved negative control is an instrument failure, not a result — it
    /// outranks every other clause, including a KILL-shaped blocks regression.
    @Test func movedNegativeControlIsInvalidNotAResult() {
        let outcome = Self.decide(
            Self.rows(blocksMAE: (8, -9), blocksGMSD: (5, 4)),
            control: Self.control(gmsdDelta: 1e-3, maeDelta: 1e-9))
        #expect(outcome.verdict == .invalid)
        #expect(outcome.decidingClause == "negative control")
    }

    /// A partial matrix — one corpus, a missing charset, a missing GMSD guard,
    /// or a fixture-limited smoke — reports numbers but is never a verdict, so
    /// a limited blocks-only run cannot be read as CANDIDATE.
    @Test func partialMatrixIsInvalidNotCandidate() {
        let full = Self.rows(blocksMAE: (10, 8), blocksGMSD: (5, 4))
        #expect(Self.decide(full).verdict == .candidate)

        let oneCorpus = full.filter { $0.corpus == "a" }
        #expect(Self.decide(oneCorpus).verdict == .invalid)
        #expect(Self.decide(oneCorpus).decidingClause == "full matrix measured")

        let noBraille = full.filter { $0.charset != "braille" }
        #expect(Self.decide(noBraille).verdict == .invalid)

        let noGuard = full.filter { $0.oracle != Self.gmsd }
        #expect(Self.decide(noGuard).verdict == .invalid)

        let smoke = PolarityGate.evaluate(
            comparisons: full, negativeControl: Self.control(gmsdDelta: 1e-9, maeDelta: 1e-9),
            polarities: [.inverted, .direct], fixtureLimit: 1)
        #expect(PolarityGate.verdict(comparisons: full, clauses: smoke).verdict == .invalid)
    }

    /// A one-polarity run reports means but cannot reach a verdict.
    @Test func singleArmRunIsInvalid() {
        let outcome = Self.decide(
            Self.rows(blocksMAE: (8, 6), blocksGMSD: (5, 4)), polarities: [.inverted])
        #expect(outcome.verdict == .invalid)
        #expect(outcome.decidingClause == "both arms measured")
    }

    /// A degenerate baseline cannot show `direct` to be worse and cannot clear
    /// the bar, so it lands in INCONCLUSIVE rather than a fifth outcome.
    @Test func nonFiniteBlocksLiftIsInconclusive() {
        let outcome = Self.decide(Self.rows(blocksMAE: (.nan, 8), blocksGMSD: (5, 4)))
        #expect(outcome.verdict == .inconclusive)
    }

    /// The mechanism check reads the kernel's own prune rule: `blocks` has
    /// fewer glyphs than `topK`, so its pool is every glyph and the tone term
    /// selects nothing.
    @Test func poolSizeReportsWhetherTheTonePrefilterBinds() {
        let small = PolarityGate.poolSizeRow(charset: "blocks", glyphs: 8)
        #expect(small.topK == 12)
        #expect(small.poolSize == 8)
        #expect(small.pruneBinds == false)

        let large = PolarityGate.poolSizeRow(charset: "standard", glyphs: 70)
        #expect(large.poolSize == 12)
        #expect(large.pruneBinds == true)
    }
}
