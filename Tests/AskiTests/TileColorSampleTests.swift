import CoreGraphics
import Foundation
import Testing
import simd
@testable import Aski

@Suite struct TileColorSampleTests {
    @Test func preparationMatchesFrozenSampleValuesAndOrder() {
        for space in [RenderColorSpace.sRGB, .displayP3] {
            // Every alpha byte, transfer-function neighbors, transparent RGB
            // payloads, and above-alpha channels exercise the original clamp.
            var pixels: [UInt8] = []
            for alpha in 0...255 {
                for channel in [0, 1, 10, 11, 127, 254, 255] {
                    pixels += [UInt8(channel), UInt8(255 - channel), UInt8(alpha), UInt8(alpha)]
                }
            }
            let prepared = TilePalette.makeColorSamples(pixels: pixels, width: 7, height: 256, colorSpace: space)
            let control = ASKI92ControlKMeans.makeSamples(pixels: pixels, width: 7, height: 256, colorSpace: space)
            #expect(prepared.count == 7 * 255)
            #expect(prepared.count == control.count)
            for (actual, expected) in zip(prepared, control) {
                expectBits(actual.oklab, expected.oklab)
                #expect(actual.alpha.bitPattern == expected.alpha.bitPattern)
            }
        }
    }

    @Test func fullQuantizationMatchesBothFrozenAlgorithms() {
        for (width, height) in [(1, 1), (7, 5), (32, 24)] {
            for kind in [0, 1, 2, 3] {
                let pixels = Self.pixels(width: width, height: height, kind: kind)
                for space in [RenderColorSpace.sRGB, .displayP3] {
                    let samples = TilePalette.makeColorSamples(pixels: pixels, width: width, height: height, colorSpace: space)
                    let candidate = WuQuantizer(samples: samples)
                    let control = ASKI92ControlWu(pixels: pixels, width: width, height: height, colorSpace: space)
                    for count in [8, 16, 64, 256] {
                        let expectedWu = control.palette(maxColors: count)
                        let actualWu = candidate.palette(maxColors: count)
                        expectPaletteBits(actualWu, expectedWu)
                        let expected = ASKI92ControlKMeans.refine(palette: expectedWu, pixels: pixels, width: width, height: height, colorSpace: space)
                        let actual = KMeansRefinement.refine(palette: actualWu, samples: samples)
                        expectPaletteBits(actual, expected)
                        let resolved = TilePalette.adaptive(maxColors: count).resolved(
                            pixels: pixels, pixelWidth: width, pixelHeight: height, colorSpace: space
                        )
                        #expect(resolved.isPassThrough == expected.isEmpty)
                        expectPaletteBits(resolved.colors.map(\.oklab), expected)
                    }
                }
            }
        }
    }

    @Test func transparentAndEmptyInputsHaveNoSamples() {
        for space in [RenderColorSpace.sRGB, .displayP3] {
            for (width, height) in [(0, 0), (0, 4), (5, 0), (32, 24)] {
                let pixels = Self.pixels(width: width, height: height, kind: 2)
                #expect(TilePalette.makeColorSamples(pixels: pixels, width: width, height: height, colorSpace: space).isEmpty)
                #expect(TilePalette.adaptive(maxColors: 16).resolved(pixels: pixels, pixelWidth: width, pixelHeight: height, colorSpace: space).isPassThrough)
            }
        }
        // Preserve the byte-entry-point's guard before reading an invalid raster.
        #expect(KMeansRefinement.refine(palette: [], pixels: [], width: Int.max, height: Int.max, colorSpace: .sRGB).isEmpty)
    }

