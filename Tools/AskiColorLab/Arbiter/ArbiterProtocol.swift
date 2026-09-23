import AskiToolSupport
import Foundation

/// The ASKI-56 perceptual arbiter, v2. Protocol frozen at
/// `docs/Research/2026-09-04-aski62-arbiter-v2-protocol.md`.
///
/// The instrument is three subcommands. `stimuli` materializes blinded
/// reference/left/right triplets from the real converter geometry and the real
/// candidate pool; `judge` runs the VLM leg through an injectable subprocess;
/// `score` joins the human answers and/or the judge results against `key.json`
/// and applies the frozen §5.1 gate and §2.3 computations.
///
/// The human owner is the arbiter (§1). Every number the VLM leg produces is
/// worth nothing until the §5.1 validation gate passes, and even then it is a
/// pre-screen and tie-breaker, never co-equal.
///
/// This file holds the value types and the two pure constructions the whole
/// protocol rests on: the seeded left/right blinding (§3) and the pair-family
/// plan (§2.1). Both are deliberately image-free so they can be tested without
/// a corpus — the family budget and the ladder geometry are the contract.
enum Arbiter {

    // MARK: - Families

    /// The six pair families of §3. Raw values are the coded family letters
    /// the protocol names them by; they appear in `key.json` and never in a
    /// rater-visible artifact.
    enum Family: String, CaseIterable, Sendable, Codable {
        /// §2.1 V — the unanimous five-oracle inversion. The §5.1 gate reads it.
        case validation = "V"
        /// §2.1 D — the ASKI-30 SSIM-inversion near-tie. Recorded, not gated.
        case disagreement = "D"
        /// V2 X — explicit inverted-versus-direct production conversion.
        case polarity = "X"
        /// §2.1 C — the calibration ladder JND75 is fitted on.
        case calibration = "C"
        /// §2.1 M — MAD-style adversarial pairs, where MAE is blind.
        case adversarial = "M"
        /// §2.1 R — delayed, re-randomized repeats; rater consistency only.
        case repeats = "R"
    }

    /// A corpus-qualified source image. The two corpora share two asset
    /// filenames at different native sizes, so an unqualified asset name would
    /// silently collapse four sources into two.
    struct SourceRef: Hashable, Sendable, Codable {
        let corpus: String
        let asset: String

        enum CodingKeys: String, CodingKey {
            case corpus
            case asset
        }

        /// The bootstrap's resampling unit (§2.3: "resampled by source image").
        var key: String { "\(corpus)/\(asset)" }
    }

    /// A converter-level treatment. Cases are closed so an unknown on-disk
    /// delta cannot be guessed or silently replaced with a default.
    enum ConverterArm: Hashable, Sendable {
        case productionInverted
        case productionDirect

        var shapeQueryPolarity: String {
            switch self {
            case .productionInverted: return "inverted"
            case .productionDirect: return "direct"
            }
        }
    }

    /// One census arm. Selection arms reuse the inverted production scaffold;
    /// converter arms own a complete grid from their own conversion.
    enum Arm: Hashable, Sendable {
        case selection(SelectionCeiling.Arm)
        case converter(ConverterArm)
    }

    /// The flat, serializable projection of a unified arm. Schema-v1 keys did
    /// not carry `kind`; their old shape decodes as a selection arm only.
    struct ArmRef: Hashable, Sendable, Codable {
        enum Kind: String, Hashable, Sendable, Codable {
            case selection
            case converter
        }

        let kind: Kind
        let name: String
        let w: Float?
        let topK: Int?
        let shapeQueryPolarity: String?
        /// True when the serialized arm carried schema-v2's required `kind`.
        /// Historical schema-v1 keys omit it and are the only files allowed to
        /// use the selection fallback.
        let kindWasExplicit: Bool

        init(_ arm: SelectionCeiling.Arm) {
            self.kind = .selection
            self.name = arm.name
            self.w = arm.w
            self.topK = arm.topK
            self.shapeQueryPolarity = nil
            self.kindWasExplicit = true
        }

