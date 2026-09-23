import AskiToolSupport
import Foundation
import simd

@_spi(AskiResearch) import Aski

extension Arbiter {

    /// The per-(source, charset) census the stimuli step runs once and every pair
    /// on that source then reads (v2 §2).
    ///
    /// This is the performance contract: a pair is a lookup into a census, not a
    /// census of its own. Each converter arm converts exactly once; selection
    /// arms share the inverted-production query and scaffold.
    ///
    /// It reuses `SelectionCeiling`'s arm selectors verbatim rather than
    /// reimplementing them. Two arms that differ in anything but the term under
    /// test are not comparable, and the census battery's selectors are the ones
    /// every standing verdict was measured with.
    enum Census {

        /// One source × charset, fully scored.
        struct Result: Sendable {
            /// Per-arm full grids, ready to render. Converter arms retain their
            /// actual grid; selection arms substitute only characters onto the
            /// inverted production grid.
            let grids: [ArmRef: ASCIIGrid]
            /// Per-arm mean oracle scores over the scored cells.
            let means: [ArmRef: [SelectionCeiling.Oracle: Double]]
            /// Audit field for the v2 performance contract.
            let converterConversionCounts: [ArmRef: Int]
            /// Cells that contributed to the MAE mean.
            let cells: Int
        }

        /// Run one real production conversion for a typed converter arm.
        static func converterGrid(
            fixture: ResidualFixture,
            characterSet: StandardCharacterSet,
            arm: ConverterArm,
            columns: Int,
            oversample: Int
        ) -> ASCIIGrid {
            var options = RenderingOptions.default
            switch arm {
            case .productionInverted:
                options.shapeQueryPolarity = .inverted
            case .productionDirect:
                options.shapeQueryPolarity = .direct
            }
            return ASCIIConverter(
                characterSet: characterSet,
                palette: BuiltInPalette.monochrome,
                options: options,
                colorSpace: .sRGB,
                oversample: oversample
            ).convert(fixture.image, columns: columns)
        }

