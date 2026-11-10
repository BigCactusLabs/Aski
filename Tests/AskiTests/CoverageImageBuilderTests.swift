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

    /// ASKI-101: the coverage image carries data, not color. A consumer reads
    /// the stored coverage as the weight whether its working space is linear or
    /// encoded; a color-managed Device Gray image read 0.5 as about 0.216 in a
    /// linear working space.
    @Test(arguments: [Float(0.25), 0.5, 0.75])
    func softCoverageReadsBackUnchangedInAnyWorkingSpace(coverage: Float) throws {
        let extent = CGRect(x: 0, y: 0, width: 100, height: 100)
        let ascii = CoverageImageBuilder.makeASCII(
            grid: ASCIIGrid(
                cells: [[ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 1, coverage: coverage)]],
                colorSpace: .sRGB
            ),
            extent: extent,
            useHardEdges: false
        )
        let tile = CoverageImageBuilder.makeTile(
            grid: TileGrid(
                cells: [[TileCell(displayColor: .one, alpha: 1, brightness: 1, coverage: coverage)]],
                colorSpace: .sRGB
            ),
            mode: .pixelArt,
            shape: .square,
            scale: 100,
            extent: extent,
            useHardEdges: false
        )
        let expected = Int((coverage * 255).rounded())
        for working in [CGColorSpace.extendedLinearSRGB, CGColorSpace.sRGB] {
            let space = try #require(CGColorSpace(name: working))
            for (name, image) in [("ascii", ascii), ("tile", tile)] {
                let value = Int(Self.sampleWorkingValue(image, x: 50, y: 50, workingSpace: space))
                #expect(abs(value - expected) <= 1, "\(name) \(working): \(value), expected \(expected)")
            }
        }
    }

    /// The red channel as the working space holds it, with no output color matching.
    private static func sampleWorkingValue(_ image: CIImage, x: Int, y: Int, workingSpace: CGColorSpace) -> UInt8 {
        let context = CIContext(options: [.workingColorSpace: workingSpace])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            image,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: x, y: y, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return pixel[0]
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
