import Foundation

extension Arbiter {

    /// The §2.1 fixed budget and the arm inventory the families draw from.
    ///
    /// The sweeps are NOT invented here. `toneWeights`, `topKs` and `lexShapeK`
    /// are the grids frozen in the ASKI-30/28 decisive rule §2.5, which is the
    /// record every arm in this instrument is comparable against; `zNormWeight`
    /// and `disagreementToneWeight` are the operating points that battery
    /// actually ran at. They are surfaced as fields so a run can record what it
    /// used, not so a run can quietly retune them.
    struct FamilyPlan: Sendable {
        /// ASKI-30 §2.5. `w = 0` is the shape-argmin anchor.
        var toneWeights: [Float] = [0, 1, 2, 5, 10, 25, 50]
        /// ASKI-28 §2.5, the `standard` grid. Widths above a charset's glyph
        /// count clamp, and `SelectionCeiling.effectivePoolWidths` de-duplicates
        /// them, so the sparse charset collapses to its full pool.
        var topKs: [Int] = [12, 18, 24, 36, 48, 64, 95]
        /// §6.1's grid endpoint on the sparse charsets.
        var lexShapeK: Int = 6
        /// §6.2 at the middle of the frozen `w` grid.
        var zNormWeight: Float = 10
        /// The ASKI-30 near-tie's operating point — `w* = 2` on `blocks`, the
        /// point the battery calibrated and the SSIM inversion was read at.
        var disagreementToneWeight: Float = 2

        /// §2.1: "charset = blocks unless stated".
        var gatingCharset = "blocks"
        /// §2.1 C: "plus ≥4 pairs on standard (dense-charset contrast)".
        var denseCharset = "standard"

        var validationCount = 6
        var disagreementCount = 6
        var polarityCount = 6
        var calibrationCount = 20
        var calibrationDenseMinimum = 4
        var adversarialCount = 8
        var repeatCount = 5
        /// The tail fraction of the sheet the R repeats may land in. §3 wants
        /// them "delayed"; 0.4 keeps every repeat well clear of its origin while
        /// leaving 18 slots for 5 repeats, so their positions are not derivable.
        var repeatDelayZone = 0.4

        /// §2.1: "Fixed conversion regime: columns=80, oversample=2 — the
        /// shipping regime every standing verdict was measured at."
        var columns = 80
        var oversample = 2
        /// The per-cell scoring footprint the census oracles run at, matching
        /// `selection-ceiling`'s default.
        var footprint = 24

        init() {}

        /// The arm inventory for one charset, in a deterministic order. This is
        /// the v2 C-family pool: `{P(inverted), P(direct), F, T(w ∈ sweep),
        /// K(topK), lex(shapeK=6), znorm(w=10)}`.
        ///
        /// Arm-K widths are reduced to distinct EFFECTIVE pool widths for the
        /// charset, exactly as the census does, so a sparse charset does not get
        /// seven identical arms under seven different labels — which would fill
        /// the calibration ladder with ΔMAE = 0 rungs that look like a finding.
        func candidateArms(charset: String) -> [Arm] {
            var arms: [Arm] = [
                .converter(.productionInverted),
                .converter(.productionDirect),
                .selection(.floor),
            ]
            arms += toneWeights.map { .selection(.toneWeighted(w: $0)) }
            let glyphCount = (try? SelectionCeiling.characterSet(named: charset))?.characters.count
            if let glyphCount {
                arms += SelectionCeiling.effectivePoolWidths(requested: topKs, glyphCount: glyphCount)
                    .map { .selection(.poolWidth(topK: $0)) }
            } else {
                arms += topKs.map { .selection(.poolWidth(topK: $0)) }
            }
            arms.append(.selection(.lexicographic(shapeK: lexShapeK)))
            arms.append(.selection(.zNormalized(w: zNormWeight)))
            // Arm K at production's own width is arm P's selector; keeping both
            // would emit a guaranteed ΔMAE = 0 pair under two labels.
            var seen = Set<ArmRef>()
            return arms.filter { seen.insert(ArmRef($0)).inserted }
        }

        /// Every (charset, arm) the stimuli census has to score for this plan.
        func requiredArms() -> [(charset: String, arms: [Arm])] {
            var charsets = [gatingCharset]
            if denseCharset != gatingCharset { charsets.append(denseCharset) }
            return charsets.map { charset in
                var arms = candidateArms(charset: charset)
                // D's arm is at a fixed w that need not be on the sweep.
                let disagreement = Arm.selection(
                    .toneWeighted(w: disagreementToneWeight))
                if !arms.contains(where: { ArmRef($0) == ArmRef(disagreement) }) {
                    arms.append(disagreement)
                }
                return (charset, arms)
            }
        }
    }

