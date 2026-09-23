import Foundation
import Testing

@testable import AskiColorLab

/// Guards ASKI-56 §2.1's pair-family construction: the fixed budget, the arm
/// contents of each family, the calibration ladder's ΔMAE coverage, the
/// adversarial family's MAE-blindness, and the repeats' re-randomization.
///
/// The families are what the protocol actually measures — V validates the
/// instrument, C calibrates JND75, M stops the calibration from only probing
/// where MAE works. A silent change in any family's size or contents changes
/// what the run means, so the budget is pinned.
@Suite struct AskiColorLabArbiterPairFamilyTests {

    private static func plan() -> Arbiter.FamilyPlan { Arbiter.FamilyPlan() }

    private static func build(seed: UInt64 = 4242) throws -> [Arbiter.Pair] {
        let sources = ArbiterTestSupport.sources()
        let plan = Self.plan()
        return try Arbiter.PairPlan.build(
            sources: sources,
            scores: ArbiterTestSupport.scoreTable(sources: sources, plan: plan),
            plan: plan,
            seed: seed)
    }

    private static func pairs(_ all: [Arbiter.Pair], _ family: Arbiter.Family) -> [Arbiter.Pair] {
        all.filter { $0.family == family }
    }

    // MARK: - Budget

    /// The v2 budget: V=6, D=6, X=6, C=20, M=8, R=5 — 51 trials,
    /// 46 unique.
    @Test func familyBudgetMatchesTheFrozenProtocol() throws {
        let all = try Self.build()
        #expect(Self.pairs(all, .validation).count == 6)
        #expect(Self.pairs(all, .disagreement).count == 6)
        #expect(Self.pairs(all, .polarity).count == 6)
        #expect(Self.pairs(all, .calibration).count == 20)
        #expect(Self.pairs(all, .adversarial).count == 8)
        #expect(Self.pairs(all, .repeats).count == 5)
        #expect(all.count == 51)
        #expect(all.filter { $0.repeatOf == nil }.count == 46)
    }

    /// Pair IDs are the coded, sequential, zero-padded identifiers the rater
    /// answers against, unique across the whole run.
    @Test func pairIDsAreSequentialCodedAndUnique() throws {
        let all = try Self.build()
        #expect(all.map(\.id) == (1...51).map { String(format: "pair-%03d", $0) })
        #expect(Set(all.map(\.id)).count == 51)
    }

    // MARK: - V and D

