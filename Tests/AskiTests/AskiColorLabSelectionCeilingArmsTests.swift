import AskiToolSupport
import CoreGraphics
import Foundation
import Testing
import simd

@_spi(AskiResearch) @testable import Aski
@testable import AskiColorLab

/// Guards the ASKI-28/30 census-battery instrument: the four gating arms
/// (P/F/T/K), the two pre-registered exploratory arms (§6.1 lexicographic,
/// §6.2 z-normalized), the duplicate-glyph guard, and the machine-readable CSV
/// the frozen rule is applied to.
///
/// The arm pick functions are pure — index in, index out — so the properties
/// that decide whether a verdict means anything can be asserted on synthetic
/// candidate sets built to make each property FAIL if the plumbing is wrong.
/// The full census is a lab run, not a unit test; what is pinned here is the
/// selection semantics every one of its numbers rests on.
///
/// Synthetic descriptor convention used throughout: a candidate's lanes are all
/// zero except `lane[0].x`, so the 60D squared-L2 shape distance between query
/// `q` and candidate `v` is exactly `(v − q)²`. That makes every expected pick
/// checkable by hand instead of by re-running the matcher.
@Suite struct AskiColorLabSelectionCeilingArmsTests {

    /// Off-axis structure plus a broad tone ramp, so cells differ in both the
    /// descriptor and the tone — a flat fixture would let a broken selector pass.
    private static func structuredImage(side: Int) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let center = Double(side) / 2
        for y in 0..<side {
            for x in 0..<side {
                let dx = Double(x) - center, dy = Double(y) - center
                let rings = (sin((dx * dx + dy * dy).squareRoot() * .pi / 7) + 1) / 2
                let ramp = Double(x + y) / Double(2 * side)
                let value = min(1, max(0, 0.55 * rings + 0.45 * ramp))
                context.setFillColor(CGColor(red: value, green: value, blue: value, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return context.makeImage()!
    }

    private static func lanes(_ value: Float) -> [SIMD4<Float>] {
        var out = [SIMD4<Float>](repeating: .zero, count: StandardCharacterSet.lanesPerCharacter)
        out[0] = SIMD4<Float>(value, 0, 0, 0)
        return out
    }

    private static func candidateLanes(_ values: [Float]) -> [SIMD4<Float>] {
        values.flatMap { lanes($0) }
    }

    // MARK: - Prerequisite 3: the floor's tone quantity

    /// Arm F must be built on PRODUCTION's tone pair — `brightnessValues`
    /// against `stats.adjustedL` — not on the `rawDensityValues`-vs-mean-block-
    /// luma pair the floor shipped with. The rule (§2.4) requires P, F and T to
    /// differ only in the scored term; a floor keyed off a different tone
    /// quantity than production's makes the F baseline incomparable, and the
    /// ASKI-30 PASS condition is a conjunction against exactly that baseline.
    ///
    /// The fixture is built so the two definitions DISAGREE: candidate 0 is
    /// nearest on the production pair, candidate 2 on the legacy pair. A floor
    /// that silently kept the old quantity picks 2 and fails here.
    @Test func floorArmRanksOnBrightnessValuesAgainstAdjustedL() {
        let brightness: [Float] = [0.50, 0.10, 0.90]
        let rawDensity: [Float] = [0.95, 0.60, 0.20]
        let adjustedL: Float = 0.52
        let meanBlockLuma: Float = 0.22

        #expect(
            SelectionCeiling.floorPick(adjustedL: adjustedL, brightnessValues: brightness) == 0,
            "the floor did not rank on brightnessValues vs adjustedL")
        #expect(
            SelectionCeiling.legacyFloorPick(
                meanBlockLuma: meanBlockLuma, rawDensityValues: rawDensity) == 2,
            "the legacy floor is no longer computable — the R8 before/after audit needs it")
        // If these ever coincide the test has stopped discriminating.
        #expect(
            SelectionCeiling.floorPick(adjustedL: adjustedL, brightnessValues: brightness)
                != SelectionCeiling.legacyFloorPick(
                    meanBlockLuma: meanBlockLuma, rawDensityValues: rawDensity),
            "fixture no longer separates the two floor definitions")
    }