    /// Builds the §2.1 pair families from a per-(source, charset, arm) table of
    /// census oracle means.
    ///
    /// Deliberately image-free: the families are a function of the scores, so
    /// the budget and the ladder geometry are testable without a corpus and
    /// without a render.
    enum PairPlan {

        /// One candidate before it becomes a trial.
        private struct Candidate {
            let source: SourceRef
            let charset: String
            let armA: ArmRef
            let armB: ArmRef
            let metrics: PairMetrics
            var signature: String {
                "\(source.key)|\(charset)|" + [armA.label, armB.label].sorted().joined(separator: "|")
            }
        }

        static func build(
            sources: [SourceRef],
            scores: [ArmKey: [SelectionCeiling.Oracle: Double]],
            plan: FamilyPlan,
            seed: UInt64
        ) throws -> [Pair] {
            func means(_ source: SourceRef, _ charset: String, _ arm: Arm) throws
                -> [SelectionCeiling.Oracle: Double]
            {
                let ref = ArmRef(arm)
                guard let value = scores[ArmKey(source: source, charset: charset, arm: ref)] else {
                    throw ArbiterError.missingScore(
                        source: source.key, charset: charset, arm: ref.label)
                }
                return value
            }

            func candidate(
                _ source: SourceRef, _ charset: String,
                _ armA: Arm, _ armB: Arm
            ) throws -> Candidate {
                Candidate(
                    source: source, charset: charset, armA: ArmRef(armA), armB: ArmRef(armB),
                    metrics: PairMetrics(
                        armAMeans: try means(source, charset, armA),
                        armBMeans: try means(source, charset, armB)))
            }

            var emitted: [Candidate] = []
            var families: [Family] = []
            var used = Set<String>()

            func append(_ candidate: Candidate, _ family: Family) {
                emitted.append(candidate)
                families.append(family)
                used.insert(candidate.signature)
            }

            // V — tone-only floor F vs production P on every source (§2.1 V).
            // Exhaustive, so it is seed-independent by construction.
            for source in sources.prefix(plan.validationCount) {
                append(
                    try candidate(
                        source, plan.gatingCharset, .selection(.floor),
                        .converter(.productionInverted)),
                    .validation)
            }

            // D — T(w*) vs F on every source (§2.1 D). Also exhaustive.
            for source in sources.prefix(plan.disagreementCount) {
                append(
                    try candidate(
                        source, plan.gatingCharset,
                        .selection(.toneWeighted(w: plan.disagreementToneWeight)),
                        .selection(.floor)),
                    .disagreement)
            }

            // X — the explicit converter-level ASKI-60 treatment on every
            // source. It is descriptive until the v2 validation gate passes.
            for source in sources.prefix(plan.polarityCount) {
                append(
                    try candidate(
                        source, plan.gatingCharset, .converter(.productionInverted),
                        .converter(.productionDirect)),
                    .polarity)
            }

            // The C/M candidate pools: every unordered distinct-arm pair on each
            // charset, over every source.
            func pool(charset: String) throws -> [Candidate] {
                let arms = plan.candidateArms(charset: charset)
                var out: [Candidate] = []
                for source in sources {
                    for indexA in arms.indices {
                        for indexB in (indexA + 1)..<arms.count {
                            let entry = try candidate(source, charset, arms[indexA], arms[indexB])
                            guard entry.metrics.signedDeltaMAE.isFinite else { continue }
                            out.append(entry)
                        }
                    }
                }
                return out
            }

            let gatingPool = try pool(charset: plan.gatingCharset)
            let densePool =
                plan.denseCharset == plan.gatingCharset ? [] : try pool(charset: plan.denseCharset)

            // C — the calibration ladder (§2.1 C). Split so the "≥4 on standard"
            // clause is structural rather than a lucky draw: the dense charset
            // gets its own ladder of `calibrationDenseMinimum` rungs and the
            // gating charset gets the rest.
            let denseRungs = densePool.isEmpty ? 0 : plan.calibrationDenseMinimum
            let gatingRungs = plan.calibrationCount - denseRungs
            var random = SeededRandom(seed: seed &+ 0x0C)
            let gatingLadder = ladder(
                from: gatingPool, rungs: gatingRungs, used: used, random: &random)
            guard gatingLadder.count == gatingRungs else {
                throw ArbiterError.notEnoughCandidates(
                    family: Family.calibration.rawValue, wanted: gatingRungs,
                    available: gatingLadder.count)
            }
            for entry in gatingLadder { append(entry, .calibration) }
            if denseRungs > 0 {
                let denseLadder = ladder(
                    from: densePool, rungs: denseRungs, used: used, random: &random)
                guard denseLadder.count == denseRungs else {
                    throw ArbiterError.notEnoughCandidates(
                        family: Family.calibration.rawValue, wanted: denseRungs,
                        available: denseLadder.count)
                }
                for entry in denseLadder { append(entry, .calibration) }
            }

            // M — MAD-style adversarial (§2.1 M): minimize |ΔMAE| while
            // maximizing |ΔSSIM|. Scored as a rank sum over the two objectives
            // so neither is expressed in the other's units, which they are not
            // comparable in. Ties break on the candidate signature, so the draw
            // is deterministic and the seed only breaks exact rank ties.
            let adversarialPool = gatingPool + densePool
            var adversarialRandom = SeededRandom(seed: seed &+ 0x0D)
            let adversarialDraw = adversarial(
                from: adversarialPool, count: plan.adversarialCount, used: used,
                random: &adversarialRandom)
            guard adversarialDraw.count == plan.adversarialCount else {
                throw ArbiterError.notEnoughCandidates(
                    family: Family.adversarial.rawValue, wanted: plan.adversarialCount,
                    available: adversarialDraw.count)
            }
            for entry in adversarialDraw { append(entry, .adversarial) }

            // Shuffle the unique pairs BEFORE assigning IDs. Emission order is
            // family order, so numbering it directly made pair-001...006 the V
            // family every single run — and a rater who can pick out the six
            // huge-margin validation pairs is no longer being screened by them,
            // which is the whole job of the §5.1 gate. Family now survives only
            // in key.json. The shuffle is seeded, so a run still reproduces and
            // stays auditable after the fact.
            var order = Array(emitted.indices)
            var orderRandom = SeededRandom(seed: seed &+ 0x1D)
            order.shuffle(using: &orderRandom)

            // Lay the sheet out as slots. The R repeats are NOT appended after
            // the unique trials: a fixed tail makes "the last five are repeats"
            // derivable by any rater who knows the budget, and a rater who knows
            // a trial is a repeat answers it from memory — which is the very
            // statistic the R family exists to measure, so the marker made the
            // number self-fulfilling. They are instead placed at seeded-random
            // slots inside the last `repeatDelayZone` of the sheet, which keeps
            // §3's "delayed" requirement without the marker.
            let uniqueCount = emitted.count
            let totalSlots = uniqueCount + plan.repeatCount
            let zoneStart = Int((Double(totalSlots) * (1 - plan.repeatDelayZone)).rounded(.up))
            guard totalSlots - zoneStart >= plan.repeatCount, zoneStart > 0 else {
                throw ArbiterError.notEnoughCandidates(
                    family: Family.repeats.rawValue, wanted: plan.repeatCount,
                    available: max(0, totalSlots - zoneStart))
            }
            var repeatRandom = SeededRandom(seed: seed &+ 0x0E)
            var zone = Array(zoneStart..<totalSlots)
            zone.shuffle(using: &repeatRandom)
            let repeatSlots = Set(zone.prefix(plan.repeatCount))

            var slots = [Pair?](repeating: nil, count: totalSlots)
            var uniqueIndex = 0
            for slot in 0..<totalSlots where !repeatSlots.contains(slot) {
                let index = order[uniqueIndex]
                uniqueIndex += 1
                let entry = emitted[index]
                let id = String(format: "pair-%03d", slot + 1)
                slots[slot] = Pair(
                    id: id, family: families[index], source: entry.source,
                    charset: entry.charset, armA: entry.armA, armB: entry.armB,
                    leftIsArmA: Blinding.leftIsFirstArm(seed: seed, pairID: id),
                    metrics: entry.metrics, repeatOf: nil)
            }

            // Each repeat draws its origin from the trials that appear EARLIER on
            // the sheet, so the re-presentation is always delayed relative to the
            // thing it repeats. No trial is repeated twice.
            //
            // The origin must be a UNIQUE trial, never another repeat. Repeat
            // slots fill in ascending order, so a later repeat can see an earlier
            // one among the trials before it; taking that as its origin applies
            // the side inversion twice, which makes the second repeat
            // pixel-identical to the ORIGINAL trial — reintroducing the exact
            // defect the inversion exists to prevent — and puts one underlying
            // trial on the sheet three times where §2.1 asks for five distinct
            // re-presentations. Starvation is impossible: the delay zone begins
            // well past the repeat budget, so every repeat slot has at least
            // `zoneStart - repeatCount` unique trials before it.
            var usedOrigins = Set<String>()
            for slot in repeatSlots.sorted() {
                let eligible = (0..<slot).compactMap { slots[$0] }
                    .filter { $0.repeatOf == nil && !usedOrigins.contains($0.id) }
                guard let origin = eligible.randomElement(using: &repeatRandom) else {
                    throw ArbiterError.notEnoughCandidates(
                        family: Family.repeats.rawValue, wanted: plan.repeatCount,
                        available: eligible.count)
                }
                usedOrigins.insert(origin.id)
                let id = String(format: "pair-%03d", slot + 1)
                slots[slot] = Pair(
                    id: id, family: .repeats, source: origin.source, charset: origin.charset,
                    armA: origin.armA, armB: origin.armB,
                    // The side is the NEGATION of the origin's, not a fresh coin
                    // flip. An independent draw left about half the repeats
                    // pixel-identical to the trial they repeat, and an identical
                    // re-presentation measures recognition rather than the
                    // consistency the R family exists for.
                    leftIsArmA: !origin.leftIsArmA,
                    metrics: origin.metrics, repeatOf: origin.id)
            }
            return slots.compactMap { $0 }
        }

