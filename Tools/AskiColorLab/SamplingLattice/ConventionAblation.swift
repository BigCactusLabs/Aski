import AskiToolSupport
import Foundation
import simd

@_spi(AskiResearch) import Aski

/// Measures what the matcher's *candidate convention* and its *sampling support*
/// cost on real photographs, at the shipping regime (ASKI-52 AC#1, ASKI-26 AC#2).
///
/// Two questions, one corpus walk:
///
/// 1. **Convention delta.** The production pick against the pick a matcher makes
///    when its candidate vocabulary is position-faithful instead of bounds-centred
///    in a 64×64 square — same charset, same shipped 60-D single-disc descriptor.
///
///    This arm is deliberately **compound**, and reading it as a clean
///    convention effect is the mistake to avoid. Production is one of its two
///    sides, so the arm necessarily also swaps the *query* path: production
///    scores a descriptor taken from the shipped thumbnail cell (a couple of
///    pixels across, single-digit live bins — the ASKI-55 collapse regime the
///    geometry table measures), while the treatment side samples the native
///    source block resampled to the candidate geometry. The single-variable
///    convention delta — same query support on both sides — is ladder rung (i)
///    against rung (iii) below, and it is the number a promotion argument may
///    quote. This arm answers a different and more product-shaped question:
///    how far the shipped pick sits from a pick made with both defects removed.
///
///    Braille is NOT a null control for this arm, contrary to what the shape of
///    the comparison suggests. Its production candidates come from
///    `BuildStandardVectors`, which rasterizes braille through
///    `BrailleRasterizer` at a **64×64 square** — the same square every text
///    glyph gets. What braille escapes is the *bounds crop* (no `CTLine` image
///    bounds are taken, so dot position survives inside the raster), not the
///    square. The faithful braille vocabulary is therefore a genuinely different
///    raster at the true cell aspect, and a non-zero braille delta here is
///    expected.
///
///    The real null control lives in the ladder: for braille,
///    `rectSingleDisc` and `faithfulSingleDisc` both rasterize
///    `BrailleRasterizer` over the whole cell rect, so they are the same
///    vocabulary and every braille number must match between those two rungs to
///    the last digit. If they diverge, the instrument moved something.
/// 2. **Ablation ladder.** Five arms that differ ONLY in the placement/sampling
///    convention, with the query side sampled by the same
///    `LogPolarCellSampling.Configuration` as the candidate side in every arm.
///    That matched support is the whole point: the shipped path samples an
///    anisotropic query cell and a square candidate with one disc apiece and
///    compares the results, which is not a comparison of like with like.
///
/// **What is held constant across every arm** — the condition that makes the
/// numbers readable (the ASTSK-31 "arms differ only in the term under test"
/// discipline):
///
/// - *The selector shape.* Every arm, and production, prune to the
///   `SelectionCeiling.productionPoolWidth` brightness-nearest candidates and
///   then take the descriptor argmin. The tone pre-filter is held IN rather than
///   removed, because removing it would let each arm's shape term answer a
///   different question (an unconstrained-tone pick is dominated by ink
///   mismatch, and the arms would separate on tone noise). The query tone is
///   the matcher's OWN `adjustedL` for that cell, read back through
///   `cellQueryDescriptors`; the candidate tone is the vocabulary's unified
///   whole-raster mean ink, max-normalized the way the shipped
///   `brightnessValues` are. The candidate tone therefore moves with the
///   convention under test, which is correct — the brightness rule is part of
///   the candidate convention (the shipped one splits text and braille onto two
///   different scales) — while the query side is held at production's.
/// - *The rendering path used for scoring.* A pick is scored as
///   `GlyphCellRaster` at the sampling cell, resampled once to the footprint —
///   the renderer's own output convention — against the cell's native source
///   block resampled to the same footprint. One path, so two arms differ only in
///   which glyph they chose, never in how that choice was drawn.
/// - *The gate.* Pick quality against the source cell, MAE-first, full oracle
///   panel reported. Never descriptor-space distance: a convention that shrinks
///   its own distances has not thereby chosen better glyphs, and the ASKI-27
///   screen already settled which oracles may define an optimum.
///
/// **Geometry.** The query cell is the converter's own resolved native block
/// (`SampledSource`, so the lattice is the one the converter actually read), and
/// it is `LumaResample`d to the arm's candidate raster geometry before sampling
/// — 64×64 for the square arm, `cellWidth × cellHeight` for the rest — because
/// a log-polar descriptor is only comparable between two rasters of the same
/// pixel geometry. The default `12 × 24` cell is the source paper's own worked
/// example (72 windows, 4320-D) at the shipping regime's 1:2 cell aspect. The
/// *thumbnail* cell the shipped kernel samples is far smaller than either — the
/// geometry table reports it, its window count and the production descriptor's
/// live-bin count, because that collapse is itself the finding ASKI-55 tracks.
enum ConventionAblation {

