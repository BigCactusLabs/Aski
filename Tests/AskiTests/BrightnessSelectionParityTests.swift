import simd
import Testing
@_spi(AskiResearch) @testable import Aski

@Suite struct BrightnessSelectionParityTests {
    @Test func fullSortFallbackPreservesSameHostNonfiniteOrder() {
        let finite: [Float] = [0.5, 0.125, 1, 0, 0.25, 0.75]
        for (query, values) in [
            (Float.nan, finite),
            (Float.infinity, finite),
            (Float(0.5), [.nan, 0.125, 1, 0, -.infinity, .infinity]),
        ] {
            for limit in [1, 3, values.count, values.count + 1] {
                #expect(
                    ShapeMatching.poolIndices(queryBrightness: query, candidateBrightness: values, topK: limit)
                        == Array(Self.fullSort(query, values).prefix(limit).map(\.index)))
            }
        }
    }

    @Test func wrappersKeepRoundedFloatTiesAndFiniteOverflowInPartialPools() {
        let maximum = Float.greatestFiniteMagnitude
        let brightness: [Float] = [0, 0x1p-26, -0.0, maximum, -maximum, 0.75, 0.25, 0.75]
        let bank = brightness + brightness + brightness + brightness + brightness
        let laneCount = StandardCharacterSet.lanesPerCharacter
        let queryLanes = Array(repeating: SIMD4<Float>.zero, count: laneCount)
        let candidateLanes = Array(repeating: SIMD4<Float>.zero, count: laneCount * bank.count)
        for query in [Float(1), 0.5, maximum, -0.0] {
            let expected = Self.fullSort(query, bank).map(\.index)
            for limit in [1, 12, 24, 36, bank.count, bank.count + 1] {
                let best = ShapeMatching.findBestScored(
                    queryLanes: queryLanes, queryBrightness: query,
                    candidateBrightness: bank, candidateLanes: candidateLanes, topK: limit)
                let ranked = ShapeMatching.findRanked(
                    queryLanes: queryLanes, queryBrightness: query,
                    candidateBrightness: bank, candidateLanes: candidateLanes,
                    brightnessLimit: limit, resultLimit: bank.count)
                let scored = ShapeMatching.findRankedScored(
                    queryLanes: queryLanes, queryBrightness: query,
                    candidateBrightness: bank, candidateLanes: candidateLanes,
                    brightnessLimit: limit, resultLimit: bank.count)
                #expect(best.index == expected[0])
                #expect(best.distance.bitPattern == 0)
                #expect(ranked == Array(expected.prefix(limit)))
                #expect(scored.map(\.index) == ranked)
                #expect(scored.allSatisfy { $0.distance.bitPattern == 0 })
            }
        }
    }

    @Test(arguments: [StandardCharacterSet.standard, .braille])
    func cellsWinnersResidualsAndCyclingMatchFullSort(set: StandardCharacterSet) throws {
        let image = TargetSizePreparationTests.photoLike(width: 98, height: 67)
        let columns = 24
        let stride = 6
        let modes: [(Int, ShapeQueryPolarity, Float)] = [
            (1, .inverted, 0), (4, .inverted, 0), (4, .direct, 0.75),
        ]
        for (oversample, polarity, edge) in modes {
            var options = RenderingOptions(edgeEmphasis: edge)
            options.shapeQueryPolarity = polarity
            var converter = ASCIIConverter(
                characterSet: set, palette: BuiltInPalette.monochrome, options: options, oversample: oversample)
            let preparation = try #require(converter.prepareConversion(image, columns: columns, mask: nil))
            let context = preparation.context
            #expect(context.cellSupportsShapeDescriptor == (oversample > 1))
            let kernel = LogPolarKernel(glyphBank: converter.glyphBank)
            let bank = converter.glyphBank
            var expected: [[ASCIICell]] = []
            var candidates: [UInt16] = []
            var residuals: [UInt32] = []
            for row in 0..<context.rows {
                var cells: [ASCIICell] = []
                for column in 0..<context.columns {
                    let coord = CellCoord(column: column, row: row)
                    let stats = context.finalizeColor(source: context.cellSourceStats(at: coord))
                    let tone = Self.fullSort(stats.adjustedL, bank.brightnessValues)
                    let ranked: [Int]
                    let residual: Float
                    if context.cellSupportsShapeDescriptor {
                        let query = kernel.researchQueryShapeVector(cell: coord, in: context)
                        let scored = tone.prefix(12).map { pair in
                            let offset = pair.index * StandardCharacterSet.lanesPerCharacter
                            var distance: Float = 0
                            for lane in query.indices {
                                let delta = query[lane] - bank.shapeVectorLanes[offset + lane]
                                distance += simd_dot(delta, delta)
                            }
                            return (index: pair.index, distance: distance, delta: pair.delta)
                        }.sorted {
                            if $0.distance != $1.distance { return $0.distance < $1.distance }
                            if $0.delta != $1.delta { return $0.delta < $1.delta }
                            return $0.index < $1.index
                        }
                        ranked = scored.prefix(stride).map(\.index)
                        residual = scored[0].distance
                        let match = kernel.matchWithDescriptor(cell: coord, stats: stats, in: context, resultLimit: stride)
                        #expect(match.lanes == query)
                        #expect(match.match.winnerIndex == ranked[0])
                    } else {
                        ranked = tone.prefix(stride).map(\.index)
                        residual = .nan
                    }
                    cells.append(
                        ASCIICell(
                            character: bank.characters[ranked[0]], displayColor: stats.displayColor,
                            alpha: stats.alpha, brightness: stats.adjustedL
                        ))
                    candidates.append(contentsOf: ranked.map { UInt16($0) })
                    residuals.append(residual.bitPattern)
                }
                expected.append(cells)
            }

            for mode: GridRowWalk.Mode in [.forcedSerial, .forcedParallel] {
                converter.rowWalkMode = mode
                let ordinary = converter.convert(image, columns: columns)
                let ranked = converter.convertWithRankedCandidates(image, columns: columns, candidateStride: stride)
                let scored = converter.convertWithResidual(image, columns: columns)
                #expect(ordinary.cells == expected)
                #expect(ranked.grid.cells == expected)
                #expect(scored.grid.cells == expected)
                #expect(Array(ranked.candidates) == candidates)
                #expect(ranked.candidateCounts.allSatisfy { $0 == UInt16(stride) })
                #expect(scored.residual.map(\.bitPattern) == residuals)
            }
        }
    }

    @Test func zeroColumnsStillReturnsEmptyConversion() {
        let image = TargetSizePreparationTests.photoLike(width: 8, height: 6)
        let converter = DefaultConverter()
        #expect(converter.convert(image, columns: 0).cells.isEmpty)
        #expect(converter.convertWithRankedCandidates(image, columns: 0, candidateStride: 6).candidates.isEmpty)
        #expect(converter.convertWithResidual(image, columns: 0).residual.isEmpty)
    }

    private static func fullSort(_ query: Float, _ values: [Float]) -> [(index: Int, delta: Float)] {
        var pairs: [(index: Int, delta: Float)] = []
        pairs.reserveCapacity(values.count)
        for index in values.indices {
            pairs.append((index, abs(values[index] - query)))
        }
        pairs.sort {
            if $0.delta == $1.delta { return $0.index < $1.index }
            return $0.delta < $1.delta
        }
        return pairs
    }
}