        init(_ arm: ConverterArm) {
            self.kind = .converter
            self.name = "P"
            self.w = nil
            self.topK = nil
            self.shapeQueryPolarity = arm.shapeQueryPolarity
            self.kindWasExplicit = true
        }

        init(_ arm: Arm) {
            switch arm {
            case .selection(let selection): self.init(selection)
            case .converter(let converter): self.init(converter)
            }
        }

        init(
            kind: Kind = .selection,
            name: String,
            w: Float? = nil,
            topK: Int? = nil,
            shapeQueryPolarity: String? = nil
        ) {
            self.kind = kind
            self.name = name
            self.w = w
            self.topK = topK
            self.shapeQueryPolarity = shapeQueryPolarity
            self.kindWasExplicit = true
        }

        enum CodingKeys: String, CodingKey {
            case kind
            case name
            case w
            case topK
            case shapeQueryPolarity = "shape_query_polarity"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let encodedKind = try container.decodeIfPresent(Kind.self, forKey: .kind)
            kind = encodedKind ?? .selection
            kindWasExplicit = encodedKind != nil
            name = try container.decode(String.self, forKey: .name)
            w = try container.decodeIfPresent(Float.self, forKey: .w)
            topK = try container.decodeIfPresent(Int.self, forKey: .topK)
            shapeQueryPolarity = try container.decodeIfPresent(
                String.self, forKey: .shapeQueryPolarity)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(w, forKey: .w)
            try container.encodeIfPresent(topK, forKey: .topK)
            try container.encodeIfPresent(shapeQueryPolarity, forKey: .shapeQueryPolarity)
        }

        /// A stable, human-readable label for logs and dedupe signatures.
        /// Never shown to the rater.
        var label: String {
            if let shapeQueryPolarity {
                return "\(name)(shapeQueryPolarity=\(shapeQueryPolarity))"
            }
            if let w { return "\(name)(w=\(w))" }
            if let topK { return "\(name)(topK=\(topK))" }
            return name
        }

        /// Rebuild the typed arm. Every field combination is validated so a key
        /// from a future protocol fails loudly instead of degrading to P.
        var arm: Arm? {
            switch kind {
            case .selection:
                guard shapeQueryPolarity == nil else { return nil }
                switch name {
                case "P" where w == nil && topK == nil:
                    return .selection(.production)
                case "F" where w == nil && topK == nil:
                    return .selection(.floor)
                case "F_legacy" where w == nil && topK == nil:
                    return .selection(.legacyFloor)
                case "T" where w != nil && topK == nil:
                    return w.map { .selection(.toneWeighted(w: $0)) }
                case "K" where w == nil && topK != nil:
                    return topK.map { .selection(.poolWidth(topK: $0)) }
                case "lex" where w == nil && topK != nil:
                    return topK.map { .selection(.lexicographic(shapeK: $0)) }
                case "znorm" where w != nil && topK == nil:
                    return w.map { .selection(.zNormalized(w: $0)) }
                default: return nil
                }
            case .converter:
                guard name == "P", w == nil, topK == nil else { return nil }
                switch shapeQueryPolarity {
                case "inverted": return .converter(.productionInverted)
                case "direct": return .converter(.productionDirect)
                default: return nil
                }
            }
        }
    }

    /// The (source, charset, arm) address of one census score.
    struct ArmKey: Hashable, Sendable {
        let source: SourceRef
        let charset: String
        let arm: ArmRef
    }

    /// Both sides' oracle means and their signed deltas, computed at stimuli
    /// time and stored ONLY in `key.json` (§2.1 step 5).
    struct PairMetrics: Sendable, Codable, Equatable {
        /// Oracle raw value -> arm A's mean score.
        let armAMeans: [String: Double]
        /// Oracle raw value -> arm B's mean score.
        let armBMeans: [String: Double]

        enum CodingKeys: String, CodingKey {
            case armAMeans = "arm_a_means"
            case armBMeans = "arm_b_means"
            case signedDeltaMAE = "delta_mae"
            case relativeMarginMAE = "relative_margin_mae"
        }

