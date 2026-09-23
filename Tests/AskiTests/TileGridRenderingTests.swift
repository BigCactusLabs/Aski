import AppKit
import CoreGraphics
import SnapshotTesting
import Testing
@testable import Aski

@Suite struct TileGridRenderingTests {

    private static func tinyGrid() -> TileGrid {
        let cells: [[TileCell]] = [
            [
                TileCell(displayColor: .init(1, 0, 0), alpha: 1, brightness: 0.5),
                TileCell(displayColor: .init(0, 1, 0), alpha: 1, brightness: 0.5),
            ],
            [
                TileCell(displayColor: .init(0, 0, 1), alpha: 1, brightness: 0.5),
                TileCell(displayColor: .init(1, 1, 1), alpha: 1, brightness: 0.5),
            ],
        ]
        return TileGrid(cells: cells, colorSpace: .sRGB)
    }

    @Test func emptyGridReturnsEmptyImage() {
        let empty = TileGrid(cells: [], colorSpace: .sRGB)
        let image = empty.renderImage()
        #expect(image.width == 1)
        #expect(image.height == 1)
    }

    @Test func zeroScaleReturnsEmptyImage() {
        let grid = Self.tinyGrid()
        let image = grid.renderImage(scale: 0)
        #expect(image.width == 1)
    }

    @Test func nonFiniteScaleReturnsEmptyImage() {
        let grid = Self.tinyGrid()
        let image = grid.renderImage(scale: .infinity)
        #expect(image.width == 1)
    }

    @Test func squareScale8ProducesExpectedDimensions() {
        let grid = Self.tinyGrid()
        let image = grid.renderImage(cellShape: .square, scale: 8)
        #expect(image.width == 16)
        #expect(image.height == 16)
    }

    @Test func renderingDeterministic() {
        let grid = Self.tinyGrid()
        let imageA = grid.renderImage(mode: .pixelArt, cellShape: .square, scale: 8)
        let imageB = grid.renderImage(mode: .pixelArt, cellShape: .square, scale: 8)
        #expect(imageA.width == imageB.width)
        #expect(imageA.height == imageB.height)

        let dataA = imageA.dataProvider?.data
        let dataB = imageB.dataProvider?.data
        #expect(dataA != nil && dataB != nil)
        if let dataA, let dataB {
            #expect(CFDataGetLength(dataA) == CFDataGetLength(dataB))
            let length = CFDataGetLength(dataA)
            for index in stride(from: 0, to: min(length, 256), by: 32) {
                #expect(CFDataGetBytePtr(dataA)[index] == CFDataGetBytePtr(dataB)[index])
            }
        }
    }

    @Test func mosaicAcceptsAllParameterRanges() {
        let grid = Self.tinyGrid()
        let modes: [TileGridMode] = [
            .mosaic,
            .mosaic(grout: CGColor(red: 0.5, green: 0, blue: 0.5, alpha: 1)),
            .mosaic(groutThickness: 0),
            .mosaic(groutThickness: 0.4),
            .mosaic(groutThickness: 99),
            .mosaic(cornerRadius: 0),
            .mosaic(cornerRadius: 0.4),
            .mosaic(cornerRadius: -1),
        ]
        for mode in modes {
            let image = grid.renderImage(mode: mode, scale: 8)
            #expect(image.width >= 1)
        }
    }

    @Test func allShapesProduceNonEmptyImage() {
        let grid = Self.tinyGrid()
        for shape in [TileCellShape.square, .hex, .triangle, .diamond, .circle] {
            let image = grid.renderImage(cellShape: shape, scale: 8)
            #expect(image.width > 0)
            #expect(image.height > 0)
        }
    }

    @Test func raggedGridDoesNotTrap() {
        let cells: [[TileCell]] = [
            [],
            [TileCell(displayColor: .init(0, 1, 0), alpha: 1, brightness: 0.5)],
            [
                TileCell(displayColor: .init(1, 0, 0), alpha: 1, brightness: 0.5),
                TileCell(displayColor: .init(0, 0, 1), alpha: 1, brightness: 0.5),
            ],
        ]
        let grid = TileGrid(cells: cells, colorSpace: .sRGB)
        #expect(grid.rows == 3)
        #expect(grid.columns == 2)
        let image = grid.renderImage(scale: 8)
        #expect(image.width >= 8)
        #expect(image.height >= 8)
    }

