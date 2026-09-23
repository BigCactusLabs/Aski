import AskiToolSupport
import Foundation
import Testing

@testable import AskiColorLab

/// Guards the ASKI-56 review findings that changed what the instrument MEANS,
/// as opposed to how it is spelled. Each test here failed against the first
/// build of the arbiter and is the reason a specific rule moved.
@Suite struct AskiColorLabArbiterReviewFixTests {

    // MARK: - C1: the §5.2 bar is a RATIO, so calibration must be too

    /// The standing bar is `MAE_arm / MAE_baseline <= 0.97`
    /// (`docs/Research/2026-08-24-aski-30-28-decisive-rule.md:97`) — a 3.0
    /// percent RELATIVE improvement. The first build fitted the psychometric
    /// curve against the ABSOLUTE mean-MAE gap and compared the resulting JND75
    /// band straight to 0.030, which is a units mismatch, not a rounding
    /// question: at the corpus's own magnitudes (production mean MAE 0.5571,
    /// floor 0.3181 on `blocks`) an absolute gap of 0.030 is only a 5.4 percent
    /// relative improvement, so the absolute reading is roughly 1.8x too
    /// permissive and every error lands on the side of keeping the bar.
    ///
    /// This fixture is built at those real magnitudes with a just-visible
    /// RELATIVE margin of about 4.3 percent, which is above the bar. Read in
    /// ratio units it is `barAdmitsInvisibleWins`. Read in the old absolute
    /// units the same data sits near 0.024 — below 0.030 — and reports
    /// `perceptuallyGrounded`, the opposite disposition.
    @Test func barAssessmentIsReadInRatioUnitsNotAbsoluteMAE() throws {
        // Production-scale baseline: the worse arm of every pair sits at the
        // measured production mean MAE on blocks.
        let baseline = 0.5571
        let jndRelative = 0.043
        var pairs: [Arbiter.Pair] = []
        var answers: [String: Arbiter.Choice] = [:]

        var index = 0
        for sourceIndex in 0..<6 {
            let source = Arbiter.SourceRef(
                corpus: "nasa-structure-v1", asset: "fixture-\(sourceIndex).png")
            for step in 0...9 {
                // Relative margin sweeps 0 ... 9 percent, straddling the 4.3
                // percent JND75 and the 3.0 percent bar.
                let relative = 0.01 * Double(step)
                let better = baseline * (1 - relative)
                for replicate in 0..<8 {
                    index += 1
                    let id = String(format: "pair-%03d", index)
                    // Arm A is the better (lower-MAE) arm throughout; the seeded
                    // side still varies so the answer is not a constant.
                    let leftIsArmA = (index % 2 == 0)
                    let pair = Arbiter.Pair(
                        id: id, family: .calibration, source: source, charset: "blocks",
                        armA: .init(name: "T", w: Float(step)), armB: .init(name: "P"),
                        leftIsArmA: leftIsArmA,
                        metrics: Arbiter.PairMetrics(
                            armAMeans: [.mae: better], armBMeans: [.mae: baseline]),
                        repeatOf: nil)
                    pairs.append(pair)
                    // A rater whose 75 percent point is at 4.3 percent relative.
                    let probability =
                        1
                        / (1
                            + exp(
                                -(-0.8 + (log(3.0) + 0.8) / jndRelative
                                    * relative)
                            ))
                    let correct = Double(replicate) < probability * 8
                    let lower = try #require(
                        pair.lowerMAESide ?? Arbiter.Choice.left as Arbiter.Choice?)
                    answers[id] = correct ? lower : (lower == .left ? .right : .left)
                }
            }
        }

        let report = try Arbiter.Score.score(
            .init(
                key: .init(seed: 99, pairs: pairs, enforcesFrozenProtocol: false),
                humanAnswers: answers, judgements: []))
        let band = try #require(report.jnd75)