        init(
            armAMeans: [SelectionCeiling.Oracle: Double],
            armBMeans: [SelectionCeiling.Oracle: Double]
        ) {
            self.armAMeans = Dictionary(
                uniqueKeysWithValues: armAMeans.map { ($0.key.rawValue, $0.value) })
            self.armBMeans = Dictionary(
                uniqueKeysWithValues: armBMeans.map { ($0.key.rawValue, $0.value) })
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            armAMeans = try container.decode([String: Double].self, forKey: .armAMeans)
            armBMeans = try container.decode([String: Double].self, forKey: .armBMeans)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(armAMeans, forKey: .armAMeans)
            try container.encode(armBMeans, forKey: .armBMeans)
            // Denormalized deliberately: the join key the readout reads most is
            // the one that should not have to be recomputed from two maps.
            try container.encode(signedDeltaMAE, forKey: .signedDeltaMAE)
            try container.encode(relativeMarginMAE, forKey: .relativeMarginMAE)
        }

        /// `mean(armA) − mean(armB)` under `oracle`. NaN when either side is
        /// missing — never 0, which would read as a genuine tie.
        func delta(_ oracle: SelectionCeiling.Oracle) -> Double {
            guard let a = armAMeans[oracle.rawValue], let b = armBMeans[oracle.rawValue] else {
                return .nan
            }
            return a - b
        }

        /// The signed absolute gap. Negative means arm A has the lower (better)
        /// MAE. Used for family construction and for naming the better side; it
        /// is NOT the calibration regressor — see `relativeMarginMAE`.
        var signedDeltaMAE: Double { delta(.mae) }

        /// The calibration regressor, and the quantity the §5.2 bar is actually
        /// written in: `1 − MAE_better / MAE_worse`, the fractional improvement
        /// of the better arm over the worse one taken as its baseline.
        ///
        /// This is exactly the standing bar's own form. `MAE_arm / MAE_baseline
        /// ≤ 0.97` (`docs/Research/2026-08-24-aski-30-28-decisive-rule.md:97`)
        /// is a 3.0 percent RELATIVE improvement, so a JND75 fitted against the
        /// absolute gap cannot be compared to it: at the corpus's own magnitudes
        /// (production mean MAE 0.5571 on `blocks`) an absolute gap of 0.030 is
        /// only a 5.4 percent relative improvement, and reading it as 3.0 makes
        /// the bar look roughly 1.8x better grounded than it is — with the error
        /// always in the direction of keeping it.
        ///
        /// `nan` when either side is missing, and 0 when the worse arm's mean is
        /// itself degenerate, which is not a 100 percent win.
        var relativeMarginMAE: Double {
            guard let a = armAMeans[SelectionCeiling.Oracle.mae.rawValue],
                let b = armBMeans[SelectionCeiling.Oracle.mae.rawValue],
                a.isFinite, b.isFinite
            else { return .nan }
            let worse = max(a, b)
            guard worse > 0 else { return 0 }
            return (worse - min(a, b)) / worse
        }
    }

    /// One emitted trial.
    struct Pair: Sendable {
        let id: String
        let family: Family
        let source: SourceRef
        let charset: String
        let armA: ArmRef
        let armB: ArmRef
        /// The §3 seeded blinding, resolved once at emission and recorded so
        /// scoring joins on what the rater actually saw.
        let leftIsArmA: Bool
        let metrics: PairMetrics
        /// For an R-family repeat, the ID of the pair it re-presents.
        let repeatOf: String?

        /// Everything about this trial including its coded ID and seeded side,
        /// for reproducibility diffs.
        var signature: String {
            [id, identitySignature, leftIsArmA ? "L=A" : "L=B"].joined(separator: "|")
        }