    /// Which way up the query field is fed to the descriptor.
    ///
    /// This is a factor, not a constant, because the two production conventions it
    /// sits between disagree and the disagreement is itself a finding.
    ///
    /// - Candidate rasters are **ink-high**: `RasterizedCharacterSet.rasterize`
    ///   fills the canvas at `gray: 0` and draws the glyph at `gray: 1`, so a
    ///   dense glyph carries descriptor mass everywhere.
    /// - Production's query field is **inverted luma**:
    ///   `LogPolarKernel.baseInkField` computes `1 − Rec.601 luma`, so the
    ///   DARK parts of a source cell carry the descriptor mass.
    /// - Production's tone pre-filter goes the other way: it matches a high source
    ///   `adjustedL` to a high candidate ink density, i.e. a BRIGHT cell asks for a
    ///   dense glyph, which is the pairing the renderer draws (light ink on a dark
    ///   ground) and the pairing every archived pick-quality screen scores under.
    ///
    /// So production's shape term and production's tone term do not agree about
    /// which end of the source is "ink". `inverted` reproduces production's shape
    /// term; `direct` puts the query on the same footing as the candidates and the
    /// scoring path. Running both is what turns the contradiction into a number
    /// instead of an assumption.
    enum QueryPolarity: String, Sendable, CaseIterable {
        /// `1 − luma`, matching `LogPolarKernel.baseInkField`.
        case inverted
        /// Raw luma, matching the ink-high candidates and the scoring path.
        case direct

        func apply(_ field: [Float]) -> [Float] {
            self == .inverted ? field.map { 1 - $0 } : field
        }
    }

    /// The five ladder arms. Each names a candidate placement and the sampling
    /// configuration applied identically to both sides.
    enum LadderArm: String, Sendable, CaseIterable {
        /// (i) The shipped convention, given matched support: bounds-centred
        /// 64×64 square candidates, one inscribed disc, query resampled to the
        /// same square. Position and cell aspect are both gone.
        case squareSingleDisc
        /// (ii) Bounds-centred at the true cell aspect. Aspect restored,
        /// position still erased — isolates what the *square* costs.
        case rectSingleDisc
        /// (iii) Position-faithful at the true cell aspect, still one disc.
        /// Isolates what *bounds-centring* costs, holding the support fixed.
        case faithfulSingleDisc
        /// (iv) Position-faithful, tiled AISS support with the paper's 7×7
        /// pre-blur. Isolates what the *single disc* costs.
        case faithfulTiled
        /// (v) As (iv) with the pre-blur removed — how much of (iv) is the blur.
        case faithfulTiledNoBlur

        var placement: PositionFaithfulVocabulary.Placement {
            switch self {
            case .squareSingleDisc: return .boundsCentredSquare
            case .rectSingleDisc: return .boundsCentredRect
            case .faithfulSingleDisc, .faithfulTiled, .faithfulTiledNoBlur:
                return .positionFaithful
            }
        }

        var sampling: LogPolarCellSampling.Configuration {
            switch self {
            case .squareSingleDisc, .rectSingleDisc, .faithfulSingleDisc:
                return .singleDisc
            case .faithfulTiled: return .tiledAISS
            case .faithfulTiledNoBlur: return .tiledAISSNoBlur
            }
        }
    }

    // MARK: - Rows

    /// One row per corpus fixture: the geometry the run actually resolved.
    /// Reported rather than assumed, because the degeneracy question ("does the
    /// shipping thumbnail cell even hold a log-polar window?") is answered by
    /// these numbers and by nothing else.
    struct GeometryRow: Sendable {
        let corpus: String
        let fixture: String
        let nativeWidth: Int
        let nativeHeight: Int
        let thumbnailWidth: Int
        let thumbnailHeight: Int
        let gridRows: Int
        let gridColumns: Int
        /// The cell the shipped kernel samples, in thumbnail pixels.
        let thumbCellWidth: Int
        let thumbCellHeight: Int
        /// Tiled windows that fit in that thumbnail cell at stride 2. Zero means
        /// the shipped cell cannot carry the paper's construction at all.
        let thumbCellWindows: Int
        /// The native source block one cell maps back to, as a RANGE over the
        /// fixture's cells. Native-to-thumbnail scaling is fractional, so the
        /// block dimensions vary cell to cell (3072 -> 160 at 80 columns gives
        /// 38 and 39 wide, 76 and 77 tall). Reporting a single value here — the
        /// last cell visited, as an earlier version did — misdescribes exactly
        /// the non-integral regime this table exists to document.
        let nativeBlockMinWidth: Int
        let nativeBlockMaxWidth: Int
        let nativeBlockMinHeight: Int
        let nativeBlockMaxHeight: Int
        /// Mean count of non-zero bins, out of 60, in the production query
        /// descriptor over the sampled cells — the ASKI-55 support-collapse
        /// number, measured on this corpus rather than quoted.
        let meanLiveBins: Double
        let sampledCells: Int
    }

    /// ASKI-52 AC#1. One row per (corpus, charset, oracle).
    struct DeltaRow: Sendable {
        let corpus: String
        let charset: String
        let oracle: String
        let cells: Int
        let glyphs: Int
        /// Mean oracle score of the PRODUCTION pick, scored through the shared
        /// rendering path.
        let productionMean: Double
        /// Mean oracle score of the position-faithful-vocabulary pick.
        let faithfulMean: Double
        /// Signed so POSITIVE always means the faithful vocabulary picked
        /// better, in both polarities, as a percentage of |productionMean|.
        let improvementPercent: Double
        /// Share of cells where the two vocabularies chose different glyphs.
        let differingPickPercent: Double
        let productionMeanInkDelta: Double
        let faithfulMeanInkDelta: Double
        let maxInkDelta: Double
    }