    @Test func transparentCellRendersBackground() {
        let cells: [[TileCell]] = [
            [
                TileCell(displayColor: .init(1, 0, 0), alpha: 0, brightness: 0)
            ]
        ]
        let grid = TileGrid(cells: cells, colorSpace: .sRGB)
        let background = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        let image = grid.renderImage(scale: 8, backgroundColor: background)

        guard let data = image.dataProvider?.data,
            let bytes = CFDataGetBytePtr(data)
        else {
            Issue.record("could not read pixels")
            return
        }

        let offset = (4 * image.width * 4) + 4 * 4
        #expect(bytes[offset + 1] > 200)
        #expect(bytes[offset] < 50)
    }

    @Test func transparentMosaicCellShowsGroutNotBackground() {
        let grid = TileGrid(
            cells: [[TileCell(displayColor: .init(0, 0, 1), alpha: 0, brightness: 0)]],
            colorSpace: .sRGB
        )
        let grout = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        let background = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        let image = grid.renderImage(
            mode: .mosaic(grout: grout),
            cellShape: .square,
            scale: 8,
            backgroundColor: background
        )

        guard let rgba = Self.pixelRGBA(image, x: 4, y: 4) else {
            Issue.record("could not read center pixel")
            return
        }

        #expect(rgba.r > 200)
        #expect(rgba.g < 50)
        #expect(rgba.b < 50)
    }

    @Test func displayP3GridRendersP3TaggedImage() {
        let grid = TileGrid(
            cells: [[TileCell(displayColor: .init(1, 0, 0), alpha: 1, brightness: 0.5)]],
            colorSpace: .displayP3
        )

        let image = grid.renderImage(scale: 4)
        #expect(image.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func highScaleSmallSquareGridKeepsExpectedDimensions() {
        let grid = Self.tinyGrid()
        let image = grid.renderImage(cellShape: .square, scale: 128)
        #expect(image.width == 256)
        #expect(image.height == 256)
    }

    @Test func raggedHexGridUsesActualRowsWithoutTrap() {
        let grid = TileGrid(
            cells: [
                [TileCell(displayColor: .init(1, 0, 0), alpha: 1, brightness: 0.5)],
                [],
                [
                    TileCell(displayColor: .init(0, 1, 0), alpha: 1, brightness: 0.5),
                    TileCell(displayColor: .init(0, 0, 1), alpha: 1, brightness: 0.5),
                ],
            ],
            colorSpace: .sRGB
        )

        let image = grid.renderImage(cellShape: .hex, scale: 12)
        #expect(image.width > 12)
        #expect(image.height > 24)
    }

    private static func pixelRGBA(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard let data = image.dataProvider?.data,
            let bytes = CFDataGetBytePtr(data),
            x >= 0, y >= 0, x < image.width, y < image.height
        else {
            return nil
        }
        let offset = (y * image.width * 4) + (x * 4)
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
    }
}

@MainActor
@Suite(.serialized) struct TileGridRenderingSnapshotTests {

    /// 8x8 reference grid: a checkerboard of red, green, blue, white. Stable
    /// fixture for all mode x shape snapshots.
    private static func referenceGrid() -> TileGrid {
        var rows: [[TileCell]] = []
        let colors: [SIMD3<Float>] = [
            .init(1, 0, 0), .init(0, 1, 0),
            .init(0, 0, 1), .init(1, 1, 1),
            .init(1, 1, 0), .init(0, 1, 1),
            .init(1, 0, 1), .init(0.5, 0.5, 0.5),
        ]
        for rowIndex in 0..<8 {
            var row: [TileCell] = []
            for columnIndex in 0..<8 {
                let index = (rowIndex + columnIndex) % colors.count
                row.append(
                    TileCell(
                        displayColor: colors[index],
                        alpha: 1,
                        brightness: 0.5
                    ))
            }
            rows.append(row)
        }
        return TileGrid(cells: rows, colorSpace: .sRGB)
    }

    private static let scale: CGFloat = 16