    /// Single polarity, matcher convention (§2.4): the floor takes the nearest
    /// tone, never the better of two polarities. A two-polarity floor hands MAE
    /// a free degree of freedom and would inflate the F baseline the ASKI-30
    /// PASS condition must clear.
    @Test func floorArmIsSinglePolarity() {
        // Candidate 1 is the nearest in absolute tone. Candidate 0 would win
        // only under an inverted reading (|1 − brightness| vs adjustedL).
        let brightness: [Float] = [0.05, 0.80]
        #expect(SelectionCeiling.floorPick(adjustedL: 0.9, brightnessValues: brightness) == 1)
    }

    // MARK: - Arm K: pool width beyond the shipped knob's reach

    /// ASKI-28 AC#1 needs `topK` swept to the FULL charset (95 / 256). The
    /// shipped `density` knob reaches only `topK ∈ [12, 36]`, so the arm has to
    /// carry an unclamped width straight through to `findBestScored`.
    ///
    /// The fixture makes the shape optimum tone-distant on purpose: candidate 40
    /// is the shape argmin but sits far from the query in brightness, so it is
    /// outside the pool at 12 and at 36 and only enters at the full width. An
    /// arm that clamped anywhere in the chain returns something else.
    @Test func poolWidthArmReachesTheFullPoolBeyondTheShippedKnobCeiling() {
        let count = 50
        // Brightness ramps away from the query at 0.0, so candidate index is
        // exactly the tone-rank: candidate i enters the pool at topK = i + 1.
        let brightness = (0..<count).map { Float($0) / Float(count) }
        // Shape: everyone is far except candidate 40, which is exact.
        var shape = [Float](repeating: 10, count: count)
        shape[40] = 0
        let lanes = Self.candidateLanes(shape)

        func pick(_ topK: Int) -> Int {
            SelectionCeiling.poolWidthPick(
                queryLanes: Self.lanes(0), adjustedL: 0,
                candidateLanes: lanes, brightnessValues: brightness, topK: topK)
        }
        #expect(pick(12) != 40, "candidate 40 must be outside the production pool")
        #expect(pick(36) != 40, "candidate 40 must be outside the shipped knob's ceiling")
        #expect(pick(48) == 40, "topK=48 did not reach candidate 40")
        #expect(pick(count) == 40, "the full pool did not reach the shape optimum")
    }