    /// ASKI-26 AC#2. One row per (corpus, charset, arm, oracle).
    struct LadderRow: Sendable {
        let corpus: String
        let charset: String
        let arm: String
        let oracle: String
        let cells: Int
        let glyphs: Int
        let candidateWidth: Int
        let candidateHeight: Int
        let descriptorDimension: Int
        let windows: Int
        let mean: Double
        /// Signed so POSITIVE means this arm beat the ladder's baseline arm
        /// (`squareSingleDisc`, the shipped convention), as a percentage of the
        /// baseline's |mean|.
        let improvementPercent: Double
        /// Share of cells where this arm agreed with the production pick.
        let productionAgreementPercent: Double
        let meanInkDelta: Double
        let maxInkDelta: Double
    }

    struct Report: Sendable {
        let geometry: [GeometryRow]
        let delta: [DeltaRow]
        let ladder: [LadderRow]
    }

    // MARK: - Selector

    /// A vocabulary plus the brightness index the pool prune needs.
    ///
    /// Brightness is fixed per vocabulary, so the `poolWidth` tone-nearest
    /// candidates are found by binary-searching a pre-sorted brightness list and
    /// expanding outward — `O(log n + poolWidth)` per cell instead of a sort per
    /// cell. It selects exactly the same set as an argsort of `|b − q|` would,
    /// with ties broken toward the lower brightness and then the lower index.
    struct Vocabulary: Sendable {
        let entries: [PositionFaithfulVocabulary.Entry]
        let width: Int
        let height: Int
        let descriptorDimension: Int
        let windows: Int
        /// Glyph indices ordered by ascending NORMALIZED brightness.
        let brightnessOrder: [Int]
        /// `entries[brightnessOrder[i]].normalizedBrightness`, for the binary
        /// search. Normalized rather than raw, because production's own
        /// pre-filter compares `adjustedL` against a max-normalized brightness
        /// array: a raw scale would put each arm's tone prune on a different
        /// interval (a bounds-centred 64×64 raster tops out near 0.63 where a
        /// cell-aspect one reaches 1.0) and the arms would separate on that
        /// rather than on the convention under test.
        let sortedBrightness: [Float]

        static func build(
            characters: [Character],
            cellWidth: Int,
            cellHeight: Int,
            placement: PositionFaithfulVocabulary.Placement,
            sampling: LogPolarCellSampling.Configuration
        ) -> Vocabulary {
            let size = PositionFaithfulVocabulary.rasterSize(
                cellWidth: cellWidth, cellHeight: cellHeight, placement: placement)
            let entries = PositionFaithfulVocabulary.build(
                characters: characters, cellWidth: cellWidth, cellHeight: cellHeight,
                placement: placement, sampling: sampling)
            let order = entries.indices.sorted {
                entries[$0].normalizedBrightness == entries[$1].normalizedBrightness
                    ? $0 < $1
                    : entries[$0].normalizedBrightness < entries[$1].normalizedBrightness
            }
            let grid: (columns: Int, rows: Int)
            if case .tiled(let stride) = sampling.support {
                grid = LogPolarCellSampling.windowGrid(
                    width: size.width, height: size.height, stride: stride)
            } else {
                grid = (1, 1)
            }
            return Vocabulary(
                entries: entries,
                width: size.width, height: size.height,
                descriptorDimension: LogPolarCellSampling.dimension(
                    width: size.width, height: size.height, configuration: sampling),
                windows: grid.columns * grid.rows,
                brightnessOrder: order,
                sortedBrightness: order.map { entries[$0].normalizedBrightness })
        }

        /// The `poolWidth` brightness-nearest glyph indices, **in production's
        /// pool order**.
        ///
        /// This mirrors `ShapeMatching.findBestScored` exactly: pair every glyph
        /// with `|brightness − query|`, sort by that delta with ties broken toward
        /// the lower glyph index, and take the first `poolWidth`. The order is
        /// part of the contract, not an implementation detail — the matcher scans
        /// the pool in it and keeps the FIRST minimum, so on a descriptor-distance
        /// tie the winner is the tone-nearest candidate, not the lowest-indexed
        /// one. Ties are not hypothetical here: the collapsed shipping descriptor
        /// makes them common.
        ///
        /// An earlier version binary-searched a pre-sorted brightness list and
        /// expanded outward. That selected the same *set* on distinct brightnesses
        /// but broke exact ties toward the lower brightness rather than the lower
        /// index, and it returned the pool in expansion order, which is not
        /// production's.
        func pool(brightness query: Float, width poolWidth: Int) -> [Int] {
            let count = entries.count
            guard count > 0 else { return [] }
            var pairs: [(index: Int, delta: Float)] = []
            pairs.reserveCapacity(count)
            for index in 0..<count {
                pairs.append((index, abs(entries[index].normalizedBrightness - query)))
            }
            pairs.sort {
                $0.delta == $1.delta ? $0.index < $1.index : $0.delta < $1.delta
            }
            return pairs.prefix(max(1, min(poolWidth, count))).map(\.index)
        }

