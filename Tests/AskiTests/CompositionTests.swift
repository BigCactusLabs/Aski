import Testing
import AppKit
import CoreGraphics  // CGColor used by Task 4 onward; importing Aski does not re-export it.
import CoreImage
import SnapshotTesting
@testable import Aski

@Suite struct PerCharacterEffectsTests {
    @Test func defaultsAreNoOp() {
        let pce = PerCharacterEffects()
        #expect(pce.bloom == nil)
        #expect(pce.chromaticAberration == nil)
    }

    @Test func bloomOptionsRoundTrip() {
        let bloom = BloomOptions(intensity: 0.5, radius: 12)
        #expect(bloom.intensity == 0.5)
        #expect(bloom.radius == 12)
    }

    @Test func aberrationOptionsRoundTrip() {
        let aberration = AberrationOptions(intensity: 0.3)
        #expect(aberration.intensity == 0.3)
    }
}

@Suite struct RenderCIImageTests {
    @Test func ciImageSyncRendersWithExpectedExtent() {
        let cell = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
        let grid = ASCIIGrid(cells: Array(repeating: Array(repeating: cell, count: 8), count: 8), colorSpace: .sRGB)
        let ci = grid.renderCIImage(
            font: ASCIIFont.system(size: 12),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )
        #expect(ci.extent.width > 0 && ci.extent.height > 0)
    }

    @Test func ciImageAsyncCancellable() async {
        let cell = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
        let grid = ASCIIGrid(cells: Array(repeating: Array(repeating: cell, count: 64), count: 64), colorSpace: .sRGB)
        let task = Task {
            try await grid.renderCIImage(
                font: ASCIIFont.system(size: 12),
                backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                scale: 1,
                composition: CompositionOptions(background: .solid(CGColor(red: 0, green: 0, blue: 0, alpha: 1))),
                effects: EffectChain([.bloom(intensity: 0.5, radius: 8)])
            )
        }
        task.cancel()
        do {
            _ = try await task.value
        } catch is CancellationError {
            return
        } catch {
            Issue.record("expected CancellationError, got \(error)")
        }
    }
}

@Suite struct BackgroundTests {
    @Test func transparentIsDefault() {
        let bg: Background = .transparent
        if case .transparent = bg { /* ok */  } else { Issue.record("expected .transparent") }
    }

    @Test func sizingCases() {
        let sizes: [BackgroundSizing] = [.fill, .fit, .stretch]
        #expect(sizes.count == 3)
    }
}

@Suite struct ColorOverlayTests {
    @Test func defaultOverlayUsesMultiply() {
        let overlay = ColorOverlay(color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        #expect(overlay.blendMode == .multiply)
        #expect(overlay.opacity == 1)
    }

    @Test func overlayOverridesAreHonored() {
        let overlay = ColorOverlay(
            color: CGColor(red: 0, green: 1, blue: 0, alpha: 1),
            blendMode: .screen,
            opacity: 0.5
        )
        #expect(overlay.blendMode == .screen)
        #expect(overlay.opacity == 0.5)
    }
}

@Suite struct CompositionOptionsTests {
    @Test func defaultIsNoOpAndTransparent() {
        let opts = CompositionOptions()
        if case .transparent = opts.background { /* ok */  } else { Issue.record("expected .transparent") }
        #expect(opts.characterBlendMode == .normal)
        #expect(opts.colorOverlay == nil)
        #expect(opts.perCharacter.bloom == nil)
        #expect(opts.perCharacter.chromaticAberration == nil)
    }

