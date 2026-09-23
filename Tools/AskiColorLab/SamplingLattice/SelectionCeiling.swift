import AskiToolSupport
import Foundation
import simd

@_spi(AskiResearch) import Aski

/// Measures how far the production glyph pick sits from the loss-optimal pick,
/// and splits that distance into the two things that can cause it
/// (2026-08-19 selection-optimality-gap note).
///
///   totalGap = (prod − optGlobal) / prod      how far the pick is from optimal
///   rankGap  = (prod − optPool)   / prod      cost of mis-ranking INSIDE the pool
///   poolGap  = (optPool − optGlobal) / prod   cost of the optimum never entering the pool
///
/// `totalGap == rankGap + poolGap` by construction, and the split is the point:
/// it separates "the descriptor ranked badly" from "the descriptor was never
/// shown the right answer."
///
/// Several oracles are run because the choice of oracle is itself contested. GMSD
/// is the metric every archived descriptor verdict was decided by, so it is what
/// makes this run readable against the record. HaarPSI is the record's existing
/// cross-check. MAE is included because both are gradient/wavelet structure
/// metrics — i.e. NOT a disjoint pair — and because Ding, Ma, Wang & Simoncelli
/// (IJCV 2021) rank GMSD last of 11 full-reference metrics used as an
/// optimization objective and diagnose it as luminance-blind, while finding plain
/// MAE competitive. RMSE and single-scale SSIM were added by the ASKI-27 oracle
/// audit. A gap that survives all of them is not a metric artifact.
///
/// The oracle that defines "optimal" here is the one the ASKI-27 audit adopted as
/// the house oracle; the others are kept so every arm stays readable against the
/// record it is being compared with. See `ReferenceRecovery` for the screen that
/// decides which of them is allowed to define an optimum at all.
enum SelectionCeiling {

    /// Higher-is-better oracles need their gap arithmetic mirrored.
    enum Polarity: Sendable { case lowerIsBetter, higherIsBetter }

    /// The candidate oracles the ASKI-27 audit screens. `gmsd` and `haarPSI` are
    /// the record's incumbents; `mae`, `rmse` and `ssim` are the candidates the
    /// audit added.
    ///
    /// MS-SSIM is deliberately absent even though Ding et al. name it one of the
    /// two dominant robust objectives: its five-scale pyramid halves the image
    /// four times and needs roughly 161px a side, against a 24px scoring
    /// footprint, so it cannot be evaluated here at all. Single-scale SSIM is the
    /// reachable stand-in. LPIPS/DISTS and the other deep metrics are out for the
    /// same reason at larger magnitude — their receptive fields are wider than
    /// the whole cell.
    ///
    /// `mae` and `rmse` are **polarity-sensitive**: they compare absolute tone,
    /// so both sides must be in one convention. Everything here is in the
    /// matcher's own — `GlyphRaster.luma` is ink-high, and the pre-filter maps
    /// high source L to high ink density.
    enum Oracle: String, Sendable, CaseIterable {
        case gmsd
        case haarPSI
        case mae
        case rmse
        case ssim

        var polarity: Polarity {
            switch self {
            case .gmsd, .mae, .rmse: return .lowerIsBetter
            case .haarPSI, .ssim: return .higherIsBetter
            }
        }

        func score(_ candidate: [Float], _ source: [Float], footprint: Int) -> Double {
            switch self {
            case .gmsd:
                return GMSD.gmsd(candidate, source, width: footprint, height: footprint)
            case .haarPSI:
                return HaarPSI.haarPSI(candidate, source, width: footprint, height: footprint)
            case .mae:
                guard candidate.count == source.count, !candidate.isEmpty else { return .nan }
                var total = 0.0
                for index in candidate.indices {
                    total += Double(abs(candidate[index] - source[index]))
                }
                return total / Double(candidate.count)
            case .rmse:
                guard candidate.count == source.count, !candidate.isEmpty else { return .nan }
                var total = 0.0
                for index in candidate.indices {
                    let delta = Double(candidate[index] - source[index])
                    total += delta * delta
                }
                return (total / Double(candidate.count)).squareRoot()
            case .ssim:
                // Single-scale, windowless SSIM over the whole cell — the same
                // implementation the ShapeResidual battery already carries as an
                // oracle. Luminance-aware (it keeps the mean term) but not
                // separable, which is the axis the audit is testing.
                return Double(
                    StructuralSimilarity.ssim(
                        candidate, source, width: footprint, height: footprint))
            }
        }
    }

    /// A realizable selector the census scores. Every arm picks a glyph index
    /// from the same candidate set for the same cell, and is scored through one
    /// identical rendering path — so two arms differ ONLY in the term under
    /// test, which is what makes the §5 ratios readable (rule §2.4).
    enum Arm: Sendable, Hashable {
        /// P — whatever the real converter picked, at its own `density: 0`.
        case production
        /// F — tone-only floor on PRODUCTION's tone pair (`brightnessValues`
        /// vs `stats.adjustedL`), single matcher-convention polarity.
        case floor
        /// F as built before prerequisite 3 (`rawDensityValues` vs mean block
        /// luma). Kept computable so the R8 before/after audit is runnable.
        case legacyFloor
        /// T — `distance + w * toneDelta²` over the full pool.
        case toneWeighted(w: Float)
        /// K — production's selector at a lab-supplied pool width.
        case poolWidth(topK: Int)
        /// §6.1 — prune to the `shapeK` shape-nearest, rank survivors by tone.
        case lexicographic(shapeK: Int)
        /// §6.2 — z-normalize both loss distributions, then combine at `w`.
        case zNormalized(w: Float)

        /// Stable CSV label. The rule selects rows by this string.
        var name: String {
            switch self {
            case .production: return "P"
            case .floor: return "F"
            case .legacyFloor: return "F_legacy"
            case .toneWeighted: return "T"
            case .poolWidth: return "K"
            case .lexicographic: return "lex"
            case .zNormalized: return "znorm"
            }
        }