        /// Production's selector shape on this vocabulary: prune by tone, then
        /// take the descriptor argmin **scanning in pool order and keeping the
        /// first minimum**, which is `ShapeMatching.findBestScored`'s rule.
        func pick(descriptor: [Float], brightness: Float, poolWidth: Int) -> Int {
            let candidates = pool(brightness: brightness, width: poolWidth)
            var best = candidates.first ?? 0
            var bestDistance = Float.infinity
            for index in candidates {
                let other = entries[index].descriptor
                guard other.count == descriptor.count else { continue }
                var distance: Float = 0
                for bin in descriptor.indices {
                    let delta = descriptor[bin] - other[bin]
                    distance += delta * delta
                }
                if distance < bestDistance {
                    bestDistance = distance
                    best = index
                }
            }
            return best
        }
    }

    // MARK: - Run

    struct Accumulator {
        var sum = 0.0
        var count = 0
        mutating func add(_ value: Double) {
            guard value.isFinite else { return }
            sum += value
            count += 1
        }
        var mean: Double { count > 0 ? sum / Double(count) : .nan }
    }

    /// Below this |mean| the improvement ratios are degenerate and print `nan`
    /// rather than an unbounded number. Same floor as `SelectionCeiling`.
    static let degenerateScoreFloor = SelectionCeiling.degenerateScoreFloor