    /// Arm K at production's width must BE production. If it is not, arm K is
    /// not a sweep of production's knob and its `topK = 12` row is not the
    /// baseline the §5.2 ratio divides by.
    @Test func poolWidthArmAtTwelveReproducesTheProductionSelector() {
        let brightness = (0..<40).map { Float($0) / 40 }
        let shape = (0..<40).map { Float($0 % 7) }
        let lanes = Self.candidateLanes(shape)
        let expected = ShapeMatching.findBestScored(
            queryLanes: Self.lanes(2), queryBrightness: 0.3,
            candidateBrightness: brightness, candidateLanes: lanes, topK: 12
        ).index
        #expect(
            SelectionCeiling.poolWidthPick(
                queryLanes: Self.lanes(2), adjustedL: 0.3,
                candidateLanes: lanes, brightnessValues: brightness, topK: 12) == expected)
    }

    /// Arm P now RUNS a selector inside its timed region instead of handing back
    /// the converter's already-computed index, so that every row of the
    /// `selectionWallSeconds` column measures the same kind of thing. That
    /// refactor is only safe while the re-run selector still reproduces
    /// production exactly — otherwise arm P silently stops being the baseline
    /// the §5 ratios divide by.
    ///
    /// Pinned here through the LAB's own path (`poolWidthPick` at
    /// `productionPoolWidth`), on a real converter over a real image, which is
    /// the composition the census actually performs. The census carries the same
    /// check at runtime and throws `productionArmDiverged` if it ever fails.
    @Test func productionArmSelectorReproducesTheConvertersOwnPick() throws {
        let image = Self.structuredImage(side: 192)
        let characterSet = StandardCharacterSet.standard
        let converter = ASCIIConverter(
            characterSet: characterSet, palette: BuiltInPalette.monochrome,
            colorSpace: .sRGB, oversample: 2)
        let queries = try #require(converter.cellQueryDescriptors(image, columns: 24))
        try #require(queries.supportsShapeDescriptor)

        let glyphs = characterSet.characters
        var checked = 0
        for row in 0..<queries.rows {
            for column in 0..<queries.columns {
                let recovered = SelectionCeiling.poolWidthPick(
                    queryLanes: queries.lanes(row: row, column: column),
                    adjustedL: queries.adjustedL(row: row, column: column),
                    candidateLanes: characterSet.shapeVectorLanes,
                    brightnessValues: characterSet.brightnessValues,
                    topK: SelectionCeiling.productionPoolWidth)
                #expect(
                    glyphs[recovered] == queries.grid.cells[row][column].character,
                    "arm P diverged from production at (\(row), \(column))")
                checked += 1
            }
        }
        #expect(checked > 0)
    }

    /// The width arm P re-runs at must be the width production actually uses:
    /// the census builds its converter with no `options:`, so `density = 0` and
    /// `topK = 12 + round(0 * 24)`. This is also why arm K's `topK = 12` row and
    /// arm P are the same selector, which §5.2's baseline depends on.
    @Test func productionPoolWidthMatchesTheDefaultDensityFormula() {
        let density = RenderingOptions.default.density
        #expect(density == 0)
        #expect(SelectionCeiling.productionPoolWidth == 12 + Int((density * 24).rounded()))
    }

    // MARK: - Arm T: tone-weighted score, pool decoupled from weight

    /// §2.5's built-in sanity anchor: at `w = 0` the tone term vanishes and arm
    /// T must reduce to a shape argmin over the FULL pool.
    ///
    /// This is the test that proves `toneLimit` is pinned to the glyph count
    /// rather than left coupled to `topK`. The shape optimum here is tone-
    /// distant, so a T arm that inherited production's width would prune it away
    /// and return a different glyph — which is exactly the ASKI-30/ASKI-28
    /// confound the rule decouples (§2.4).
    @Test func toneWeightedArmAtZeroWeightIsAFullPoolShapeArgmin() {
        let count = 40
        let brightness = (0..<count).map { Float($0) / Float(count) }
        var shape = [Float](repeating: 5, count: count)
        shape[33] = 0  // shape optimum, tone-distant from a query at 0
        let lanes = Self.candidateLanes(shape)

        let pick = SelectionCeiling.toneWeightedPick(
            queryLanes: Self.lanes(0), adjustedL: 0,
            candidateLanes: lanes, brightnessValues: brightness, toneWeight: 0)
        #expect(pick == 33, "w=0 did not reduce to a full-pool shape argmin")
        // And it agrees with the shape argmin computed independently.
        #expect(pick == shape.indices.min(by: { abs(shape[$0]) < abs(shape[$1]) })!)
    }

    /// The weight has to actually do something, monotonically: as `w` rises the
    /// arm must move off the shape optimum toward the tone-nearest candidate.
    /// An arm where `w` was dropped on the floor would return the same pick at
    /// every point of the §2.5 sweep and quietly report a flat curve.
    @Test func toneWeightedArmMovesTowardToneAsTheWeightRises() {
        let brightness: [Float] = [0.0, 0.9]
        // Candidate 1 is the shape optimum; candidate 0 is the tone match.
        let lanes = Self.candidateLanes([1.0, 0.0])
        func pick(_ w: Float) -> Int {
            SelectionCeiling.toneWeightedPick(
                queryLanes: Self.lanes(0), adjustedL: 0,
                candidateLanes: lanes, brightnessValues: brightness, toneWeight: w)
        }
        #expect(pick(0) == 1, "at w=0 the shape term must decide")
        #expect(pick(50) == 0, "at the top of the swept range the tone term must decide")
    }

    // MARK: - §6.1 exploratory arm: lexicographic inversion

    /// The count-based grid's two endpoints are anchors the rule names
    /// explicitly (§2.5): `shapeK = 1` reproduces production's shape argmin
    /// modulo tie-break, and `shapeK = glyphCount` reproduces the tone-only
    /// floor F. An arm that fails either endpoint is not the arm §6.1
    /// pre-registers.
    @Test func lexicographicArmEndpointsReproduceShapeArgminAndTheFloor() {
        let brightness: [Float] = [0.10, 0.50, 0.55, 0.95]
        let lanes = Self.candidateLanes([3.0, 2.0, 1.0, 0.0])
        let adjustedL: Float = 0.52
        func pick(_ shapeK: Int) -> Int {
            SelectionCeiling.lexicographicPick(
                queryLanes: Self.lanes(0), adjustedL: adjustedL,
                candidateLanes: lanes, brightnessValues: brightness, shapeK: shapeK)
        }
        #expect(pick(1) == 3, "shapeK=1 is not the shape argmin")
        #expect(
            pick(brightness.count)
                == SelectionCeiling.floorPick(adjustedL: adjustedL, brightnessValues: brightness),
            "shapeK=glyphCount is not the tone-only floor")
    }

    /// The endpoint anchor has to hold ON A TONE TIE, which is where it actually
    /// bites: at `shapeK = glyphCount` every candidate survives the prune, so the
    /// only thing left deciding the pick is the tie policy. Arm F breaks ties by
    /// glyph index; a lex arm that iterated survivors in SHAPE order would break
    /// them by shape and silently return a different glyph, making §2.5's
    /// "shapeK = glyphCount ≡ F" false.
    ///
    /// Not hypothetical: the frozen grid runs `shapeK = 6` against the 4-glyph
    /// (`diagonal`, `diamond`) and 5-glyph (`cross`) sets, so the full-pool
    /// endpoint is reached on three of the eight sparse charsets.
    @Test func lexicographicFullPoolEndpointMatchesTheFloorOnAToneTie() {
        // Both candidates sit exactly 0.25 from the query tone. Candidate 1 is
        // the shape optimum, so a shape-ordered tie-break returns 1; F returns 0.
        let brightness: [Float] = [0.25, 0.75]
        let lanes = Self.candidateLanes([1.0, 0.0])
        let adjustedL: Float = 0.5
        let floor = SelectionCeiling.floorPick(adjustedL: adjustedL, brightnessValues: brightness)
        #expect(floor == 0, "fixture no longer produces the intended tone tie")
        for shapeK in [brightness.count, brightness.count + 4] {
            #expect(
                SelectionCeiling.lexicographicPick(
                    queryLanes: Self.lanes(0), adjustedL: adjustedL,
                    candidateLanes: lanes, brightnessValues: brightness, shapeK: shapeK) == floor,
                "shapeK=\(shapeK) broke the tone tie by shape order instead of glyph index")
        }
    }

    /// The middle of the grid must be a genuine inversion of production's
    /// order: prune by SHAPE, then rank the survivors by TONE. Here the two
    /// shape-nearest are candidates 3 and 2; of those, 2 is the tone match. A
    /// implementation that pruned by tone first would return 1.
    @Test func lexicographicArmPrunesByShapeThenRanksByTone() {
        let brightness: [Float] = [0.10, 0.51, 0.55, 0.95]
        let lanes = Self.candidateLanes([3.0, 2.0, 1.0, 0.0])
        #expect(
            SelectionCeiling.lexicographicPick(
                queryLanes: Self.lanes(0), adjustedL: 0.52,
                candidateLanes: lanes, brightnessValues: brightness, shapeK: 2) == 2)
    }

    // MARK: - §6.2 exploratory arm: z-normalized combination

    /// The whole point of §6.2 is that the two losses are put on a common scale
    /// BEFORE weighting, replacing the fixed ×50. So a z-normalized arm must be
    /// invariant to an affine rescaling of either loss distribution: multiply
    /// every shape distance by 1000 and the pick must not move. The fixed-scale
    /// arm T has no such invariance, which is the property under test.
    @Test func zNormalizedArmIsInvariantToRescalingTheShapeLossDistribution() {
        let brightness: [Float] = [0.0, 0.3, 0.6, 0.9]
        let small = Self.candidateLanes([0.0, 1.0, 2.0, 3.0])
        // lane[0].x is squared into the distance, so scaling values by sqrt(k)
        // scales the distance distribution by k.
        let large = Self.candidateLanes([0.0, 1.0, 2.0, 3.0].map { $0 * 100 })

        for w in [Float(0), 1, 5, 50] {
            let a = SelectionCeiling.zNormalizedPick(
                queryLanes: Self.lanes(0), adjustedL: 0.5,
                candidateLanes: small, brightnessValues: brightness, toneWeight: w)
            let b = SelectionCeiling.zNormalizedPick(
                queryLanes: Self.lanes(0), adjustedL: 0.5,
                candidateLanes: large, brightnessValues: brightness, toneWeight: w)
            #expect(a == b, "z-normalized pick moved under a pure rescale at w=\(w)")
        }
    }

    /// The arm normalizes the tone LOSS, and the loss arm T is built from is
    /// `toneDelta²` (`ShapeMatching.swift`: `distance + toneWeight * toneDelta *
    /// toneDelta`). Normalizing `|toneDelta|` instead would z-score a different
    /// quantity than the one §6.2 exists to rescale, so the arm would not be
    /// comparable with T at the same `w` — which is exactly what R7 reports.
    ///
    /// Squaring is not a monotone no-op here: z-scoring is affine in the value,
    /// and squaring changes the SPREAD of the distribution, so it reorders picks.
    /// This fixture separates the two readings — the squared form picks 0, the
    /// absolute form picks 2.
    @Test func zNormalizedArmNormalizesTheSquaredToneLossNotItsAbsoluteValue() {
        // distance = lane², so these lanes give shape losses 3.4, 8.2, 6.6.
        let lanes = Self.candidateLanes([Float(3.4).squareRoot(), Float(8.2).squareRoot(), Float(6.6).squareRoot()])
        // |brightness − adjustedL| = 0.5, 0.9, 0.
        let brightness: [Float] = [0.4, 0.0, 0.9]
        let pick = SelectionCeiling.zNormalizedPick(
            queryLanes: Self.lanes(0), adjustedL: 0.9,
            candidateLanes: lanes, brightnessValues: brightness, toneWeight: 2)
        #expect(pick == 0, "the arm normalized |toneDelta| rather than toneDelta²")
    }

    /// A degenerate distribution (zero spread) must not divide by zero and
    /// silently produce a NaN score, which a `<` comparison would order
    /// arbitrarily — leaving index 0 as the fallthrough winner and making the
    /// arm look like it decided something when it had not.
    ///
    /// Here the TONE loss is degenerate (every candidate is exactly on the query
    /// tone) while the shape loss is not, so the tone term is constant and the
    /// arm must reduce to the shape argmin — which is index 1, deliberately NOT
    /// the index a NaN fallthrough would return.
    @Test func zNormalizedArmReducesToTheShapeArgminOnADegenerateToneDistribution() {
        let brightness: [Float] = [0.4, 0.4, 0.4]
        let lanes = Self.candidateLanes([2.0, 1.0, 3.0])  // shape losses 4, 1, 9
        for w in [Float(0), 5, 50] {
            let scores = SelectionCeiling.zNormalizedScores(
                queryLanes: Self.lanes(0), adjustedL: 0.4,
                candidateLanes: lanes, brightnessValues: brightness, toneWeight: w)
            let allFinite = scores.allSatisfy { $0.isFinite }
            #expect(allFinite, "degenerate spread produced non-finite scores at w=\(w): \(scores)")
            #expect(
                SelectionCeiling.zNormalizedPick(
                    queryLanes: Self.lanes(0), adjustedL: 0.4,
                    candidateLanes: lanes, brightnessValues: brightness, toneWeight: w) == 1,
                "a constant tone term did not leave the shape argmin standing at w=\(w)")
        }
    }

    // MARK: - Per-charset pool-width grids

    /// The frozen K grids are ASYMMETRIC — `{12,18,24,36,48,64,95}` on
    /// `standard` and `{12,18,24,36,48,64,128,256}` on `braille` (§2.5). A single
    /// global list cannot express that: the union runs 95 on `braille`, a point
    /// that is not in its grid, and 128/256 on `standard`, which do not exist
    /// there. Calibration picks `topK*` from the CSV, so an unregistered point is
    /// a real hazard, not a cosmetic one.
    @Test func topKGridsParsePerCharsetAndFallBackToTheGlobalList() throws {
        let parsed = try parseScopedIntLists(
            ["standard=12,18,95", "braille=12,256"], flag: "--topk")
        #expect(parsed.global.isEmpty)
        #expect(parsed.scoped["standard"] == [12, 18, 95])
        #expect(parsed.scoped["braille"] == [12, 256])

        // A bare list stays valid and covers every charset without its own entry.
        let mixed = try parseScopedIntLists(["12,36", "braille=12,256"], flag: "--topk")
        #expect(mixed.global == [12, 36])
        #expect(mixed.scoped["braille"] == [12, 256])

        var sweeps = SelectionCeiling.Sweeps()
        sweeps.topKs = mixed.global
        sweeps.topKsByCharset = mixed.scoped
        #expect(sweeps.topKs(for: "braille") == [12, 256], "the scoped grid did not win")
        #expect(sweeps.topKs(for: "standard") == [12, 36], "the global grid did not apply")
    }

    /// Two malformed shapes that would silently corrupt a sweep rather than fail.
    @Test func scopedGridParsingRejectsAmbiguousInput() {
        #expect(throws: (any Error).self) {
            // Two bare lists: which one is the global?
            _ = try parseScopedIntLists(["12,36", "48,64"], flag: "--topk")
        }
        #expect(throws: (any Error).self) {
            // The same charset scoped twice.
            _ = try parseScopedIntLists(["standard=12", "standard=36"], flag: "--topk")
        }
        #expect(throws: (any Error).self) {
            _ = try parseScopedIntLists(["standard="], flag: "--topk")
        }
    }

    /// A pool width can never exceed the charset — `findBestScored` prunes to
    /// `min(topK, count)`. So a requested 128 and a requested 256 are the SAME
    /// arm on a 95-glyph set, and recording them as two rows at their requested
    /// widths would put two identical results in the CSV under labels that
    /// describe pools the run never used. Record the effective width, and run
    /// each distinct one once.
    @Test func requestedPoolWidthsCollapseToDistinctEffectiveWidths() {
        #expect(
            SelectionCeiling.effectivePoolWidths(requested: [12, 36, 95, 128, 256], glyphCount: 95)
                == [12, 36, 95],
            "over-wide requests were not clamped and deduped")
        #expect(
            SelectionCeiling.effectivePoolWidths(requested: [12, 128, 256], glyphCount: 256)
                == [12, 128, 256],
            "widths inside the charset were altered")
        // Order of first appearance is preserved, and a clamp that collides with
        // an EARLIER request drops the later one rather than reordering.
        #expect(
            SelectionCeiling.effectivePoolWidths(requested: [8, 12, 4], glyphCount: 8) == [8, 4],
            "dedupe did not preserve first-appearance order")
    }

    // MARK: - Prerequisite 5: duplicate-glyph guard

    /// Production picks are recovered by `firstIndex(of:)`. On a charset holding
    /// a repeated character that collapses two indices onto one, mis-attributing
    /// every pick of the second to the first — a silent, uniform corruption of
    /// `meanRank` and of every arm ratio. Fail the run instead.
    @Test func duplicateGlyphGuardFiresAndNamesTheOffender() throws {
        #expect(throws: Never.self) {
            try SelectionCeiling.assertUniqueGlyphs(["x", "y", "z"], charset: "clean")
        }
        let error = #expect(throws: SelectionCeilingError.self) {
            try SelectionCeiling.assertUniqueGlyphs(["x", "y", "x"], charset: "dupes")
        }
        let described = String(describing: try #require(error))
        #expect(described.contains("'dupes'"), "the error did not name the charset")
        #expect(described.contains("'x'"), "the error did not name the repeated glyph")
    }

    /// Every built-in the battery runs over must pass the guard, or the guard is
    /// a tripwire that fires on the real run instead of on a bad charset.
    @Test func everyBuiltInCharsetTheBatteryRunsPassesTheGuard() throws {
        for name in [
            "blocks", "diagonal", "diamond", "cross", "dots", "minimal", "lines", "mixed",
            "standard", "braille",
        ] {
            let characters = try SelectionCeiling.characterSet(named: name).characters as [Character]
            #expect(throws: Never.self) {
                try SelectionCeiling.assertUniqueGlyphs(characters, charset: name)
            }
        }
    }
}