        /// The `w` column. Nil for arms that take no weight — rendered as an
        /// empty cell, never `0`, because `w = 0` is a swept anchor (§2.5).
        var w: Float? {
            switch self {
            case .toneWeighted(let w), .zNormalized(let w): return w
            default: return nil
            }
        }

        /// The `topK` column. Carries arm K's pool width and, for the
        /// lexicographic arm, its `shapeK` — both are candidate-count prune
        /// widths, which is what the column means.
        var topK: Int? {
            switch self {
            case .poolWidth(let k), .lexicographic(let k): return k
            default: return nil
            }
        }
    }

    /// Mean and standard deviation of a loss distribution, for the §6.2 arm.
    struct LossStats: Sendable {
        var shapeMean = 0.0
        var shapeDeviation = 0.0
        var toneMean = 0.0
        var toneDeviation = 0.0
    }

    /// One CSV row: one arm's mean score under every oracle, for one
    /// (corpus, charset, arm, w, topK) point. **The frozen rule is applied to
    /// this and to nothing else** (ASTSK-31 discipline).
    struct ArmRow: Sendable {
        let corpus: String
        let charset: String
        let arm: String
        let w: Float?
        let topK: Int?
        let columns: Int
        let oversample: Int
        let footprint: Int
        let stride: Int
        let cells: Int
        let glyphs: Int
        let means: [Oracle: Double]
        /// Wall seconds spent in this arm's SELECTION for this census — oracle
        /// scoring excluded. Median-of-3 is orchestrated across runs (§2.5), so
        /// one run emits one number.
        let selectionWallSeconds: Double
        let gitSHA: String
        /// The `RenderingOptions.shapeQueryPolarity` the converter ran under
        /// (`PolarityGate.label`). Recorded per row because the knob changes the
        /// converter and therefore every measured arm; without it a `direct`
        /// census is indistinguishable on disk from the default one (ASKI-60).
        let shapeQueryPolarity: String
    }

    /// Everything one `run` produces: the stdout table's rows, unchanged, plus
    /// the machine-readable arm census.
    struct Census: Sendable {
        let rows: [Row]
        let armRows: [ArmRow]
    }

    /// The sweep grids (§2.5). Empty grids switch an arm off; the two baselines
    /// P and F always run, because every §5 ratio divides by one of them.
    struct Sweeps: Sendable {
        var toneWeights: [Float] = []
        /// Arm K's grid for charsets with no scoped entry of their own.
        var topKs: [Int] = []
        /// Per-charset arm-K grids. The frozen grids are ASYMMETRIC — §2.5 runs
        /// `{12,18,24,36,48,64,95}` on `standard` and
        /// `{12,18,24,36,48,64,128,256}` on `braille` — and a single global list
        /// cannot express that without running `95` on `braille`, a point that
        /// is not in its grid. Calibration selects `topK*` from the CSV, so an
        /// unregistered point is a live hazard.
        var topKsByCharset: [String: [Int]] = [:]
        var lexShapeKs: [Int] = []
        var zNormWeights: [Float] = []
        /// Compute arm F the pre-prerequisite-3 way as well (readout R8).
        var includeLegacyFloor = false

        init() {}

        /// The requested arm-K grid for one charset: its own if it has one,
        /// otherwise the global list.
        func topKs(for charset: String) -> [Int] {
            topKsByCharset[charset] ?? topKs
        }

        /// The arm-K arms actually run for one charset, already reduced to
        /// distinct EFFECTIVE pool widths.
        func poolWidthArms(for charset: String, glyphCount: Int) -> [Arm] {
            effectivePoolWidths(requested: topKs(for: charset), glyphCount: glyphCount)
                .map { Arm.poolWidth(topK: $0) }
        }
    }

    /// Requested pool widths reduced to the distinct widths the matcher will
    /// actually use, in order of first appearance.
    ///
    /// `findBestScored` prunes to `min(topK, count)`, so on a 95-glyph set a
    /// requested `128` and a requested `256` are the SAME arm as `95`. Emitting
    /// them as separate CSV rows at their requested widths would put identical
    /// results under labels describing pools the run never used — and §5.2 reads
    /// `topK*` straight out of that column. Record what ran.
    static func effectivePoolWidths(requested: [Int], glyphCount: Int) -> [Int] {
        var out: [Int] = []
        for width in requested {
            let effective = max(1, min(width, glyphCount))
            if !out.contains(effective) { out.append(effective) }
        }
        return out
    }

    struct Row: Sendable {
        let charset: String
        let oracle: String
        let oversample: Int
        let cells: Int
        let glyphs: Int
        let poolWidth: Double
        let prod: Double
        let optPool: Double
        let optGlobal: Double
        let toneOnly: Double
        let meanRank: Double
        let totalGapPercent: Double
        let rankGapPercent: Double
        let poolGapPercent: Double
        let exactOptimalPercent: Double
        let optInPoolPercent: Double
    }

    struct Accumulator {
        var prod = 0.0
        var optPool = 0.0
        var optGlobal = 0.0
        var toneOnly = 0.0
        var rank = 0.0
        var poolWidth = 0.0
        var exactOptimal = 0
        var optInPool = 0
        var cells = 0
    }

    /// The pool width production selects at. The census builds its converter
    /// with no `options:`, so `RenderingOptions.default` applies and
    /// `density = 0` gives `topK = 12 + round(0 * 24)`. Arm P re-runs the
    /// matcher at exactly this width, which is why arm K's `topK = 12` row and
    /// arm P are the same selector.
    static let productionPoolWidth = 12

    /// Below this |mean production score| the gap percentages are degenerate and
    /// are reported as `nan` rather than as an unbounded ratio.
    static let degenerateScoreFloor = 1e-6

    static func characterSet(named name: String) throws -> StandardCharacterSet {
        switch name {
        case "standard": return .standard
        case "minimal": return .minimal
        case "blocks": return .blocks
        case "dots": return .dots
        case "lines": return .lines
        case "diagonal": return .diagonal
        case "cross": return .cross
        case "diamond": return .diamond
        case "mixed": return .mixed
        case "braille": return .braille
        default:
            throw SelectionCeilingError.unknownCharacterSet(name)
        }
    }

    // MARK: - Arm selectors (pure: candidates in, index out)