    static func run(
        columns: Int,
        oversample: Int,
        footprint: Int,
        cellWidth: Int,
        cellHeight: Int,
        stride: Int,
        charsetNames: [String],
        corpora: [String?],
        queryPolarity: QueryPolarity
    ) throws -> Report {
        var geometry: [GeometryRow] = []
        var delta: [DeltaRow] = []
        var ladder: [LadderRow] = []

        for corpus in corpora {
            let fixtures = try SteerableBattery.naturals(corpusDirectory: corpus)
            let corpusName = SelectionCeiling.corpusLabel(corpus)
            var geometryRecorded = false

            for charsetName in charsetNames {
                let characterSet = try SelectionCeiling.characterSet(named: charsetName)
                let glyphs = characterSet.characters
                try SelectionCeiling.assertUniqueGlyphs(glyphs, charset: charsetName)

                // ONE rendering path for every arm and for production: the
                // renderer's own convention at the sampling cell, resampled once
                // to the footprint.
                let scoringRasters = scoringRasters(
                    glyphs: glyphs, cellWidth: cellWidth, cellHeight: cellHeight,
                    footprint: footprint)
                // Mean ink of each scoring raster, for the calibration columns.
                // One array per charset, not per arm: the scoring path is shared,
                // so a glyph's rendered ink cannot depend on which arm chose it.
                let scoringInk = scoringRasters.map { PositionFaithfulVocabulary.meanInk($0) }
                var vocabularies: [LadderArm: Vocabulary] = [:]
                for arm in LadderArm.allCases {
                    vocabularies[arm] = Vocabulary.build(
                        characters: glyphs, cellWidth: cellWidth, cellHeight: cellHeight,
                        placement: arm.placement, sampling: arm.sampling)
                }
                // ASKI-52 AC#1's treatment: the shipped 60-D single-disc
                // descriptor over a position-faithful vocabulary. Same arm as
                // ladder rung (iii) by construction — the convention delta IS
                // "swap the vocabulary, change nothing else".
                let faithfulArm = LadderArm.faithfulSingleDisc

                let converter = ASCIIConverter(
                    characterSet: characterSet,
                    palette: BuiltInPalette.monochrome,
                    colorSpace: .sRGB,
                    oversample: oversample
                )

                var productionScores: [SelectionCeiling.Oracle: Accumulator] = [:]
                var faithfulScores: [SelectionCeiling.Oracle: Accumulator] = [:]
                var armScores: [LadderArm: [SelectionCeiling.Oracle: Accumulator]] = [:]
                for oracle in SelectionCeiling.Oracle.allCases {
                    productionScores[oracle] = Accumulator()
                    faithfulScores[oracle] = Accumulator()
                }
                for arm in LadderArm.allCases {
                    armScores[arm] = Dictionary(
                        uniqueKeysWithValues: SelectionCeiling.Oracle.allCases.map {
                            ($0, Accumulator())
                        })
                }
                var cells = 0
                var differingPicks = 0
                var productionInk = Accumulator()
                var faithfulInk = Accumulator()
                var maxInkDelta = 0.0
                var armInk: [LadderArm: (accumulator: Accumulator, max: Double)] = [:]
                var armAgreement: [LadderArm: Int] = [:]
                for arm in LadderArm.allCases {
                    armInk[arm] = (Accumulator(), 0)
                    armAgreement[arm] = 0
                }

                for fixture in fixtures {
                    let grid = converter.convert(fixture.image, columns: columns)
                    guard grid.rows > 0, grid.columns > 0,
                        let samplingGeometry = converter.samplingGeometry(
                            fixture.image, columns: columns),
                        samplingGeometry.rows == grid.rows,
                        samplingGeometry.columns == grid.columns
                    else { continue }
                    let queries = converter.cellQueryDescriptors(fixture.image, columns: columns)
                    var liveBins = Accumulator()
                    var geometryCells = 0
                    var nativeBlock =
                        (minW: Int.max, maxW: Int.min, minH: Int.max, maxH: Int.min)

                    for row in Swift.stride(from: 0, to: grid.rows, by: stride) {
                        for col in Swift.stride(from: 0, to: grid.columns, by: stride) {
                            guard
                                let block = SampledSource.lumaBlock(
                                    fixture, cellRow: row, cellCol: col,
                                    geometry: samplingGeometry),
                                block.width >= 2, block.height >= 2
                            else { continue }
                            let picked = grid.cells[row][col].character
                            guard let productionIndex = glyphs.firstIndex(of: picked) else {
                                continue
                            }
                            nativeBlock.minW = min(nativeBlock.minW, block.width)
                            nativeBlock.maxW = max(nativeBlock.maxW, block.width)
                            nativeBlock.minH = min(nativeBlock.minH, block.height)
                            nativeBlock.maxH = max(nativeBlock.maxH, block.height)
                            geometryCells += 1
                            // The matcher's OWN query tone for this cell. Every
                            // arm prunes its pool on this quantity, so the arms
                            // — and production — differ in the candidate
                            // convention alone and not in what "the cell's
                            // brightness" means. A cell whose reflection is
                            // unavailable is skipped rather than fed a
                            // re-derived guess; re-deriving the query is what
                            // inverted the polarity on the first run of the
                            // neighbouring selection-ceiling probe.
                            guard let queries, queries.supportsShapeDescriptor,
                                row < queries.rows, col < queries.columns
                            else { continue }
                            let queryTone = queries.adjustedL(row: row, column: col)
                            var live = 0
                            for lane in queries.lanes(row: row, column: col) {
                                for component in 0..<4 where lane[component] != 0 { live += 1 }
                            }
                            liveBins.add(Double(live))

                            let source = LumaResample.resample(
                                block.luma, srcWidth: block.width, srcHeight: block.height,
                                dstWidth: footprint, dstHeight: footprint)
                            let sourceInk = PositionFaithfulVocabulary.meanInk(source)

                            // The query cell at each candidate geometry the arms
                            // use. Built once per cell and shared, so two arms
                            // on the same geometry read identical pixels.
                            //
                            // The polarity is applied HERE and only here: the
                            // descriptor query is the only thing it may touch.
                            // `source` above (and `sourceInk`) stay raw luma,
                            // because the scoring path is the house convention
                            // every archived screen used and is not the term
                            // under test.
                            var queryCells: [String: [Float]] = [:]
                            func queryCell(width: Int, height: Int) -> [Float] {
                                let key = "\(width)x\(height)"
                                if let cached = queryCells[key] { return cached }
                                let resampled = queryPolarity.apply(
                                    LumaResample.resample(
                                        block.luma, srcWidth: block.width, srcHeight: block.height,
                                        dstWidth: width, dstHeight: height))
                                queryCells[key] = resampled
                                return resampled
                            }

                            // Oracle scores memoized per picked glyph: the arms
                            // agree on most cells, so this collapses six scoring
                            // passes into one or two.
                            var scoredIndices: [Int] = []
                            var scoredValues: [[SelectionCeiling.Oracle: Double]] = []
                            func scores(for index: Int) -> [SelectionCeiling.Oracle: Double] {
                                if let slot = scoredIndices.firstIndex(of: index) {
                                    return scoredValues[slot]
                                }
                                var values: [SelectionCeiling.Oracle: Double] = [:]
                                for oracle in SelectionCeiling.Oracle.allCases {
                                    values[oracle] = oracle.score(
                                        scoringRasters[index], source, footprint: footprint)
                                }
                                scoredIndices.append(index)
                                scoredValues.append(values)
                                return values
                            }

                            var armPicks: [LadderArm: Int] = [:]
                            for arm in LadderArm.allCases {
                                guard let vocabulary = vocabularies[arm] else { continue }
                                let cell = queryCell(
                                    width: vocabulary.width, height: vocabulary.height)
                                let descriptor = LogPolarCellSampling.descriptor(
                                    cell, width: vocabulary.width, height: vocabulary.height,
                                    configuration: arm.sampling)
                                armPicks[arm] = vocabulary.pick(
                                    descriptor: descriptor, brightness: queryTone,
                                    poolWidth: SelectionCeiling.productionPoolWidth)
                            }
                            guard let faithfulIndex = armPicks[faithfulArm] else { continue }

                            cells += 1
                            let productionValues = scores(for: productionIndex)
                            let faithfulValues = scores(for: faithfulIndex)
                            for oracle in SelectionCeiling.Oracle.allCases {
                                productionScores[oracle]!.add(productionValues[oracle] ?? .nan)
                                faithfulScores[oracle]!.add(faithfulValues[oracle] ?? .nan)
                            }
                            if productionIndex != faithfulIndex { differingPicks += 1 }
                            let productionDelta = Double(abs(sourceInk - scoringInk[productionIndex]))
                            let faithfulDelta = Double(abs(sourceInk - scoringInk[faithfulIndex]))
                            productionInk.add(productionDelta)
                            faithfulInk.add(faithfulDelta)
                            maxInkDelta = max(maxInkDelta, max(productionDelta, faithfulDelta))

                            for (arm, index) in armPicks {
                                let values = scores(for: index)
                                for oracle in SelectionCeiling.Oracle.allCases {
                                    armScores[arm]![oracle]!.add(values[oracle] ?? .nan)
                                }
                                if index == productionIndex { armAgreement[arm]! += 1 }
                                let inkDelta = Double(abs(sourceInk - scoringInk[index]))
                                armInk[arm]!.accumulator.add(inkDelta)
                                armInk[arm]!.max = max(armInk[arm]!.max, inkDelta)
                            }
                        }
                    }

                    // Geometry is a property of the corpus and the regime, not of
                    // the charset, so it is recorded on the first charset pass only.
                    if !geometryRecorded, geometryCells > 0 {
                        let windowGrid = LogPolarCellSampling.windowGrid(
                            width: samplingGeometry.cellWidth,
                            height: samplingGeometry.cellHeight, stride: 2)
                        geometry.append(
                            GeometryRow(
                                corpus: corpusName, fixture: fixture.id,
                                nativeWidth: fixture.width, nativeHeight: fixture.height,
                                thumbnailWidth: samplingGeometry.thumbnailWidth,
                                thumbnailHeight: samplingGeometry.thumbnailHeight,
                                gridRows: grid.rows, gridColumns: grid.columns,
                                thumbCellWidth: samplingGeometry.cellWidth,
                                thumbCellHeight: samplingGeometry.cellHeight,
                                thumbCellWindows: windowGrid.columns * windowGrid.rows,
                                nativeBlockMinWidth: nativeBlock.minW,
                                nativeBlockMaxWidth: nativeBlock.maxW,
                                nativeBlockMinHeight: nativeBlock.minH,
                                nativeBlockMaxHeight: nativeBlock.maxH,
                                meanLiveBins: liveBins.mean,
                                sampledCells: geometryCells))
                    }
                }
                geometryRecorded = true

                guard cells > 0 else { continue }
                let cellCount = Double(cells)

                for oracle in SelectionCeiling.Oracle.allCases {
                    let production = productionScores[oracle]!.mean
                    let faithful = faithfulScores[oracle]!.mean
                    delta.append(
                        DeltaRow(
                            corpus: corpusName, charset: charsetName, oracle: oracle.rawValue,
                            cells: productionScores[oracle]!.count, glyphs: glyphs.count,
                            productionMean: production, faithfulMean: faithful,
                            improvementPercent: improvement(
                                baseline: production, arm: faithful, polarity: oracle.polarity),
                            differingPickPercent: Double(differingPicks) / cellCount * 100,
                            productionMeanInkDelta: productionInk.mean,
                            faithfulMeanInkDelta: faithfulInk.mean,
                            maxInkDelta: maxInkDelta))
                }

                for arm in LadderArm.allCases {
                    guard let vocabulary = vocabularies[arm] else { continue }
                    for oracle in SelectionCeiling.Oracle.allCases {
                        let mean = armScores[arm]![oracle]!.mean
                        let baseline = armScores[.squareSingleDisc]![oracle]!.mean
                        ladder.append(
                            LadderRow(
                                corpus: corpusName, charset: charsetName, arm: arm.rawValue,
                                oracle: oracle.rawValue,
                                cells: armScores[arm]![oracle]!.count, glyphs: glyphs.count,
                                candidateWidth: vocabulary.width,
                                candidateHeight: vocabulary.height,
                                descriptorDimension: vocabulary.descriptorDimension,
                                windows: vocabulary.windows,
                                mean: mean,
                                improvementPercent: improvement(
                                    baseline: baseline, arm: mean, polarity: oracle.polarity),
                                productionAgreementPercent: Double(armAgreement[arm]!) / cellCount
                                    * 100,
                                meanInkDelta: armInk[arm]!.accumulator.mean,
                                maxInkDelta: armInk[arm]!.max))
                    }
                }
            }
        }
        return Report(geometry: geometry, delta: delta, ladder: ladder)
    }

