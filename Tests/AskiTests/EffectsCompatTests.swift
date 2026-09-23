import Testing
import CoreGraphics
@testable import Aski

@Suite struct EffectsCompatTests {
    @Test func legacyAndNewPathProduceByteIdenticalImagesForASCIIGrid() {
        let cell = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
        let grid = ASCIIGrid(cells: Array(repeating: Array(repeating: cell, count: 16), count: 16), colorSpace: .sRGB)
        let font = ASCIIFont.system(size: 12)
        let bg = CGColor(red: 0, green: 0, blue: 0.4, alpha: 1)

        let legacy = grid.renderImage(font: font, backgroundColor: bg, scale: 1)
        let viaNew = grid.renderImage(
            font: font,
            backgroundColor: bg,
            scale: 1,
            composition: CompositionOptions(),
            lighting: nil,
            effects: EffectChain()
        )

        #expect(imagesAreByteIdentical(legacy, viaNew))
    }

    @Test func legacyAndNewPathProduceByteIdenticalImagesForTileGrid() {
        let cell = TileCell(displayColor: SIMD3<Float>(0, 1, 0), alpha: 1, brightness: 0.5)
        let grid = TileGrid(cells: Array(repeating: Array(repeating: cell, count: 16), count: 16), colorSpace: .sRGB)
        let bg = CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)

        let legacy = grid.renderImage(mode: .pixelArt, cellShape: .square, scale: 1, backgroundColor: bg)
        let viaNew = grid.renderImage(
            mode: .pixelArt,
            cellShape: .square,
            scale: 1,
            backgroundColor: bg,
            composition: CompositionOptions(),
            lighting: nil,
            effects: EffectChain()
        )

        #expect(imagesAreByteIdentical(legacy, viaNew))
    }

    private func imagesAreByteIdentical(_ lhs: CGImage, _ rhs: CGImage) -> Bool {
        TestImages.deviceRGBBytes(lhs) == TestImages.deviceRGBBytes(rhs)
    }
}