        /// WHAT this trial is — family, source, charset, arms — without its
        /// coded ID or its seeded side. V and D are exhaustive over the sources,
        /// so the set of their identity signatures must not move with `--seed`,
        /// even though both the IDs they are numbered with and the sides they
        /// are shown on do.
        var identitySignature: String {
            [family.rawValue, source.key, charset, armA.label, armB.label, repeatOf ?? "-"]
                .joined(separator: "|")
        }

        /// The arm the rater picked, given a side.
        func arm(for choice: Choice) -> ArmRef? {
            switch choice {
            case .left: return leftIsArmA ? armA : armB
            case .right: return leftIsArmA ? armB : armA
            case .tie: return nil
            }
        }

        /// The side holding the lower-MAE arm, or `nil` on an exact tie.
        var lowerMAESide: Choice? {
            let delta = metrics.signedDeltaMAE
            guard delta.isFinite, delta != 0 else { return nil }
            let lowerIsArmA = delta < 0
            return (lowerIsArmA == leftIsArmA) ? .left : .right
        }
    }

    /// The rater's answer for one pair. Raw values are the `answers.csv`
    /// vocabulary.
    enum Choice: String, Sendable, Codable, Equatable {
        case left = "L"
        case right = "R"
        case tie
    }

    // MARK: - Blinding (§3)

    enum Blinding {
        /// FNV-1a 64. Swift's `Hasher` is seeded per process, so using it would
        /// make the blinding irreproducible across runs — the one property §3
        /// most needs. This is the canonical algorithm with the canonical
        /// constants, so the mapping is auditable from the pair ID alone.
        static func stableHash(_ text: String) -> UInt64 {
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            for byte in text.utf8 {
                hash ^= UInt64(byte)
                hash &*= 0x0000_0100_0000_01b3
            }
            return hash
        }

        /// The §3 left/right assignment: a seeded function of the pair ID, so
        /// it reproduces exactly, moves with `--seed`, and varies pair to pair.
        ///
        /// The seed is mixed through SplitMix64's finalizer rather than XORed
        /// straight into the hash: FNV-1a's low bits move very little between
        /// adjacent short strings, and taking bit 0 of a bare XOR would put a
        /// long run of consecutive pair IDs on the same side.
        static func leftIsFirstArm(seed: UInt64, pairID: String) -> Bool {
            var state = stableHash(pairID) &+ (seed &* 0x9e37_79b9_7f4a_7c15)
            state = (state ^ (state >> 30)) &* 0xbf58_476d_1ce4_e5b9
            state = (state ^ (state >> 27)) &* 0x94d0_49bb_1331_11eb
            state ^= state >> 31
            return state & 1 == 0
        }
    }

    /// Deterministic RNG for the seeded family draws. SplitMix64: small, exact,
    /// and identical on every platform — `SystemRandomNumberGenerator` is not
    /// reproducible and `Hasher` is not stable.
    struct SeededRandom: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { self.state = seed &+ 0x9e37_79b9_7f4a_7c15 }

