import CoreGraphics
import Testing
import simd
@testable import Aski

@Suite struct TileGridConverterTests {

    @Test func tinyImageWithLargeColumnsReturnsEmptyGrid() {
        let image = TestImages.horizontalGradient(width: 1, height: 1)
        let grid = TileGridConverter().convert(image, columns: 100)
        #expect(grid.cells.isEmpty)
        #expect(grid.rows == 0)
        #expect(grid.columns == 0)
    }

    @Test func extremeColumnsReturnEmptyGridInsteadOfTrapping() {
        let image = TestImages.horizontalGradient(width: 1, height: 1)
        let grid = TileGridConverter().convert(image, columns: Int.max)
        #expect(grid.cells.isEmpty)
        #expect(grid.rows == 0)
        #expect(grid.columns == 0)
    }

    @Test func extremeOversampleReturnsEmptyGridInsteadOfTrapping() {
        let image = TestImages.horizontalGradient(width: 1, height: 1)
        let grid = TileGridConverter(oversample: Int.max).convert(image, columns: 16)
        #expect(grid.cells.isEmpty)
        #expect(grid.rows == 0)
        #expect(grid.columns == 0)
    }

    @Test func zeroColumnsReturnsEmptyGrid() {
        let image = TestImages.horizontalGradient(width: 64, height: 64)
        let grid = TileGridConverter().convert(image, columns: 0)
        #expect(grid.cells.isEmpty)
    }

    @Test func smokeRunGradient() {
        let image = TestImages.horizontalGradient(width: 200, height: 100)
        let grid = TileGridConverter(palette: .adaptive(maxColors: 8))
            .convert(image, columns: 40)
        #expect(grid.columns == 40)
        #expect(grid.rows >= 1)
        #expect(grid.cells.count == grid.rows)
        for row in grid.cells {
            #expect(row.count == grid.columns)
        }
    }

    @Test func deterministicForFixedInput() {
        let image = TestImages.horizontalGradient(width: 200, height: 100)
        let converter = TileGridConverter(palette: .adaptive(maxColors: 8))
        let g1 = converter.convert(image, columns: 40)
        let g2 = converter.convert(image, columns: 40)
        #expect(g1.cells.count == g2.cells.count)
        for (r1, r2) in zip(g1.cells, g2.cells) {
            #expect(r1 == r2)
        }
    }

    @Test func samplingShapeChangesRowCount() {
        let image = TestImages.horizontalGradient(width: 800, height: 100)
        let square = TileGridConverter(samplingShape: .square).convert(image, columns: 80)
        let wide = TileGridConverter(samplingShape: .wide).convert(image, columns: 80)
        #expect(wide.rows < square.rows)
    }

    @Test func brickPaletteUsedAtConvertTime() {
        let image = TestImages.horizontalGradient(width: 100, height: 50)
        let grid = TileGridConverter(palette: .brick).convert(image, columns: 20)
        #expect(grid.cells.count > 0)
        for row in grid.cells {
            for cell in row {
                #expect(cell.displayColor.x >= 0 && cell.displayColor.x <= 1)
                #expect(cell.displayColor.y >= 0 && cell.displayColor.y <= 1)
                #expect(cell.displayColor.z >= 0 && cell.displayColor.z <= 1)
            }
        }
    }

    @Test func brightnessOptionPropagatesToCellBrightness() {
        let image = TestImages.horizontalGradient(width: 100, height: 50)
        var brighter = TileGridConverter(palette: .adaptive(maxColors: 16))
        brighter.options = RenderingOptions(brightness: 0.3)
        let normal = TileGridConverter(palette: .adaptive(maxColors: 16)).convert(image, columns: 20)
        let bright = brighter.convert(image, columns: 20)

        var normalSum: Float = 0
        var brightSum: Float = 0
        var count = 0
        for row in normal.cells {
            for cell in row {
                normalSum += cell.brightness
                count += 1
            }
        }
        for row in bright.cells {
            for cell in row {
                brightSum += cell.brightness
            }
        }
        #expect(brightSum / Float(count) > normalSum / Float(count))
    }

    @Test func tileGridConverterKeepsLegacyGamutMappingUntilPolicyKnobExists() {
        let displayP3 = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        let p3Yellow = CGColor(colorSpace: displayP3, components: [1, 1, 0, 1])!
        let image = TestImages.horizontalGradient(width: 32, height: 16)
        let grid = TileGridConverter(
            palette: .fixed([p3Yellow]),
            colorSpace: .sRGB
        ).convert(image, columns: 4)

        let sourceOKLAB = ColorConversion.cgColorToOKLAB(p3Yellow)
        let expectedLegacy = mapToDisplayColor(
            for: sourceOKLAB,
            colorSpace: .sRGB,
            policy: .adaptiveL0
        )
        let rayTrace = mapToDisplayColor(
            for: sourceOKLAB,
            colorSpace: .sRGB,
            policy: .rayTrace
        )

        #expect(simd_length(expectedLegacy - rayTrace) > 0.1)
        #expect(!grid.cells.isEmpty)
        for row in grid.cells {
            for cell in row {
                #expect(simd_length(cell.displayColor - expectedLegacy) < 1e-5)
            }
        }
    }

    @Test func fixedTilePaletteResolvedOKLABValuesArePreserved() {
        let pixels = [UInt8](repeating: 255, count: 4 * 4 * 4)
        let resolved = TilePalette.brick.resolved(
            pixels: pixels,
            pixelWidth: 4,
            pixelHeight: 4,
            colorSpace: .sRGB
        )

        #expect(!resolved.isPassThrough)
        #expect(resolved.colors.count == BrickColors.oklab.count)
        for index in BrickColors.oklab.indices {
            #expect(simd_length(resolved.colors[index].oklab - BrickColors.oklab[index]) < 1e-6)
        }
    }

    @Test func adaptiveTilePaletteBridgeMatchesLegacyQuantizerPath() {
        let image = TestImages.horizontalGradient(width: 16, height: 16)
        let pixels = readRGBA8(image, targetColorSpace: .sRGB) ?? []
        let wu = WuQuantizer(
            pixels: pixels,
            width: image.width,
            height: image.height,
            colorSpace: .sRGB
        ).palette(maxColors: 8)
        let legacy = KMeansRefinement.refine(
            palette: wu,
            pixels: pixels,
            width: image.width,
            height: image.height,
            colorSpace: .sRGB
        )
        let resolved = TilePalette.adaptive(maxColors: 8).resolved(
            pixels: pixels,
            pixelWidth: image.width,
            pixelHeight: image.height,
            colorSpace: .sRGB
        )

        #expect(resolved.colors.count == legacy.count)
        for index in legacy.indices {
            #expect(resolved.colors[index].oklab == legacy[index])
        }
    }
}
