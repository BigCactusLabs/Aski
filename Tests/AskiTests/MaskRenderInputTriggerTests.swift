import CoreGraphics
import CoreImage
import Testing
@testable import Aski

@Suite struct MaskRenderInputTriggerTests {
    @Test func effectiveGroundRequiresPositiveFiniteAlpha() {
        #expect(effectiveMaskGroundColor(nil) == nil)
        #expect(effectiveMaskGroundColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0)) == nil)
        #expect(effectiveMaskGroundColor(CGColor(red: 0, green: 0, blue: 0, alpha: .nan)) == nil)

        let partial = effectiveMaskGroundColor(
            CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        )
        #expect(abs((partial?.alpha ?? 0) - 0.4) < 0.001)
    }

    @Test func asciiAllWhiteCoverageBuildsNoMaskInput() {
        let grid = ASCIIGrid(
            cells: [[ASCIICell(character: "#", displayColor: .one, alpha: 1, brightness: 1, coverage: 1)]],
            colorSpace: .sRGB,
            maskFallback: .solid(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        )
        let input = EffectsRenderEngine.makeASCIIMaskInput(
            grid: grid,
            font: .system(size: 12),
            scale: 1,
            extent: CGRect(x: 0, y: 0, width: 12, height: 12)
        )
        #expect(input == nil)
    }

    @Test func asciiTransparentFallbackBuildsNoMaskInput() {
        let grid = ASCIIGrid(
            cells: [[ASCIICell(character: "#", displayColor: .one, alpha: 1, brightness: 1, coverage: 0)]],
            colorSpace: .sRGB,
            maskFallback: .transparent
        )
        let input = EffectsRenderEngine.makeASCIIMaskInput(
            grid: grid,
            font: .system(size: 12),
            scale: 1,
            extent: CGRect(x: 0, y: 0, width: 12, height: 12)
        )
        #expect(input == nil)
    }

    @Test func asciiAllWhiteGroundBuildsGroupedInputWithoutFallback() {
        let grid = ASCIIGrid(
            cells: [[ASCIICell(character: "#", displayColor: .one, alpha: 1, brightness: 1, coverage: 1)]],
            colorSpace: .sRGB,
            maskFallback: .transparent,
            maskGroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        )
        let input = EffectsRenderEngine.makeASCIIMaskInput(
            grid: grid,
            font: .system(size: 12),
            scale: 1,
            extent: CGRect(x: 0, y: 0, width: 12, height: 12)
        )

        #expect(input?.activeGround != nil)
        #expect(input?.fallback == nil)
        #expect(input?.usesGroupedComposition == true)
    }

    @Test func asciiZeroAlphaGroundKeepsAllWhiteLegacyTrigger() {
        let grid = ASCIIGrid(
            cells: [[ASCIICell(character: "#", displayColor: .one, alpha: 1, brightness: 1, coverage: 1)]],
            colorSpace: .sRGB,
            maskFallback: .solid(CGColor(red: 1, green: 0, blue: 0, alpha: 1)),
            maskGroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 0)
        )
        let input = EffectsRenderEngine.makeASCIIMaskInput(
            grid: grid,
            font: .system(size: 12),
            scale: 1,
            extent: CGRect(x: 0, y: 0, width: 12, height: 12)
        )

        #expect(input == nil)
    }

