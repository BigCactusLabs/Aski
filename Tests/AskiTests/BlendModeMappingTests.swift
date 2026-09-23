import Testing
import CoreGraphics
import CoreImage
@testable import Aski

@Suite struct BlendModeMappingTests {
    @Test func allWidelyUsedW3CModesMapToNonNilKernel() {
        let modes: [CGBlendMode] = [
            .normal, .multiply, .screen, .overlay, .darken, .lighten,
            .colorDodge, .colorBurn, .softLight, .hardLight,
            .difference, .exclusion, .hue, .saturation, .color, .luminosity,
        ]
        for mode in modes {
            let kernel = BlendModeMapping.kernel(for: mode)
            #expect(kernel != nil, "blend mode \(mode.rawValue) returned nil")
        }
    }

    @Test func porterDuffModesMapToNonNilKernel() {
        let modes: [CGBlendMode] = [
            .copy, .clear, .sourceIn, .sourceOut, .sourceAtop,
            .destinationOver, .destinationIn, .destinationOut, .destinationAtop, .xor,
        ]
        for mode in modes {
            let kernel = BlendModeMapping.kernel(for: mode)
            #expect(kernel != nil, "porter-duff mode \(mode.rawValue) returned nil")
        }
    }

    @Test func additiveModesMapToNonNilKernel() {
        for mode in [CGBlendMode.plusLighter, .plusDarker] {
            let kernel = BlendModeMapping.kernel(for: mode)
            #expect(kernel != nil, "additive mode \(mode.rawValue) returned nil")
        }
    }

    @Test func unknownDefaultFallsBackToSourceOver() {
        let unknown = CGBlendMode(rawValue: 999) ?? .normal
        let kernel = BlendModeMapping.kernel(for: unknown)
        #expect(kernel != nil)
    }

    @Test func appliedKernelProducesNonEmptyImage() {
        let extent = CGRect(x: 0, y: 0, width: 4, height: 4)
        let fg = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        let bg = CIImage(color: CIColor(red: 0, green: 0, blue: 1, alpha: 1)).cropped(to: extent)
        let kernel = BlendModeMapping.kernel(for: .multiply)!
        let out = kernel.apply(foreground: fg, background: bg, colorSpace: WorkingColorSpace.extendedLinearSRGB)
        #expect(out != nil)
        #expect(!(out?.extent.isEmpty ?? true))
    }
}

@Suite struct UnknownBlendModeBehaviorTests {
    @Test func unknownCharacterBlendModeFallsBackToSourceOverInBothOverloads() async throws {
        guard let unknown = CGBlendMode(rawValue: 9_999) else { return }

        let sourceOver = Self.characterComposition(blendMode: .normal)
        let syncFallback = Self.renderSync(composition: Self.characterComposition(blendMode: unknown))
        let asyncFallback = try await Self.renderAsync(composition: Self.characterComposition(blendMode: unknown))
        let expected = Self.renderSync(composition: sourceOver)

        #expect(Self.imagesAreByteIdentical(syncFallback, expected))
        #expect(Self.imagesAreByteIdentical(asyncFallback, expected))
        #expect(Self.imagesAreByteIdentical(syncFallback, asyncFallback))
    }

    @Test func unknownColorOverlayBlendModeFallsBackToSourceOverInBothOverloads() async throws {
        guard let unknown = CGBlendMode(rawValue: 9_999) else { return }

        let sourceOver = Self.colorOverlayComposition(blendMode: .normal)
        let syncFallback = Self.renderSync(composition: Self.colorOverlayComposition(blendMode: unknown))
        let asyncFallback = try await Self.renderAsync(composition: Self.colorOverlayComposition(blendMode: unknown))
        let expected = Self.renderSync(composition: sourceOver)

        #expect(Self.imagesAreByteIdentical(syncFallback, expected))
        #expect(Self.imagesAreByteIdentical(asyncFallback, expected))
        #expect(Self.imagesAreByteIdentical(syncFallback, asyncFallback))
    }

    @Test func allKnownBlendModesRenderByteIdenticallyAcrossBothOverloads() async throws {
        for mode in Self.knownBlendModes {
            let characterSync = Self.renderSync(composition: Self.characterComposition(blendMode: mode))
            let characterAsync = try await Self.renderAsync(composition: Self.characterComposition(blendMode: mode))
            #expect(
                Self.imagesAreByteIdentical(characterSync, characterAsync),
                "character blend mode \(mode.rawValue)"
            )

            let overlaySync = Self.renderSync(composition: Self.colorOverlayComposition(blendMode: mode))
            let overlayAsync = try await Self.renderAsync(composition: Self.colorOverlayComposition(blendMode: mode))
            #expect(
                Self.imagesAreByteIdentical(overlaySync, overlayAsync),
                "color overlay blend mode \(mode.rawValue)"
            )
        }
    }

    private static let knownBlendModes: [CGBlendMode] = [
        .normal, .multiply, .screen, .overlay, .darken, .lighten,
        .colorDodge, .colorBurn, .softLight, .hardLight,
        .difference, .exclusion, .hue, .saturation, .color, .luminosity,
        .copy, .clear, .sourceIn, .sourceOut, .sourceAtop,
        .destinationOver, .destinationIn, .destinationOut, .destinationAtop, .xor,
        .plusLighter, .plusDarker,
    ]

    private static func renderSync(composition: CompositionOptions) -> CGImage {
        let background = CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        return makeGrid().renderImage(
            font: .system(size: 12),
            backgroundColor: background,
            scale: 1,
            composition: composition
        )
    }

    private static func renderAsync(composition: CompositionOptions) async throws -> CGImage {
        let background = CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        return try await makeGrid().renderImage(
            font: .system(size: 12),
            backgroundColor: background,
            scale: 1,
            composition: composition
        )
    }

    private static func characterComposition(blendMode: CGBlendMode) -> CompositionOptions {
        CompositionOptions(
            background: .solid(CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)),
            characterBlendMode: blendMode
        )
    }

    private static func colorOverlayComposition(blendMode: CGBlendMode) -> CompositionOptions {
        CompositionOptions(
            background: .solid(CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)),
            colorOverlay: ColorOverlay(
                color: CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1),
                blendMode: blendMode,
                opacity: 0.75
            )
        )
    }

    private static func makeGrid() -> ASCIIGrid {
        let cell = ASCIICell(
            character: "#",
            displayColor: SIMD3<Float>(0.9, 0.8, 0.7),
            alpha: 1,
            brightness: 0.5
        )
        return ASCIIGrid(cells: [[cell]], colorSpace: .sRGB)
    }

    private static func imagesAreByteIdentical(_ lhs: CGImage, _ rhs: CGImage) -> Bool {
        TestImages.deviceRGBBytes(lhs) == TestImages.deviceRGBBytes(rhs)
    }
}