    @Test func explicitConstructionRoundTrip() {
        let opts = CompositionOptions(
            background: .solid(CGColor(red: 0, green: 0, blue: 0, alpha: 1)),
            characterBlendMode: .screen,
            colorOverlay: ColorOverlay(color: CGColor(red: 1, green: 0, blue: 0, alpha: 1)),
            perCharacter: PerCharacterEffects(bloom: BloomOptions(intensity: 0.5, radius: 8))
        )
        #expect(opts.characterBlendMode == .screen)
        #expect(opts.colorOverlay != nil)
        #expect(opts.perCharacter.bloom != nil)
    }
}

@Suite struct ASCIIGridEffectsRenderTests {
    private let font = ASCIIFont.system(size: 12)

    private func makeGrid() -> ASCIIGrid {
        let cell = ASCIICell(
            character: "#",
            displayColor: SIMD3<Float>(1, 1, 1),
            alpha: 1,
            brightness: 0.5
        )
        return ASCIIGrid(
            cells: Array(repeating: Array(repeating: cell, count: 8), count: 8),
            colorSpace: .sRGB
        )
    }

    @Test func solidBackgroundRendersToCGImage() {
        let grid = makeGrid()
        let opts = CompositionOptions(background: .solid(CGColor(red: 1, green: 0, blue: 0, alpha: 1)))
        let image = grid.renderImage(
            font: font,
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1,
            composition: opts
        )
        #expect(image.width > 0)
        #expect(image.height > 0)
    }

    @Test func transparentDefaultUsesLegacyBackgroundColor() {
        let grid = makeGrid()
        let background = CGColor(red: 0, green: 0, blue: 0.5, alpha: 1)
        let legacy = grid.renderImage(font: font, backgroundColor: background, scale: 1)
        let new = grid.renderImage(
            font: font,
            backgroundColor: background,
            scale: 1,
            composition: CompositionOptions(),
            effects: EffectChain()
        )
        #expect(legacy.width == new.width)
        #expect(legacy.height == new.height)
    }

    @Test func emptyEffectChainIsNoOpVsSolidBackground() {
        let grid = makeGrid()
        let opts = CompositionOptions(background: .solid(CGColor(red: 0, green: 0, blue: 0, alpha: 1)))
        let image = grid.renderImage(
            font: font,
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1,
            composition: opts,
            effects: EffectChain()
        )
        #expect(image.width > 0)
    }

    @Test func vignetteEffectChainProducesOutput() {
        let grid = makeGrid()
        let image = grid.renderImage(
            font: font,
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1,
            composition: CompositionOptions(background: .solid(CGColor(red: 0, green: 0, blue: 0, alpha: 1))),
            effects: EffectChain([.vignette(intensity: 0.8)])
        )
        #expect(image.width > 0)
    }

    @Test func degenerateScaleReturnsFallbackInsteadOfTrapping() {
        let grid = makeGrid()
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let composition = CompositionOptions(background: .solid(background))
        let nanImage = grid.renderImage(font: font, backgroundColor: background, scale: .nan, composition: composition)
        let infinityImage = grid.renderImage(font: font, backgroundColor: background, scale: .infinity, composition: composition)
        let zeroImage = grid.renderImage(font: font, backgroundColor: background, scale: 0, composition: composition)
        let negativeImage = grid.renderImage(font: font, backgroundColor: background, scale: -1, composition: composition)
        #expect(nanImage.width == 1 && nanImage.height == 1)
        #expect(infinityImage.width == 1 && infinityImage.height == 1)
        #expect(zeroImage.width == 1 && zeroImage.height == 1)
        #expect(negativeImage.width == 1 && negativeImage.height == 1)
    }

    @Test func lightingProducesOutput() {
        let grid = makeGrid()
        let lighting = LightingOptions(
            lights: [
                PointLight(
                    position: CGPoint(x: 0.5, y: 0.5),
                    radius: 0.5,
                    intensity: 1,
                    color: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
                )
            ],
            ambient: 0.5
        )
        let image = grid.renderImage(
            font: font,
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1,
            lighting: lighting
        )
        #expect(image.width > 0)
    }
}

@Suite struct TileGridEffectsRenderTests {
    private func makeGrid() -> TileGrid {
        let cell = TileCell(displayColor: SIMD3<Float>(0, 1, 0), alpha: 1, brightness: 0.5)
        return TileGrid(
            cells: Array(repeating: Array(repeating: cell, count: 8), count: 8),
            colorSpace: .sRGB
        )
    }

