import CoreGraphics
import Testing
@testable import Aski

@Suite struct TileGridEffectsMaskTests {
    @Test func positiveGroundAppliesThroughEveryBasicTileMode() {
        let modes: [TileGridMode] = [
            .pixelArt,
            .brick,
            .mosaic(grout: CGColor(red: 0, green: 0, blue: 0, alpha: 0), groutThickness: 0),
        ]
        let grid = TileGrid(
            cells: [[TileCell(displayColor: SIMD3<Float>(0, 1, 0), alpha: 0, brightness: 0, coverage: 1)]],
            colorSpace: .sRGB,
            maskFallback: .transparent,
            maskGroundColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        )

        for mode in modes {
            let image = grid.renderImage(
                mode: mode,
                cellShape: .square,
                scale: 16,
                backgroundColor: CGColor(red: 0, green: 0, blue: 1, alpha: 1)
            )
            let center = Self.pixel(image, x: 8, y: 8)
            #expect(center.r > 200)
            #expect(center.b < 50)
        }
    }

    @Test func effectiveNoGroundLeavesEveryBasicTileModeByteIdentical() {
        let modes: [TileGridMode] = [
            .pixelArt,
            .brick,
            .mosaic(grout: CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1), groutThickness: 0.2),
        ]
        let cells = [[TileCell(displayColor: SIMD3<Float>(1, 0, 0), alpha: 0.8, brightness: 1, coverage: 0.4)]]
        let fallback = MaskFallback.solid(CGColor(red: 0, green: 1, blue: 0, alpha: 0.7))
        let background = CGColor(red: 0, green: 0, blue: 1, alpha: 1)

        for mode in modes {
            let legacy = TileGrid(cells: cells, colorSpace: .sRGB, maskFallback: fallback)
                .renderImage(mode: mode, scale: 16, backgroundColor: background)
            let legacyBytes = TestImages.deviceRGBBytes(legacy)
            for ground in [
                CGColor(red: 1, green: 0, blue: 1, alpha: 0),
                CGColor(red: 1, green: 0, blue: 1, alpha: .nan),
            ] {
                let image = TileGrid(
                    cells: cells,
                    colorSpace: .sRGB,
                    maskFallback: fallback,
                    maskGroundColor: ground
                ).renderImage(mode: mode, scale: 16, backgroundColor: background)
                #expect(TestImages.deviceRGBBytes(image) == legacyBytes)
            }
        }
    }

    @Test func mosaicTransparentFallbackFadesCellsAndGroutToBackground() {
        let grid = TileGrid(
            cells: [[TileCell(displayColor: SIMD3<Float>(1, 0, 0), alpha: 1, brightness: 1, coverage: 0)]],
            colorSpace: .sRGB,
            maskFallback: .transparent
        )
        let background = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        let image = grid.renderImage(
            mode: .mosaic(grout: CGColor(red: 0, green: 0, blue: 1, alpha: 1), groutThickness: 0.3),
            cellShape: .square,
            scale: 16,
            backgroundColor: background
        )

        let center = Self.pixel(image, x: 8, y: 8)
        #expect(center.g > 200)
        #expect(center.r < 50)
        #expect(center.b < 50)
    }

    @Test func mosaicSolidFallbackCoversMaskedOutGrout() {
        let grid = TileGrid(
            cells: [[TileCell(displayColor: SIMD3<Float>(1, 0, 0), alpha: 1, brightness: 1, coverage: 0)]],
            colorSpace: .sRGB,
            maskFallback: .solid(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        )
        let image = grid.renderImage(
            mode: .mosaic(grout: CGColor(red: 1, green: 0, blue: 0, alpha: 1), groutThickness: 0.3),
            cellShape: .square,
            scale: 16,
            backgroundColor: CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        )

        let center = Self.pixel(image, x: 8, y: 8)
        #expect(center.b > 200)
        #expect(center.g < 50)
    }

    @Test func pixelArtCircleFallbackDoesNotPaintShapeGap() {
        let grid = TileGrid(
            cells: [[TileCell(displayColor: SIMD3<Float>(1, 0, 0), alpha: 1, brightness: 1, coverage: 0)]],
            colorSpace: .sRGB,
            maskFallback: .solid(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        )
        let image = grid.renderImage(
            mode: .pixelArt,
            cellShape: .circle,
            scale: 20,
            backgroundColor: CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        )

        let corner = Self.pixel(image, x: 0, y: 0)
        let center = Self.pixel(image, x: 10, y: 10)
        #expect(corner.g > 200)
        #expect(center.b > 200)
    }

    private static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &bytes,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = y * image.width * 4 + x * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
    }
}
