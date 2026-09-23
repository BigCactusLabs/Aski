@_spi(AskiResearch) import Aski
import CoreGraphics
import Foundation

/// A synthetic source pushed through the *real* `ASCIIConverter`, plus the HDR
/// expectation gate G3 grades it against. Using the real converter means
/// `brightness`/`displayColor` are the genuine pipeline values, so emission keys
/// on real source luminance rather than hand-authored cells.
struct HDRFixture {
    enum Expectation: String { case blooms, flat }
    let id: String
    let grid: ASCIIGrid
    let gamut: RenderColorSpace
    let expectation: Expectation
    let emissionSource: EmissionOptions.Source
}

enum HDRFixtures {
    static let sourceSize = 256

    /// The fixture corpus. Bright/edge/gradient/mono should bloom; the dark
    /// fixture must stay flat (no spurious emission). `bright-p3` exercises the
    /// `extendedLinearDisplayP3` path; the rest are sRGB.
    static func all(columns: Int) -> [HDRFixture] {
        [
            fixture(id: "bright-srgb", gamut: .sRGB, palette: BuiltInPalette.fullColor, expectation: .blooms, columns: columns) {
                fillUniform($0, gray: 1.0)
            },
            fixture(id: "bright-p3", gamut: .displayP3, palette: BuiltInPalette.fullColor, expectation: .blooms, columns: columns) {
                fillUniform($0, gray: 1.0)
            },
            fixture(id: "dark-srgb", gamut: .sRGB, palette: BuiltInPalette.fullColor, expectation: .flat, columns: columns) {
                fillUniform($0, gray: 0.08)
            },
            fixture(id: "edge-srgb", gamut: .sRGB, palette: BuiltInPalette.fullColor, expectation: .blooms, columns: columns) {
                drawSplit($0)
            },
            fixture(id: "gradient-srgb", gamut: .sRGB, palette: BuiltInPalette.fullColor, expectation: .blooms, columns: columns) {
                drawGradient($0)
            },
            fixture(id: "mono-bright-srgb", gamut: .sRGB, palette: BuiltInPalette.monochrome, expectation: .blooms, columns: columns) {
                fillUniform($0, gray: 0.95)
            },
            authoredFixture(
                id: "authored-dark-emits",
                character: "*",
                displayColor: SIMD3<Float>(1, 1, 1),
                brightness: 0.05,
                expectation: .blooms,
                columns: columns,
                source: .authored(GlyphEmissionSpec(["*": 1.25]))
            ),
            authoredFixture(
                id: "authored-bright-flat",
                character: "#",
                displayColor: SIMD3<Float>(1, 1, 1),
                brightness: 1.0,
                expectation: .flat,
                columns: columns,
                source: .authored(GlyphEmissionSpec(["*": 1.25]))
            ),
            authoredIntensitySweep(columns: columns),
        ]
    }

    private static func fixture(
        id: String,
        gamut: RenderColorSpace,
        palette: BuiltInPalette,
        expectation: HDRFixture.Expectation,
        columns: Int,
        draw: (CGContext) -> Void
    ) -> HDRFixture {
        let image = makeSource(draw: draw)
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: palette,
            colorSpace: gamut
        )
        let grid = converter.convert(image, columns: columns)
        return HDRFixture(id: id, grid: grid, gamut: gamut, expectation: expectation, emissionSource: .brightnessCurve)
    }

    private static func authoredFixture(
        id: String,
        character: Character,
        displayColor: SIMD3<Float>,
        brightness: Float,
        expectation: HDRFixture.Expectation,
        columns: Int,
        source: EmissionOptions.Source
    ) -> HDRFixture {
        let rows = max(1, columns / 2)
        let cell = ASCIICell(character: character, displayColor: displayColor, alpha: 1, brightness: brightness)
        let grid = ASCIIGrid(
            cells: Array(repeating: Array(repeating: cell, count: columns), count: rows),
            colorSpace: .sRGB
        )
        return HDRFixture(id: id, grid: grid, gamut: .sRGB, expectation: expectation, emissionSource: source)
    }

    private static func authoredIntensitySweep(columns: Int) -> HDRFixture {
        let rows = max(1, columns / 2)
        let pattern: [Character] = [".", "+", "*", "@"]
        let spec = GlyphEmissionSpec([
            ".": 0.25,
            "+": 0.75,
            "*": 1.25,
            "@": 1.75,
        ])
        let cells = (0..<rows).map { _ in
            (0..<columns).map { column in
                ASCIICell(
                    character: pattern[column % pattern.count],
                    displayColor: SIMD3<Float>(1, 1, 1),
                    alpha: 1,
                    brightness: 0.25
                )
            }
        }
        let grid = ASCIIGrid(cells: cells, colorSpace: .sRGB)
        return HDRFixture(
            id: "authored-intensity-sweep",
            grid: grid,
            gamut: .sRGB,
            expectation: .blooms,
            emissionSource: .authored(spec)
        )
    }

    private static func makeSource(draw: (CGContext) -> Void) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: sourceSize, height: sourceSize, bitsPerComponent: 8,
            bytesPerRow: sourceSize * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: sourceSize, height: sourceSize))
        draw(ctx)
        return ctx.makeImage()!
    }

    private static func fillUniform(_ ctx: CGContext, gray: CGFloat) {
        ctx.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: sourceSize, height: sourceSize))
    }

    private static func drawSplit(_ ctx: CGContext) {
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: sourceSize / 2, height: sourceSize))
    }

    private static func drawGradient(_ ctx: CGContext) {
        for x in 0..<sourceSize {
            let t = CGFloat(x) / CGFloat(sourceSize - 1)
            ctx.setFillColor(CGColor(red: t, green: t, blue: t, alpha: 1))
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: sourceSize))
        }
    }
}
