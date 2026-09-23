import Testing
@testable import AskiMotionLab

@Suite struct AskiMotionLabSyntheticImageTests {
    @Test func pixelBufferHasRGBA8Length() {
        #expect(SyntheticImage.pixels(width: 4, height: 4).count == 4 * 4 * 4)
    }

    @Test func pixelGenerationIsDeterministic() {
        #expect(SyntheticImage.pixels(width: 8, height: 8) == SyntheticImage.pixels(width: 8, height: 8))
    }

    @Test func everyPixelIsOpaque() {
        let px = SyntheticImage.pixels(width: 8, height: 8)
        for alphaIndex in stride(from: 3, to: px.count, by: 4) {
            #expect(px[alphaIndex] == 255)
        }
    }

    @Test func makeProducesImageWithRequestedDimensions() {
        let image = SyntheticImage.make(width: 16, height: 16)
        #expect(image.width == 16)
        #expect(image.height == 16)
    }
}