        /// Scores every arm in `arms` on one fixture and charset.
        ///
        /// Mirrors `SelectionCeiling.census`'s inner loop with one difference:
        /// only the ARMS' picked glyphs are scored per cell, not all glyphs. The
        /// optimality gap needs the whole candidate row; the arbiter needs two
        /// sides, so the cost is `cells × arms × oracles` rather than
        /// `cells × glyphs × oracles`.
        static func run(
            fixture: ResidualFixture,
            charsetName: String,
            arms: [Arm],
            columns: Int,
            oversample: Int,
            footprint: Int
        ) throws -> Result {
            let characterSet = try SelectionCeiling.characterSet(named: charsetName)
            let glyphs = characterSet.characters
            try SelectionCeiling.assertUniqueGlyphs(glyphs, charset: charsetName)
            let density = characterSet.rawDensityValues
            let brightness = characterSet.brightnessValues
            let candidateLanes = characterSet.shapeVectorLanes
            let rasters = glyphs.map {
                GlyphRaster.luma(character: $0, width: footprint, height: footprint)
            }

            let selectionConverter = ASCIIConverter(
                characterSet: characterSet,
                palette: BuiltInPalette.monochrome,
                colorSpace: .sRGB,
                oversample: oversample
            )
            let converterArms = arms.compactMap { arm -> ConverterArm? in
                guard case .converter(let converter) = arm else { return nil }
                return converter
            }
            var converterGrids: [ArmRef: ASCIIGrid] = [:]
            var converterConversionCounts: [ArmRef: Int] = [:]
            for arm in converterArms {
                let ref = ArmRef(arm)
                converterGrids[ref] = converterGrid(
                    fixture: fixture, characterSet: characterSet, arm: arm,
                    columns: columns, oversample: oversample)
                converterConversionCounts[ref, default: 0] += 1
            }
            let baselineRef = ArmRef(ConverterArm.productionInverted)
            guard let baselineGrid = converterGrids[baselineRef] else {
                throw ArbiterError.missingScore(
                    source: fixture.id, charset: charsetName, arm: baselineRef.label)
            }
            let gridRows = baselineGrid.rows, gridCols = baselineGrid.columns
            guard gridRows > 0, gridCols > 0 else {
                throw ArbiterError.missingScore(
                    source: fixture.id, charset: charsetName, arm: "(empty grid)")
            }
            for (ref, grid) in converterGrids
            where grid.rows != gridRows || grid.columns != gridCols {
                throw ArbiterError.missingScore(
                    source: fixture.id, charset: charsetName,
                    arm: "\(ref.label) (grid geometry mismatch)")
            }
            let queries = selectionConverter.cellQueryDescriptors(
                fixture.image, columns: columns)
            let geometry = selectionConverter.samplingGeometry(
                fixture.image, columns: columns)
            let selectionArms = arms.compactMap { arm -> SelectionCeiling.Arm? in
                guard case .selection(let selection) = arm else { return nil }
                return selection
            }

            // §6.2's pooled per-charset moments, gathered exactly as the census
            // battery gathers them so the z-normalized arm here IS that arm.
            var zStats: SelectionCeiling.LossStats?
            if selectionArms.contains(where: {
                if case .zNormalized = $0 { return true }
                return false
            }),
                let queries
            {
                var accumulator = SelectionCeiling.LossAccumulator()
                for row in 0..<queries.rows {
                    for col in 0..<queries.columns {
                        let tone = queries.adjustedL(row: row, column: col)
                        let distances = SelectionCeiling.shapeDistances(
                            queryLanes: queries.lanes(row: row, column: col),
                            candidateLanes: candidateLanes)
                        for index in distances.indices {
                            accumulator.add(
                                shape: distances[index],
                                tone: SelectionCeiling.toneLoss(brightness[index], tone))
                        }
                    }
                }
                zStats = accumulator.resolved()
            }

            // Every selection arm starts as inverted production's characters,
            // so an unscored cell keeps a real glyph rather than a hole. Each
            // converter arm already owns its real grid. Means count only cells
            // the arm actually supplies, so no fallback glyph enters a score.
            let productionCharacters = baselineGrid.cells.map { $0.map(\.character) }
            var selectionPicks: [ArmRef: [[Character]]] = [:]
            var sums: [ArmRef: [SelectionCeiling.Oracle: Double]] = [:]
            var counts: [ArmRef: [SelectionCeiling.Oracle: Int]] = [:]
            for arm in arms {
                let ref = ArmRef(arm)
                if case .selection = arm {
                    selectionPicks[ref] = productionCharacters
                }
                sums[ref] = Dictionary(
                    uniqueKeysWithValues: SelectionCeiling.Oracle.allCases.map { ($0, 0.0) })
                counts[ref] = Dictionary(
                    uniqueKeysWithValues: SelectionCeiling.Oracle.allCases.map { ($0, 0) })
            }

            let descriptorSupported = queries?.supportsShapeDescriptor ?? false

            for row in 0..<gridRows {
                for col in 0..<gridCols {
                    guard
                        let geometry,
                        let block = SampledSource.lumaBlock(
                            fixture, cellRow: row, cellCol: col, geometry: geometry),
                        block.width >= 2, block.height >= 2
                    else { continue }
                    let source = LumaResample.resample(
                        block.luma, srcWidth: block.width, srcHeight: block.height,
                        dstWidth: footprint, dstHeight: footprint)
                    let meanLuma = block.luma.reduce(0, +) / Float(block.luma.count)
                    let query: (lanes: [SIMD4<Float>], tone: Float)? = {
                        guard let queries, row < queries.rows, col < queries.columns else {
                            return nil
                        }
                        return (
                            queries.lanes(row: row, column: col),
                            queries.adjustedL(row: row, column: col)
                        )
                    }()

                    var cellPicks: [ArmRef: Int] = [:]
                    for (ref, grid) in converterGrids {
                        let picked = grid.cells[row][col].character
                        if let index = glyphs.firstIndex(of: picked) {
                            cellPicks[ref] = index
                        }
                    }
                    for arm in selectionArms {
                        let index: Int?
                        switch arm {
                        case .production:
                            index = glyphs.firstIndex(
                                of: baselineGrid.cells[row][col].character)
                        case .floor:
                            index =
                                query.map {
                                    SelectionCeiling.floorPick(
                                        adjustedL: $0.tone, brightnessValues: brightness)
                                }
                                ?? SelectionCeiling.legacyFloorPick(
                                    meanBlockLuma: meanLuma, rawDensityValues: density)
                        case .legacyFloor:
                            index = SelectionCeiling.legacyFloorPick(
                                meanBlockLuma: meanLuma, rawDensityValues: density)
                        case .toneWeighted(let w):
                            index =
                                descriptorSupported
                                ? query.map {
                                    SelectionCeiling.toneWeightedPick(
                                        queryLanes: $0.lanes, adjustedL: $0.tone,
                                        candidateLanes: candidateLanes,
                                        brightnessValues: brightness, toneWeight: w)
                                } : nil
                        case .poolWidth(let topK):
                            index =
                                descriptorSupported
                                ? query.map {
                                    SelectionCeiling.poolWidthPick(
                                        queryLanes: $0.lanes, adjustedL: $0.tone,
                                        candidateLanes: candidateLanes,
                                        brightnessValues: brightness, topK: topK)
                                } : nil
                        case .lexicographic(let shapeK):
                            index =
                                descriptorSupported
                                ? query.map {
                                    SelectionCeiling.lexicographicPick(
                                        queryLanes: $0.lanes, adjustedL: $0.tone,
                                        candidateLanes: candidateLanes,
                                        brightnessValues: brightness, shapeK: shapeK)
                                } : nil
                        case .zNormalized(let w):
                            index =
                                descriptorSupported
                                ? query.map {
                                    SelectionCeiling.zNormalizedPick(
                                        queryLanes: $0.lanes, adjustedL: $0.tone,
                                        candidateLanes: candidateLanes,
                                        brightnessValues: brightness, toneWeight: w,
                                        stats: zStats)
                                } : nil
                        }
                        if let index {
                            cellPicks[ArmRef(Arm.selection(arm))] = index
                        }
                    }

                    for (ref, index) in cellPicks {
                        selectionPicks[ref]?[row][col] = glyphs[index]
                        for oracle in SelectionCeiling.Oracle.allCases {
                            let score = oracle.score(rasters[index], source, footprint: footprint)
                            guard score.isFinite else { continue }
                            sums[ref]?[oracle]? += score
                            counts[ref]?[oracle]? += 1
                        }
                    }
                }
            }

            var means: [ArmRef: [SelectionCeiling.Oracle: Double]] = [:]
            for arm in arms {
                let ref = ArmRef(arm)
                var armMeans: [SelectionCeiling.Oracle: Double] = [:]
                for oracle in SelectionCeiling.Oracle.allCases {
                    let count = counts[ref]?[oracle] ?? 0
                    guard count > 0 else { continue }
                    armMeans[oracle] = (sums[ref]?[oracle] ?? 0) / Double(count)
                }
                means[ref] = armMeans
            }
            var grids = converterGrids
            for (ref, characters) in selectionPicks {
                grids[ref] = substituted(grid: baselineGrid, characters: characters)
            }
            let scoredCells = counts[baselineRef]?[.mae] ?? 0
            return Result(
                grids: grids, means: means,
                converterConversionCounts: converterConversionCounts,
                cells: scoredCells)
        }

        /// Substitute an arm's characters into the production grid. Colour,
        /// alpha, coverage and geometry stay production's, so the two sides of a
        /// pair differ ONLY in the glyph selection under test.
        static func substituted(grid: ASCIIGrid, characters: [[Character]]) -> ASCIIGrid {
            var cells = grid.cells
            for row in cells.indices where row < characters.count {
                for col in cells[row].indices where col < characters[row].count {
                    let cell = cells[row][col]
                    cells[row][col] = ASCIICell(
                        character: characters[row][col],
                        displayColor: cell.displayColor,
                        alpha: cell.alpha,
                        brightness: cell.brightness,
                        coverage: cell.coverage)
                }
            }
            return ASCIIGrid(
                cells: cells, colorSpace: grid.colorSpace, composition: grid.composition,
                maskFallback: grid.maskFallback, maskUsesHardEdges: grid.maskUsesHardEdges)
        }
    }
}
