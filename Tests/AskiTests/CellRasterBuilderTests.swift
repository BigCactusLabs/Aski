import Testing
import CoreImage
import CoreGraphics
@testable import Aski

@Suite struct CellRasterBuilderTests {
    @Test func rasterExtentMatchesGridDimensions() {
        let cell = ASCIICell(
            character: "A",
            displayColor: SIMD3<Float>(1, 0, 0),
            alpha: 1,
            brightness: 0.5
        )
        let grid = ASCIIGrid(cells: [[cell, cell], [cell, cell]], colorSpace: .sRGB)
        let font = ASCIIFont.system(size: 12)
        let raster = CellRasterBuilder.makeASCIIRaster(grid: grid, font: font, scale: 1)
        #expect(raster.image.extent.width > 0)
        #expect(raster.image.extent.height > 0)
    }

    @Test func backgroundIsTransparent() {
        let cell = ASCIICell(
            character: "A",
            displayColor: SIMD3<Float>(1, 1, 1),
            alpha: 1,
            brightness: 0.5
        )
        let grid = ASCIIGrid(cells: [[cell]], colorSpace: .sRGB)
        let font = ASCIIFont.system(size: 12)
        let raster = CellRasterBuilder.makeASCIIRaster(grid: grid, font: font, scale: 1)

        let ctx = CIContext(options: nil)
        var pixel = [UInt8](repeating: 255, count: 4)
        let probe = CGRect(
            x: raster.image.extent.maxX - 1,
            y: raster.image.extent.maxY - 1,
            width: 1,
            height: 1
        )
        ctx.render(
            raster.image,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: probe,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        #expect(pixel[3] < 32)
    }

    @Test func glyphPixelsAreOpaque() {
        let cell = ASCIICell(
            character: "@",
            displayColor: SIMD3<Float>(1, 1, 1),
            alpha: 1,
            brightness: 0.5
        )
        let grid = ASCIIGrid(cells: [[cell]], colorSpace: .sRGB)
        let font = ASCIIFont.system(size: 18)
        let raster = CellRasterBuilder.makeASCIIRaster(grid: grid, font: font, scale: 1)

        let ctx = CIContext(options: nil)
        var pixel = [UInt8](repeating: 0, count: 4)
        let probe = CGRect(x: raster.image.extent.midX, y: raster.image.extent.midY, width: 1, height: 1)
        ctx.render(
            raster.image,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: probe,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        #expect(pixel[3] > 64)
    }

    @Test func intrinsicAlphaModeDoesNotMultiplyMaskCoverage() {
        let cell = ASCIICell(
            character: "@",
            displayColor: SIMD3<Float>(1, 1, 1),
            alpha: 1,
            brightness: 0.5,
            coverage: 0.25
        )
        let grid = ASCIIGrid(cells: [[cell]], colorSpace: .sRGB)
        let font = ASCIIFont.system(size: 24)

        let legacy = CellRasterBuilder.makeASCIIRaster(grid: grid, font: font, scale: 1)
        let intrinsic = CellRasterBuilder.makeASCIIRaster(
            grid: grid,
            font: font,
            scale: 1,
            coverageMode: .intrinsicAlpha
        )

        let legacyAlpha = Self.maximumAlpha(in: legacy.image)
        let intrinsicAlpha = Self.maximumAlpha(in: intrinsic.image)
        #expect(legacyAlpha < 80)
        #expect(intrinsicAlpha > 220)
    }

    private static func maximumAlpha(in image: CIImage) -> UInt8 {
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        CIContext(options: nil).render(
            image,
            toBitmap: &pixels,
            rowBytes: width * 4,
            bounds: image.extent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }.max() ?? 0
    }
}

@Suite struct TileCellRasterBuilderTests {
    private func makeGrid() -> TileGrid {
        let cell = TileCell(
            displayColor: SIMD3<Float>(1, 0, 0),
            alpha: 1,
            brightness: 0.5
        )
        return TileGrid(cells: [[cell, cell], [cell, cell]], colorSpace: .sRGB)
    }

    @Test func tileRasterHasExpectedExtent() {
        let raster = CellRasterBuilder.makeTileRaster(
            grid: makeGrid(),
            mode: .pixelArt,
            cellShape: .square,
            scale: 1
        )
        #expect(raster.image.extent.width > 0)
        #expect(raster.image.extent.height > 0)
    }

    @Test func tileRasterBackgroundIsTransparent() {
        let transparentCell = TileCell(displayColor: SIMD3<Float>(1, 0, 0), alpha: 0, brightness: 0)
        let grid = TileGrid(cells: [[transparentCell]], colorSpace: .sRGB)
        let raster = CellRasterBuilder.makeTileRaster(
            grid: grid,
            mode: .pixelArt,
            cellShape: .square,
            scale: 1
        )

        let ctx = CIContext(options: nil)
        var pixel = [UInt8](repeating: 255, count: 4)
        let probe = CGRect(x: raster.image.extent.midX, y: raster.image.extent.midY, width: 1, height: 1)
        ctx.render(
            raster.image,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: probe,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        #expect(pixel[3] < 32)
    }
}
