import CoreGraphics
import Testing
@testable import Aski

@Suite struct TileGridConverterMaskTests {
    @Test func noMaskProducesFullCoverageAndNoFallback() {
        let image = TestImages.horizontalGradient(width: 120, height: 60)
        let grid = TileGridConverter(palette: .adaptive(maxColors: 4)).convert(image, columns: 12)

        #expect(grid.maskFallback == nil)
        #expect(grid.maskGroundColor == nil)
        #expect(!grid.maskUsesHardEdges)
        for cell in grid.cells.flatMap({ $0 }) {
            #expect(cell.coverage == 1)
        }
    }

    @Test func maskCoverageAndGridPolicyRoundTrip() {
        let image = TestImages.horizontalGradient(width: 120, height: 60)
        let fallback = CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        let ground = CGColor(red: 0, green: 0, blue: 0, alpha: 0.6)
        let grid = TileGridConverter(palette: .adaptive(maxColors: 4)).convert(
            image,
            columns: 4,
            mask: MaskOptions(
                image: Self.horizontalFourStepMask(),
                fallback: .solid(fallback),
                groundColor: ground,
                softEdges: false,
                invert: false
            )
        )

        #expect(grid.columns == 4)
        #expect(grid.maskUsesHardEdges)
        #expect(grid.maskFallback != nil)
        #expect(abs((grid.maskGroundColor?.alpha ?? 0) - 0.6) < 0.001)
        for row in grid.cells {
            #expect(row[0].coverage == 0)
            #expect(row[1].coverage == 0)
            #expect(row[2].coverage == 1)
            #expect(row[3].coverage == 1)
        }
    }

    private static func horizontalFourStepMask() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(
            data: nil,
            width: 4,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        let values: [CGFloat] = [0.0, 0.49, 0.5, 1.0]
        for x in 0..<4 {
            context.setFillColor(gray: values[x], alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 1, height: 1))
        }
        return context.makeImage()!
    }
}