    /// V is the tone-only floor F against production P, on blocks, on all six
    /// sources. This is the pair family §5.1 gates the instrument on.
    @Test func validationFamilyIsFloorVersusProductionOnEverySource() throws {
        let v = Self.pairs(try Self.build(), .validation)
        #expect(Set(v.map(\.source)).count == 6)
        for pair in v {
            #expect(pair.charset == "blocks")
            #expect(Set([pair.armA.name, pair.armB.name]) == Set(["F", "P"]))
            let production = try #require(
                [pair.armA, pair.armB].first { $0.kind == .converter })
            #expect(production.shapeQueryPolarity == "inverted")
        }
    }

    /// X is not a lucky C/M draw: every registered source gets the exact
    /// converter-level polarity comparison.
    @Test func polarityFamilyIsDirectVersusInvertedOnEverySource() throws {
        let x = Self.pairs(try Self.build(), .polarity)
        #expect(Set(x.map(\.source)).count == 6)
        for pair in x {
            #expect(pair.charset == "blocks")
            #expect(pair.armA.kind == .converter)
            #expect(pair.armB.kind == .converter)
            #expect(
                Set([pair.armA.shapeQueryPolarity, pair.armB.shapeQueryPolarity])
                    == Set(["inverted", "direct"]))
        }
    }

    /// D is the ASKI-30 near-tie: tone-weighted T at w = 2 against the floor F,
    /// on blocks, all six sources.
    @Test func disagreementFamilyIsToneWeightedAtTwoVersusFloor() throws {
        let d = Self.pairs(try Self.build(), .disagreement)
        #expect(Set(d.map(\.source)).count == 6)
        for pair in d {
            #expect(pair.charset == "blocks")
            let names = Set([pair.armA.name, pair.armB.name])
            #expect(names == Set(["T", "F"]))
            let toneArm = [pair.armA, pair.armB].first { $0.name == "T" }
            #expect(toneArm?.w == 2)
        }
    }

    // MARK: - C, the calibration ladder

    /// The ladder spans near-0 to the largest available margin in roughly even
    /// steps, and at least four of its rungs are on the dense charset.
    @Test func calibrationLadderSpansTheMarginRangeAndIncludesDensePairs() throws {
        let c = Self.pairs(try Self.build(), .calibration)
        #expect(c.filter { $0.charset == "standard" }.count >= 4)
        #expect(c.filter { $0.charset == "blocks" }.count >= 1)

        let blocksMargins = c.filter { $0.charset == "blocks" }
            .map { abs($0.metrics.signedDeltaMAE) }.sorted()
        let largest = try #require(blocksMargins.last)
        let smallest = try #require(blocksMargins.first)
        #expect(smallest < largest / 4, "the ladder never gets near a 0 margin")

        // Roughly even steps: no gap between consecutive rungs may swallow more
        // than half the whole range, or the "ladder" is two clusters.
        var largestGap = 0.0
        for index in 1..<blocksMargins.count {
            largestGap = max(largestGap, blocksMargins[index] - blocksMargins[index - 1])
        }
        #expect(largestGap < (largest - smallest) * 0.5)
    }

    /// A pair compares two DIFFERENT arms on one source and charset, and no
    /// unique pair is emitted twice across V/D/C/M.
    @Test func uniquePairsAreDistinctArmsAndNeverDuplicated() throws {
        let all = try Self.build().filter { $0.repeatOf == nil }
        var seen = Set<String>()
        for pair in all {
            #expect(pair.armA != pair.armB, "\(pair.id) compares an arm with itself")
            let armKeys = [pair.armA, pair.armB].map(\.label).sorted()
            let signature =
                "\(pair.source.corpus)/\(pair.source.asset)|\(pair.charset)|"
                + armKeys.joined(separator: "|")
            #expect(seen.insert(signature).inserted, "duplicate pair: \(signature)")
        }
    }

    // MARK: - M, the adversarial family

    /// MAD-style: the adversarial pairs must sit at a SMALLER |ΔMAE| and a
    /// LARGER |ΔSSIM| than the calibration ladder's typical rung. That is the
    /// whole reason the family exists — calibration must be probed where MAE is
    /// blind, not only where it works.
    @Test func adversarialFamilyProbesWhereMAEIsBlind() throws {
        let all = try Self.build()
        let m = Self.pairs(all, .adversarial)
        let c = Self.pairs(all, .calibration)

        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
        let adversarialMAE = median(m.map { abs($0.metrics.signedDeltaMAE) })
        let calibrationMAE = median(c.map { abs($0.metrics.signedDeltaMAE) })
        #expect(adversarialMAE < calibrationMAE)

        let adversarialSSIM = median(m.map { abs($0.metrics.delta(.ssim)) })
        let calibrationSSIM = median(c.map { abs($0.metrics.delta(.ssim)) })
        #expect(adversarialSSIM > calibrationSSIM)
    }

    // MARK: - R, the repeats

    /// Repeats re-present an already-emitted pair under a NEW pair ID, so the
    /// rater cannot recognize it, and they are excluded from the verdict n.
    @Test func repeatsReuseEmittedPairsWithFreshIDs() throws {
        let all = try Self.build()
        let unique = all.filter { $0.repeatOf == nil }
        let repeats = Self.pairs(all, .repeats)

        let byID = Dictionary(uniqueKeysWithValues: unique.map { ($0.id, $0) })
        #expect(Set(repeats.map(\.id)).count == repeats.count)
        for repeated in repeats {
            let origin = try #require(repeated.repeatOf.flatMap { byID[$0] })
            #expect(repeated.id != origin.id)
            #expect(repeated.source == origin.source)
            #expect(repeated.charset == origin.charset)
            #expect(repeated.armA == origin.armA && repeated.armB == origin.armB)
        }
        #expect(Set(repeats.compactMap(\.repeatOf)).count == repeats.count, "a pair was repeated twice")
    }

    // MARK: - Seeding

    /// The same seed reproduces the run exactly; a different seed moves the
    /// seeded selections (C/M draws and R re-draws) or `--seed` is decorative.
    @Test func planIsReproducibleUnderOneSeedAndMovesUnderAnother() throws {
        let a = try Self.build(seed: 11)
        let b = try Self.build(seed: 11)
        #expect(a.map(\.signature) == b.map(\.signature))

        let c = try Self.build(seed: 12)
        #expect(a.map(\.signature) != c.map(\.signature))

        // V and D are exhaustive over the sources, so the SET of trials in each
        // must not move with the seed — only the IDs they are numbered with and
        // the sides they are shown on may. Compared as sets, because the seeded
        // shuffle that hides the family from the pair ID (§3) deliberately moves
        // the order these appear in.
        #expect(
            Set(Self.pairs(a, .validation).map(\.identitySignature))
                == Set(Self.pairs(c, .validation).map(\.identitySignature)))
        #expect(Self.pairs(a, .validation).count == Self.pairs(c, .validation).count)
        #expect(
            Set(Self.pairs(a, .disagreement).map(\.identitySignature))
                == Set(Self.pairs(c, .disagreement).map(\.identitySignature)))
        #expect(
            Set(Self.pairs(a, .polarity).map(\.identitySignature))
                == Set(Self.pairs(c, .polarity).map(\.identitySignature)))
    }

    /// A missing score is a hard error, never a silently dropped pair: the
    /// budget is part of the protocol.
    @Test func aMissingArmScoreFailsTheRun() {
        let sources = ArbiterTestSupport.sources()
        let plan = Self.plan()
        var scores = ArbiterTestSupport.scoreTable(sources: sources, plan: plan)
        scores.removeValue(
            forKey: Arbiter.ArmKey(source: sources[0], charset: "blocks", arm: .init(.floor)))
        #expect(throws: ArbiterError.self) {
            try Arbiter.PairPlan.build(sources: sources, scores: scores, plan: plan, seed: 1)
        }
    }
}