    /// The ONE rendering path every arm — and every instrument that wants to be
    /// comparable with this one — scores a pick through: `GlyphCellRaster` at the
    /// sampling cell, resampled once to the footprint. Shared rather than copied
    /// so a second instrument cannot quietly score on a different raster
    /// (`polarity-gate`, ASKI-60, is the second caller).
    static func scoringRasters(
        glyphs: [Character], cellWidth: Int, cellHeight: Int, footprint: Int
    ) -> [[Float]] {
        glyphs.map { glyph -> [Float] in
            let raster = GlyphCellRaster.luma(
                character: glyph, width: cellWidth, height: cellHeight)
            return LumaResample.resample(
                raster, srcWidth: cellWidth, srcHeight: cellHeight,
                dstWidth: footprint, dstHeight: footprint)
        }
    }

    /// Percentage improvement of `arm` over `baseline`, signed so POSITIVE always
    /// means "the arm is better" whichever way the oracle points. Degenerate
    /// baselines print `nan` rather than an unbounded ratio.
    static func improvement(
        baseline: Double, arm: Double, polarity: SelectionCeiling.Polarity
    ) -> Double {
        guard baseline.isFinite, arm.isFinite, abs(baseline) >= degenerateScoreFloor else {
            return .nan
        }
        let sign: Double = polarity == .lowerIsBetter ? 1 : -1
        let value = sign * (baseline - arm) / abs(baseline) * 100
        return value == 0 ? 0 : value
    }

    // MARK: - Output

    static let geometryCSVHeader =
        "corpus,fixture,nativeW,nativeH,thumbW,thumbH,gridRows,gridCols,"
        + "thumbCellW,thumbCellH,thumbCellWindows,nativeBlockMinW,nativeBlockMaxW,"
        + "nativeBlockMinH,nativeBlockMaxH,meanLiveBins,cells"

