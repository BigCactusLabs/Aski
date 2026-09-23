import CoreGraphics
import Testing
import simd
@testable import Aski

/// A1 byte-identical regression after the lift refactor is enforced by the
/// existing snapshot tests in `SnapshotTests.swift` (e.g.
/// `plainTextGradient80cols`), which run the same `DefaultConverter` over the
/// same horizontal gradient and lock the rendered plain text against a
/// committed snapshot. Tests in this file are unit-level guards on each
/// individually-lifted helper.
@Suite struct CellSamplingRefactorTests {

    @Test func liftedGridDimensionsMatchesA1Defaults() throws {
        // ASCIIConverter's default `tileShape` is `.wide`; the lifted free
        // function must produce identical (cols, rows) when given .wide.
        let (cols, rows) = try #require(
            gridDimensions(
                imageWidth: 800, imageHeight: 100, columns: 80, tileShape: .wide
            ))
        #expect(cols == 80)
        // 100/800 = 0.125; (80 × 0.125) / 2.2 = 4.545 → max(1, 4) = 4
        #expect(rows == 4)
    }

    @Test func liftedGridDimensionsHandlesSquareAspect() throws {
        let (cols, rows) = try #require(
            gridDimensions(
                imageWidth: 100, imageHeight: 100, columns: 50, tileShape: .square
            ))
        #expect(cols == 50)
        #expect(rows == 50)
    }

    @Test func liftedGridDimensionsRejectsUnrepresentableRows() {
        let dimensions = gridDimensions(
            imageWidth: 1, imageHeight: 4, columns: Int.max, tileShape: .wide
        )
        if dimensions != nil {
            Issue.record("expected unrepresentable grid dimensions to return nil")
        }
    }

    /// A portrait scale that rounds to `Double(Int.max)` must return the empty
    /// preparation path. `Double(Int.max)` is one integer past `Int.max` on
    /// 64-bit platforms, so converting it would trap.
    @Test func portraitThumbnailSizeRejectsTheDoubleIntMaxBoundary() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = context.makeImage()!
        let columns = 1 << 61

        #expect(
            DefaultConverter().thumbnailMaxPixelSize(
                image: image, columns: columns, rows: columns
            ) == nil)
    }

    @Test func liftedReadRGBA8IsDeterministic() {
        let image = TestImages.horizontalGradient(width: 32, height: 32)
        let p1 = readRGBA8(image, targetColorSpace: .sRGB)
        let p2 = readRGBA8(image, targetColorSpace: .sRGB)
        #expect(p1 != nil)
        #expect(p1?.count == 32 * 32 * 4)
        #expect(p1 == p2)

        guard let pixels = p1 else { return }
        let leftEdge = Array(pixels[0..<4])
        let rightEdgeOffset = (32 - 1) * 4
        let rightEdge = Array(pixels[rightEdgeOffset..<(rightEdgeOffset + 4)])

        #expect(abs(Int(leftEdge[0]) - 0) <= 2)
        #expect(abs(Int(leftEdge[1]) - 0) <= 2)
        #expect(abs(Int(leftEdge[2]) - 0) <= 2)
        #expect(leftEdge[3] == 255)
        #expect(abs(Int(rightEdge[0]) - 255) <= 2)
        #expect(abs(Int(rightEdge[1]) - 255) <= 2)
        #expect(abs(Int(rightEdge[2]) - 255) <= 2)
        #expect(rightEdge[3] == 255)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo =
            CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        let context = CGContext(
            data: nil,
            width: 2,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 2 * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        context.setFillColor(red: 11.0 / 255.0, green: 73.0 / 255.0, blue: 181.0 / 255.0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.setFillColor(red: 201.0 / 255.0, green: 37.0 / 255.0, blue: 99.0 / 255.0, alpha: 1)
        context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))

        let nonGrayPixels = readRGBA8(context.makeImage()!, targetColorSpace: .sRGB)
        #expect(nonGrayPixels?.count == 2 * 1 * 4)
        guard let nonGrayPixels else { return }
        #expect(abs(Int(nonGrayPixels[0]) - 11) <= 2)
        #expect(abs(Int(nonGrayPixels[1]) - 73) <= 2)
        #expect(abs(Int(nonGrayPixels[2]) - 181) <= 2)
        #expect(nonGrayPixels[3] == 255)
        #expect(abs(Int(nonGrayPixels[4]) - 201) <= 2)
        #expect(abs(Int(nonGrayPixels[5]) - 37) <= 2)
        #expect(abs(Int(nonGrayPixels[6]) - 99) <= 2)
        #expect(nonGrayPixels[7] == 255)
    }

    @Test func liftedNearestPaletteOKLABReturnsClosestEntry() {
        let black = SIMD3<Float>(0, 0, 0)
        let white = SIMD3<Float>(1, 0, 0)
        let mid = SIMD3<Float>(0.5, 0, 0)

        // Near-white query → white centroid.
        #expect(nearestPaletteOKLAB(SIMD3(0.95, 0.001, 0.001), palette: [black, white]) == white)
        // Near-black query → black centroid.
        #expect(nearestPaletteOKLAB(SIMD3(0.05, 0.001, 0.001), palette: [black, white]) == black)
        // Three-entry palette: midpoint is closest to mid.
        #expect(nearestPaletteOKLAB(SIMD3(0.5, 0, 0), palette: [black, mid, white]) == mid)

        let cool = SIMD3<Float>(0.6, -0.18, -0.10)
        let warm = SIMD3<Float>(0.6, 0.18, 0.10)
        #expect(nearestPaletteOKLAB(SIMD3(0.6, -0.16, -0.09), palette: [warm, cool]) == cool)
    }

    @Test func liftedCellStatsIsDeterministic() {
        // Same context, same coord, two calls — must produce bit-identical results.
        let pixels = [UInt8](repeating: 128, count: 8 * 8 * 4)
        let context = ConversionContext(
            pixels: pixels,
            pixelWidth: 8, pixelHeight: 8,
            cellWidth: 4, cellHeight: 4,
            columns: 2, rows: 2,
            palette: .passThrough,
            options: ResolvedRenderingOptions(.default),
            colorSpace: .sRGB
        )
        let a = context.cellStats(at: CellCoord(column: 0, row: 0))
        let b = context.cellStats(at: CellCoord(column: 0, row: 0))
        #expect(a.displayColor == b.displayColor)
        #expect(a.alpha == b.alpha)
        #expect(a.adjustedL == b.adjustedL)
        #expect(a.rawL == b.rawL)

        let black: [UInt8] = [0, 0, 0, 255]
        let gray: [UInt8] = [128, 128, 128, 255]
        let white: [UInt8] = [255, 255, 255, 255]
        var coordinatePixels: [UInt8] = []
        for y in 0..<4 {
            for x in 0..<4 {
                if y < 2 {
                    coordinatePixels += x < 2 ? black : white
                } else {
                    coordinatePixels += x < 2 ? gray : white
                }
            }
        }

        let coordinateContext = ConversionContext(
            pixels: coordinatePixels,
            pixelWidth: 4, pixelHeight: 4,
            cellWidth: 2, cellHeight: 2,
            columns: 2, rows: 2,
            palette: .passThrough,
            options: ResolvedRenderingOptions(.default),
            colorSpace: .sRGB
        )
        let topLeft = coordinateContext.cellStats(at: CellCoord(column: 0, row: 0))
        let topRight = coordinateContext.cellStats(at: CellCoord(column: 1, row: 0))
        let bottomLeft = coordinateContext.cellStats(at: CellCoord(column: 0, row: 1))

        #expect(topLeft.alpha == 1)
        #expect(topRight.alpha == 1)
        #expect(bottomLeft.alpha == 1)
        #expect(topLeft.rawL < bottomLeft.rawL)
        #expect(bottomLeft.rawL < topRight.rawL)
        #expect(topLeft.displayColor.x < bottomLeft.displayColor.x)
        #expect(bottomLeft.displayColor.x < topRight.displayColor.x)
    }

    @Test func liftedCellStatsRespectsBrightnessOption() {
        // Same gray pixels with +brightness must produce a higher adjustedL
        // than the default options. rawL is pre-options and must be identical.
        let pixel: [UInt8] = [128, 128, 128, 255]
        let pixels = Array(repeating: pixel, count: 4 * 4)
            .flatMap { $0 }
        let baseline = ConversionContext(
            pixels: pixels,
            pixelWidth: 4, pixelHeight: 4,
            cellWidth: 4, cellHeight: 4,
            columns: 1, rows: 1,
            palette: .passThrough,
            options: ResolvedRenderingOptions(.default),
            colorSpace: .sRGB
        )
        let lifted = ConversionContext(
            pixels: pixels,
            pixelWidth: 4, pixelHeight: 4,
            cellWidth: 4, cellHeight: 4,
            columns: 1, rows: 1,
            palette: .passThrough,
            options: ResolvedRenderingOptions(RenderingOptions(brightness: 0.3)),
            colorSpace: .sRGB
        )
        let baseStats = baseline.cellStats(at: CellCoord(column: 0, row: 0))
        let liftStats = lifted.cellStats(at: CellCoord(column: 0, row: 0))
        #expect(liftStats.adjustedL > baseStats.adjustedL)
        #expect(abs(liftStats.rawL - baseStats.rawL) < 1e-6)
    }
}
