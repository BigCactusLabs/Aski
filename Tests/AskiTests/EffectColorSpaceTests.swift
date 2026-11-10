import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import Aski

/// Caller effect colors are interpreted in their declared color space (ASKI-99).
/// Expectations come from independent Core Graphics fills of the same tagged color.
@Suite struct EffectColorSpaceTests {
    private let font = ASCIIFont.system(size: 40)
    private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    private let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!

    private func space(_ gamut: RenderColorSpace) -> CGColorSpace {
        gamut == .sRGB ? sRGB : displayP3
    }

    private func color(_ space: CGColorSpace, _ rgb: [CGFloat], alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: space, components: rgb + [alpha])!
    }

    /// One fully filled pixel drawn by Core Graphics into `destination`.
    private func oracle(_ source: CGColor, destination: CGColorSpace) throws -> [Int] {
        let context = try #require(
            CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: destination, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(source)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<4).map { Int(data[$0]) }
    }

    /// The center pixel of `image`, read in the image's own color space.
    private func center(_ image: CGImage) throws -> [Int] {
        let colorSpace = try #require(image.colorSpace)
        let context = try #require(
            CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = ((image.height / 2) * image.width + image.width / 2) * 4
        return (0..<4).map { Int(data[offset + $0]) }
    }

    private func render(_ image: CIImage, at point: CGPoint, into destination: CGColorSpace) -> [Int] {
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: nil).render(
            image, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: point.x, y: point.y, width: 1, height: 1),
            format: .RGBA8, colorSpace: destination)
        return pixel.map(Int.init)
    }

    private func expectClose(_ actual: [Int], _ expected: [Int], _ label: String) {
        #expect(
            zip(actual, expected).allSatisfy { abs($0 - $1) <= 1 },
            "\(label): actual \(actual), expected \(expected)")
    }

    private func grid(_ gamut: RenderColorSpace) -> ASCIIGrid {
        ASCIIGrid(
            cells: [[ASCIICell(character: "█", displayColor: SIMD3(0.3, 0.5, 0.7), alpha: 1, brightness: 0.5)]],
            colorSpace: gamut)
    }

    private func overlayRender(_ overlay: CGColor, output: RenderColorSpace) -> CGImage {
        grid(output).renderImage(
            font: font,
            backgroundColor: CGColor(gray: 0, alpha: 1),
            scale: 1,
            composition: CompositionOptions(colorOverlay: ColorOverlay(color: overlay, blendMode: .normal, opacity: 1))
        )
    }

    // MARK: - Color overlay

    @Test(arguments: [RenderColorSpace.sRGB, .displayP3])
    func colorOverlayIsColorMatchedIntoOutputSpace(output: RenderColorSpace) throws {
        let source: RenderColorSpace = output == .sRGB ? .displayP3 : .sRGB
        let overlay = color(space(source), [0.8, 0.2, 0.1])
        let image = overlayRender(overlay, output: output)
        #expect(image.colorSpace?.name == space(output).name)
        expectClose(try center(image), try oracle(overlay, destination: space(output)), "\(source) overlay into \(output)")
    }

    @Test func colorOverlayIgnoresTheColorsOwnAlpha() throws {
        let opaque = overlayRender(color(displayP3, [0.8, 0.2, 0.1]), output: .sRGB)
        let translucent = overlayRender(color(displayP3, [0.8, 0.2, 0.1], alpha: 0.3), output: .sRGB)
        #expect(try center(translucent) == center(opaque))
    }

    /// The pre-ASKI-99 overlay construction, which read every color's numbers as sRGB.
    /// For an sRGB-tagged color the corrected kernel must produce the same bytes.
    @Test(arguments: [CGBlendMode.normal, .multiply, .screen, .overlay, .color, .hue, .plusDarker, .copy], [0.0, 0.4, 1.0, 1.5])
    func sRGBTaggedOverlayMatchesLegacyConstruction(blendMode: CGBlendMode, opacity: Double) throws {
        let extent = CGRect(x: 0, y: 0, width: 4, height: 4)
        let context = EffectContext(
            workingColorSpace: WorkingColorSpace.extendedLinearSRGB, outputExtent: extent,
            renderColorSpace: .sRGB, deviceCapability: .full)
        let input = CIImage(color: CIColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1)).cropped(to: extent)
        let overlay = color(sRGB, [1, 0.7, 0.25])

        let output = try StockCIEffectKernel(kind: .colorOverlay(color: overlay, blendMode: blendMode, opacity: opacity))
            .apply(to: input, in: context)

        let legacyColor = CIColor(red: 1, green: 0.7, blue: 0.25, alpha: CGFloat(max(0, min(1, opacity))))
        let kernel = try #require(BlendModeMapping.kernel(for: blendMode))
        let legacy = try #require(
            kernel.apply(
                foreground: CIImage(color: legacyColor).cropped(to: extent), background: input,
                colorSpace: context.workingColorSpace)
        ).cropped(to: extent)

        for destination in [sRGB, displayP3] {
            #expect(
                render(output, at: CGPoint(x: 1, y: 1), into: destination)
                    == render(legacy, at: CGPoint(x: 1, y: 1), into: destination),
                "\(blendMode.rawValue) opacity \(opacity)")
        }
    }

    // MARK: - Point lights

    private func lightCenter(_ light: CGColor, intensity: Double) -> [Int] {
        // A large extent keeps the radial falloff at the sampled center pixel far below 1/255.
        let extent = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        let context = EffectContext(
            workingColorSpace: WorkingColorSpace.extendedLinearSRGB, outputExtent: extent,
            renderColorSpace: .sRGB, deviceCapability: .full)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: extent)
        let lighting = LightingOptions(
            lights: [PointLight(position: CGPoint(x: 0.5, y: 0.5), radius: 1, intensity: intensity, color: light)],
            ambient: 0)
        let result = LightingApplicator().apply(lighting, to: white, in: context)
        return render(result, at: CGPoint(x: 512, y: 512), into: sRGB)
    }

    /// The light field's absolute scale is the applicator's own model, so the
    /// reference is the same physical color declared in sRGB. Intensity keeps its
    /// existing meaning: an sRGB color and its Display P3 equivalent light the
    /// scene identically at any intensity.
    @Test(arguments: [0.6, 1.0])
    func pointLightIntensityIsIndependentOfSourceSpace(intensity: Double) throws {
        let sRGBLight = color(sRGB, [0.9, 0.5, 0.3])
        let p3Light = try #require(sRGBLight.converted(to: displayP3, intent: .relativeColorimetric, options: nil))
        expectClose(
            lightCenter(p3Light, intensity: intensity), lightCenter(sRGBLight, intensity: intensity),
            "intensity \(intensity)")
    }

    // MARK: - Generic RGB

    /// `CGColor(red:green:blue:alpha:)` is tagged Generic RGB. Effect colors follow
    /// that tag like any other, matching `Background.solid`.
    @Test(arguments: [RenderColorSpace.sRGB, .displayP3])
    func genericRGBOverlayIsColorMatched(output: RenderColorSpace) throws {
        let overlay = CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1)
        #expect((overlay.colorSpace?.name as String?) == "kCGColorSpaceGenericRGB")
        let image = overlayRender(overlay, output: output)
        expectClose(try center(image), try oracle(overlay, destination: space(output)), "Generic RGB overlay into \(output)")
    }

    @Test func genericRGBPointLightMatchesItsSRGBEquivalent() throws {
        let generic = CGColor(red: 0.9, green: 0.5, blue: 0.3, alpha: 1)
        let equivalent = try #require(generic.converted(to: sRGB, intent: .relativeColorimetric, options: nil))
        expectClose(lightCenter(generic, intensity: 0.6), lightCenter(equivalent, intensity: 0.6), "Generic RGB light")
    }
}