        mutating func next() -> UInt64 {
            state &+= 0x9e37_79b9_7f4a_7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
            z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
            return z ^ (z >> 31)
        }
    }

    // MARK: - The key file

    /// `key.json` — the ONLY identity-bearing artifact (§3). The rater must not
    /// open it before submitting answers.
    struct KeyFile: Sendable, Codable {
        struct Entry: Sendable, Codable {
            let pairID: String
            let family: Family
            let source: SourceRef
            let charset: String
            let armA: ArmRef
            let armB: ArmRef
            let leftIsArmA: Bool
            let repeatOf: String?
            let metrics: PairMetrics

            enum CodingKeys: String, CodingKey {
                case pairID = "pair_id"
                case family
                case source
                case charset
                case armA = "arm_a"
                case armB = "arm_b"
                case leftIsArmA = "left_is_arm_a"
                case repeatOf = "repeat_of"
                case metrics
            }
        }

        let schemaVersion: String
        let protocolVersion: String
        let seed: UInt64
        /// The per-family budget. It lives HERE, not in the rater-visible
        /// manifest: knowing there are exactly six validation pairs is most of
        /// the way to finding them, and a found V pair no longer screens anyone.
        let familyCounts: [String: Int]
        let entries: [Entry]
        /// Decoded keys and emitted production keys enforce the complete frozen
        /// protocol. Pure scoring tests may opt out so they can exercise small,
        /// synthetic psychometric fixtures without pretending those are runs.
        let enforcesFrozenProtocol: Bool

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case protocolVersion = "protocol_version"
            case seed
            case familyCounts = "family_counts"
            case entries
        }

        init(seed: UInt64, pairs: [Pair], enforcesFrozenProtocol: Bool = true) {
            self.schemaVersion = "2"
            self.protocolVersion = Arbiter.protocolVersion
            self.seed = seed
            self.enforcesFrozenProtocol = enforcesFrozenProtocol
            var counts: [String: Int] = [:]
            for pair in pairs { counts[pair.family.rawValue, default: 0] += 1 }
            self.familyCounts = counts
            self.entries = pairs.map {
                Entry(
                    pairID: $0.id, family: $0.family, source: $0.source, charset: $0.charset,
                    armA: $0.armA, armB: $0.armB, leftIsArmA: $0.leftIsArmA,
                    repeatOf: $0.repeatOf, metrics: $0.metrics)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
            protocolVersion = try container.decode(String.self, forKey: .protocolVersion)
            seed = try container.decode(UInt64.self, forKey: .seed)
            familyCounts = try container.decode([String: Int].self, forKey: .familyCounts)
            entries = try container.decode([Entry].self, forKey: .entries)
            enforcesFrozenProtocol = true
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(schemaVersion, forKey: .schemaVersion)
            try container.encode(protocolVersion, forKey: .protocolVersion)
            try container.encode(seed, forKey: .seed)
            try container.encode(familyCounts, forKey: .familyCounts)
            try container.encode(entries, forKey: .entries)
        }

        /// Rebuild the emitted pairs from a key read back off disk.
        func pairs() throws -> [Pair] {
            guard schemaVersion == "1" || schemaVersion == "2" else {
                throw ArbiterError.unknownSchema(schemaVersion)
            }

            guard !enforcesFrozenProtocol || protocolVersion == schemaVersion else {
                throw ArbiterError.invalidKey(
                    "schema v\(schemaVersion) cannot claim protocol v\(protocolVersion)")
            }

            if enforcesFrozenProtocol {
                let expectedCounts: [String: Int]
                switch schemaVersion {
                case "1":
                    expectedCounts = ["V": 6, "D": 6, "C": 20, "M": 8, "R": 5]
                case "2":
                    expectedCounts = ["V": 6, "D": 6, "X": 6, "C": 20, "M": 8, "R": 5]
                default:
                    preconditionFailure("schema guard above is exhaustive")
                }
                guard familyCounts == expectedCounts else {
                    throw ArbiterError.invalidKey(
                        "schema v\(schemaVersion) family_counts do not match the frozen budget")
                }
            }

            var actualCounts: [String: Int] = [:]
            for entry in entries { actualCounts[entry.family.rawValue, default: 0] += 1 }
            guard actualCounts == familyCounts else {
                throw ArbiterError.invalidKey("family_counts do not match the entries")
            }

            let pairIDs = entries.map(\.pairID)
            guard pairIDs.allSatisfy({ !$0.isEmpty }), Set(pairIDs).count == pairIDs.count else {
                throw ArbiterError.invalidKey("pair IDs must be nonempty and unique")
            }

            let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.pairID, $0) })
            var repeatOrigins = Set<String>()
            for entry in entries {
                let arms = [entry.armA, entry.armB]
                if enforcesFrozenProtocol && schemaVersion == "1" {
                    guard arms.allSatisfy({ !$0.kindWasExplicit && $0.kind == .selection }) else {
                        throw ArbiterError.invalidKey(
                            "schema v1 arms must use the historical selection-only shape")
                    }
                } else if enforcesFrozenProtocol {
                    guard arms.allSatisfy(\.kindWasExplicit) else {
                        throw ArbiterError.invalidKey("schema v2 requires kind on every arm")
                    }
                    guard !arms.contains(where: { $0.kind == .selection && $0.name == "P" }) else {
                        throw ArbiterError.invalidKey(
                            "schema v2 does not register selection-arm P")
                    }
                }
                guard entry.armA.arm != nil, entry.armB.arm != nil else {
                    throw ArbiterError.unknownArm(entry.armA.label + " / " + entry.armB.label)
                }

                if entry.family == .repeats {
                    guard let originID = entry.repeatOf, originID != entry.pairID,
                        let origin = byID[originID], origin.family != .repeats,
                        repeatOrigins.insert(originID).inserted,
                        origin.source == entry.source, origin.charset == entry.charset,
                        origin.armA == entry.armA, origin.armB == entry.armB,
                        origin.metrics == entry.metrics,
                        origin.leftIsArmA != entry.leftIsArmA
                    else {
                        throw ArbiterError.invalidKey(
                            "repeat \(entry.pairID) must uniquely reference an opposite-side copy of one non-repeat pair")
                    }
                } else if entry.repeatOf != nil {
                    throw ArbiterError.invalidKey(
                        "only R-family entries may carry repeat_of")
                }
            }

            return entries.map { entry in
                return Pair(
                    id: entry.pairID, family: entry.family, source: entry.source,
                    charset: entry.charset, armA: entry.armA, armB: entry.armB,
                    leftIsArmA: entry.leftIsArmA, metrics: entry.metrics,
                    repeatOf: entry.repeatOf)
            }
        }
    }

    static let protocolVersion = "2"

    /// The frozen note this instrument executes.
    static let protocolNote = "docs/Research/2026-09-04-aski62-arbiter-v2-protocol.md"

    static func protocolNote(for version: String) -> String {
        version == "1"
            ? "docs/Research/2026-08-25-aski56-arbiter-protocol.md"
            : protocolNote
    }
}