        // The band is in RATIO units: a few percent, not a few hundredths of a
        // mean MAE that happens to look similar.
        #expect(
            abs(band.point - jndRelative) < 0.015,
            "JND75 point \(band.point) is not the relative margin the data was built at")
        #expect(report.calibrationUnits == "relative-mae-margin")

        // And the disposition follows the ratio reading.
        #expect(report.barAssessment == .barAdmitsInvisibleWins)

        // The same data read the OLD way — absolute mean-MAE gap — would sit
        // below the bar and report the opposite disposition. Pinning that here
        // is what makes this a units test rather than a threshold test.
        let absoluteEquivalent = jndRelative * baseline
        #expect(absoluteEquivalent < Arbiter.Score.barFraction)
        #expect(
            ArbiterStatistics.assessBar(
                band: (low: absoluteEquivalent * 0.9, high: absoluteEquivalent * 1.1),
                barFraction: Arbiter.Score.barFraction) == .perceptuallyGrounded)
    }

    /// The relative margin is exactly the standing bar's own quantity:
    /// `1 - MAE_better / MAE_worse`, so a pair that just clears
    /// `ratio <= 0.97` has a margin of exactly 0.03.
    @Test func relativeMarginIsOneMinusTheStandingRatio() {
        let metrics = Arbiter.PairMetrics(
            armAMeans: [.mae: 0.97], armBMeans: [.mae: 1.0])
        #expect(abs(metrics.relativeMarginMAE - 0.03) < 1e-12)

        // Symmetric: which side is better does not change the margin.
        let flipped = Arbiter.PairMetrics(
            armAMeans: [.mae: 1.0], armBMeans: [.mae: 0.97])
        #expect(abs(flipped.relativeMarginMAE - 0.03) < 1e-12)

        // A degenerate baseline is not a 100 percent win.
        let degenerate = Arbiter.PairMetrics(armAMeans: [.mae: 0], armBMeans: [.mae: 0])
        #expect(degenerate.relativeMarginMAE == 0)
        let missing = Arbiter.PairMetrics(armAMeans: [.ssim: 1], armBMeans: [.mae: 0.5])
        #expect(missing.relativeMarginMAE.isNaN)
    }

    // MARK: - H1: the family must not be recoverable from the pair ID

    /// The first build assigned IDs in family emission order, so pair-001 to
    /// pair-006 were always the V family — and the manifest published the family
    /// counts, so the rater knew the budget. A rater who can spot the six
    /// huge-margin validation pairs is no longer being screened by them, which
    /// is the entire job of the §5.1 gate.
    @Test func pairIDOrderDoesNotTrackFamilyOrder() throws {
        let pairs = try Self.plan()
        let unique = pairs.filter { $0.repeatOf == nil }

        // The V pairs must not occupy a contiguous run at the front.
        let validationIDs = unique.filter { $0.family == .validation }.map(\.id).sorted()
        #expect(
            validationIDs != (1...6).map { String(format: "pair-%03d", $0) },
            "the validation family is still the first six IDs")

        // Stronger and seed-independent: the families must interleave. Count
        // adjacent same-family runs — a grouped layout has 4 boundaries across
        // the 40 unique pairs, an interleaved one has many more.
        let families = unique.sorted { $0.id < $1.id }.map(\.family)
        var boundaries = 0
        for index in 1..<families.count where families[index] != families[index - 1] {
            boundaries += 1
        }
        #expect(boundaries > 10, "families are still emitted in blocks (\(boundaries) boundaries)")
    }

    /// The rater-visible manifest must not publish the family budget either:
    /// knowing there are exactly six V pairs is most of the way to finding them.
    @Test func familyCountsLiveInTheKeyNotTheManifest() throws {
        let pairs = try Self.plan()
        let manifest = Arbiter.Stimuli.Manifest(
            schemaVersion: "1", protocolVersion: "1", protocolNote: "note",
            runner: "AskiColorLab", date: "2026-08-25", askiGitSHA: "abc", command: "cmd",
            seed: 1, columns: 80, oversample: 2, footprint: 24, gatingCharset: "blocks",
            denseCharset: "standard", toneWeights: [], topKs: [],
            sources: ArbiterTestSupport.sources(), pairCount: pairs.count,
            calibrationLadderRule: "rule", adversarialObjective: "objective")
        let manifestText = String(
            decoding: try StableJSONForTest.encode(manifest), as: UTF8.self)
        for family in Arbiter.Family.allCases {
            #expect(!manifestText.contains("\"\(family.rawValue)\""))
        }
        #expect(!manifestText.contains("family"))

        let keyText = String(
            decoding: try StableJSONForTest.encode(Arbiter.KeyFile(seed: 1, pairs: pairs)),
            as: UTF8.self)
        #expect(keyText.contains("\"family_counts\""))
    }

    // MARK: - M2: a repeat must actually re-randomize the side

    /// The R family exists to measure whether the rater answers the same pair
    /// the same way twice. When the repeat lands on the same side as its origin
    /// the trial is pixel-identical, so it measures recognition, not
    /// consistency. The first build drew the side from an independent coin
    /// flip, so about half the repeats were identical re-presentations.
    @Test func everyRepeatPresentsTheOppositeSideFromItsOrigin() throws {
        let pairs = try Self.plan()
        let byID = Dictionary(uniqueKeysWithValues: pairs.map { ($0.id, $0) })
        let repeats = pairs.filter { $0.repeatOf != nil }
        #expect(!repeats.isEmpty)
        for repeated in repeats {
            let origin = try #require(repeated.repeatOf.flatMap { byID[$0] })
            #expect(
                repeated.leftIsArmA == !origin.leftIsArmA,
                "\(repeated.id) re-presents \(origin.id) on the same side")
        }
    }

    /// Repeats sit at seeded positions inside the delay zone, not in a fixed
    /// tail. Appending them made "the last five are repeats" derivable by any
    /// rater who knows the budget — and a rater who KNOWS a trial is a repeat
    /// answers it from memory, which is the very statistic the R family exists
    /// to measure. The marker made the number self-fulfilling.
    @Test func repeatsSitInsideTheDelayZoneRatherThanAFixedTail() throws {
        let plan = Arbiter.FamilyPlan()
        for seed in [UInt64(3), 11, 4242] {
            let pairs = try Self.plan(seed: seed)
            let repeats = pairs.filter { $0.repeatOf != nil }
            #expect(repeats.count == plan.repeatCount)

            // Not the tail.
            let tail = Set(pairs.suffix(plan.repeatCount).map(\.id))
            #expect(
                Set(repeats.map(\.id)) != tail,
                "seed \(seed): the repeats are still the last \(plan.repeatCount) IDs")

            let position = Dictionary(
                uniqueKeysWithValues: pairs.enumerated().map { ($0.element.id, $0.offset) })
            let zoneStart = Int(
                (Double(pairs.count) * (1 - plan.repeatDelayZone)).rounded(.up))
            for repeated in repeats {
                let slot = try #require(position[repeated.id])
                // Still delayed: inside the zone, and strictly after its origin.
                #expect(slot >= zoneStart, "seed \(seed): \(repeated.id) landed before the zone")
                let originSlot = try #require(repeated.repeatOf.flatMap { position[$0] })
                #expect(
                    originSlot < slot,
                    "seed \(seed): \(repeated.id) precedes the trial it repeats")
            }
        }
    }

    /// A repeat's origin must always be a UNIQUE trial, never another repeat.
    ///
    /// Repeat slots are filled in ascending order, so a later repeat can see an
    /// earlier one among the trials before it. Picking that as its origin is
    /// quietly destructive: the side inversion is applied twice, which makes the
    /// second repeat pixel-identical to the ORIGINAL trial — reintroducing
    /// exactly the defect the inversion was added to fix — and it puts one
    /// underlying trial on the sheet three times, where §2.1 asks for five
    /// distinct re-presentations.
    ///
    /// Swept rather than spot-checked. This fires on roughly a quarter of seeds,
    /// so a handful of hand-picked ones passes by luck: the previous three-seed
    /// placement test did exactly that.
    @Test func noRepeatEverRepeatsAnotherRepeat() throws {
        var offendingSeeds: [UInt64] = []
        for seed in UInt64(0)..<200 {
            let pairs = try Self.plan(seed: seed)
            let byID = Dictionary(uniqueKeysWithValues: pairs.map { ($0.id, $0) })
            for repeated in pairs where repeated.repeatOf != nil {
                guard let origin = repeated.repeatOf.flatMap({ byID[$0] }) else {
                    offendingSeeds.append(seed)
                    break
                }
                if origin.repeatOf != nil {
                    offendingSeeds.append(seed)
                    break
                }
            }
        }
        #expect(
            offendingSeeds.isEmpty,
            "a repeat took another repeat as its origin on seeds \(offendingSeeds.prefix(12))")
    }

    // MARK: - M3: a short family is never acceptable

    /// `ArbiterError.notEnoughCandidates` exists because the pair budget is part
    /// of the protocol. The ladder and the adversarial draw used to return
    /// whatever they could find, so a thin candidate pool silently shrank the C
    /// or M family and quietly changed what JND75 was fitted on.
    @Test func aThinCandidatePoolFailsTheRunRatherThanShrinkingAFamily() {
        let sources = Array(ArbiterTestSupport.sources().prefix(1))
        var plan = Arbiter.FamilyPlan()
        // Five arms on one source is ten distinct pairs per charset — enough to
        // build V and D and score every arm, so this exercises the SHORT LADDER
        // path specifically rather than tripping the missing-score guard first.
        plan.toneWeights = [plan.disagreementToneWeight]
        plan.topKs = []
        plan.calibrationCount = 20
        let scores = ArbiterTestSupport.scoreTable(sources: sources, plan: plan)
        #expect {
            try Arbiter.PairPlan.build(sources: sources, scores: scores, plan: plan, seed: 3)
        } throws: { error in
            guard case ArbiterError.notEnoughCandidates = error else { return false }
            return true
        }
    }

    // MARK: - M4: the band must not be clamped around the point estimate

    /// The first build clamped the bootstrap interval to always contain the
    /// point estimate. That hides bootstrap bias — the case where the resamples
    /// systematically land off the full-data fit is exactly the signal that the
    /// fit is unstable — and it made "the point sits inside the band" true by
    /// construction rather than by evidence.
    @Test func theBandIsNotWidenedToSwallowThePointEstimate() throws {
        // A deliberately skewed design: one source carries a far shallower
        // curve than the rest, so the by-source resamples straddle two regimes
        // and the percentile interval need not contain the full-data fit.
        var trials: [ArbiterStatistics.CalibrationTrial] = []
        for sourceIndex in 0..<6 {
            let slope = sourceIndex == 0 ? 20.0 : 150.0
            for step in 0...20 {
                let margin = Double(step) * 0.002
                let probability = 1 / (1 + exp(-(-0.8 + slope * margin)))
                for replicate in 0..<20 {
                    trials.append(
                        ArbiterStatistics.CalibrationTrial(
                            sourceKey: "source-\(sourceIndex)", relativeMarginMAE: margin,
                            choseLowerMAESide: Double(replicate) < probability * 20))
                }
            }
        }
        let seed: UInt64 = 5
        let resamples = 80
        let band = try #require(
            ArbiterStatistics.jnd75Band(trials: trials, seed: seed, resamples: resamples))

        // Recompute the percentile interval independently from the same public
        // pieces. The reported band must BE that interval — not that interval
        // widened until it swallowed the point estimate.
        var estimates: [Double] = []
        for sample in ArbiterStatistics.bootstrapResample(
            trials: trials, seed: seed, draws: resamples)
        {
            guard
                let fit = ArbiterStatistics.fitLogistic(
                    x: sample.map(\.relativeMarginMAE),
                    y: sample.map { $0.choseLowerMAESide ? 1.0 : 0.0 }),
                fit.converged,
                let level = ArbiterStatistics.level(fit, probability: 0.75), level.isFinite
            else { continue }
            estimates.append(level)
        }
        estimates.sort()
        func percentile(_ fraction: Double) -> Double {
            let position = fraction * Double(estimates.count - 1)
            let lower = Int(position.rounded(.down))
            let upper = min(estimates.count - 1, lower + 1)
            let weight = position - Double(lower)
            return estimates[lower] * (1 - weight) + estimates[upper] * weight
        }
        #expect(abs(band.low - percentile(0.025)) < 1e-12, "the lower edge was clamped")
        #expect(abs(band.high - percentile(0.975)) < 1e-12, "the upper edge was clamped")

        // Whether the point sits inside is then DATA, reported not enforced.
        #expect(
            band.containsPointEstimate == (band.low <= band.point && band.point <= band.high))

        // Force the case the clamp existed to paper over: an interval taken
        // from the top decile of the resamples cannot contain a point estimate
        // that sits near their median. The clamped implementation dragged the
        // lower edge down onto the point and reported the interval as
        // containing it; the raw interval says plainly that it does not.
        let upperTail = try #require(
            ArbiterStatistics.jnd75Band(
                trials: trials, seed: seed, resamples: resamples,
                lowerPercentile: 0.90, upperPercentile: 0.95))
        #expect(abs(upperTail.low - percentile(0.90)) < 1e-12, "the lower edge was clamped")
        #expect(upperTail.low > upperTail.point, "the clamp pulled the band onto the point")
        #expect(upperTail.containsPointEstimate == false)
    }

    // MARK: - M1: the fit is C + M only

    /// §2.3 fits the psychometric curve on the calibration ladder. The V pairs
    /// sit an order of magnitude beyond the ladder's largest rung, so including
    /// them makes six trials the highest-leverage points in the regression and
    /// lets them set the slope. M is registered as calibration-adjacent by
    /// §2.1 — it exists to probe where MAE is blind — so it belongs; V and D do
    /// not.
    @Test func theCalibrationFitUsesOnlyTheLadderAndTheAdversarialFamily() throws {
        let pairs = try Self.plan()
        let answers = Dictionary(
            uniqueKeysWithValues: pairs.map { pair -> (String, Arbiter.Choice) in
                (pair.id, pair.lowerMAESide ?? .left)
            })
        let report = try Arbiter.Score.score(
            .init(
                key: .init(seed: 4242, pairs: pairs, enforcesFrozenProtocol: false),
                humanAnswers: answers, judgements: []))

        let expected = pairs.filter {
            $0.repeatOf == nil && ($0.family == .calibration || $0.family == .adversarial)
                && $0.lowerMAESide != nil
        }.count
        #expect(report.calibrationTrials == expected)
        #expect(report.calibrationFamilies == ["C", "M"])
        #expect(Arbiter.Score.readout(report).contains("C + M"))
    }

    // MARK: - LOW findings

    /// An exact MAE tie has no lower-MAE side, so scoring it as a binomial
    /// failure invents a wrong answer for a question with no right one, and
    /// feeding it to the fit adds a `y = 0` point at margin 0.
    @Test func anExactMAETieIsExcludedFromTheBinomialAndTheFit() throws {
        let tied = Arbiter.Pair(
            id: "pair-001", family: .calibration,
            source: .init(corpus: "c", asset: "a.png"), charset: "blocks",
            armA: .init(name: "T", w: 1), armB: .init(name: "K", topK: 12), leftIsArmA: true,
            metrics: Arbiter.PairMetrics(armAMeans: [.mae: 0.5], armBMeans: [.mae: 0.5]),
            repeatOf: nil)
        let report = try Arbiter.Score.score(
            .init(
                key: .init(seed: 1, pairs: [tied], enforcesFrozenProtocol: false),
                humanAnswers: ["pair-001": .left],
                judgements: []))
        #expect(report.humanDecidedN == 0, "an exact MAE tie entered the binomial denominator")
        #expect(report.calibrationTrials == 0)
        #expect(report.metricTies == 1)
    }

    /// A duplicated pair ID in `answers.csv` used to silently keep the last row.
    /// A rater who answered a pair twice has given two answers, and quietly
    /// dropping one of them is the kind of thing that shifts an n = 40 verdict.
    @Test func aDuplicatePairIDInTheAnswersCSVIsAHardError() throws {
        let known: Set<String> = ["pair-001", "pair-002"]
        #expect(throws: ArbiterError.self) {
            try Arbiter.Score.parseAnswers(
                csv: "pairID,choice\npair-001,L\npair-002,R\npair-001,R\n", known: known)
        }
    }

    /// A pair where BOTH order-majorities are nil is a pair the judge never
    /// answered. Counting it as "the two orders agreed" makes an all-invalid
    /// run look perfectly order-consistent.
    @Test func anAllInvalidPairIsExcludedFromTheOrderInconsistencyRate() throws {
        let pairs = try Self.plan()
        let validation = pairs.filter { $0.family == .validation }
        let allInvalid = validation.map {
            Arbiter.Judge.PairJudgement(
                pairID: $0.id,
                calls: Arbiter.Judge.Order.allCases.flatMap { order in
                    (0..<3).map {
                        Arbiter.Judge.Call(
                            order: order, sample: $0, verdict: .invalid, retried: true)
                    }
                },
                decision: .tie)
        }
        let report = try Arbiter.Score.score(
            .init(key: .init(seed: 4242, pairs: pairs), humanAnswers: [:], judgements: allInvalid))
        #expect(
            report.vlmOrderInconsistencyRate["V"] == nil,
            "an all-invalid family reported an inconsistency rate off an empty denominator")
    }

    // MARK: - Helpers

    private static func plan(seed: UInt64 = 4242) throws -> [Arbiter.Pair] {
        let sources = ArbiterTestSupport.sources()
        let plan = Arbiter.FamilyPlan()
        return try Arbiter.PairPlan.build(
            sources: sources,
            scores: ArbiterTestSupport.scoreTable(sources: sources, plan: plan),
            plan: plan,
            seed: seed)
    }

    // MARK: - Codex PR-review P2: a bad key must fail the run, not empty it

    /// `KeyFile.pairs()` throws `unknownArm` on a key whose arm labels this
    /// build cannot resolve (a corrupted key, or one from a newer protocol).
    /// The first build swallowed that with `try?`, scored an EMPTY pair list,
    /// and exited 0 with a plausible not-evaluated report — a silent masquerade
    /// exactly where the instrument must fail loudly.
    @Test func aKeyWithAnUnknownArmFailsScoringLoudly() {
        let pair = Arbiter.Pair(
            id: "pair-001", family: .validation,
            source: Arbiter.SourceRef(
                corpus: "nasa-steerable-v1", asset: "earth-limb-sunrise"),
            charset: "blocks",
            armA: .init(name: "NOT-AN-ARM"), armB: .init(name: "P"),
            leftIsArmA: true,
            metrics: Arbiter.PairMetrics(
                armAMeans: [.mae: 0.31], armBMeans: [.mae: 0.55]),
            repeatOf: nil)
        #expect(throws: ArbiterError.self) {
            _ = try Arbiter.Score.score(
                .init(
                    key: .init(seed: 7, pairs: [pair], enforcesFrozenProtocol: false),
                    humanAnswers: ["pair-001": .left], judgements: []))
        }
    }
}