    /// Prerequisite 5. Production picks are recovered by `firstIndex(of:)`, so a
    /// charset holding a repeated character collapses two indices onto one and
    /// mis-attributes every pick of the second to the first — a silent, uniform
    /// corruption of `meanRank` and of every arm ratio. Fail the run instead.
    static func assertUniqueGlyphs(_ glyphs: [Character], charset: String) throws {
        var seen = Set<Character>()
        for glyph in glyphs where !seen.insert(glyph).inserted {
            throw SelectionCeilingError.duplicateGlyph(charset: charset, glyph: glyph)
        }
    }

    /// Arm F (prerequisite 3). Argmin over the FULL charset of
    /// `abs(brightnessValues[i] − adjustedL)`.
    ///
    /// This is production's own tone pair — the quantities its brightness
    /// pre-filter compares — so P, F and T differ only in the scored term, which
    /// is the condition that makes the §5.1 conjunction readable. The floor as
    /// originally built compared `rawDensityValues` (absolute ink area) against
    /// the mean of the native `block.luma`, a *related but different* pair;
    /// `legacyFloorPick` keeps that computable for the R8 audit.
    ///
    /// Single polarity, matcher convention: `GlyphRaster.luma` is ink-high and
    /// the pre-filter maps high source L to high ink density. Trying both
    /// polarities and keeping the better is harmless under the inversion-
    /// invariant oracles but hands the floor a free degree of freedom under MAE,
    /// which is polarity-sensitive — and MAE is the verdict oracle.
    static func floorPick(adjustedL: Float, brightnessValues: [Float]) -> Int {
        nearest(to: adjustedL, in: brightnessValues)
    }

    /// Arm F as built before prerequisite 3, retained only for readout R8.
    static func legacyFloorPick(meanBlockLuma: Float, rawDensityValues: [Float]) -> Int {
        nearest(to: meanBlockLuma, in: rawDensityValues)
    }

    private static func nearest(to query: Float, in values: [Float]) -> Int {
        var best = 0
        var bestError = Float.infinity
        for index in values.indices {
            let error = abs(values[index] - query)
            if error < bestError {
                bestError = error
                best = index
            }
        }
        return best
    }

    /// Arm K. Production's selector — prune to the `topK` brightness-nearest,
    /// then argmin of pure shape distance — at a lab-supplied width.
    ///
    /// Calls the public `findBestScored` directly rather than going through
    /// `RenderingOptions.density`, whose reachable range is `topK ∈ [12, 36]`
    /// and cannot express the full pool at 95 (`standard`) or 256 (`braille`)
    /// that ASKI-28 AC#1 requires. At `topK = 12` this IS production.
    static func poolWidthPick(
        queryLanes: [SIMD4<Float>],
        adjustedL: Float,
        candidateLanes: [SIMD4<Float>],
        brightnessValues: [Float],
        topK: Int
    ) -> Int {
        ShapeMatching.findBestScored(
            queryLanes: queryLanes,
            queryBrightness: adjustedL,
            candidateBrightness: brightnessValues,
            candidateLanes: candidateLanes,
            topK: max(1, min(topK, brightnessValues.count))
        ).index
    }

    /// Arm T. `distance + w · toneDelta²`, scored over the FULL pool.
    ///
    /// The full pool is deliberate (rule §2.4): it holds pool width constant
    /// across the whole `w` sweep, so the only thing moving is the term under
    /// test.
    ///
    /// The tone pair fed here is PRODUCTION's — `brightnessValues` against
    /// `adjustedL` — not the occupancy path's `rawDensityValues`-derived
    /// composited tones, for the same P/F/T comparability reason as arm F.
    static func toneWeightedPick(
        queryLanes: [SIMD4<Float>],
        adjustedL: Float,
        candidateLanes: [SIMD4<Float>],
        brightnessValues: [Float],
        toneWeight: Float
    ) -> Int {
        let distances = shapeDistances(
            queryLanes: queryLanes, candidateLanes: candidateLanes)
        let weight = max(0, toneWeight)
        return distances.indices.min {
            let leftToneDelta = abs(brightnessValues[$0] - adjustedL)
            let rightToneDelta = abs(brightnessValues[$1] - adjustedL)
            let leftScore = distances[$0] + weight * leftToneDelta * leftToneDelta
            let rightScore = distances[$1] + weight * rightToneDelta * rightToneDelta
            if leftScore != rightScore { return leftScore < rightScore }
            if leftToneDelta != rightToneDelta { return leftToneDelta < rightToneDelta }
            return $0 < $1
        } ?? 0
    }

    /// §6.1, exploratory and non-gating. Prune to the `shapeK` shape-nearest
    /// candidates, then rank the survivors by tone — the inverse of production's
    /// prune-by-tone-then-rank-by-shape, and a lexicographic order rather than a
    /// sum of two incomparable scores.
    ///
    /// The grid is count-based (§2.5) so it is scale-free, and its endpoints are
    /// anchors: `shapeK = 1` is production's shape argmin modulo tie-break, and
    /// `shapeK = glyphCount` is arm F.
    static func lexicographicPick(
        queryLanes: [SIMD4<Float>],
        adjustedL: Float,
        candidateLanes: [SIMD4<Float>],
        brightnessValues: [Float],
        shapeK: Int
    ) -> Int {
        let distances = shapeDistances(queryLanes: queryLanes, candidateLanes: candidateLanes)
        let width = max(1, min(shapeK, brightnessValues.count))
        // Prune: shape ascending, ties by index ascending — the matcher's own
        // tie rule.
        let survivors = distances.indices
            .sorted { distances[$0] == distances[$1] ? $0 < $1 : distances[$0] < distances[$1] }
            .prefix(width)
        // Rank: tone ascending, ties by GLYPH INDEX ascending — arm F's tie rule,
        // not the survivor order's. At `shapeK = glyphCount` every candidate
        // survives, so the tie policy is the only thing left deciding the pick;
        // breaking ties by shape order there would make §2.5's
        // "shapeK = glyphCount ≡ F" anchor false. The frozen grid reaches that
        // endpoint on the 4- and 5-glyph sparse sets at shapeK = 6.
        var best = survivors.first ?? 0
        var bestError = Float.infinity
        for index in survivors.sorted() {
            let error = abs(brightnessValues[index] - adjustedL)
            if error < bestError {
                bestError = error
                best = index
            }
        }
        return best
    }