        /// The §2.1 C construction: "arm pairs chosen (seeded) so signed ΔMAE
        /// spans roughly even steps from near-0 to the largest available
        /// margin".
        ///
        /// Read mechanically: split `[0, max|ΔMAE|]` into `rungs` equal-width
        /// bins and draw one candidate per bin, seeded. A bin with no candidate
        /// falls back to the nearest unused candidate by |ΔMAE|, so the ladder
        /// is always the requested length — a short C family would silently
        /// change what JND75 is fitted on.
        private static func ladder(
            from pool: [Candidate], rungs: Int, used: Set<String>, random: inout SeededRandom
        ) -> [Candidate] {
            guard rungs > 0 else { return [] }
            let available = pool.filter { !used.contains($0.signature) }
            guard !available.isEmpty else { return [] }
            let magnitudes = available.map { abs($0.metrics.signedDeltaMAE) }
            let maximum = magnitudes.max() ?? 0
            guard maximum > 0 else { return Array(available.prefix(rungs)) }

            var taken = Set<String>()
            var out: [Candidate] = []
            let width = maximum / Double(rungs)
            for rung in 0..<rungs {
                let low = Double(rung) * width
                let high = rung == rungs - 1 ? maximum * 1.000_001 : Double(rung + 1) * width
                let inBin = available.filter {
                    let magnitude = abs($0.metrics.signedDeltaMAE)
                    return magnitude >= low && magnitude < high && !taken.contains($0.signature)
                }
                let target = (low + high) / 2
                let chosen: Candidate?
                if inBin.isEmpty {
                    chosen =
                        available
                        .filter { !taken.contains($0.signature) }
                        .min {
                            abs(abs($0.metrics.signedDeltaMAE) - target)
                                < abs(abs($1.metrics.signedDeltaMAE) - target)
                        }
                } else {
                    chosen = inBin.sorted { $0.signature < $1.signature }
                        .randomElement(using: &random)
                }
                guard let chosen else { continue }
                taken.insert(chosen.signature)
                out.append(chosen)
            }
            return out
        }

