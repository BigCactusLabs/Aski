import CoreGraphics
import Foundation
import Testing
import simd
@_spi(AskiResearch) @testable import Aski

@Suite("ASKI-90 fixed-palette display preparation")
struct FixedPaletteDisplayTests {
    private static let spaces: [RenderColorSpace] = [.sRGB, .displayP3]
    private static let matchingPolicies: [PaletteMatchingPolicy] = [
        .oklabEuclidean, .oklabHyAB, .helmlabEuclidean, .helmlabCompressed,
    ]
    private static let gamutPolicies: [GamutMappingPolicy] = [.rayTrace, .adaptiveL0, .clip]
    private static let contents: [PaletteContent] = [
        BuiltInPalette.ansi16.content, BuiltInPalette.monochrome.content, .passThrough,
        .fixed([
            PaletteColor(SIMD3(0, 1, 0), colorSpace: .displayP3),
            PaletteColor(SIMD3(1, 0, 0), colorSpace: .displayP3),
            PaletteColor(SIMD3(0.1, 0.3, 0.9)),
            PaletteColor(SIMD3(0.1, 0.3, 0.9)),
        ]),
    ]

    @Test func finalizationMatchesFrozenScalarAcrossPolicies() {
        for content in Self.contents {
            for matching in Self.matchingPolicies {
                let palette = ResolvedPalette(content: content, needsHelmlab: matching.needsHelmlab)
                for space in Self.spaces {
                    for gamut in Self.gamutPolicies {
                        let context = Self.context(palette: palette, space: space, matching: matching, gamut: gamut)
                        #expect(context.paletteDisplayColors.count == palette.colors.count)
                        for (index, color) in palette.colors.enumerated() {
                            #expect(
                                Self.bits(context.paletteDisplayColors[index])
                                    == Self.bits(
                                        mapToDisplayColor(for: color.oklab, colorSpace: space, policy: gamut)))
                        }
                        for source in Self.sources {
                            Self.expectSame(context.finalizeColor(source: source), Self.scalar(source, in: context))
                        }
                    }
                }
            }
        }
    }

    @Test func indexSelectionPreservesMidpointDuplicateAndUnorderedTies() {
        let colors = [
            ResolvedPaletteColor(source: nil, oklab: SIMD3(0.5, -0.125, 0), helmlab: .zero),
            ResolvedPaletteColor(source: nil, oklab: SIMD3(0.5, 0.125, 0), helmlab: .zero),
            ResolvedPaletteColor(source: nil, oklab: SIMD3(0.5, -0.125, 0), helmlab: .zero),
        ]
        for policy in Self.matchingPolicies {
            // Midpoint ties for OKLab; identical MetricSpace coordinates for Helmlab.
            #expect(ResolvedPalette.nearestIndex(SIMD3(0.5, 0, 0), in: colors, policy: policy) == 0)
            for query in [SIMD3<Float>(0.5, 0, 0), SIMD3(.nan, 0, 0), SIMD3(.infinity, 0, 0)] {
                let index = ResolvedPalette.nearestIndex(query, in: colors, policy: policy)
                #expect(Self.bits(colors[index].oklab) == Self.bits(legacyPaletteMatch(query, palette: colors, policy: policy)))
            }
        }
        for policy in [PaletteMatchingPolicy.oklabEuclidean, .oklabHyAB] {
            #expect(ResolvedPalette.nearestIndex(colors[1].oklab, in: colors, policy: policy) == 1)
            #expect(ResolvedPalette.nearestIndex(colors[2].oklab, in: colors, policy: policy) == 0)
        }
    }

    @Test func passThroughHasNoPreparedEntriesAndPreservesPerCellValues() {
        for space in Self.spaces {
            for gamut in Self.gamutPolicies {
                let context = Self.context(palette: .passThrough, space: space, gamut: gamut)
                #expect(context.paletteDisplayColors.isEmpty)
                for source in Self.sources {
                    Self.expectSame(context.finalizeColor(source: source), Self.scalar(source, in: context))
                }
            }
        }
    }

    @Test func contextsDoNotShareMutablePreparedColors() {
        let palette = ResolvedPalette(content: Self.contents[3])
        let first = Self.context(palette: palette, space: .sRGB, gamut: .clip)
        let frozen = first.paletteDisplayColors.map(Self.bits)
        var detachedCopy = first.paletteDisplayColors
        detachedCopy[0] = .zero
        for space in Self.spaces {
            for gamut in Self.gamutPolicies {
                let next = Self.context(palette: palette, space: space, gamut: gamut)
                for source in Self.sources {
                    Self.expectSame(next.finalizeColor(source: source), Self.scalar(source, in: next))
                }
            }
        }
        #expect(first.paletteDisplayColors.map(Self.bits) == frozen)
    }

    @Test func sharedContextIsDeterministicAcrossTasks() async {
        let context = Self.context(
            palette: ResolvedPalette(content: Self.contents[3], needsHelmlab: true),
            space: .displayP3, matching: .helmlabCompressed, gamut: .adaptiveL0)
        let expected = Self.sources.map { Self.bits(Self.scalar($0, in: context)) }
        await withTaskGroup(of: [[UInt32]].self) { group in
            for _ in 0..<32 {
                group.addTask {
                    Self.sources.map { Self.bits(context.finalizeColor(source: $0)) }
                }
            }
            for await actual in group { #expect(actual == expected) }
        }
    }

    @Test func sampledAlphaAndBrightnessRemainSourceDerived() {
        for sampling in [ColorSamplingPolicy.encodedAverageLegacy, .linearLightAverage] {
            for space in Self.spaces {
                let context = ConversionContext(
                    pixels: Self.pixels, pixelWidth: 8, pixelHeight: 6,
                    cellWidth: 2, cellHeight: 2, columns: 4, rows: 3,
                    palette: ResolvedPalette(content: BuiltInPalette.monochrome.content),
                    options: ResolvedRenderingOptions(RenderingOptions(brightness: 0.2, contrast: -0.3)),
                    colorSpace: space, colorSampling: sampling)
                for row in 0..<context.rows {
                    for column in 0..<context.columns {
                        let coord = CellCoord(column: column, row: row)
                        let source = context.cellSourceStats(at: coord)
                        Self.expectSame(context.cellStats(at: coord), Self.scalar(source, in: context))
                    }
                }
            }
        }
    }

    @Test func ordinaryRankedResidualGridsMatchScalarCellControl() throws {
        let provider = try #require(CGDataProvider(data: Data(Self.pixels) as CFData))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let image = try #require(
            CGImage(
                width: 8, height: 6, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 32,
                space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        for palette in [BuiltInPalette.ansi16, .monochrome, .fullColor] {
            for mode in [GridRowWalk.Mode.forcedSerial, .forcedParallel] {
                var converter = DefaultConverter(
                    characterSet: .standard, palette: palette,
                    options: RenderingOptions(density: 0.5, brightness: 0.1, contrast: -0.2),
                    colorSpace: .displayP3, oversample: 4, gamutMapping: .clip,
                    composition: .extendedLinearPerGamut)
                converter.rowWalkMode = mode
                let preparation = try #require(converter.prepareConversion(image, columns: 4, mask: nil))
                let context = preparation.context
                let kernel = LogPolarKernel(glyphBank: converter.glyphBank)
                let ordinary = converter.convert(image, columns: 4)
                let ranked = converter.convertWithRankedCandidates(image, columns: 4, candidateStride: 6)
                let residual = converter.convertWithResidual(image, columns: 4)
                for grid in [ordinary, ranked.grid, residual.grid] {
                    #expect(grid.colorSpace == converter.colorSpace)
                    #expect(grid.composition == converter.composition)
                    #expect(grid.cells.count == context.rows)
                    for row in 0..<context.rows {
                        #expect(grid.cells[row].count == context.columns)
                        for column in 0..<context.columns {
                            let coord = CellCoord(column: column, row: row)
                            let stats = Self.scalar(context.cellSourceStats(at: coord), in: context)
                            let cell = grid.cells[row][column]
                            #expect(cell.character == kernel.score(cell: coord, stats: stats, in: context))
                            #expect(Self.bits(cell.displayColor) == Self.bits(stats.displayColor))
                            #expect(cell.alpha.bitPattern == stats.alpha.bitPattern)
                            #expect(cell.brightness.bitPattern == stats.adjustedL.bitPattern)
                            #expect(cell.coverage.bitPattern == Float(1).bitPattern)
                        }
                    }
                }
                for row in 0..<context.rows {
                    for column in 0..<context.columns {
                        let coord = CellCoord(column: column, row: row)
                        let stats = Self.scalar(context.cellSourceStats(at: coord), in: context)
                        let control = kernel.scoreScored(cell: coord, stats: stats, in: context)
                        #expect(residual.residual[row * context.columns + column].bitPattern == control.distance.bitPattern)
                        let expected = kernel.match(cell: coord, stats: stats, in: context, resultLimit: 6).rankedIndices
                        let cellIndex = row * context.columns + column
                        #expect(ranked.candidateCounts[cellIndex] == UInt16(Set(expected).count))
                        let base = cellIndex * 6
                        for slot in 0..<6 {
                            #expect(ranked.candidates[base + slot] == UInt16(slot < expected.count ? expected[slot] : expected[0]))
                        }
                    }
                }
            }
        }
    }

    private static func context(
        palette: ResolvedPalette, space: RenderColorSpace,
        matching: PaletteMatchingPolicy = .oklabEuclidean, gamut: GamutMappingPolicy = .rayTrace
    ) -> ConversionContext {
        ConversionContext(
            pixels: [], pixelWidth: 0, pixelHeight: 0, cellWidth: 1, cellHeight: 1,
            columns: 0, rows: 0, palette: palette, options: ResolvedRenderingOptions(.default),
            colorSpace: space, paletteMatching: matching, gamutMapping: gamut)
    }

    private static let sources: [CellSourceStats] = (0..<65).map { index in
        let t = Float(index) / 64
        return CellSourceStats(
            oklab: SIMD3(t, 0.35 * (2 * t - 1), 0.3 * (1 - 2 * t)),
            adjustedL: 1 - t,
            alpha: [Float(0), Float.leastNonzeroMagnitude, 0.5, 1][index % 4])
    }

    private static let pixels: [UInt8] = (0..<48).flatMap { index in
        let alpha = [0, 64, 128, 255][index % 4]
        return [
            UInt8(((index * 37) % 256) * alpha / 255),
            UInt8(((index * 73) % 256) * alpha / 255),
            UInt8(((index * 19) % 256) * alpha / 255), UInt8(alpha),
        ]
    }

    private static func scalar(_ source: CellSourceStats, in context: ConversionContext) -> CellStats {
        let query = SIMD3(source.adjustedL, source.oklab.y, source.oklab.z)
        let matched =
            context.palette.isPassThrough
            ? query
            : legacyPaletteMatch(
                query, palette: context.palette.colors, policy: context.paletteMatching)
        return CellStats(
            displayColor: mapToDisplayColor(for: matched, colorSpace: context.colorSpace, policy: context.gamutMapping),
            alpha: source.alpha, adjustedL: source.adjustedL, rawL: source.oklab.x)
    }

    private static func bits(_ value: SIMD3<Float>) -> [UInt32] {
        [value.x.bitPattern, value.y.bitPattern, value.z.bitPattern]
    }

    private static func bits(_ value: CellStats) -> [UInt32] {
        bits(value.displayColor) + [value.alpha.bitPattern, value.adjustedL.bitPattern, value.rawL.bitPattern]
    }

    private static func expectSame(_ actual: CellStats, _ expected: CellStats) {
        #expect(bits(actual) == bits(expected))
    }
}

// Frozen pre-ASKI-90 selector from CellSampling.swift at ca5dbaff.
// Keep independent of ResolvedPalette.nearestIndex: using the candidate to
// compute the expected winner would hide changes to arithmetic or tie order.
private func legacyPaletteMatch(
    _ query: SIMD3<Float>,
    palette: [ResolvedPaletteColor],
    policy: PaletteMatchingPolicy = .oklabEuclidean
) -> SIMD3<Float> {
    switch policy.kind {
    case .oklabEuclidean:
        var nearest = palette[0].oklab
        var nearestDistance = Float.infinity
        for color in palette {
            let distance = simd_length_squared(color.oklab - query)
            if distance < nearestDistance {
                nearest = color.oklab
                nearestDistance = distance
            }
        }
        return nearest
    case .oklabHyAB:
        // |ΔL| + √(Δa² + Δb²) — ported verbatim from Tools/AskiColorLab/
        // PaletteMatching/PaletteMatchPolicies.swift:16-19. Unlike Euclidean,
        // HyAB is not monotonic in its squared form, so the full distance is
        // computed each iteration.
        var nearest = palette[0].oklab
        var nearestDistance = Float.infinity
        for color in palette {
            let delta = color.oklab - query
            let distance = abs(delta.x) + simd_length(SIMD2<Float>(delta.y, delta.z))
            if distance < nearestDistance {
                nearest = color.oklab
                nearestDistance = distance
            }
        }
        return nearest
    case .helmlabEuclidean, .helmlabCompressed:
        // Convert the query OKLab → linRGB → XYZ → MetricSpace once. The
        // OKLab→linRGB→XYZ composition is gamut-invariant, so the sRGB pair is
        // canonical regardless of the converter's target gamut. The matched
        // entry's OKLab is still returned (downstream is OKLab→display).
        let queryLinRGB = ColorConversion.oklabToLinearSRGB(query)
        let queryXYZ = ColorConversion.linearSRGBToXYZ(SIMD3<Double>(queryLinRGB))
        let queryHelmlab = HelmlabMetric.xyzToHelmlabMetric(queryXYZ)

        var nearest = palette[0].oklab
        var nearestDistance = Double.infinity
        for color in palette {
            guard let candidateHelmlab = color.helmlab else {
                preconditionFailure("Helmlab policy requires ResolvedPaletteColor.helmlab to be populated; resolve the palette with needsHelmlab: true")
            }
            let distance =
                policy.kind == .helmlabEuclidean
                ? HelmlabMetric.euclideanDistance(queryHelmlab, candidateHelmlab)
                : HelmlabMetric.compressedDeltaE(queryHelmlab, candidateHelmlab)
            if distance < nearestDistance {
                nearest = color.oklab
                nearestDistance = distance
            }
        }
        return nearest
    }
}
