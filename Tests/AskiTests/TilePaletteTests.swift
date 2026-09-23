import CoreGraphics
import Testing
import simd
@testable import Aski

@Suite struct TilePaletteTests {

    @Test func adaptiveClampsMaxColors() {
        let lo = TilePalette.adaptive(maxColors: 0)
        let hi = TilePalette.adaptive(maxColors: 9999)

        if case .adaptive(let n) = lo.strategy {
            #expect(n == 2)
        } else {
            Issue.record("expected adaptive strategy")
        }

        if case .adaptive(let n) = hi.strategy {
            #expect(n == 256)
        } else {
            Issue.record("expected adaptive strategy")
        }
    }

    @Test func brickReturnsPrecomputedOKLAB() {
        if case .fixedOKLAB(let colors) = TilePalette.brick.strategy {
            #expect(colors.count == BrickColors.oklab.count)
            for (a, b) in zip(colors, BrickColors.oklab) {
                #expect(simd_length(a - b) < 1e-6)
            }
        } else {
            Issue.record("expected fixedOKLAB strategy")
        }
    }

    @Test func fixedSRGBConvertsAtConstruction() {
        let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        let palette = TilePalette.fixed([red])
        guard case .fixedOKLAB(let colors) = palette.strategy else {
            Issue.record("expected fixedOKLAB strategy")
            return
        }
        #expect(colors.count == 1)
        #expect(abs(colors[0].x - 0.628) < 0.02)
        #expect(colors[0].y > 0.15)
    }

    @Test func adaptiveResolvedRespectsMaxColors() {
        let pixels = WuQuantizationTestsFixture.fourQuadrants(width: 64, height: 64)
        let palette = TilePalette.adaptive(maxColors: 4)
        let resolved = palette.resolved(
            pixels: pixels,
            pixelWidth: 64,
            pixelHeight: 64,
            colorSpace: .sRGB
        )
        #expect(resolved.colors.count <= 4)
        #expect(resolved.colors.count >= 2)
    }

    @Test func brickResolvedHasPrecomputedColors() {
        let pixels = WuQuantizationTestsFixture.fourQuadrants(width: 8, height: 8)
        let resolved = TilePalette.brick.resolved(
            pixels: pixels,
            pixelWidth: 8,
            pixelHeight: 8,
            colorSpace: .sRGB
        )
        #expect(resolved.colors.count == BrickColors.oklab.count)
    }

    #if !SWT_NO_EXIT_TESTS
        @Test func emptyFixedPaletteFailsPrecondition() async {
            await #expect(processExitsWith: .failure) {
                _ = TilePalette.fixed([])
            }
        }
    #endif

    @Test func adaptiveFullyTransparentPaletteResolvesAsPassThrough() {
        let pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        let resolved = TilePalette.adaptive(maxColors: 8).resolved(
            pixels: pixels,
            pixelWidth: 8,
            pixelHeight: 8,
            colorSpace: .sRGB
        )

        #expect(resolved.isPassThrough)
        #expect(resolved.colors.isEmpty)
    }

    @Test func fixedDisplayP3ConvertsCorrectly() {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        guard let p3Red = CGColor(colorSpace: p3, components: [1, 0, 0, 1]) else {
            Issue.record("could not construct P3 red")
            return
        }
        let palette = TilePalette.fixed([p3Red])
        guard case .fixedOKLAB(let colors) = palette.strategy, colors.count == 1 else {
            Issue.record("expected one fixedOKLAB color")
            return
        }
        #expect(colors[0].x > 0.5 && colors[0].x < 0.75)
        #expect(colors[0].y > 0.20)
    }

    @Test func fixedGenericGrayConvertsViaSRGB() {
        let gray = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2) ?? CGColorSpaceCreateDeviceGray()
        guard let mid = CGColor(colorSpace: gray, components: [0.5, 1]) else {
            Issue.record("could not construct generic gray 0.5")
            return
        }
        let palette = TilePalette.fixed([mid])
        guard case .fixedOKLAB(let colors) = palette.strategy, colors.count == 1 else {
            Issue.record("expected one fixedOKLAB color")
            return
        }
        #expect(abs(colors[0].x - 0.59) < 0.05)
        #expect(abs(colors[0].y) < 0.02)
        #expect(abs(colors[0].z) < 0.02)
    }

    @Test func fixedCMYKFallsThroughToSRGB() {
        guard let cmyk = CGColorSpace(name: CGColorSpace.genericCMYK) else {
            return
        }
        guard let cyan = CGColor(colorSpace: cmyk, components: [1, 0, 0, 0, 1]) else {
            Issue.record("could not construct CMYK cyan")
            return
        }
        let palette = TilePalette.fixed([cyan])
        guard case .fixedOKLAB(let colors) = palette.strategy, colors.count == 1 else {
            Issue.record("expected one fixedOKLAB color")
            return
        }
        #expect(!colors[0].x.isNaN)
        #expect(colors[0].y < 0)
        #expect(colors[0].x > 0.3)
    }
}