    @Test func tileSolidBackgroundRendersToCGImage() {
        let grid = makeGrid()
        let opts = CompositionOptions(background: .solid(CGColor(red: 0, green: 0, blue: 0, alpha: 1)))
        let image = grid.renderImage(
            mode: .pixelArt,
            cellShape: .square,
            scale: 1,
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            composition: opts
        )
        #expect(image.width > 0)
        #expect(image.height > 0)
    }

    @Test func tileVignettePass() {
        let grid = makeGrid()
        let image = grid.renderImage(
            mode: .pixelArt,
            cellShape: .square,
            scale: 1,
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            composition: CompositionOptions(background: .solid(CGColor(red: 0, green: 0, blue: 0, alpha: 1))),
            effects: EffectChain([.vignette(intensity: 0.8)])
        )
        #expect(image.width > 0)
    }

    @Test func tileDegenerateScaleReturnsFallbackInsteadOfTrapping() {
        let grid = makeGrid()
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let composition = CompositionOptions(background: .solid(background))
        let nanImage = grid.renderImage(scale: .nan, backgroundColor: background, composition: composition)
        let infinityImage = grid.renderImage(scale: .infinity, backgroundColor: background, composition: composition)
        let zeroImage = grid.renderImage(scale: 0, backgroundColor: background, composition: composition)
        let negativeImage = grid.renderImage(scale: -1, backgroundColor: background, composition: composition)
        #expect(nanImage.width == 1 && nanImage.height == 1)
        #expect(infinityImage.width == 1 && infinityImage.height == 1)
        #expect(zeroImage.width == 1 && zeroImage.height == 1)
        #expect(negativeImage.width == 1 && negativeImage.height == 1)
    }
}

@Suite struct MetallibThroughOrchestratorTests {
    @Test func scanLinesEffectInChainModifiesPixels() {
        let cell = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
        let grid = ASCIIGrid(
            cells: Array(repeating: Array(repeating: cell, count: 16), count: 16),
            colorSpace: .sRGB
        )
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let baseline = grid.renderImage(
            font: ASCIIFont.system(size: 12),
            backgroundColor: background,
            scale: 1,
            composition: CompositionOptions(background: .solid(background)),
            effects: EffectChain()
        )
        let withEffects = grid.renderImage(
            font: ASCIIFont.system(size: 12),
            backgroundColor: background,
            scale: 1,
            composition: CompositionOptions(background: .solid(background)),
            effects: EffectChain([.scanLines(intensity: 0.8, frequency: 8)])
        )
        #expect(baseline.width == withEffects.width && baseline.height == withEffects.height)
        #expect(hasAnyByteDifference(baseline, withEffects))
    }