        /// The §2.1 M construction: "minimize |ΔMAE| while maximizing |ΔSSIM|".
        ///
        /// Both objectives are converted to ranks over the same candidate pool
        /// and summed. Ranks rather than a ratio or a weighted difference,
        /// because |ΔMAE| and |ΔSSIM| are in incomparable units and any fixed
        /// exchange rate between them would be a free parameter nobody
        /// pre-registered.
        private static func adversarial(
            from pool: [Candidate], count: Int, used: Set<String>, random: inout SeededRandom
        ) -> [Candidate] {
            guard count > 0 else { return [] }
            let available = pool.filter {
                !used.contains($0.signature) && $0.metrics.delta(.ssim).isFinite
            }
            guard !available.isEmpty else { return [] }

            let byMAE = available.indices.sorted {
                let left = abs(available[$0].metrics.signedDeltaMAE)
                let right = abs(available[$1].metrics.signedDeltaMAE)
                return left == right
                    ? available[$0].signature < available[$1].signature : left < right
            }
            let bySSIM = available.indices.sorted {
                let left = abs(available[$0].metrics.delta(.ssim))
                let right = abs(available[$1].metrics.delta(.ssim))
                return left == right
                    ? available[$0].signature < available[$1].signature : left > right
            }
            var rank = [Int](repeating: 0, count: available.count)
            for (position, index) in byMAE.enumerated() { rank[index] += position }
            for (position, index) in bySSIM.enumerated() { rank[index] += position }

            let ordered = available.indices.sorted {
                rank[$0] == rank[$1]
                    ? available[$0].signature < available[$1].signature : rank[$0] < rank[$1]
            }
            _ = random.next()  // keep the seed stream advancing with the family
            return ordered.prefix(count).map { available[$0] }
        }
    }
}