/// Failures that must stop a run rather than silently shrink it. The pair budget
/// is part of the protocol, so a dropped pair is never acceptable.
enum ArbiterError: Error, CustomStringConvertible, Equatable {
    case missingScore(source: String, charset: String, arm: String)
    case unknownSchema(String)
    case invalidKey(String)
    case unknownArm(String)
    case unknownPairID(String)
    case malformedAnswer(row: Int, value: String)
    case duplicateAnswer(String)
    case judgeTemplateMissingPlaceholders([String])
    case notEnoughCandidates(family: String, wanted: Int, available: Int)
    case keyUnreadable(String)

    var description: String {
        switch self {
        case .missingScore(let source, let charset, let arm):
            return
                "no census score for arm '\(arm)' on '\(charset)' for source '\(source)'; the pair budget is part of the protocol, so a missing score fails the run rather than shrinking a family"
        case .unknownSchema(let version):
            return "unsupported arbiter key schema '\(version)'"
        case .invalidKey(let detail):
            return "invalid arbiter key: \(detail)"
        case .unknownArm(let label):
            return "key.json names an arm this build cannot rebuild: '\(label)'"
        case .unknownPairID(let id):
            return "answers name pair '\(id)', which is not in key.json"
        case .malformedAnswer(let row, let value):
            return "answers.csv row \(row): choice '\(value)' is not one of L, R, tie"
        case .judgeTemplateMissingPlaceholders(let missing):
            return
                "--runner-arg never substitutes \(missing.joined(separator: ", ")), so the judge would be run without the images; a judge that cannot see them still answers, and the whole leg becomes position bias that looks like data"
        case .duplicateAnswer(let id):
            return
                "answers.csv answers pair '\(id)' more than once; two answers for one trial is a rater error, and silently keeping the last one drops the other"
        case .notEnoughCandidates(let family, let wanted, let available):
            return
                "family \(family) needs \(wanted) pairs but only \(available) distinct candidates exist; widen the arm sweep or the source set rather than shipping a short family"
        case .keyUnreadable(let path):
            return "could not read key.json at '\(path)'"
        }
    }
}