    private func nsImage(from image: CGImage) -> NSImage {
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    @Test func pixelArtSquare() {
        let image = Self.referenceGrid().renderImage(mode: .pixelArt, cellShape: .square, scale: Self.scale)
        assertSnapshot(of: nsImage(from: image), as: .image, named: "pixelArt-square")
    }

    @Test func pixelArtHex() {
        let image = Self.referenceGrid().renderImage(mode: .pixelArt, cellShape: .hex, scale: Self.scale)
        assertSnapshot(of: nsImage(from: image), as: .image, named: "pixelArt-hex")
    }

    @Test func pixelArtTriangle() {
        let image = Self.referenceGrid().renderImage(mode: .pixelArt, cellShape: .triangle, scale: Self.scale)
        assertSnapshot(of: nsImage(from: image), as: .image, named: "pixelArt-triangle")
    }

    @Test func pixelArtDiamond() {
        let image = Self.referenceGrid().renderImage(mode: .pixelArt, cellShape: .diamond, scale: Self.scale)
        assertSnapshot(of: nsImage(from: image), as: .image, named: "pixelArt-diamond")
    }

    @Test func pixelArtCircle() {
        let image = Self.referenceGrid().renderImage(mode: .pixelArt, cellShape: .circle, scale: Self.scale)
        assertSnapshot(of: nsImage(from: image), as: .image, named: "pixelArt-circle")
    }

    @Test func brickSquare() {
        let image = Self.referenceGrid().renderImage(mode: .brick, cellShape: .square, scale: Self.scale)
        assertSnapshot(of: nsImage(from: image), as: .image, named: "brick-square")
    }

    @Test func brickHex() {
        let image = Self.referenceGrid().renderImage(mode: .brick, cellShape: .hex, scale: Self.scale)
        assertSnapshot(of: nsImage(from: image), as: .image, named: "brick-hex")
    }

    @Test func brickTriangle() {
        let image = Self.referenceGrid().renderImage(mode: .brick, cellShape: .triangle, scale: Self.scale)
        assertSnapshot(of: nsImage(from: image), as: .image, named: "brick-triangle")
    }

    @Test func brickDiamond() {
        let image = Self.referenceGrid().renderImage(mode: .brick, cellShape: .diamond, scale: Self.scale)
        assertSnapshot(of: nsImage(from: image), as: .image, named: "brick-diamond")
    }

    @Test func brickCircle() {
        let image = Self.referenceGrid().renderImage(mode: .brick, cellShape: .circle, scale: Self.scale)
        assertSnapshot(of: nsImage(from: image), as: .image, named: "brick-circle")
    }

    @Test func mosaicSquare() {
        let image = Self.referenceGrid().renderImage(mode: .mosaic, cellShape: .square, scale: Self.scale)
        assertSnapshot(of: nsImage(from: image), as: .image, named: "mosaic-square")
    }

    @Test func mosaicHex() {
        let image = Self.referenceGrid().renderImage(mode: .mosaic, cellShape: .hex, scale: Self.scale)
        assertSnapshot(of: nsImage(from: image), as: .image, named: "mosaic-hex")
    }

    @Test func mosaicTriangle() {
        let image = Self.referenceGrid().renderImage(mode: .mosaic, cellShape: .triangle, scale: Self.scale)
        assertSnapshot(of: nsImage(from: image), as: .image, named: "mosaic-triangle")
    }

    @Test func mosaicDiamond() {
        let image = Self.referenceGrid().renderImage(mode: .mosaic, cellShape: .diamond, scale: Self.scale)
        assertSnapshot(of: nsImage(from: image), as: .image, named: "mosaic-diamond")
    }

    @Test func mosaicCircle() {
        let image = Self.referenceGrid().renderImage(mode: .mosaic, cellShape: .circle, scale: Self.scale)
        assertSnapshot(of: nsImage(from: image), as: .image, named: "mosaic-circle")
    }

    @Test func mosaicCustomGroutColor() {
        let image = Self.referenceGrid().renderImage(
            mode: .mosaic(grout: CGColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1)),
            cellShape: .square,
            scale: Self.scale
        )
        assertSnapshot(of: nsImage(from: image), as: .image, named: "mosaic-grout-gray")
    }

    @Test func mosaicHighThickness() {
        let image = Self.referenceGrid().renderImage(
            mode: .mosaic(groutThickness: 0.3),
            cellShape: .square,
            scale: Self.scale
        )
        assertSnapshot(of: nsImage(from: image), as: .image, named: "mosaic-thick-grout")
    }

    @Test func mosaicNoCornerRadius() {
        let image = Self.referenceGrid().renderImage(
            mode: .mosaic(cornerRadius: 0),
            cellShape: .square,
            scale: Self.scale
        )
        assertSnapshot(of: nsImage(from: image), as: .image, named: "mosaic-sharp-corners")
    }
}