    static func geometryCSV(_ rows: [GeometryRow]) -> String {
        var lines = [geometryCSVHeader]
        for row in rows {
            lines.append(
                [
                    row.corpus, row.fixture, String(row.nativeWidth), String(row.nativeHeight),
                    String(row.thumbnailWidth), String(row.thumbnailHeight),
                    String(row.gridRows), String(row.gridColumns),
                    String(row.thumbCellWidth), String(row.thumbCellHeight),
                    String(row.thumbCellWindows), String(row.nativeBlockMinWidth),
                    String(row.nativeBlockMaxWidth), String(row.nativeBlockMinHeight),
                    String(row.nativeBlockMaxHeight), trimmed(row.meanLiveBins),
                    String(row.sampledCells),
                ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    /// Every row names the query polarity it was measured under, for the same
    /// reason it names its corpus: the two polarities are different regimes and a
    /// number lifted out of one of them without its label is not quotable.
    static let deltaCSVHeader =
        "queryPolarity,corpus,charset,oracle,cells,glyphs,productionMean,faithfulMean,"
        + "improvementPercent,"
        + "differingPickPercent,productionMeanInkDelta,faithfulMeanInkDelta,maxInkDelta"

    static func deltaCSV(_ rows: [DeltaRow], queryPolarity: QueryPolarity) -> String {
        var lines = [deltaCSVHeader]
        for row in rows {
            lines.append(
                [
                    queryPolarity.rawValue,
                    row.corpus, row.charset, row.oracle, String(row.cells), String(row.glyphs),
                    trimmed(row.productionMean), trimmed(row.faithfulMean),
                    trimmed(row.improvementPercent), trimmed(row.differingPickPercent),
                    trimmed(row.productionMeanInkDelta), trimmed(row.faithfulMeanInkDelta),
                    trimmed(row.maxInkDelta),
                ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static let ladderCSVHeader =
        "queryPolarity,corpus,charset,arm,oracle,cells,glyphs,candidateW,candidateH,dimension,"
        + "windows,"
        + "mean,improvementPercent,productionAgreementPercent,meanInkDelta,maxInkDelta"

    static func ladderCSV(_ rows: [LadderRow], queryPolarity: QueryPolarity) -> String {
        var lines = [ladderCSVHeader]
        for row in rows {
            lines.append(
                [
                    queryPolarity.rawValue,
                    row.corpus, row.charset, row.arm, row.oracle, String(row.cells),
                    String(row.glyphs), String(row.candidateWidth), String(row.candidateHeight),
                    String(row.descriptorDimension), String(row.windows),
                    trimmed(row.mean), trimmed(row.improvementPercent),
                    trimmed(row.productionAgreementPercent),
                    trimmed(row.meanInkDelta), trimmed(row.maxInkDelta),
                ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    /// MAE first in every table: it is the house oracle, and GMSD/HaarPSI are
    /// disqualified from defining an optimum (ASKI-27).
    static let oracleOrder: [SelectionCeiling.Oracle] = SelectionCeiling.csvOracleOrder

    static func format(
        _ report: Report, stride: Int, reproduce: String? = nil,
        queryPolarity: QueryPolarity
    ) -> String {
        var lines = ["# Candidate-convention delta and sampling-support ablation (ASKI-52 / ASKI-26)"]
        lines.append("")
        lines.append("Query polarity: **\(queryPolarity.rawValue)**.")
        if stride > 1 {
            lines.append(
                "NOTE: stride \(stride) — FIXED-PHASE sample at (0,0) mod \(stride), not a population mean."
            )
        }
        if let reproduce {
            lines.append("")
            lines.append("## Reproduce")
            lines.append("")
            lines.append("```")
            lines.append(reproduce)
            lines.append("```")
        }

        lines.append("")
        lines.append("## How to read these tables")
        lines.append("")
        lines.append(
            "- **The convention-delta table is a COMPOUND comparison, not a clean convention effect.**"
        )
        lines.append(
            "  Production is one of its two sides, so the arm swaps the query path as well as the"
        )
        lines.append(
            "  candidate vocabulary: production scores a descriptor taken from the shipped thumbnail"
        )
        lines.append(
            "  cell (see `thumbCell`/`liveBins` in the geometry table), while the treatment side samples"
        )
        lines.append(
            "  the native source block. The single-variable convention delta is ladder rung"
        )
        lines.append(
            "  `squareSingleDisc` against `faithfulSingleDisc`, which holds the query support fixed."
        )
        lines.append(
            "- **The braille null control is in the LADDER, not the delta table.** `BrailleRasterizer`"
        )
        lines.append(
            "  draws dots over the whole cell rect under either cell-aspect placement, so for braille"
        )
        lines.append(
            "  `rectSingleDisc` and `faithfulSingleDisc` are the SAME vocabulary and every braille number"
        )
        lines.append(
            "  must agree between those two rungs exactly. Braille production candidates really are"
        )
        lines.append(
            "  rasterized at 64x64 (`BuildStandardVectors`), so rung `squareSingleDisc` is a different"
        )
        lines.append("  raster and is expected to differ.")
        lines.append(
            "- **Corpus caveat.** `nasa-occupancy-v1` and `nasa-isoluminant-v1` are committed as JPEGs."
        )
        lines.append(
            "  `RealFixture.load` accepted PNG only until this run, which is why no earlier Tools-side"
        )
        lines.append(
            "  census could reach them (it threw rather than dropping them silently) and why"
        )
        lines.append(
            "  `2026-08-19-sampling-lattice-support-collapse.md` had to retract two fixtures. JPEG is now"
        )
        lines.append(
            "  accepted; the compression artifacts in those assets are part of the measurement, so any"
        )
        lines.append("  figure quoted from that corpus must name it.")
        lines.append(
            "- **MAE is the verdict oracle (ASKI-27).** SSIM ratios against a near-zero baseline are"
        )
        lines.append(
            "  arithmetically true and perceptually meaningless; read the absolute means, not the percent."
        )
        lines.append(
            "- **Query polarity is a REGIME, not a detail.** Candidate rasters are ink-high"
        )
        lines.append(
            "  (`RasterizedCharacterSet.rasterize` fills at gray 0, draws at gray 1). Production's shape"
        )
        lines.append(
            "  query is `1 - luma` (`LogPolarKernel.baseInkField`), so its shape term treats DARK"
        )
        lines.append(
            "  source regions as ink, while its tone pre-filter matches a BRIGHT cell to a dense glyph."
        )
        lines.append(
            "  Those two disagree inside production. `inverted` reproduces production's shape term;"
        )
        lines.append(
            "  `direct` puts the query on the same footing as the candidates and the scoring path."
        )
        lines.append(
            "  Compare the two runs before reading any arm as a verdict on the candidate convention."
        )

        lines.append("")
        lines.append("## Resolved geometry (the regime, measured)")
        lines.append(
            "corpus | fixture | native | thumb | grid | thumbCell | windows@thumbCell | nativeBlock(min-max) | liveBins/60 | cells"
        )
        for row in report.geometry {
            lines.append(
                String(
                    format: "%@ | %@ | %dx%d | %dx%d | %dx%d | %dx%d | %d | %@x%@ | %.2f | %d",
                    row.corpus, row.fixture, row.nativeWidth, row.nativeHeight,
                    row.thumbnailWidth, row.thumbnailHeight, row.gridRows, row.gridColumns,
                    row.thumbCellWidth, row.thumbCellHeight, row.thumbCellWindows,
                    span(row.nativeBlockMinWidth, row.nativeBlockMaxWidth),
                    span(row.nativeBlockMinHeight, row.nativeBlockMaxHeight),
                    row.meanLiveBins, row.sampledCells))
        }

        lines.append("")
        lines.append("## ASKI-52 AC#1 — convention delta (production vs position-faithful vocabulary)")
        lines.append(
            "corpus | charset | oracle | cells | glyphs | prod | faithful | improve% | differ% | inkΔ(prod) | inkΔ(faithful) | maxInkΔ"
        )
        for row in ordered(report.delta, oracle: \.oracle) {
            lines.append(
                String(
                    format: "%@ | %@ | %@ | %d | %d | %.5f | %.5f | %.2f | %.1f | %.4f | %.4f | %.4f",
                    row.corpus, row.charset, row.oracle, row.cells, row.glyphs,
                    row.productionMean, row.faithfulMean, row.improvementPercent,
                    row.differingPickPercent, row.productionMeanInkDelta,
                    row.faithfulMeanInkDelta, row.maxInkDelta))
        }

        lines.append("")
        lines.append("## ASKI-26 AC#2 — ablation ladder (query and candidate sampled identically)")
        lines.append(
            "corpus | charset | arm | oracle | cells | cand | dim | win | mean | vsSquare% | prodAgree% | meanInkΔ"
        )
        for row in ordered(report.ladder, oracle: \.oracle) {
            lines.append(
                String(
                    format: "%@ | %@ | %@ | %@ | %d | %dx%d | %d | %d | %.5f | %.2f | %.1f | %.4f",
                    row.corpus, row.charset, row.arm, row.oracle, row.cells,
                    row.candidateWidth, row.candidateHeight, row.descriptorDimension,
                    row.windows, row.mean, row.improvementPercent,
                    row.productionAgreementPercent, row.meanInkDelta))
        }
        return lines.joined(separator: "\n")
    }

    /// Stable-sorts rows into the MAE-first oracle order without disturbing the
    /// corpus/charset/arm grouping the run emitted them in.
    private static func ordered<Row>(_ rows: [Row], oracle: KeyPath<Row, String>) -> [Row] {
        let rank = Dictionary(
            uniqueKeysWithValues: oracleOrder.enumerated().map { ($1.rawValue, $0) })
        return rows.enumerated()
            .sorted {
                let a = rank[$0.element[keyPath: oracle]] ?? Int.max
                let b = rank[$1.element[keyPath: oracle]] ?? Int.max
                return a == b ? $0.offset < $1.offset : a < b
            }
            .map(\.element)
    }

    /// A dimension that may vary across a fixture's cells: `39` when constant,
    /// `38-39` when the fractional lattice makes it vary.
    private static func span(_ low: Int, _ high: Int) -> String {
        low == high ? String(low) : "\(low)-\(high)"
    }

    static func trimmed(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "nan" : (value > 0 ? "inf" : "-inf") }
        return "\(value)".hasSuffix(".0") ? String("\(value)".dropLast(2)) : "\(value)"
    }
}
