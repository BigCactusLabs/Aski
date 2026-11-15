import CoreGraphics
import CoreImage
import Testing

@testable import Aski
import AskiToolSupport

/// ASKI-17: every raster entry point must reach its documented degenerate
/// fallback for large-but-finite scale and font sizes, instead of trapping in
/// the `Double` -> `Int` pixel-dimension conversion.
private let extremeScales: [CGFloat] = [1e30, .greatestFiniteMagnitude]
private let extremeFontSizes: [CGFloat] = [.infinity, 1e30]

@Suite struct RenderGeometryBoundsTests {

    private static func asciiGrid() -> ASCIIGrid {
        let cell = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
        return ASCIIGrid(cells: Array(repeating: Array(repeating: cell, count: 4), count: 3), colorSpace: .sRGB)
    }

    private static func tileGrid() -> TileGrid {
        let cell = TileCell(displayColor: SIMD3<Float>(0, 1, 0), alpha: 1, brightness: 0.5)
        return TileGrid(cells: Array(repeating: Array(repeating: cell, count: 4), count: 3), colorSpace: .sRGB)
    }

    private static let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    private static let effects = EffectChain([.vignette(intensity: 0.5)])

    // MARK: - ASCIIGrid direct

    @Test(arguments: extremeScales)
    func asciiGridDirectRenderDegradesForExtremeScale(scale: CGFloat) {
        let image = Self.asciiGrid().renderImage(
            font: .system(size: 12),
            backgroundColor: Self.background,
            scale: scale
        )
        #expect(image.width == 1)
        #expect(image.height == 1)
    }

    @Test(arguments: extremeFontSizes)
    func asciiGridDirectRenderDegradesForExtremeFontSize(size: CGFloat) {
        let image = Self.asciiGrid().renderImage(
            font: ASCIIFont(name: "Menlo", size: size),
            backgroundColor: Self.background,
            scale: 1
        )
        #expect(image.width == 1)
        #expect(image.height == 1)
    }

    // MARK: - TileGrid direct

    @Test(arguments: extremeScales)
    func tileGridDirectRenderDegradesForExtremeScale(scale: CGFloat) {
        let image = Self.tileGrid().renderImage(scale: scale, backgroundColor: Self.background)
        #expect(image.width == 1)
        #expect(image.height == 1)
    }

    // MARK: - Effects path (CellRasterBuilder)

    @Test(arguments: extremeScales)
    func asciiGridEffectsRenderDegradesForExtremeScale(scale: CGFloat) {
        let image = Self.asciiGrid().renderImage(
            font: .system(size: 12),
            backgroundColor: Self.background,
            scale: scale,
            effects: Self.effects
        )
        #expect(image.width == 1)
        #expect(image.height == 1)
    }

    @Test(arguments: extremeFontSizes)
    func asciiGridEffectsRenderDegradesForExtremeFontSize(size: CGFloat) {
        let image = Self.asciiGrid().renderImage(
            font: ASCIIFont(name: "Menlo", size: size),
            backgroundColor: Self.background,
            scale: 1,
            effects: Self.effects
        )
        #expect(image.width == 1)
        #expect(image.height == 1)
    }

    @Test(arguments: extremeScales)
    func tileGridEffectsRenderDegradesForExtremeScale(scale: CGFloat) {
        let image = Self.tileGrid().renderImage(
            scale: scale,
            backgroundColor: Self.background,
            effects: Self.effects
        )
        #expect(image.width == 1)
        #expect(image.height == 1)
    }

    @Test(arguments: extremeScales)
    func asciiGridEffectsAsyncThrowsForExtremeScale(scale: CGFloat) async {
        do {
            _ = try await Self.asciiGrid().renderImage(
                font: .system(size: 12),
                backgroundColor: Self.background,
                scale: scale,
                effects: Self.effects
            )
            Issue.record("expected EffectError.degenerateOutput")
        } catch EffectError.degenerateOutput {
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test(arguments: extremeFontSizes)
    func asciiGridEffectsAsyncThrowsForExtremeFontSize(size: CGFloat) async {
        do {
            _ = try await Self.asciiGrid().renderImage(
                font: ASCIIFont(name: "Menlo", size: size),
                backgroundColor: Self.background,
                scale: 1,
                effects: Self.effects
            )
            Issue.record("expected EffectError.degenerateOutput")
        } catch EffectError.degenerateOutput {
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    // MARK: - CIImage path

    @Test(arguments: extremeScales)
    func asciiGridCIImageDegradesForExtremeScale(scale: CGFloat) {
        let image = Self.asciiGrid().renderCIImage(
            font: .system(size: 12),
            backgroundColor: Self.background,
            scale: scale,
            effects: Self.effects
        )
        #expect(image.extent.isEmpty)
    }

    @Test(arguments: extremeFontSizes)
    func asciiGridCIImageDegradesForExtremeFontSize(size: CGFloat) {
        let image = Self.asciiGrid().renderCIImage(
            font: ASCIIFont(name: "Menlo", size: size),
            backgroundColor: Self.background,
            scale: 1,
            effects: Self.effects
        )
        #expect(image.extent.isEmpty)
    }

    @Test(arguments: extremeScales)
    func tileGridCIImageDegradesForExtremeScale(scale: CGFloat) {
        let image = Self.tileGrid().renderCIImage(
            scale: scale,
            backgroundColor: Self.background,
            effects: Self.effects
        )
        #expect(image.extent.isEmpty)
    }

    // MARK: - Conversion followed by rendering

    private static func renderConvertedPortrait(scale: CGFloat, fontSize: CGFloat) -> CGImage {
        let source = TestImages.structuredPortraitProxy(width: 48, height: 64)
        return FrozenRenderReference.makeConverter()
            .convert(source, columns: 12)
            .renderImage(
                font: .courierPrime(size: fontSize),
                backgroundColor: FrozenRenderReference.backgroundColor,
                scale: scale,
                preserveSourceAspect: true
            )
    }

    @Test(arguments: extremeScales)
    func convertedPortraitDegradesForExtremeScale(scale: CGFloat) {
        let rendered = Self.renderConvertedPortrait(scale: scale, fontSize: 14)
        #expect(rendered.width == 1)
        #expect(rendered.height == 1)
    }

    @Test(arguments: extremeFontSizes)
    func convertedPortraitDegradesForExtremeFontSize(size: CGFloat) {
        let rendered = Self.renderConvertedPortrait(scale: 2, fontSize: size)
        #expect(rendered.width == 1)
        #expect(rendered.height == 1)
    }

    // MARK: - Valid geometry is untouched

    @Test func validScaleAndFontSizeStillRenderExpectedPixelDimensions() {
        let grid = Self.asciiGrid()
        let image = grid.renderImage(
            font: ASCIIFont(name: "Menlo", size: 10),
            backgroundColor: Self.background,
            scale: 2
        )
        // 4 columns * (10 * 0.6) glyph width * 2 = 48; 3 rows * (10 * 1.2) * 2 = 72.
        #expect(image.width == 48)
        #expect(image.height == 72)
    }
}
