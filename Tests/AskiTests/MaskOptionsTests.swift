import CoreGraphics
import Testing
@testable import Aski

@Suite struct MaskOptionsTests {
    @Test func defaultsAreTransparentSoftNonInverted() {
        let image = Self.solidGrayImage(value: 1, width: 2, height: 2)
        let options = MaskOptions(image: image)

        #expect(options.image.width == 2)
        if case .transparent = options.fallback {
        } else {
            Issue.record("expected transparent fallback")
        }
        #expect(options.groundColor == nil)
        #expect(options.softEdges)
        #expect(!options.invert)
    }

    @Test func explicitInitializerStoresArguments() {
        let image = Self.solidGrayImage(value: 0, width: 3, height: 4)
        let fallbackColor = CGColor(red: 1, green: 0, blue: 0, alpha: 0.75)
        let groundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        let options = MaskOptions(
            image: image,
            fallback: .solid(fallbackColor),
            groundColor: groundColor,
            softEdges: false,
            invert: true
        )

        #expect(options.image.width == 3)
        #expect(options.image.height == 4)
        #expect(!options.softEdges)
        #expect(options.invert)
        if case .solid(let storedColor) = options.fallback {
            #expect(abs(storedColor.alpha - 0.75) < 0.001)
        } else {
            Issue.record("expected solid fallback")
        }
        #expect(options.groundColor?.alpha == 0.5)
    }

    @Test func cellAndGridDefaultsPreserveUnmaskedState() {
        let asciiCell = ASCIICell(
            character: "#",
            displayColor: SIMD3<Float>(1, 1, 1),
            alpha: 0.8,
            brightness: 0.5
        )
        #expect(asciiCell.coverage == 1)

        let tileCell = TileCell(
            displayColor: SIMD3<Float>(0, 1, 0),
            alpha: 0.7,
            brightness: 0.4
        )
        #expect(tileCell.coverage == 1)

        let asciiGrid = ASCIIGrid(cells: [[asciiCell]], colorSpace: .sRGB)
        #expect(asciiGrid.maskFallback == nil)
        #expect(asciiGrid.maskGroundColor == nil)
        #expect(!asciiGrid.maskUsesHardEdges)

        let tileGrid = TileGrid(cells: [[tileCell]], colorSpace: .displayP3)
        #expect(tileGrid.maskFallback == nil)
        #expect(tileGrid.maskGroundColor == nil)
        #expect(!tileGrid.maskUsesHardEdges)
    }

    @Test func explicitCellAndGridMaskFieldsRoundTrip() {
        let asciiCell = ASCIICell(
            character: "@",
            displayColor: SIMD3<Float>(1, 0, 0),
            alpha: 1,
            brightness: 0.9,
            coverage: 0.25
        )
        let tileCell = TileCell(
            displayColor: SIMD3<Float>(0, 0, 1),
            alpha: 1,
            brightness: 0.2,
            coverage: 0.75
        )
        let fallback = MaskFallback.character("#", color: nil)
        let ground = CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0)

        let asciiGrid = ASCIIGrid(
            cells: [[asciiCell]],
            colorSpace: .sRGB,
            maskFallback: fallback,
            maskGroundColor: ground,
            maskUsesHardEdges: true
        )
        let tileGrid = TileGrid(
            cells: [[tileCell]],
            colorSpace: .sRGB,
            maskFallback: .transparent,
            maskGroundColor: ground,
            maskUsesHardEdges: true
        )

        #expect(asciiGrid.cells[0][0].coverage == 0.25)
        #expect(tileGrid.cells[0][0].coverage == 0.75)
        #expect(asciiGrid.maskFallback != nil)
        #expect(tileGrid.maskFallback != nil)
        #expect(asciiGrid.maskGroundColor?.alpha == 0)
        #expect(tileGrid.maskGroundColor?.alpha == 0)
        #expect(asciiGrid.maskUsesHardEdges)
        #expect(tileGrid.maskUsesHardEdges)
    }

    private static func solidGrayImage(value: CGFloat, width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.setFillColor(gray: value, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
