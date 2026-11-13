import CoreGraphics
import Testing
@_spi(AskiResearch) @testable import Aski

struct LogPolarFootprintIntegrationTests {
    @Test func ordinaryRankedResidualAndHeldGlyphPathsMatchScalar() {
        for (width, height) in [(1, 5), (2, 3), (3, 3), (4, 7), (8, 12), (16, 24)] {
            for polarity in [ShapeQueryPolarity.inverted, .direct] {
                for emphasis: Float in [0, 0.5, 1] {
                    for density: Float in [0, 0.5, 1] {
                        var options = RenderingOptions(density: density, edgeEmphasis: emphasis)
                        options.shapeQueryPolarity = polarity
                        let pixelWidth = width * 3
                        let pixelHeight = height * 2
                        let pixels = (0..<(pixelWidth * pixelHeight * 4)).map { UInt8(($0 * 37 + 19) % 256) }
                        let context = ConversionContext(
                            pixels: pixels, pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                            cellWidth: width, cellHeight: height, columns: 3, rows: 2,
                            options: ResolvedRenderingOptions(options), colorSpace: .sRGB
                        )
                        for charset in [StandardCharacterSet.standard, .blocks] {
                            let bank = GlyphBank.adapting(charset)
                            let kernel = LogPolarKernel(glyphBank: bank)
                            let control = ScalarFootprintControl(glyphBank: bank)
                            for row in 0..<2 {
                                for column in 0..<3 {
                                    let cell = CellCoord(column: column, row: row)
                                    let stats = context.cellStats(at: cell)
                                    let lanes = control.lanes(cell: cell, in: context)
                                    #expect(bits(kernel.researchQueryShapeVector(cell: cell, in: context)) == bits(lanes))
                                    let expected = control.score(cell: cell, stats: stats, in: context)
                                    #expect(kernel.score(cell: cell, stats: stats, in: context) == expected)
                                    let scored = kernel.scoreScored(cell: cell, stats: stats, in: context)
                                    #expect(scored.character == expected)
                                    if context.cellSupportsShapeDescriptor {
                                        let scalar = ShapeMatching.findBestScored(
                                            queryLanes: lanes, queryBrightness: stats.adjustedL,
                                            candidateBrightness: bank.brightnessValues, candidateLanes: bank.shapeVectorLanes,
                                            topK: 12 + Int((density * 24).rounded())
                                        )
                                        #expect(scored.distance.bitPattern == scalar.distance.bitPattern)
                                    } else {
                                        #expect(scored.distance.isNaN)
                                    }
                                    for limit in [1, 6] {
                                        let match = kernel.matchWithDescriptor(cell: cell, stats: stats, in: context, resultLimit: limit)
                                        let ranked = control.ranked(cell: cell, stats: stats, in: context, limit: limit)
                                        #expect(Array(match.match.rankedIndices) == ranked)
                                        #expect(match.match.winnerIndex == ranked[0])
                                        #expect(match.match.winnerCharacter == expected)
                                        #expect(bits(match.lanes) == bits(context.cellSupportsShapeDescriptor ? lanes : []))
                                    }
                                    for glyph in [-1, 0, bank.characters.count / 2, bank.characters.count - 1, bank.characters.count] {
                                        let actual = kernel.distance(ofGlyph: glyph, forCell: cell, in: context)
                                        let expectedDistance = kernel.distance(fromLanes: lanes, toGlyph: glyph)
                                        #expect(actual.bitPattern == expectedDistance.bitPattern)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test(arguments: [1, 8, 80, 120], [2, 4, 8])
    func finalGridsMatchScalarInBothRowWalks(columns: Int, oversample: Int) throws {
        let context = try #require(
            CGContext(
                data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 3200,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
        for x in 0..<800 {
            let t = CGFloat(x) / 799
            context.setFillColor(red: t, green: 1 - t, blue: CGFloat(x % 19) / 18, alpha: x.isMultiple(of: 5) ? 0.5 : 1)
            context.fill(CGRect(x: x, y: 0, width: 1, height: 600))
        }
        let image = try #require(context.makeImage())
        var converter = DefaultConverter()
        converter.oversample = oversample
        converter.options.edgeEmphasis = 0.5
        converter.options.shapeQueryPolarity = .direct
        let preparation = try #require(converter.prepareConversion(image, columns: columns, mask: nil))
        let reference = ConversionEngine.renderRows(
            preparation: preparation, mode: .forcedSerial,
            capture: PlainCellCapture(kernel: ScalarFootprintControl(glyphBank: converter.glyphBank))
        )
        for mode in [GridRowWalk.Mode.forcedSerial, .forcedParallel] {
            converter.rowWalkMode = mode
            let ordinary = converter.convert(image, columns: columns)
            let ranked = converter.convertWithRankedCandidates(image, columns: columns, candidateStride: 6)
            let residual = converter.convertWithResidual(image, columns: columns)
            for cells in [ordinary.cells, ranked.grid.cells, residual.grid.cells] {
                #expect(cells == reference)
                #expect(cellBits(cells) == cellBits(reference))
            }
        }
    }

    private func bits(_ lanes: [SIMD4<Float>]) -> [UInt32] {
        lanes.flatMap { [$0.x.bitPattern, $0.y.bitPattern, $0.z.bitPattern, $0.w.bitPattern] }
    }

    private func cellBits(_ rows: [[ASCIICell]]) -> [UInt32] {
        rows.flatMap { row in
            row.flatMap { cell in
                [
                    cell.displayColor.x.bitPattern, cell.displayColor.y.bitPattern, cell.displayColor.z.bitPattern,
                    cell.alpha.bitPattern, cell.brightness.bitPattern, cell.coverage.bitPattern,
                ]
            }
        }
    }
}

/// Test-only control: extraction arithmetic from 4c675957, with the unchanged
/// scalar histogram. No runtime switch or second production matching policy.
private struct ScalarFootprintControl: CharacterScoring {
    let glyphBank: GlyphBank

    func score(cell: CellCoord, stats: CellStats, in context: borrowing ConversionContext) -> Character {
        glyphBank.characters[ranked(cell: cell, stats: stats, in: context, limit: 1)[0]]
    }

    func ranked(cell: CellCoord, stats: CellStats, in context: borrowing ConversionContext, limit: Int) -> [Int] {
        guard context.cellSupportsShapeDescriptor else {
            return ShapeMatching.poolIndices(queryBrightness: stats.adjustedL, candidateBrightness: glyphBank.brightnessValues, topK: limit)
        }
        let query = lanes(cell: cell, in: context)
        let topK = 12 + Int((context.options.density * 24).rounded())
        if limit == 1 {
            return [
                ShapeMatching.findBest(
                    queryLanes: query, queryBrightness: stats.adjustedL,
                    candidateBrightness: glyphBank.brightnessValues, candidateLanes: glyphBank.shapeVectorLanes, topK: topK
                )
            ]
        }
        return ShapeMatching.findRanked(
            queryLanes: query, queryBrightness: stats.adjustedL,
            candidateBrightness: glyphBank.brightnessValues, candidateLanes: glyphBank.shapeVectorLanes,
            brightnessLimit: topK, resultLimit: limit
        )
    }

    func lanes(cell: CellCoord, in context: borrowing ConversionContext) -> [SIMD4<Float>] {
        let w = context.cellWidth
        let h = context.cellHeight
        var grayscale = [Float](repeating: 0, count: w * h)
        for dy in 0..<h {
            for dx in 0..<w {
                let x = cell.column * w + dx
                let y = cell.row * h + dy
                let offset = (y * context.pixelWidth + x) * 4
                let red = Float(context.pixels[offset]) / 255
                let green = Float(context.pixels[offset + 1]) / 255
                let blue = Float(context.pixels[offset + 2]) / 255
                let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
                grayscale[dy * w + dx] = context.options.shapeQueryPolarity == .inverted ? 1 - luminance : luminance
            }
        }
        let emphasis = context.options.edgeEmphasis
        if emphasis > 0 {
            var sobel = [Float](repeating: 0, count: w * h)
            if w >= 3, h >= 3 {
                for y in 1..<(h - 1) {
                    for x in 1..<(w - 1) {
                        let gx =
                            -grayscale[(y - 1) * w + (x - 1)] + grayscale[(y - 1) * w + (x + 1)]
                            + -2 * grayscale[y * w + (x - 1)] + 2 * grayscale[y * w + (x + 1)]
                            + -grayscale[(y + 1) * w + (x - 1)] + grayscale[(y + 1) * w + (x + 1)]
                        let gy =
                            -grayscale[(y - 1) * w + (x - 1)] - 2 * grayscale[(y - 1) * w + x] - grayscale[(y - 1) * w + (x + 1)]
                            + grayscale[(y + 1) * w + (x - 1)] + 2 * grayscale[(y + 1) * w + x] + grayscale[(y + 1) * w + (x + 1)]
                        sobel[y * w + x] = (gx * gx + gy * gy).squareRoot()
                    }
                }
            }
            let peak = sobel.max() ?? 0
            if peak > 0 {
                for i in 0..<grayscale.count {
                    let g = grayscale[i]
                    let s = sobel[i] / peak
                    grayscale[i] = g * (1 - emphasis) + s * emphasis
                }
            }
        }
        let descriptor = ShapeContext.histogram60(grayscale, width: w, height: h)
        return stride(from: 0, to: ShapeContext.dimension, by: 4).map {
            SIMD4(descriptor[$0], descriptor[$0 + 1], descriptor[$0 + 2], descriptor[$0 + 3])
        }
    }
}