    @Test func filmGrainSeedDeterminismThroughOrchestrator() {
        let cell = ASCIICell(character: "@", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
        let grid = ASCIIGrid(
            cells: Array(repeating: Array(repeating: cell, count: 8), count: 8),
            colorSpace: .sRGB
        )
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let render = { (seed: UInt64) -> CGImage in
            grid.renderImage(
                font: ASCIIFont.system(size: 12),
                backgroundColor: background,
                scale: 1,
                composition: CompositionOptions(background: .solid(background)),
                effects: EffectChain([.filmGrain(intensity: 0.5, seed: seed)])
            )
        }
        let first = render(42)
        let second = render(42)
        #expect(first.width == second.width && first.height == second.height)
    }

    private func imageBytes(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    private func hasAnyByteDifference(_ lhs: CGImage, _ rhs: CGImage) -> Bool {
        imageBytes(lhs) != imageBytes(rhs)
    }
}

@MainActor
@Suite(.serialized)
struct CompositionSnapshotTests {
    private nonisolated static let cases = [
        "background-transparent",
        "background-solid-red",
        "background-original-fill",
        "background-blurred-fill",
        "background-sizing-fill",
        "background-sizing-fit",
        "background-sizing-stretch",
        "blend-normal",
        "blend-overlay",
        "blend-screen",
        "blend-multiply",
        "blend-plusLighter",
        "blend-xor",
        "overlay-multiply",
        "overlay-color",
        "overlay-hue",
        "overlay-plusDarker",
        "overlay-copy",
        "perCharacter-bloom-off",
        "perCharacter-bloom-on",
        "perCharacter-aberration-off",
        "perCharacter-aberration-on",
    ]

    private func makeGrid() -> ASCIIGrid {
        var rows: [[ASCIICell]] = []
        for row in 0..<16 {
            var cells: [ASCIICell] = []
            for column in 0..<24 {
                let t = Float(column) / 23
                let y = Float(row) / 15
                cells.append(
                    ASCIICell(
                        character: (row + column).isMultiple(of: 3) ? "@" : "#",
                        displayColor: SIMD3<Float>(1, max(0.25, t), max(0.25, 1 - y)),
                        alpha: 1,
                        brightness: 0.5
                    ))
            }
            rows.append(cells)
        }
        return ASCIIGrid(cells: rows, colorSpace: .sRGB)
    }

    private func sourceImage() -> CGImage {
        TestImages.horizontalGradient(width: 96, height: 40)
    }

    private func composition(named name: String) -> CompositionOptions {
        let image = sourceImage()
        let solidBlack = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let warmOverlay = CGColor(red: 1, green: 0.7, blue: 0.25, alpha: 1)

        switch name {
        case "background-transparent":
            return CompositionOptions(background: .transparent)
        case "background-solid-red":
            return CompositionOptions(background: .solid(CGColor(red: 0.85, green: 0.05, blue: 0.02, alpha: 1)))
        case "background-original-fill", "background-sizing-fill":
            return CompositionOptions(background: .original(image, sizing: .fill))
        case "background-blurred-fill":
            return CompositionOptions(background: .blurred(image, radius: 8, opacity: 0.8, sizing: .fill))
        case "background-sizing-fit":
            return CompositionOptions(background: .original(image, sizing: .fit))
        case "background-sizing-stretch":
            return CompositionOptions(background: .original(image, sizing: .stretch))
        case "blend-normal":
            return blendComposition(.normal, image: image)
        case "blend-overlay":
            return blendComposition(.overlay, image: image)
        case "blend-screen":
            return blendComposition(.screen, image: image)
        case "blend-multiply":
            return blendComposition(.multiply, image: image)
        case "blend-plusLighter":
            return blendComposition(.plusLighter, image: image)
        case "blend-xor":
            return blendComposition(.xor, image: image)
        case "overlay-multiply":
            return overlayComposition(.multiply, color: warmOverlay)
        case "overlay-color":
            return overlayComposition(.color, color: warmOverlay)
        case "overlay-hue":
            return overlayComposition(.hue, color: warmOverlay)
        case "overlay-plusDarker":
            return overlayComposition(.plusDarker, color: warmOverlay)
        case "overlay-copy":
            return overlayComposition(.copy, color: warmOverlay)
        case "perCharacter-bloom-off":
            return CompositionOptions(background: .solid(solidBlack))
        case "perCharacter-bloom-on":
            return CompositionOptions(
                background: .solid(solidBlack),
                perCharacter: PerCharacterEffects(bloom: BloomOptions(intensity: 1.2, radius: 8))
            )
        case "perCharacter-aberration-off":
            return CompositionOptions(background: .solid(solidBlack))
        case "perCharacter-aberration-on":
            return CompositionOptions(
                background: .solid(solidBlack),
                perCharacter: PerCharacterEffects(chromaticAberration: AberrationOptions(intensity: 1.0))
            )
        default:
            return CompositionOptions(background: .solid(solidBlack))
        }
    }

    private func blendComposition(_ mode: CGBlendMode, image: CGImage) -> CompositionOptions {
        CompositionOptions(background: .original(image, sizing: .fill), characterBlendMode: mode)
    }

    private func overlayComposition(_ mode: CGBlendMode, color: CGColor) -> CompositionOptions {
        CompositionOptions(
            background: .solid(CGColor(red: 0, green: 0, blue: 0, alpha: 1)),
            colorOverlay: ColorOverlay(color: color, blendMode: mode, opacity: 0.8)
        )
    }

    private func render(_ options: CompositionOptions) -> CGImage {
        makeGrid().renderImage(
            font: ASCIIFont.courierPrime(size: 12),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1,
            composition: options
        )
    }

    private func snapshot(_ cg: CGImage) -> NSImage {
        NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    @Test(arguments: CompositionSnapshotTests.cases)
    func compositionSnapshot(name: String) {
        assertSnapshot(of: snapshot(render(composition(named: name))), as: .image, named: name)
    }
}

@Suite struct PerCharacterEffectsApplyTests {
    private let font = ASCIIFont.system(size: 18)

    private func makeGrid() -> ASCIIGrid {
        // Mid-gray so bloom has headroom to brighten; pure white would saturate.
        let cell = ASCIICell(
            character: "@",
            displayColor: SIMD3<Float>(0.4, 0.4, 0.4),
            alpha: 1,
            brightness: 0.4
        )
        return ASCIIGrid(
            cells: Array(repeating: Array(repeating: cell, count: 4), count: 4),
            colorSpace: .sRGB
        )
    }

    @Test func perCharacterBloomBrightensGlyphPixelsButNotGutter() {
        let grid = makeGrid()
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

        let withoutBloom = grid.renderImage(
            font: font,
            backgroundColor: bg,
            scale: 1,
            composition: CompositionOptions(background: .solid(bg))
        )
        let withBloom = grid.renderImage(
            font: font,
            backgroundColor: bg,
            scale: 1,
            composition: CompositionOptions(
                background: .solid(bg),
                perCharacter: PerCharacterEffects(bloom: BloomOptions(intensity: 2, radius: 8))
            )
        )
        #expect(withoutBloom.width == withBloom.width)

        let maxDelta = maximumRedIncrease(from: withoutBloom, to: withBloom)
        #expect(maxDelta >= 8, "expected bloom to brighten glyph pixels; max delta was \(maxDelta)")

        let plainCorner = pixelAt(withoutBloom, x: withoutBloom.width - 1, y: withoutBloom.height - 1)
        let bloomedCorner = pixelAt(withBloom, x: withBloom.width - 1, y: withBloom.height - 1)
        #expect(
            abs(Int(bloomedCorner.0) - Int(plainCorner.0)) < 8,
            "gutter should be unchanged; got plain=\(plainCorner.0) bloomed=\(bloomedCorner.0)")

        #expect(hasAnyByteDifference(withoutBloom, withBloom))
    }

    private func pixelAt(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let bytes = imageBytes(image)
        let i = (y * image.width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    private func imageBytes(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    private func maximumRedIncrease(from before: CGImage, to after: CGImage) -> Int {
        let beforeBytes = imageBytes(before)
        let afterBytes = imageBytes(after)
        var maximum = 0
        for index in stride(from: 0, to: min(beforeBytes.count, afterBytes.count), by: 4) {
            maximum = max(maximum, Int(afterBytes[index]) - Int(beforeBytes[index]))
        }
        return maximum
    }

    private func hasAnyByteDifference(_ lhs: CGImage, _ rhs: CGImage) -> Bool {
        imageBytes(lhs) != imageBytes(rhs)
    }
}
