import CoreGraphics
import CoreImage
import Testing
@testable import Aski

@Suite struct CoverageImageBuilderTests {
    @Test func asciiHardCoverageKeepsCellValuesFlat() {
        let grid = ASCIIGrid(
            cells: [
                [
                    ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 1, coverage: 0),
                    ASCIICell(character: "B", displayColor: .one, alpha: 1, brightness: 1, coverage: 1),
                ]
            ],
            colorSpace: .sRGB,
            maskUsesHardEdges: true
        )
        let image = CoverageImageBuilder.makeASCII(
            grid: grid,
            extent: CGRect(x: 0, y: 0, width: 20, height: 10),
            useHardEdges: true
        )

        let left = Self.sampleGray(image, x: 5, y: 5)
        let right = Self.sampleGray(image, x: 15, y: 5)
        #expect(left < 8)
        #expect(right > 247)
    }

    @Test func tilePixelArtCoverageLeavesCircleGapWhite() {
        let grid = TileGrid(
            cells: [[TileCell(displayColor: .one, alpha: 1, brightness: 1, coverage: 0)]],
            colorSpace: .sRGB
        )
        let image = CoverageImageBuilder.makeTile(
            grid: grid,
            mode: .pixelArt,
            shape: .circle,
            scale: 20,
            extent: CGRect(x: 0, y: 0, width: 20, height: 20),
            useHardEdges: true
        )

        let corner = Self.sampleGray(image, x: 0, y: 0)
        let center = Self.sampleGray(image, x: 10, y: 10)
        #expect(corner > 247)
        #expect(center < 8)
    }

    @Test func tileMosaicCoverageInitializesMarginsBlack() {
        let grid = TileGrid(
            cells: [[TileCell(displayColor: .one, alpha: 1, brightness: 1, coverage: 1)]],
            colorSpace: .sRGB
        )
        let image = CoverageImageBuilder.makeTile(
            grid: grid,
            mode: .mosaic,
            shape: .square,
            scale: 10,
            extent: CGRect(x: 0, y: 0, width: 20, height: 20),
            useHardEdges: true
        )

        let inside = Self.sampleGray(image, x: 5, y: 5)
        let margin = Self.sampleGray(image, x: 15, y: 15)
        #expect(inside > 247)
        #expect(margin < 8)
    }

    private static func sampleGray(_ image: CIImage, x: Int, y: Int) -> UInt8 {
        let context = CIContext(options: nil)
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            image,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: x, y: y, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return pixel[0]
    }
}