    @Test func duplicateCentersAndEmptyClustersKeepOldSemantics() {
        let pixels = Self.pixels(width: 8, height: 8, kind: 3)
        let samples = TilePalette.makeColorSamples(pixels: pixels, width: 8, height: 8, colorSpace: .sRGB)
        let center = samples[0].oklab
        let palette = [center, center, SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0)]
        let expected = ASKI92ControlKMeans.refine(palette: palette, pixels: pixels, width: 8, height: 8, colorSpace: .sRGB)
        expectPaletteBits(KMeansRefinement.refine(palette: palette, samples: samples), expected)
        #expect(KMeansRefinement.refine(palette: palette, samples: []).isEmpty)
    }

    @Test func fixedPaletteDoesNotReadOrPrepareSourcePixels() {
        let result = TilePalette.brick.resolved(pixels: [], pixelWidth: Int.max, pixelHeight: Int.max, colorSpace: .sRGB)
        #expect(!result.isPassThrough)
        expectPaletteBits(result.colors.map(\.oklab), BrickColors.oklab)
    }

    @Test func sharedSampleConsumersAreDeterministicUnderConcurrency() async {
        let pixels = Self.pixels(width: 16, height: 12, kind: 1)
        let samples = TilePalette.makeColorSamples(pixels: pixels, width: 16, height: 12, colorSpace: .displayP3)
        let expected = KMeansRefinement.refine(palette: WuQuantizer(samples: samples).palette(maxColors: 8), samples: samples)
        await withTaskGroup(of: [SIMD3<Float>].self) { group in
            for _ in 0..<8 {
                group.addTask {
                    KMeansRefinement.refine(palette: WuQuantizer(samples: samples).palette(maxColors: 8), samples: samples)
                }
            }
            for await result in group { expectPaletteBits(result, expected) }
        }
    }

    @Test func finalTilesMatchFrozenPaletteOnTheActualLattice() throws {
        for space in [RenderColorSpace.sRGB, .displayP3] {
            for kind in [0, 1, 2] {
                let image = try Self.image(width: 65, height: 49, kind: kind, space: space)
                for shape in [ASCIITileShape.square, .wide] {
                    let options = RenderingOptions(brightness: 0.1, contrast: 0.2)
                    let converter = TileGridConverter(palette: .adaptive(maxColors: 16), samplingShape: shape, options: options, colorSpace: space)
                    let actual = converter.convert(image, columns: 8)
                    let dimensions = try #require(gridDimensions(imageWidth: image.width, imageHeight: image.height, columns: 8, tileShape: shape))
                    let thumbnail = try ImageIOThumbnail.decode(image: image, maxPixelSize: max(dimensions.cols, dimensions.rows) * 2)
                    let lattice = try #require(samplingLattice(thumbnail: thumbnail, columns: dimensions.cols, rows: dimensions.rows, colorSpace: space))
                    let wu = ASKI92ControlWu(pixels: lattice.pixels, width: lattice.pixelWidth, height: lattice.pixelHeight, colorSpace: space).palette(maxColors: 16)
                    let colors = ASKI92ControlKMeans.refine(palette: wu, pixels: lattice.pixels, width: lattice.pixelWidth, height: lattice.pixelHeight, colorSpace: space)
                    let context = ConversionContext(
                        pixels: lattice.pixels, pixelWidth: lattice.pixelWidth, pixelHeight: lattice.pixelHeight,
                        cellWidth: lattice.cellWidth, cellHeight: lattice.cellHeight, columns: dimensions.cols, rows: dimensions.rows,
                        palette: colors.isEmpty ? .passThrough : ResolvedPalette(oklabColors: colors), options: ResolvedRenderingOptions(options),
                        colorSpace: space, gamutMapping: .adaptiveL0
                    )
                    #expect(actual.columns == dimensions.cols && actual.rows == dimensions.rows)
                    #expect(actual.colorSpace == space)
                    #expect(actual.maskFallback == nil && actual.maskGroundColor == nil && !actual.maskUsesHardEdges)
                    for row in 0..<dimensions.rows {
                        for column in 0..<dimensions.cols {
                            let expected = context.cellStats(at: CellCoord(column: column, row: row))
                            let cell = actual.cells[row][column]
                            expectBits(cell.displayColor, expected.displayColor)
                            #expect(cell.alpha.bitPattern == expected.alpha.bitPattern)
                            #expect(cell.brightness.bitPattern == expected.adjustedL.bitPattern)
                            #expect(cell.coverage.bitPattern == Float(1).bitPattern)
                        }
                    }
                }
            }
        }
    }

    /// kind: opaque rich, mixed alpha (including a transparent prefix), all
    /// transparent with nonzero payload, or a repeated solid color.
    private static func pixels(width: Int, height: Int, kind: Int) -> [UInt8] {
        var result: [UInt8] = []
        for index in 0..<(width * height) {
            let alpha = kind == 2 || (kind == 1 && index < 9) ? 0 : (kind == 1 ? (index * 37) & 255 : 255)
            let values = kind == 3 ? [64, 128, 192] : [(index * 13 + 31) & 255, (index * 29 + 7) & 255, (index * 19 + 111) & 255]
            for value in values { result.append(UInt8(alpha == 0 ? value : value * alpha / 255)) }
            result.append(UInt8(alpha))
        }
        return result
    }

    private static func image(width: Int, height: Int, kind: Int, space: RenderColorSpace) throws -> CGImage {
        let pixels = pixels(width: width, height: height, kind: kind)
        let cgSpace = try #require(CGColorSpace(name: space == .sRGB ? CGColorSpace.sRGB : CGColorSpace.displayP3))
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        return try #require(
            CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: cgSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            ))
    }
}

private func expectPaletteBits(_ actual: [SIMD3<Float>], _ expected: [SIMD3<Float>]) {
    #expect(actual.count == expected.count)
    for (a, e) in zip(actual, expected) { expectBits(a, e) }
}

private func expectBits(_ actual: SIMD3<Float>, _ expected: SIMD3<Float>) {
    #expect(actual.x.bitPattern == expected.x.bitPattern)
    #expect(actual.y.bitPattern == expected.y.bitPattern)
    #expect(actual.z.bitPattern == expected.z.bitPattern)
}
