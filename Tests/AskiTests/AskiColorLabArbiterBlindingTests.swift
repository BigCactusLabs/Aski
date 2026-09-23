import Foundation
import Testing

@testable import AskiColorLab

/// Guards the ASKI-56 §3 blinding contract.
///
/// The arbiter's whole claim to being an instrument rests on the rater not being
/// able to infer which side is which. Two properties carry that claim: the
/// left/right assignment is a seeded function of the pair, so a run reproduces
/// exactly and is auditable after the fact; and `key.json` is the ONLY artifact
/// that names an arm, a charset, a source or a metric. Everything the rater can
/// open — the PNG filenames, the composite sheet labels, the answers template —
/// carries the coded pair ID and nothing else.
@Suite struct AskiColorLabArbiterBlindingTests {

    private static func samplePairs() -> [Arbiter.Pair] {
        let sources = ArbiterTestSupport.sources()
        let plan = Arbiter.FamilyPlan()
        let scores = ArbiterTestSupport.scoreTable(sources: sources, plan: plan)
        return try! Arbiter.PairPlan.build(sources: sources, scores: scores, plan: plan, seed: 7)
    }

    // MARK: - Seeded determinism

    /// Same seed, same pair ID -> same side. A blinding that drifted between the
    /// stimuli run and the scoring run would silently invert answers.
    @Test func leftRightAssignmentIsDeterministicPerSeedAndPairID() {
        for id in ["pair-001", "pair-017", "pair-042"] {
            let first = Arbiter.Blinding.leftIsFirstArm(seed: 12345, pairID: id)
            for _ in 0..<8 {
                #expect(Arbiter.Blinding.leftIsFirstArm(seed: 12345, pairID: id) == first)
            }
        }
    }

    /// The assignment is a function of BOTH inputs: it must vary across pair IDs
    /// at one seed (otherwise every pair puts the same arm left, and the rater
    /// learns the layout), and it must vary across seeds at one pair ID
    /// (otherwise `--seed` is decorative).
    @Test func leftRightAssignmentVariesAcrossPairIDsAndAcrossSeeds() {
        let ids = (1...60).map { String(format: "pair-%03d", $0) }
        let atSeedOne = ids.map { Arbiter.Blinding.leftIsFirstArm(seed: 1, pairID: $0) }
        #expect(atSeedOne.contains(true) && atSeedOne.contains(false))

        let atSeedTwo = ids.map { Arbiter.Blinding.leftIsFirstArm(seed: 2, pairID: $0) }
        #expect(atSeedOne != atSeedTwo, "the seed did not move the left/right assignment")

        // Not a hard balance requirement — just a guard against a degenerate
        // hash that lands 90% of pairs on one side.
        let leftCount = atSeedOne.filter { $0 }.count
        #expect(leftCount > 15 && leftCount < 45, "assignment is lopsided: \(leftCount)/60 left")
    }

    /// The hash behind the assignment must not be Swift's per-process-seeded
    /// `Hasher`. A repeated call inside one process cannot see that difference,
    /// so the property is pinned on the stable hash directly against a value
    /// that is fixed by the algorithm, not by the run.
    @Test func stableHashIsProcessIndependent() {
        // FNV-1a 64 of "pair-001", computed independently of this implementation.
        #expect(Arbiter.Blinding.stableHash("") == 0xcbf2_9ce4_8422_2325)
        #expect(Arbiter.Blinding.stableHash("a") == 0xaf63_dc4c_8601_ec8c)
        #expect(Arbiter.Blinding.stableHash("foobar") == 0x85944171f73967e8)
    }

    /// A unique pair carries the seeded side it was emitted under, so scoring
    /// joins on the recorded value rather than recomputing it from a possibly
    /// different seed.
    @Test func emittedPairsCarryTheirSeededSide() {
        let pairs = Self.samplePairs()
        for pair in pairs where pair.repeatOf == nil {
            #expect(pair.leftIsArmA == Arbiter.Blinding.leftIsFirstArm(seed: 7, pairID: pair.id))
        }
    }

