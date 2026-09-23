import Testing
import simd
@testable import Aski

@Suite struct PaletteTests {
    @Test func fullColorIsPassThroughContent() {
        let palette = BuiltInPalette.fullColor
        #expect(palette.content.isPassThrough)
        #expect(palette.content.colors == nil)
    }

    @Test func fixedContentExposesNonEmptyColors() {
        let red = PaletteColor(SIMD3<Float>(1, 0, 0), colorSpace: .sRGB)
        let content = PaletteContent.fixed([red])

        #expect(!content.isPassThrough)
        #expect(content.colors == [red])
    }

    #if !SWT_NO_EXIT_TESTS
        @Test func fixedEmptyPaletteFailsPrecondition() async {
            await #expect(processExitsWith: .failure) {
                _ = PaletteContent.fixed([])
            }
        }
    #endif

    @Test func paletteColorDefaultsToSRGB() {
        let color = PaletteColor(SIMD3<Float>(0.25, 0.5, 0.75))

        #expect(color.components == SIMD3<Float>(0.25, 0.5, 0.75))
        #expect(color.colorSpace == .sRGB)
    }

    @Test func paletteColorSpaceUsesStaticMembers() {
        #expect(PaletteColorSpace.sRGB == .sRGB)
        #expect(PaletteColorSpace.sRGB != .displayP3)
    }

    @Test func ansi16HasSixteenFixedSRGBColors() {
        let content = BuiltInPalette.ansi16.content
        #expect(!content.isPassThrough)

        let colors = content.colors ?? []
        #expect(colors.count == 16)
        #expect(colors[0] == PaletteColor(SIMD3<Float>(0, 0, 0), colorSpace: .sRGB))
        #expect(colors[9] == PaletteColor(SIMD3<Float>(1, 0, 0), colorSpace: .sRGB))
        #expect(colors[15] == PaletteColor(SIMD3<Float>(1, 1, 1), colorSpace: .sRGB))
    }

    @Test func monochromeHasOneFixedWhiteSRGBColor() {
        let content = BuiltInPalette.monochrome.content
        #expect(!content.isPassThrough)

        let colors = content.colors ?? []
        #expect(colors == [PaletteColor(SIMD3<Float>(1, 1, 1), colorSpace: .sRGB)])
    }
}
