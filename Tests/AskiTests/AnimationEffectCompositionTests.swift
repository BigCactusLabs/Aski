import CoreGraphics
import Testing
@testable import Aski

@Suite
struct AnimationEffectCompositionTests {
    @Test
    func renderImageConvenienceMatchesGridRender() {
        let image = TestImages.horizontalGradient(width: 80, height: 80)
        let animated = DefaultConverter().animate(
            image,
            columns: 12,
            options: AnimationOptions(duration: 1, cycling: nil, ongoing: .pulse(period: 1, depth: 0))
        )
        let font = ASCIIFont.system(size: 8)
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

        let direct = animated.grid(at: 0.25).renderImage(
            font: font,
            backgroundColor: background,
            scale: 1,
            effects: EffectChain([.vignette(intensity: 0.2)])
        )
        let convenience = animated.renderImage(
            at: 0.25,
            font: font,
            backgroundColor: background,
            scale: 1,
            effects: EffectChain([.vignette(intensity: 0.2)])
        )

        #expect(direct.width == convenience.width)
        #expect(direct.height == convenience.height)
    }
}