    /// §6.2, exploratory and non-gating. Z-normalize the shape-loss and
    /// tone-loss distributions, then combine as `zShape + w · zTone`.
    ///
    /// This replaces the fixed `toneErrorWeight = 50`, whose own doc comment
    /// admits it only puts the terms "into the same rough magnitude range". The
    /// defining property is scale-freedom: rescaling either loss distribution
    /// must not move the pick.
    ///
    /// `stats` supplies POOLED per-charset moments (the census passes them, per
    /// §6.2's "per-charset normalization"). Passing `nil` normalizes against the
    /// cell's own candidate distribution instead, which is scale-free too and is
    /// what the unit tests exercise. A zero spread degenerates to the unweighted
    /// term rather than dividing by zero and sorting NaNs arbitrarily.
    static func zNormalizedPick(
        queryLanes: [SIMD4<Float>],
        adjustedL: Float,
        candidateLanes: [SIMD4<Float>],
        brightnessValues: [Float],
        toneWeight: Float,
        stats: LossStats? = nil
    ) -> Int {
        let scores = zNormalizedScores(
            queryLanes: queryLanes, adjustedL: adjustedL, candidateLanes: candidateLanes,
            brightnessValues: brightnessValues, toneWeight: toneWeight, stats: stats)
        var best = 0
        var bestScore = Double.infinity
        for index in scores.indices where scores[index] < bestScore {
            bestScore = scores[index]
            best = index
        }
        return best
    }

    /// The §6.2 combined score per candidate. Split out from `zNormalizedPick`
    /// so a degenerate distribution can be asserted to produce finite scores
    /// rather than NaNs that a `<` comparison would silently order.
    static func zNormalizedScores(
        queryLanes: [SIMD4<Float>],
        adjustedL: Float,
        candidateLanes: [SIMD4<Float>],
        brightnessValues: [Float],
        toneWeight: Float,
        stats: LossStats? = nil
    ) -> [Double] {
        let distances = shapeDistances(queryLanes: queryLanes, candidateLanes: candidateLanes)
        let tones = brightnessValues.map { toneLoss($0, adjustedL) }
        let moments = stats ?? cellLossStats(distances: distances, tones: tones)

        func normalize(_ value: Float, _ mean: Double, _ deviation: Double) -> Double {
            deviation > 0 ? (Double(value) - mean) / deviation : Double(value) - mean
        }

        let weight = Double(max(0, toneWeight))
        return distances.indices.map { index in
            normalize(distances[index], moments.shapeMean, moments.shapeDeviation)
                + weight * normalize(tones[index], moments.toneMean, moments.toneDeviation)
        }
    }

    /// The tone LOSS, matching arm T's local equation: `toneDelta²`, weighted
    /// as `toneWeight * toneDelta * toneDelta`.
    ///
    /// §6.2 exists to replace the fixed scale ON THAT LOSS, so it must z-score
    /// the squared form. Normalizing `|toneDelta|` would rescale a different
    /// quantity and break comparability with T at the same `w` — and it is not a
    /// harmless monotone substitution, because z-scoring is affine in the value
    /// and squaring changes the distribution's spread, which reorders picks.
    static func toneLoss(_ candidateBrightness: Float, _ adjustedL: Float) -> Float {
        let delta = candidateBrightness - adjustedL
        return delta * delta
    }

