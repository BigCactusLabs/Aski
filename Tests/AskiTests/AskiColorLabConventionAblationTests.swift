import AskiToolSupport
import Foundation
import Testing

@_spi(AskiResearch) @testable import Aski
@testable import AskiColorLab

/// Guards the plumbing of the ASKI-52 / ASKI-26 convention-ablation arms.
///
/// What these tests pin is the *instrument's* invariants — that the ladder is
/// complete, that every arm samples its query side with the same configuration
/// as its candidate side, that the two sides share a pixel geometry before
/// sampling, and that the selector and reporting arithmetic behave. They pin no
/// corpus number: the measured tables are the run's output, and freezing them
/// here would turn a research result into a regression test and make an honest
/// re-measurement look like a break.
@Suite struct AskiColorLabConventionAblationTests {

    private static let cellWidth = 12
    private static let cellHeight = 24

    /// The ladder is the argument: five rungs, each isolating one step from the
    /// shipped convention to the paper's. A rung silently dropped would leave a
    /// gap in the chain that the report would still read as continuous.
    @Test func theLadderCarriesAllFiveRungs() {
        let arms = ConventionAblation.LadderArm.allCases
        #expect(arms.count == 5)
        #expect(
            arms.map(\.rawValue) == [
                "squareSingleDisc", "rectSingleDisc", "faithfulSingleDisc",
                "faithfulTiled", "faithfulTiledNoBlur",
            ])
        // The rungs walk exactly one step at a time: square→rect changes the
        // raster geometry only, rect→faithful the placement only, and the last
        // two the sampling support only.
        #expect(ConventionAblation.LadderArm.squareSingleDisc.placement == .boundsCentredSquare)
        #expect(ConventionAblation.LadderArm.rectSingleDisc.placement == .boundsCentredRect)
        #expect(ConventionAblation.LadderArm.faithfulSingleDisc.placement == .positionFaithful)
        #expect(ConventionAblation.LadderArm.faithfulTiled.placement == .positionFaithful)
        #expect(ConventionAblation.LadderArm.faithfulTiledNoBlur.placement == .positionFaithful)
        #expect(ConventionAblation.LadderArm.squareSingleDisc.sampling.support == .singleDisc)
        #expect(ConventionAblation.LadderArm.rectSingleDisc.sampling.support == .singleDisc)
        #expect(ConventionAblation.LadderArm.faithfulSingleDisc.sampling.support == .singleDisc)
        #expect(ConventionAblation.LadderArm.faithfulTiled.sampling.support == .tiled(stride: 2))
        #expect(
            ConventionAblation.LadderArm.faithfulTiledNoBlur.sampling.support == .tiled(stride: 2))
        // The blur ablation differs from its blurred twin in the blur ALONE.
        #expect(ConventionAblation.LadderArm.faithfulTiled.sampling.blurSigma != nil)
        #expect(ConventionAblation.LadderArm.faithfulTiledNoBlur.sampling.blurSigma == nil)
    }

    /// The whole premise of the ladder is matched support: an arm's query side is
    /// sampled with the SAME configuration and at the SAME pixel geometry as its
    /// candidates. If a query could be sampled at a different geometry the two
    /// descriptors would not even have the same length, and a distance between
    /// them would be arithmetic rather than a comparison.
    @Test func everyArmSamplesQueryAndCandidateAtOneGeometryAndOneConfiguration() {
        // A stand-in native block at a geometry no arm uses, so a query that
        // failed to be resampled would show up as a length mismatch.
        let nativeWidth = 39, nativeHeight = 77
        let block = (0..<(nativeWidth * nativeHeight)).map { Float($0 % 7) / 6 }

        for arm in ConventionAblation.LadderArm.allCases {
            let vocabulary = ConventionAblation.Vocabulary.build(
                characters: ["A", "▄", "▀", " "],
                cellWidth: Self.cellWidth, cellHeight: Self.cellHeight,
                placement: arm.placement, sampling: arm.sampling)
            let query = LumaResample.resample(
                block, srcWidth: nativeWidth, srcHeight: nativeHeight,
                dstWidth: vocabulary.width, dstHeight: vocabulary.height)
            #expect(query.count == vocabulary.width * vocabulary.height)
            let descriptor = LogPolarCellSampling.descriptor(
                query, width: vocabulary.width, height: vocabulary.height,
                configuration: arm.sampling)
            #expect(
                descriptor.count == vocabulary.descriptorDimension,
                "\(arm.rawValue): query descriptor is \(descriptor.count)-D, candidates are \(vocabulary.descriptorDimension)-D"
            )
            for entry in vocabulary.entries {
                #expect(
                    entry.descriptor.count == descriptor.count,
                    "\(arm.rawValue): candidate '\(entry.character)' descriptor length differs from the query's")
                #expect(entry.width == vocabulary.width && entry.height == vocabulary.height)
            }
        }
    }

    /// The candidate geometry each rung declares must be the one it actually
    /// rasterizes at — the square rung at 64×64 regardless of the cell, the rest
    /// at the true cell aspect — and the tiled rungs must carry the paper's
    /// window arithmetic rather than a single disc.
    @Test func armGeometriesAndWindowCountsAreWhatTheRungsClaim() {
        func vocabulary(_ arm: ConventionAblation.LadderArm) -> ConventionAblation.Vocabulary {
            ConventionAblation.Vocabulary.build(
                characters: ["A", "M"], cellWidth: Self.cellWidth, cellHeight: Self.cellHeight,
                placement: arm.placement, sampling: arm.sampling)
        }
        let square = vocabulary(.squareSingleDisc)
        #expect(square.width == 64 && square.height == 64)
        #expect(square.windows == 1 && square.descriptorDimension == 60)

        for arm in [
            ConventionAblation.LadderArm.rectSingleDisc, .faithfulSingleDisc,
        ] {
            let rect = vocabulary(arm)
            #expect(rect.width == Self.cellWidth && rect.height == Self.cellHeight)
            #expect(rect.windows == 1 && rect.descriptorDimension == 60)
        }
        for arm in [ConventionAblation.LadderArm.faithfulTiled, .faithfulTiledNoBlur] {
            let tiled = vocabulary(arm)
            #expect(tiled.width == Self.cellWidth && tiled.height == Self.cellHeight)
            // 12×24 at stride 2 is the paper's own worked example.
            #expect(tiled.windows == 72)
            #expect(tiled.descriptorDimension == 4320)
        }
    }

    /// The ladder's braille null control. Braille has no bounds-cropped form:
    /// `BrailleRasterizer` draws dots over the whole cell rect whatever the
    /// placement asks for, so rungs (ii) and (iii) are the SAME vocabulary for
    /// braille and every braille number must agree between them exactly. That
    /// identity is what licenses reading a braille difference elsewhere in the
    /// report as the instrument rather than the convention — so it is pinned
    /// here rather than inferred from the run.
    ///
    /// The square rung is deliberately excluded: braille production candidates
    /// really are rasterized at 64×64 (`BuildStandardVectors`), so rung (i) is a
    /// different raster and is expected to differ.
    @Test func brailleIsInertBetweenTheTwoCellAspectPlacements() {
        let glyphs: [Character] = [
            "\u{2800}", "\u{2801}", "\u{2808}", "\u{2847}", "\u{28FF}",
        ]
        let rect = ConventionAblation.Vocabulary.build(
            characters: glyphs, cellWidth: Self.cellWidth, cellHeight: Self.cellHeight,
            placement: .boundsCentredRect, sampling: .singleDisc)
        let faithful = ConventionAblation.Vocabulary.build(
            characters: glyphs, cellWidth: Self.cellWidth, cellHeight: Self.cellHeight,
            placement: .positionFaithful, sampling: .singleDisc)
        #expect(rect.width == faithful.width && rect.height == faithful.height)
        for (a, b) in zip(rect.entries, faithful.entries) {
            #expect(a.character == b.character)
            #expect(a.descriptor == b.descriptor, "braille '\(a.character)' descriptor moved")
            #expect(a.normalizedBrightness == b.normalizedBrightness)
        }
        // The contrast that makes the control meaningful: a TEXT glyph with ink
        // off the centre of its cell does move between the same two placements.
        let text = ["_"] as [Character]
        let textRect = ConventionAblation.Vocabulary.build(
            characters: text, cellWidth: Self.cellWidth, cellHeight: Self.cellHeight,
            placement: .boundsCentredRect, sampling: .singleDisc)
        let textFaithful = ConventionAblation.Vocabulary.build(
            characters: text, cellWidth: Self.cellWidth, cellHeight: Self.cellHeight,
            placement: .positionFaithful, sampling: .singleDisc)
        #expect(textRect.entries[0].descriptor != textFaithful.entries[0].descriptor)
    }

    /// The pool prune must select exactly the `poolWidth` tone-nearest
    /// candidates. It is implemented as a binary search into a pre-sorted
    /// brightness list rather than a per-cell argsort, so the equivalence with
    /// the naive selection is a property worth pinning rather than assuming.
    @Test func theTonePruneSelectsTheSameSetAnArgsortWould() {
        let vocabulary = ConventionAblation.Vocabulary.build(
            characters: ["█", "▓", "▒", "░", "▄", "▀", "▌", " "],
            cellWidth: Self.cellWidth, cellHeight: Self.cellHeight,
            placement: .positionFaithful, sampling: .singleDisc)
        let brightness = vocabulary.entries.map(\.normalizedBrightness)
        for query in stride(from: Float(0), through: 1, by: 0.125) {
            for width in [1, 3, 12] {
                let pool = Set(vocabulary.pool(brightness: query, width: width))
                let expected = Set(
                    brightness.indices
                        .sorted {
                            let a = abs(brightness[$0] - query), b = abs(brightness[$1] - query)
                            return a == b ? $0 < $1 : a < b
                        }
                        .prefix(min(width, brightness.count)))
                #expect(
                    pool.count == min(width, brightness.count),
                    "pool at q=\(query) width=\(width) returned \(pool.count) candidates")
                // Ties may resolve to a different member of an equal-error pair,
                // so compare the achieved tone errors rather than the indices.
                #expect(
                    pool.map { abs(brightness[$0] - query) }.sorted()
                        == expected.map { abs(brightness[$0] - query) }.sorted(),
                    "pool at q=\(query) width=\(width) is not the tone-nearest set")
            }
        }
        // A width at or above the glyph count makes the prune inert — which is
        // the case on the shipping `blocks` preset, whose 8 glyphs sit under the
        // production pool width of 12.
        #expect(
            vocabulary.pool(brightness: 0.5, width: SelectionCeiling.productionPoolWidth).count
                == vocabulary.entries.count)
    }

    /// The selector must be a descriptor argmin inside that pool: handed a
    /// candidate's own descriptor it has to return that candidate, or the arms
    /// are not measuring glyph choice at all.
    @Test func theSelectorRecoversACandidateFromItsOwnDescriptor() {
        for arm in ConventionAblation.LadderArm.allCases {
            let vocabulary = ConventionAblation.Vocabulary.build(
                characters: ["█", "▄", "▀", "A", " "],
                cellWidth: Self.cellWidth, cellHeight: Self.cellHeight,
                placement: arm.placement, sampling: arm.sampling)
            for (index, entry) in vocabulary.entries.enumerated() {
                let pick = vocabulary.pick(
                    descriptor: entry.descriptor, brightness: entry.normalizedBrightness,
                    poolWidth: SelectionCeiling.productionPoolWidth)
                #expect(
                    pick == index
                        || vocabulary.entries[pick].descriptor == entry.descriptor,
                    "\(arm.rawValue): '\(entry.character)' did not recover itself (got '\(vocabulary.entries[pick].character)')"
                )
            }
        }
    }

    /// Query polarity has to be exactly `1 - luma` under `inverted`, because that
    /// is what `LogPolarKernel.baseInkField` computes and the whole point of
    /// the arm is to reproduce production's shape term rather than approximate it.
    /// `direct` must be the identity, not a near-identity.
    @Test func queryPolarityReproducesTheProductionInversionExactly() {
        let field: [Float] = [0, 0.25, 0.5, 0.75, 1]
        #expect(ConventionAblation.QueryPolarity.direct.apply(field) == field)
        #expect(
            ConventionAblation.QueryPolarity.inverted.apply(field) == [1, 0.75, 0.5, 0.25, 0])
        // Involution: inverting twice is the identity, so the factor cannot leak
        // a scale or an offset into one of the two regimes.
        let once = ConventionAblation.QueryPolarity.inverted.apply(field)
        #expect(ConventionAblation.QueryPolarity.inverted.apply(once) == field)
    }

    /// The square rung claims to BE the shipped candidate convention, so its text
    /// rasters must carry production's point size. `BuildStandardVectors` uses
    /// 32pt into a 64x64 canvas; letting the point size follow the canvas puts it
    /// at 64pt, and the rung would measure a 2x scale change on top of the
    /// convention it is supposed to isolate.
    @Test func theSquareRungRasterizesAtProductionsPointSize() {
        let glyph: Character = "M"
        let square = PositionFaithfulVocabulary.raster(
            character: glyph, width: 64, height: 64, placement: .boundsCentredSquare)
        let atProductionScale = GlyphRaster.luma(
            character: glyph, width: 64, height: 64,
            pointSize: GlyphRaster.productionShapeVectorPointSize)
        #expect(square == atProductionScale)

        // And it is genuinely a different raster from the canvas-derived default,
        // so the assertion above is not vacuous.
        let atCanvasScale = GlyphRaster.luma(character: glyph, width: 64, height: 64)
        #expect(square != atCanvasScale)
        // The 32pt glyph covers less of the canvas than the 64pt one.
        let squareInk = PositionFaithfulVocabulary.meanInk(square)
        let canvasInk = PositionFaithfulVocabulary.meanInk(atCanvasScale)
        #expect(squareInk < canvasInk)
        // Every pre-existing caller passes no point size and must be unchanged.
        #expect(
            GlyphRaster.luma(character: glyph, width: 24, height: 24)
                == GlyphRaster.luma(character: glyph, width: 24, height: 24, pointSize: 24))
    }

    /// The pool must come back in PRODUCTION's order — sorted by brightness delta,
    /// ties to the lower glyph index — because `ShapeMatching.findBestScored`
    /// scans in that order and keeps the FIRST minimum. On a descriptor-distance
    /// tie the winner is therefore the tone-nearest candidate, not the
    /// lowest-indexed one, and the collapsed shipping descriptor makes such ties
    /// common rather than hypothetical.
    @Test func theToneOrderIsProductionsPoolOrder() {
        let vocabulary = ConventionAblation.Vocabulary.build(
            characters: ["█", "▓", "▒", "░", "▄", "▀", "▌", " "],
            cellWidth: Self.cellWidth, cellHeight: Self.cellHeight,
            placement: .positionFaithful, sampling: .singleDisc)
        let brightness = vocabulary.entries.map(\.normalizedBrightness)
        for query in stride(from: Float(0), through: 1, by: 0.125) {
            for width in [1, 3, 8] {
                let pool = vocabulary.pool(brightness: query, width: width)
                // Exactly ShapeMatching.findBestScored's sort.
                var pairs: [(index: Int, delta: Float)] = []
                for index in brightness.indices {
                    pairs.append((index, abs(brightness[index] - query)))
                }
                pairs.sort {
                    $0.delta == $1.delta ? $0.index < $1.index : $0.delta < $1.delta
                }
                let expected: [Int] = pairs.prefix(min(width, brightness.count)).map(\.index)
                #expect(
                    pool == expected,
                    "pool at q=\(query) width=\(width) is not in production's order")
            }
        }
    }

    /// Rungs (ii) and (iii) must differ in the CENTRING RULE and in nothing else.
    /// Routing (ii) through `GlyphRaster` put a 24pt native raster against an
    /// effectively 20pt supersampled one at a 12x24 cell, so the delta that rung
    /// pair exists to isolate was confounded with scale, hinting and clipping.
    @Test func theTwoCellAspectPlacementsShareOneScaleAndOneRasterPath() {
        let glyph: Character = "_"
        let rect = PositionFaithfulVocabulary.raster(
            character: glyph, width: Self.cellWidth, height: Self.cellHeight,
            placement: .boundsCentredRect)
        let faithful = PositionFaithfulVocabulary.raster(
            character: glyph, width: Self.cellWidth, height: Self.cellHeight,
            placement: .positionFaithful)
        // Same path and scale: the ink MASS is preserved to within resampling
        // noise, because only the position moved. A 20pt-vs-24pt comparison
        // would move total ink by far more than this.
        let rectInk = PositionFaithfulVocabulary.meanInk(rect)
        let faithfulInk = PositionFaithfulVocabulary.meanInk(faithful)
        #expect(abs(rectInk - faithfulInk) < 0.02, "ink mass moved: \(rectInk) vs \(faithfulInk)")
        // And the placement really did change: '_' sits on the baseline
        // typographically and in the middle once bounds-centred.
        #expect(rect != faithful)

        // The old confound, pinned so it cannot come back: the canvas-derived
        // point size is a genuinely different raster from the shared path's.
        let viaGlyphRaster = GlyphRaster.luma(
            character: glyph, width: Self.cellWidth, height: Self.cellHeight)
        #expect(viaGlyphRaster != rect)
    }

    /// Braille has no bounds-cropped form, so the centring flag must be inert for
    /// it — this is what keeps the ladder's braille null control exact.
    @Test func theCentringFlagIsInertForBraille() {
        for scalar in ["\u{2801}", "\u{2847}", "\u{28FF}"] as [Character] {
            let plain = GlyphCellRaster.luma(
                character: scalar, width: Self.cellWidth, height: Self.cellHeight)
            let centred = GlyphCellRaster.luma(
                character: scalar, width: Self.cellWidth, height: Self.cellHeight,
                boundsCentred: true)
            #expect(plain == centred, "braille '\(scalar)' moved under bounds-centring")
        }
    }

    /// The native block varies cell to cell under fractional scaling, so the
    /// geometry table reports a range. A single value would misdescribe exactly
    /// the non-integral regime the table documents.
    @Test func theGeometryTableReportsANativeBlockRange() {
        #expect(ConventionAblation.geometryCSVHeader.contains("nativeBlockMinW"))
        #expect(ConventionAblation.geometryCSVHeader.contains("nativeBlockMaxW"))
        #expect(ConventionAblation.geometryCSVHeader.contains("nativeBlockMinH"))
        #expect(ConventionAblation.geometryCSVHeader.contains("nativeBlockMaxH"))
    }

    /// The improvement column is signed so that POSITIVE always reads "the arm
    /// is better", in both oracle polarities. Getting that backwards on one
    /// polarity would invert half the report without changing a single number.
    @Test func improvementIsSignedTowardsBetterInBothPolarities() {
        // Lower-is-better: a smaller arm mean is an improvement.
        #expect(
            ConventionAblation.improvement(baseline: 0.4, arm: 0.2, polarity: .lowerIsBetter) == 50)
        #expect(
            ConventionAblation.improvement(baseline: 0.2, arm: 0.4, polarity: .lowerIsBetter)
                == -100)
        // Higher-is-better: a larger arm mean is an improvement.
        #expect(
            ConventionAblation.improvement(baseline: 0.2, arm: 0.4, polarity: .higherIsBetter)
                == 100)
        #expect(
            ConventionAblation.improvement(baseline: 0.4, arm: 0.2, polarity: .higherIsBetter)
                == -50)
        // A vanishing baseline prints nan, not an unbounded ratio that would
        // read as a finding.
        #expect(
            ConventionAblation.improvement(baseline: 0, arm: 0.2, polarity: .lowerIsBetter).isNaN)
        #expect(
            ConventionAblation.improvement(baseline: 0.4, arm: .nan, polarity: .lowerIsBetter)
                .isNaN)
    }

    /// The CSVs are what a later reader applies a rule to, so their headers and
    /// column counts have to stay in step with the rows they describe.
    @Test func csvRowsMatchTheirHeaders() {
        let geometry = ConventionAblation.GeometryRow(
            corpus: "c", fixture: "f", nativeWidth: 3072, nativeHeight: 3072,
            thumbnailWidth: 160, thumbnailHeight: 160, gridRows: 36, gridColumns: 80,
            thumbCellWidth: 2, thumbCellHeight: 4, thumbCellWindows: 2,
            nativeBlockMinWidth: 38, nativeBlockMaxWidth: 39,
            nativeBlockMinHeight: 76, nativeBlockMaxHeight: 77,
            meanLiveBins: 3, sampledCells: 10)
        let delta = ConventionAblation.DeltaRow(
            corpus: "c", charset: "blocks", oracle: "mae", cells: 10, glyphs: 8,
            productionMean: 0.5, faithfulMean: 0.25, improvementPercent: 50,
            differingPickPercent: 40, productionMeanInkDelta: 0.1,
            faithfulMeanInkDelta: 0.05, maxInkDelta: 0.2)
        let ladder = ConventionAblation.LadderRow(
            corpus: "c", charset: "blocks", arm: "faithfulTiled", oracle: "mae", cells: 10,
            glyphs: 8, candidateWidth: 12, candidateHeight: 24, descriptorDimension: 4320,
            windows: 72, mean: 0.3, improvementPercent: 1, productionAgreementPercent: 2,
            meanInkDelta: 0.1, maxInkDelta: 0.2)

        func columns(_ line: Substring) -> Int { line.split(separator: ",", omittingEmptySubsequences: false).count }
        for (csv, header) in [
            (ConventionAblation.geometryCSV([geometry]), ConventionAblation.geometryCSVHeader),
            (ConventionAblation.deltaCSV([delta], queryPolarity: .inverted), ConventionAblation.deltaCSVHeader),
            (ConventionAblation.ladderCSV([ladder], queryPolarity: .inverted), ConventionAblation.ladderCSVHeader),
        ] {
            let lines = csv.split(separator: "\n")
            #expect(lines.count == 2)
            #expect(String(lines[0]) == header)
            #expect(columns(lines[0]) == columns(lines[1]))
        }
    }

    /// MAE leads every printed table: it is the house oracle, and GMSD/HaarPSI
    /// are disqualified from defining an optimum (ASKI-27). A table that led
    /// with a disqualified oracle would invite exactly the reading the audit
    /// removed.
    @Test func printedTablesLeadWithTheHouseOracle() {
        #expect(ConventionAblation.oracleOrder.first == .mae)
        let report = ConventionAblation.Report(
            geometry: [],
            delta: SelectionCeiling.Oracle.allCases.map {
                ConventionAblation.DeltaRow(
                    corpus: "c", charset: "blocks", oracle: $0.rawValue, cells: 1, glyphs: 8,
                    productionMean: 0.5, faithfulMean: 0.25, improvementPercent: 50,
                    differingPickPercent: 0, productionMeanInkDelta: 0,
                    faithfulMeanInkDelta: 0, maxInkDelta: 0)
            },
            ladder: [])
        let lines = ConventionAblation.format(report, stride: 1, queryPolarity: .inverted).split(separator: "\n")
        let dataRows = lines.filter { $0.contains(" | blocks | ") }
        let firstOracle = try? #require(dataRows.first)
        #expect(firstOracle?.contains(" | mae | ") == true)
    }
}