    @Test func asciiSolidFallbackBuildsCoverageAndFallback() {
        let grid = ASCIIGrid(
            cells: [[ASCIICell(character: "#", displayColor: .one, alpha: 1, brightness: 1, coverage: 0)]],
            colorSpace: .sRGB,
            maskFallback: .solid(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        )
        let input = EffectsRenderEngine.makeASCIIMaskInput(
            grid: grid,
            font: .system(size: 12),
            scale: 1,
            extent: CGRect(x: 0, y: 0, width: 12, height: 12)
        )
        #expect(input != nil)
        #expect(input?.fallback != nil)
    }

    @Test func tilePixelArtTransparentFallbackBuildsNoMaskInput() {
        let grid = TileGrid(
            cells: [[TileCell(displayColor: .one, alpha: 1, brightness: 1, coverage: 0)]],
            colorSpace: .sRGB,
            maskFallback: .transparent
        )
        let input = EffectsRenderEngine.makeTileMaskInput(
            grid: grid,
            mode: .pixelArt,
            cellShape: .square,
            scale: 8,
            extent: CGRect(x: 0, y: 0, width: 8, height: 8)
        )
        #expect(input == nil)
    }

    @Test func tileBrickTransparentFallbackBuildsNoMaskInput() {
        let grid = TileGrid(
            cells: [[TileCell(displayColor: .one, alpha: 1, brightness: 1, coverage: 0)]],
            colorSpace: .sRGB,
            maskFallback: .transparent
        )
        let input = EffectsRenderEngine.makeTileMaskInput(
            grid: grid,
            mode: .brick,
            cellShape: .square,
            scale: 8,
            extent: CGRect(x: 0, y: 0, width: 8, height: 8)
        )
        #expect(input == nil)
    }

    @Test func tileMosaicTransparentFallbackBuildsCoverageOnlyInput() {
        let grid = TileGrid(
            cells: [[TileCell(displayColor: .one, alpha: 1, brightness: 1, coverage: 0)]],
            colorSpace: .sRGB,
            maskFallback: .transparent
        )
        let input = EffectsRenderEngine.makeTileMaskInput(
            grid: grid,
            mode: .mosaic,
            cellShape: .square,
            scale: 8,
            extent: CGRect(x: 0, y: 0, width: 8, height: 8)
        )
        #expect(input != nil)
        #expect(input?.fallback == nil)
    }

    @Test func tileAllWhiteCoverageBuildsNoMaskInput() {
        let grid = TileGrid(
            cells: [[TileCell(displayColor: .one, alpha: 1, brightness: 1, coverage: 1)]],
            colorSpace: .sRGB,
            maskFallback: .solid(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        )
        let input = EffectsRenderEngine.makeTileMaskInput(
            grid: grid,
            mode: .mosaic,
            cellShape: .square,
            scale: 8,
            extent: CGRect(x: 0, y: 0, width: 8, height: 8)
        )
        #expect(input == nil)
    }

    @Test func tileAllWhiteGroundBuildsGroupedInput() {
        let grid = TileGrid(
            cells: [[TileCell(displayColor: .one, alpha: 1, brightness: 1, coverage: 1)]],
            colorSpace: .sRGB,
            maskFallback: .transparent,
            maskGroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        )
        let input = EffectsRenderEngine.makeTileMaskInput(
            grid: grid,
            mode: .pixelArt,
            cellShape: .square,
            scale: 8,
            extent: CGRect(x: 0, y: 0, width: 8, height: 8)
        )

        #expect(input?.activeGround != nil)
        #expect(input?.usesGroupedComposition == true)
    }
}

@Suite struct MaskCompositorTests {
    private let extent = CGRect(x: 0, y: 0, width: 1, height: 1)

    @Test func groundFactoryPreservesPartialAlpha() {
        let image = MaskFallbackImageFactory.makeGround(
            CGColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.4),
            extent: extent,
            colorSpace: .sRGB
        )
        let pixel = sample(image)
        #expect(abs(pixel[3] - 0.4) < 0.02)
    }

    @Test func sourceOverComposesFiniteBranchesBeforeMasking() {
        let source = CIImage(color: CIColor(red: 0, green: 0, blue: 1, alpha: 0.5)).cropped(to: extent)
        let background = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1)).cropped(to: extent)

        let pixel = sample(MaskCompositor.sourceOver(source, background: background, extent: extent))

        #expect(abs(pixel[0] - 0.5) < 0.03)
        #expect(pixel[1] < 0.03)
        #expect(abs(pixel[2] - 0.5) < 0.03)
        #expect(abs(pixel[3] - 1) < 0.03)
    }

    @Test func blendWithMaskInterpolatesCompletedBranchesOnce() {
        let active = CIImage(color: CIColor(red: 0, green: 0, blue: 1, alpha: 1)).cropped(to: extent)
        let inactive = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        let coverage = CIImage(color: CIColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1)).cropped(to: extent)

        let pixel = sample(
            MaskCompositor.blendWithMask(
                source: active,
                background: inactive,
                mask: coverage,
                extent: extent
            )
        )

        #expect(abs(pixel[0] - 0.75) < 0.03)
        #expect(pixel[1] < 0.03)
        #expect(abs(pixel[2] - 0.25) < 0.03)
        #expect(abs(pixel[3] - 1) < 0.03)
    }

    private func sample(_ image: CIImage) -> [Float] {
        var pixel = [Float](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            image,
            toBitmap: &pixel,
            rowBytes: MemoryLayout<Float>.size * 4,
            bounds: extent,
            format: .RGBAf,
            colorSpace: nil
        )
        return pixel
    }
}
