import Aski
import CoreGraphics
import Testing

@Suite struct ConverterHelmlabIntegrationTests {
    private func gradient(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        for x in 0..<width {
            let t = CGFloat(x) / CGFloat(width - 1)
            ctx.setFillColor(red: t, green: 1 - t, blue: 0.5, alpha: 1)
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return ctx.makeImage()!
    }

    @Test func convertWithHelmlabPolicyDoesNotCrashAndProducesGrid() {
        let image = gradient(width: 64, height: 32)
        for policy in [PaletteMatchingPolicy.helmlabEuclidean, .helmlabCompressed] {
            let converter = ASCIIConverter(
                characterSet: StandardCharacterSet.standard,
                palette: BuiltInPalette.ansi16,
                paletteMatching: policy
            )
            let grid = converter.convert(image, columns: 20)
            #expect(!grid.cells.isEmpty)
        }
    }

    @Test func animateWithHelmlabPolicyDoesNotCrash() {
        let image = gradient(width: 64, height: 32)
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.ansi16,
            paletteMatching: .helmlabCompressed
        )
        let animated = converter.animate(image, columns: 20, options: .init(duration: 1.0))
        #expect(!animated.baseGrid.cells.isEmpty)
    }
}