    /// The 60D squared-L2 distance from `queryLanes` to every candidate — the
    /// same accumulation `findBestScored` performs, run over the full set.
    static func shapeDistances(
        queryLanes: [SIMD4<Float>],
        candidateLanes: [SIMD4<Float>]
    ) -> [Float] {
        let lanesPerCharacter = StandardCharacterSet.lanesPerCharacter
        let count = candidateLanes.count / lanesPerCharacter
        var out = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let offset = index * lanesPerCharacter
            var distance: Float = 0
            for lane in 0..<lanesPerCharacter {
                let delta = queryLanes[lane] - candidateLanes[offset + lane]
                distance += simd_dot(delta, delta)
            }
            out[index] = distance
        }
        return out
    }

    private static func cellLossStats(distances: [Float], tones: [Float]) -> LossStats {
        var stats = LossStats()
        var accumulator = LossAccumulator()
        for index in distances.indices {
            accumulator.add(shape: distances[index], tone: tones[index])
        }
        stats = accumulator.resolved()
        return stats
    }

    /// Streaming moments for the §6.2 pooled statistics.
    struct LossAccumulator {
        private var shapeSum = 0.0
        private var shapeSquares = 0.0
        private var toneSum = 0.0
        private var toneSquares = 0.0
        private var count = 0

        mutating func add(shape: Float, tone: Float) {
            let s = Double(shape), t = Double(tone)
            shapeSum += s
            shapeSquares += s * s
            toneSum += t
            toneSquares += t * t
            count += 1
        }

        func resolved() -> LossStats {
            guard count > 0 else { return LossStats() }
            let inverse = 1.0 / Double(count)
            let shapeMean = shapeSum * inverse
            let toneMean = toneSum * inverse
            // Population variance; clamped at zero so float cancellation on a
            // degenerate distribution cannot produce a NaN deviation.
            let shapeVariance = max(0, shapeSquares * inverse - shapeMean * shapeMean)
            let toneVariance = max(0, toneSquares * inverse - toneMean * toneMean)
            return LossStats(
                shapeMean: shapeMean, shapeDeviation: shapeVariance.squareRoot(),
                toneMean: toneMean, toneDeviation: toneVariance.squareRoot())
        }
    }

    /// Back-compatible entry point: the stdout table only, no arm census.
    static func run(
        columns: Int,
        oversamples: [Int],
        charsetNames: [String],
        footprint: Int,
        stride: Int,
        corpus: String?
    ) throws -> [Row] {
        try census(
            columns: columns, oversamples: oversamples, charsetNames: charsetNames,
            footprint: footprint, stride: stride, corpus: corpus,
            sweeps: Sweeps(), gitSHA: ""
        ).rows
    }

    /// The corpus label recorded in every CSV row. The audit's standing rule 4
    /// is that no gap or headroom figure is quotable without naming its corpus,
    /// and the two this battery runs disagree by up to 10 gap points — so the
    /// label travels with the number rather than with the invocation.
    static func corpusLabel(_ corpus: String?) -> String {
        let path = corpus ?? SteerableBattery.defaultCorpusRelativePath
        let url = URL(fileURLWithPath: path)
        // Corpora are laid out as `<name>/assets`, so the name is one level up.
        let last = url.lastPathComponent
        return last == "assets" ? url.deletingLastPathComponent().lastPathComponent : last
    }

    static func census(
        columns: Int,
        oversamples: [Int],
        charsetNames: [String],
        footprint: Int,
        stride: Int,
        corpus: String?,
        sweeps: Sweeps,
        gitSHA: String,
        shapeQueryPolarity: ShapeQueryPolarity = .inverted
    ) throws -> Census {
        // Defaults to the 3072px `nasa-steerable-v1` corpus — the same native
        // side `ReferenceRecovery` resolves its cell block from, so the screen
        // and the ceiling describe one regime. `RealFixture.load`'s own nil
        // default is the 2048px `nasa-structure-v1` corpus the ShapeResidual
        // battery uses, and silently inheriting it is what made the companion
        // note's reproduce command run a different corpus than it reported.
        let fixtures = try SteerableBattery.naturals(corpusDirectory: corpus)
        let corpusName = corpusLabel(corpus)
        var rows: [Row] = []
        var armRows: [ArmRow] = []

        for charsetName in charsetNames {
            let characterSet = try Self.characterSet(named: charsetName)
            let glyphs = characterSet.characters
            // Prerequisite 5: fail before scoring, not after mis-attributing.
            try Self.assertUniqueGlyphs(glyphs, charset: charsetName)
            let density = characterSet.rawDensityValues
            let brightness = characterSet.brightnessValues
            let candidateLanes = characterSet.shapeVectorLanes
            // The arms this census scores. P and F always run: every ratio in
            // §5 divides by one of them.
            var arms: [Arm] = [.production, .floor]
            if sweeps.includeLegacyFloor { arms.append(.legacyFloor) }
            arms += sweeps.toneWeights.map { Arm.toneWeighted(w: $0) }
            // Effective widths, so the CSV's `topK` column names the pool that
            // actually ran and a clamped duplicate is not re-run.
            arms += sweeps.poolWidthArms(for: charsetName, glyphCount: glyphs.count)
            arms += sweeps.lexShapeKs.map { Arm.lexicographic(shapeK: $0) }
            arms += sweeps.zNormWeights.map { Arm.zNormalized(w: $0) }
            // Every candidate is rastered once at the scoring footprint. Keep
            // the archived ASTSK-35/42 candidate-raster convention so this run
            // stays directly comparable after that dedicated arm is removed.
            let rasters = glyphs.map {
                GlyphRaster.luma(character: $0, width: footprint, height: footprint)
            }

            for oversample in oversamples {
                var accumulators: [Oracle: Accumulator] = [:]
                for oracle in Oracle.allCases { accumulators[oracle] = Accumulator() }
                // Per-arm running sums, one per oracle, plus the selection-only
                // wall clock (§2.5 cost; oracle scoring is deliberately outside
                // it, since every arm pays the identical oracle bill).
                var armSums: [Arm: [Oracle: Double]] = [:]
                // Counted per (arm, oracle), mirroring `Accumulator.cells`: an
                // oracle that could not score a cell contributes to neither the
                // numerator nor the denominator, so a partial sum is never
                // divided by a full count.
                var armCounts: [Arm: [Oracle: Int]] = [:]
                var armSeconds: [Arm: Double] = [:]
                for arm in arms {
                    armSums[arm] = Dictionary(
                        uniqueKeysWithValues: Oracle.allCases.map { ($0, 0.0) })
                    armCounts[arm] = Dictionary(
                        uniqueKeysWithValues: Oracle.allCases.map { ($0, 0) })
                    armSeconds[arm] = 0
                }
                // §6.2 pools its normalization moments across the charset's
                // whole census, so they are gathered in a cheap descriptor-only
                // pre-pass before any oracle runs.
                var zStats: LossStats?
                // First (recovered, rendered) glyph pair where arm P's re-run
                // selector disagreed with the converter, if any.
                var productionDivergence: (charset: String, recovered: Character, rendered: Character)?

                // ASKI-60: the ONLY thing the polarity option may touch. The
                // arms, the pool rule, the oracle panel and the scoring path are
                // untouched, so an archived verdict re-run under `.direct`
                // differs from its record in the query convention alone.
                var options = RenderingOptions.default
                options.shapeQueryPolarity = shapeQueryPolarity
                let converter = ASCIIConverter(
                    characterSet: characterSet,
                    palette: BuiltInPalette.monochrome,
                    options: options,
                    colorSpace: .sRGB,
                    oversample: oversample
                )

                // §6.2 pre-pass: pooled per-charset loss moments. Descriptor
                // arithmetic only — no oracle, no raster — so it is negligible
                // beside the census it precedes, and the exploratory arms are
                // sparse-charset readouts (R7) where the candidate set is tiny.
                if !sweeps.zNormWeights.isEmpty {
                    var accumulator = LossAccumulator()
                    for fixture in fixtures {
                        guard
                            let queries = converter.cellQueryDescriptors(
                                fixture.image, columns: columns)
                        else { continue }
                        for row in Swift.stride(from: 0, to: queries.rows, by: stride) {
                            for col in Swift.stride(from: 0, to: queries.columns, by: stride) {
                                let tone = queries.adjustedL(row: row, column: col)
                                let distances = shapeDistances(
                                    queryLanes: queries.lanes(row: row, column: col),
                                    candidateLanes: candidateLanes)
                                for index in distances.indices {
                                    accumulator.add(
                                        shape: distances[index],
                                        tone: toneLoss(brightness[index], tone))
                                }
                            }
                        }
                    }
                    zStats = accumulator.resolved()
                }

                for fixture in fixtures {
                    let grid = converter.convert(fixture.image, columns: columns)
                    let gridRows = grid.rows, gridCols = grid.columns
                    guard gridRows > 0, gridCols > 0 else { continue }
                    // Prerequisite 0. The per-cell 60D query and tone the matcher
                    // itself scored — the inputs arms F/T/K/lex/znorm all take as
                    // parameters. Re-deriving them here is what inverted the
                    // polarity convention on the first run of this probe.
                    let queries = converter.cellQueryDescriptors(fixture.image, columns: columns)
                    // The REAL pool, read back from the matcher. Rebuilding it by
                    // hand gets the polarity convention wrong (the pre-filter
                    // compares source OKLab L against glyph ink density), which is
                    // exactly how the first version of this probe produced a
                    // structurally impossible negative rankGap.
                    let pools = converter.rankedCandidateIndices(
                        fixture.image, columns: columns, limit: glyphs.count)
                    guard pools.count == gridRows else { continue }
                    // The REAL lattice, for the same reason. Since ASKI-65 it
                    // agrees with the equal native `rows*cols` partition, but
                    // reading it back keeps that checked rather than assumed:
                    // when the two diverged, scoring the equal partition charged
                    // each glyph to a patch displaced by a function of
                    // oversample, which confounded the support sweep.
                    guard let geometry = converter.samplingGeometry(fixture.image, columns: columns),
                        geometry.rows == gridRows, geometry.columns == gridCols
                    else { continue }

                    for row in Swift.stride(from: 0, to: gridRows, by: stride) {
                        for col in Swift.stride(from: 0, to: gridCols, by: stride) {
                            guard
                                let block = SampledSource.lumaBlock(
                                    fixture, cellRow: row, cellCol: col, geometry: geometry),
                                block.width >= 2, block.height >= 2
                            else { continue }
                            let source = LumaResample.resample(
                                block.luma, srcWidth: block.width, srcHeight: block.height,
                                dstWidth: footprint, dstHeight: footprint)
                            let picked = grid.cells[row][col].character
                            guard let pickIndex = glyphs.firstIndex(of: picked) else { continue }
                            let pool = pools[row][col]
                            guard !pool.isEmpty else { continue }

                            let meanLuma = block.luma.reduce(0, +) / Float(block.luma.count)
                            // The matcher's own query for THIS cell, or nil if
                            // the reflection is unavailable (non-logPolar) or
                            // does not cover the cell. Arms that need it are
                            // skipped for the cell rather than fed a guess.
                            let descriptorSupported = queries?.supportsShapeDescriptor ?? false
                            let query: (lanes: [SIMD4<Float>], tone: Float)? = {
                                guard let queries, row < queries.rows, col < queries.columns
                                else { return nil }
                                return (
                                    queries.lanes(row: row, column: col),
                                    queries.adjustedL(row: row, column: col)
                                )
                            }()
                            // Each arm's pick for this cell. Timed per arm and
                            // excluding oracle work, so the §5.2 cost cap
                            // compares selection against selection.
                            //
                            // Every arm RUNS its selector inside its own timed
                            // region, including the two baselines. Assigning an
                            // already-computed index would have made P and F
                            // report clock and switch overhead while K reported
                            // real work — the cost cap only ever compares K rows
                            // against K rows, so no verdict moved, but a column
                            // has to mean one thing in every row of it.
                            var picks: [Arm: Int] = [:]
                            for arm in arms {
                                let started = DispatchTime.now().uptimeNanoseconds
                                let index: Int?
                                switch arm {
                                case .production:
                                    // Production's own selector, re-run through
                                    // the lab's path at production's width. The
                                    // converter's pick stays the authority for
                                    // scoring; this call is timed and then
                                    // CHECKED against it, so a divergence fails
                                    // the run instead of quietly redefining what
                                    // arm P measures.
                                    if let query, descriptorSupported {
                                        let recovered = poolWidthPick(
                                            queryLanes: query.lanes,
                                            adjustedL: query.tone,
                                            candidateLanes: candidateLanes,
                                            brightnessValues: brightness,
                                            topK: productionPoolWidth)
                                        if recovered != pickIndex, productionDivergence == nil {
                                            productionDivergence = (
                                                charsetName, glyphs[recovered], glyphs[pickIndex]
                                            )
                                        }
                                    }
                                    index = pickIndex
                                case .floor:
                                    // Prerequisite 3: arm F on production's tone
                                    // pair. See `floorPick` for why the shipped
                                    // `rawDensityValues`-vs-mean-luma pair was
                                    // wrong for a baseline the PASS conjunction
                                    // divides by. The legacy fallback preserves
                                    // this arm's never-skipped semantics when the
                                    // reflection is unavailable.
                                    index =
                                        query.map {
                                            floorPick(
                                                adjustedL: $0.tone, brightnessValues: brightness)
                                        }
                                        ?? legacyFloorPick(
                                            meanBlockLuma: meanLuma, rawDensityValues: density)
                                case .legacyFloor:
                                    index = legacyFloorPick(
                                        meanBlockLuma: meanLuma, rawDensityValues: density)
                                case .toneWeighted(let w):
                                    index = query.map {
                                        toneWeightedPick(
                                            queryLanes: $0.lanes,
                                            adjustedL: $0.tone,
                                            candidateLanes: candidateLanes,
                                            brightnessValues: brightness, toneWeight: w)
                                    }
                                case .poolWidth(let topK):
                                    index = query.map {
                                        poolWidthPick(
                                            queryLanes: $0.lanes,
                                            adjustedL: $0.tone,
                                            candidateLanes: candidateLanes,
                                            brightnessValues: brightness, topK: topK)
                                    }
                                case .lexicographic(let shapeK):
                                    index = query.map {
                                        lexicographicPick(
                                            queryLanes: $0.lanes,
                                            adjustedL: $0.tone,
                                            candidateLanes: candidateLanes,
                                            brightnessValues: brightness, shapeK: shapeK)
                                    }
                                case .zNormalized(let w):
                                    index = query.map {
                                        zNormalizedPick(
                                            queryLanes: $0.lanes,
                                            adjustedL: $0.tone,
                                            candidateLanes: candidateLanes,
                                            brightnessValues: brightness, toneWeight: w,
                                            stats: zStats)
                                    }
                                }
                                armSeconds[arm]! +=
                                    Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9
                                if let index { picks[arm] = index }
                            }
                            // The stdout table's `toneOnly` column IS arm F, so
                            // it reads F's own pick rather than a second copy.
                            let toneIndex = picks[.floor] ?? pickIndex

                            for oracle in Oracle.allCases {
                                var scores = [Double](repeating: .nan, count: glyphs.count)
                                for index in glyphs.indices {
                                    scores[index] = oracle.score(
                                        rasters[index], source, footprint: footprint)
                                }
                                let finite = scores.enumerated().filter { $0.element.isFinite }
                                guard !finite.isEmpty, scores[pickIndex].isFinite else { continue }

                                let best: (offset: Int, element: Double)
                                let poolBest: Double
                                switch oracle.polarity {
                                case .lowerIsBetter:
                                    best = finite.min(by: { $0.element < $1.element })!
                                    poolBest =
                                        pool.map { scores[$0] }.filter(\.isFinite).min()
                                        ?? scores[pickIndex]
                                case .higherIsBetter:
                                    best = finite.max(by: { $0.element < $1.element })!
                                    poolBest =
                                        pool.map { scores[$0] }.filter(\.isFinite).max()
                                        ?? scores[pickIndex]
                                }

                                accumulators[oracle]!.prod += scores[pickIndex]
                                accumulators[oracle]!.optGlobal += best.element
                                accumulators[oracle]!.optPool += poolBest
                                accumulators[oracle]!.toneOnly +=
                                    scores[toneIndex].isFinite ? scores[toneIndex] : scores[pickIndex]
                                // 1-based competition rank of the production
                                // pick in the oracle's own ordering — ties share
                                // a rank. `exactOptimal` credits only an exact
                                // index match, so it reads as catastrophic on any
                                // charset with near-ties; the rank says how far
                                // off the pick actually is. Counted in place: this
                                // is the innermost loop (cells x glyphs x oracles),
                                // and a `filter{}.count` here allocates an array
                                // per cell per oracle.
                                let pickScore = scores[pickIndex]
                                var better = 0
                                for entry in finite {
                                    switch oracle.polarity {
                                    case .lowerIsBetter: if entry.element < pickScore { better += 1 }
                                    case .higherIsBetter: if entry.element > pickScore { better += 1 }
                                    }
                                }
                                accumulators[oracle]!.rank += Double(better + 1)
                                accumulators[oracle]!.poolWidth += Double(pool.count)
                                if pickIndex == best.offset { accumulators[oracle]!.exactOptimal += 1 }
                                if pool.contains(best.offset) { accumulators[oracle]!.optInPool += 1 }
                                accumulators[oracle]!.cells += 1

                                // Every arm's score for this cell is just this
                                // oracle's score at that arm's pick — the whole
                                // candidate row was computed above, so adding an
                                // arm costs a lookup, not another oracle pass.
                                for (arm, index) in picks where scores[index].isFinite {
                                    armSums[arm]![oracle]! += scores[index]
                                    armCounts[arm]![oracle]! += 1
                                }
                            }
                        }
                    }
                }

                if let divergence = productionDivergence {
                    throw SelectionCeilingError.productionArmDiverged(
                        charset: divergence.charset,
                        recovered: divergence.recovered,
                        rendered: divergence.rendered)
                }

                for arm in arms {
                    // `cells` reports the verdict oracle's census, matching the
                    // stdout table's convention; a cross-check oracle that
                    // scored fewer cells still gets its own honest denominator.
                    let cells = armCounts[arm]?[.mae] ?? 0
                    guard cells > 0 else { continue }
                    var means: [Oracle: Double] = [:]
                    for oracle in Oracle.allCases {
                        let count = armCounts[arm]?[oracle] ?? 0
                        guard count > 0 else { continue }
                        means[oracle] = (armSums[arm]?[oracle] ?? 0) / Double(count)
                    }
                    armRows.append(
                        ArmRow(
                            corpus: corpusName, charset: charsetName, arm: arm.name,
                            w: arm.w, topK: arm.topK, columns: columns, oversample: oversample,
                            footprint: footprint, stride: stride, cells: cells,
                            glyphs: glyphs.count, means: means,
                            selectionWallSeconds: armSeconds[arm] ?? 0, gitSHA: gitSHA,
                            shapeQueryPolarity: PolarityGate.label(shapeQueryPolarity)))
                }

                for oracle in Oracle.allCases {
                    let accumulator = accumulators[oracle]!
                    guard accumulator.cells > 0 else { continue }
                    let inverse = 1.0 / Double(accumulator.cells)
                    let prod = accumulator.prod * inverse
                    let optPool = accumulator.optPool * inverse
                    let optGlobal = accumulator.optGlobal * inverse
                    // Signed so that a positive gap always means "optimal is better",
                    // in both polarities.
                    let sign: Double = oracle.polarity == .lowerIsBetter ? 1 : -1
                    // Normalize signed zero. `poolGap` carries a hard sign
                    // constraint (a pool minimum can never beat the global
                    // minimum), so it is the run's tripwire — printing "-0.00"
                    // for an exact zero would spend someone's afternoon.
                    func zeroed(_ value: Double) -> Double { value == 0 ? 0 : value }
                    // Every percentage normalizes by |prod|. Single-scale SSIM is
                    // the first oracle in the panel that is higher-is-better and
                    // can average near zero on a sparse charset, so a vanishing
                    // denominator would print an unbounded ratio that reads as a
                    // finding. Below the floor the ratios are reported as `nan`
                    // and the row is kept for its absolute scores and `meanRank`,
                    // which stay meaningful. The floor is three orders of
                    // magnitude under the smallest production mean any reported
                    // run produced (SSIM on `blocks`, 0.00214), so it suppresses
                    // only genuine degeneracy.
                    let degenerate = abs(prod) < degenerateScoreFloor
                    func ratio(_ numerator: Double) -> Double {
                        degenerate ? .nan : zeroed(sign * numerator / abs(prod) * 100)
                    }
                    rows.append(
                        Row(
                            charset: charsetName, oracle: oracle.rawValue, oversample: oversample,
                            cells: accumulator.cells, glyphs: glyphs.count,
                            poolWidth: accumulator.poolWidth * inverse,
                            prod: prod, optPool: optPool, optGlobal: optGlobal,
                            toneOnly: accumulator.toneOnly * inverse,
                            meanRank: accumulator.rank * inverse,
                            totalGapPercent: ratio(prod - optGlobal),
                            rankGapPercent: ratio(prod - optPool),
                            poolGapPercent: ratio(optPool - optGlobal),
                            exactOptimalPercent: Double(accumulator.exactOptimal) * inverse * 100,
                            optInPoolPercent: Double(accumulator.optInPool) * inverse * 100))
                }
            }
        }
        return Census(rows: rows, armRows: armRows)
    }

    /// Column order the frozen rule reads by name. Oracle columns are lower-cased
    /// `Oracle` raw values so `haarPSI` reads as `haarpsi`.
    static let csvHeader =
        "corpus,charset,arm,w,topK,columns,oversample,footprint,stride,cells,glyphs,"
        + "mae,rmse,ssim,gmsd,haarpsi,selectionWallSeconds,gitSHA,shapeQueryPolarity"

    /// The oracle columns, in header order. MAE first because it is the verdict
    /// oracle; RMSE and SSIM next because they are the two cross-checks with the
    /// power to demote; GMSD and HaarPSI last because they can never gate.
    static let csvOracleOrder: [Oracle] = [.mae, .rmse, .ssim, .gmsd, .haarPSI]

    /// The machine-readable census. **The frozen rule is applied to this file
    /// and to nothing else** — the ASTSK-31 discipline, so a verdict is read
    /// mechanically rather than argued from a printed table.
    ///
    /// A parameter that does not apply to an arm is an EMPTY cell, never `0`:
    /// `w = 0` is a swept anchor with a defined meaning (§2.5), so writing `0`
    /// for arm P would forge a data point. A missing oracle mean is likewise
    /// empty, because `0.0` is a legitimate — indeed maximal — MAE score.
    static func csv(_ rows: [ArmRow]) -> String {
        var lines = [csvHeader]
        for row in rows {
            var fields: [String] = [
                row.corpus, row.charset, row.arm,
                row.w.map { trimmed(Double($0)) } ?? "",
                row.topK.map(String.init) ?? "",
                String(row.columns), String(row.oversample), String(row.footprint),
                String(row.stride), String(row.cells), String(row.glyphs),
            ]
            for oracle in csvOracleOrder {
                fields.append(row.means[oracle].map { trimmed($0) } ?? "")
            }
            fields.append(trimmed(row.selectionWallSeconds))
            fields.append(row.gitSHA)
            fields.append(row.shapeQueryPolarity)
            lines.append(fields.map(escaped).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    /// Shortest round-trippable form, so `w = 0` reads as `0` rather than
    /// `0.000000` and a sub-millisecond selection time is not rounded away.
    private static func trimmed(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "nan" : (value > 0 ? "inf" : "-inf") }
        return "\(value)".hasSuffix(".0") ? String("\(value)".dropLast(2)) : "\(value)"
    }

    /// Corpus directories and `--aski-git-sha` overrides are user-supplied and
    /// could carry a separator; the rule is applied by machine, so the file has
    /// to actually parse.
    private static func escaped(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func format(_ rows: [Row], stride: Int = 1) -> String {
        var lines = ["# Selection optimality gap"]
        if stride > 1 {
            // Both loops start at zero, so a stride above 1 keeps only the cells
            // congruent to (0,0) mod stride. That is one phase of the lattice,
            // not an unbiased draw from it: it can alias with periodic content
            // and with cell-position effects. Say so rather than presenting the
            // aggregate as a population mean.
            lines.append(
                "NOTE: stride \(stride) — FIXED-PHASE sample at (0,0) mod \(stride), not a population mean."
            )
        }
        lines.append(
            "charset | oracle | os | cells | glyphs | poolW | prod | optPool | optGlobal | "
                + "toneOnly | meanRank | totalGap% | rankGap% | poolGap% | exactOpt% | optInPool%")
        for row in rows {
            lines.append(
                String(
                    format:
                        "%@ | %@ | %d | %d | %d | %.1f | %.5f | %.5f | %.5f | %.5f | %.2f | %.2f | %.2f | %.2f | %.1f | %.1f",
                    row.charset, row.oracle, row.oversample, row.cells, row.glyphs, row.poolWidth,
                    row.prod, row.optPool, row.optGlobal, row.toneOnly, row.meanRank,
                    row.totalGapPercent, row.rankGapPercent, row.poolGapPercent,
                    row.exactOptimalPercent, row.optInPoolPercent))
        }
        return lines.joined(separator: "\n")
    }
}

enum SelectionCeilingError: Error, CustomStringConvertible {
    case unknownCharacterSet(String)
    case duplicateGlyph(charset: String, glyph: Character)
    case productionArmDiverged(charset: String, recovered: Character, rendered: Character)

    var description: String {
        switch self {
        case .unknownCharacterSet(let name):
            return
                "unknown character set '\(name)' (expected one of: standard, minimal, blocks, dots, lines, diagonal, cross, diamond, mixed, braille)"
        case .duplicateGlyph(let charset, let glyph):
            return
                "character set '\(charset)' repeats the glyph '\(glyph)'; production picks are recovered by firstIndex(of:), which would collapse its indices and mis-attribute every pick of the later one"
        case .productionArmDiverged(let charset, let recovered, let rendered):
            return
                "on '\(charset)' arm P's re-run selector picked '\(recovered)' where the converter rendered '\(rendered)'; arm P is supposed to BE production, so the baseline every §5 ratio divides by is no longer production's"
        }
    }
}