    /// An R repeat is the one exception: its side is the NEGATION of its
    /// origin's, not an independent seeded draw. An independent draw left about
    /// half the repeats pixel-identical to the trial they repeat, which measures
    /// recognition instead of the consistency the R family exists for.
    @Test func repeatsInvertTheirOriginsSideRatherThanRedrawingIt() throws {
        let pairs = Self.samplePairs()
        let byID = Dictionary(uniqueKeysWithValues: pairs.map { ($0.id, $0) })
        for repeated in pairs where repeated.repeatOf != nil {
            let origin = try #require(repeated.repeatOf.flatMap { byID[$0] })
            #expect(repeated.leftIsArmA == !origin.leftIsArmA)
        }
    }

    // MARK: - key.json is the only identity-bearing artifact

    /// Every rater-visible filename is the coded triplet and nothing else.
    @Test func raterVisibleFilenamesCarryNoIdentity() {
        let pairs = Self.samplePairs()
        for pair in pairs {
            let names = Arbiter.Stimuli.raterVisibleFilenames(for: pair)
            #expect(
                names == [
                    "\(pair.id)-ref.png", "\(pair.id)-left.png", "\(pair.id)-right.png",
                    "sheet/\(pair.id).png",
                ])
            for name in names {
                ArbiterTestSupport.expectNoIdentity(name, pair: pair)
            }
        }
    }

    /// The composite sheet label is the coded pair ID. No arm, no charset, no
    /// source, no metric — the ASKI-56 §2.1 step-4 bound on the sheet.
    @Test func sheetLabelsCarryOnlyTheCodedPairID() {
        for pair in Self.samplePairs() {
            let label = Arbiter.Stimuli.sheetLabel(for: pair)
            #expect(label == pair.id)
            ArbiterTestSupport.expectNoIdentity(label, pair: pair)
        }
    }

    /// `answers-template.csv` gives the rater a pairID and a choice column. It
    /// must not leak the family either: knowing a pair is a V pair tells the
    /// rater the margin is huge.
    @Test func answersTemplateCarriesNoIdentityAndNoFamily() {
        let pairs = Self.samplePairs()
        let csv = Arbiter.Stimuli.answersTemplateCSV(pairs)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        #expect(lines.first == "pairID,choice")
        #expect(lines.count >= pairs.count + 1)
        for pair in pairs {
            ArbiterTestSupport.expectNoIdentity(csv, pair: pair)
        }
        // No family letter may appear as a field, or as a letter run inside one:
        // a family column, or a `pair-001-V` style ID, would tell the rater that
        // a V pair's margin is huge. Checked per field rather than as a substring
        // of the whole file, because the header cell `pairID` itself ends in the
        // D-family letter and a raw `contains("D,")` sweep fires on it.
        for line in lines where !line.isEmpty {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map(String.init)
            #expect(fields.count == 2, "the answers template grew a column: \(line)")
            let letterRuns = fields.flatMap {
                $0.split(whereSeparator: { !$0.isLetter }).map(String.init)
            }
            for family in Arbiter.Family.allCases {
                #expect(
                    !letterRuns.contains(family.rawValue),
                    "family leaked into the answers template: \(line)")
            }
        }
        // Rows are the pair IDs with an empty choice cell to fill in.
        for (index, pair) in pairs.enumerated() {
            #expect(lines[index + 1] == "\(pair.id),")
        }
    }

    /// The key is where identity lives, and it must actually carry all of it —
    /// arm names, charset, source, side assignment and the per-pair metric
    /// deltas — or the scoring leg cannot join.
    @Test func keyFileCarriesEveryIdentityFieldScoringNeeds() throws {
        let pairs = Self.samplePairs()
        let key = Arbiter.KeyFile(seed: 7, pairs: pairs)
        let data = try StableJSONForTest.encode(key)
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("\"arm_a\""))
        #expect(text.contains("\"arm_b\""))
        #expect(text.contains("\"charset\""))
        #expect(text.contains("\"left_is_arm_a\""))
        #expect(text.contains("\"delta_mae\""))
        #expect(text.contains("\"family\""))
        #expect(text.contains("\"source\""))

        let decoded = try JSONDecoder().decode(Arbiter.KeyFile.self, from: data)
        #expect(decoded.seed == 7)
        #expect(decoded.entries.count == pairs.count)
        #expect(decoded.entries.map(\.pairID) == pairs.map(\.id))
    }
}

enum StableJSONForTest {
    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
