import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import Aski

@Suite struct EffectChannelAlphaTests {
    private let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
    private let center = CGPoint(x: 32, y: 32)
    private let components: [CGFloat] = [0.6, 0.4, 0.2]

    @Test(arguments: [RenderColorSpace.sRGB, .displayP3], [1.0, 0.5])
    func chromaticAberrationPreservesUniformColor(gamut: RenderColorSpace, alpha: Double) throws {
        let fill = try color(gamut, alpha: alpha)
        let image = grid(gamut).renderImage(
            font: ASCIIFont.system(size: 64), backgroundColor: fill, scale: 1,
            effects: EffectChain([.chromaticAberration(intensity: 1)]))
        let sample = CGPoint(x: image.width / 2, y: image.height / 2)
        try expectClose(pixel(image, at: sample), to: oracle(fill))
    }

    @Test(arguments: [RenderColorSpace.sRGB, .displayP3], [1.0, 0.5])
    func rgbSplitFallbackPreservesUniformColor(gamut: RenderColorSpace, alpha: Double) throws {
        let fill = try color(gamut, alpha: alpha)
        let source = CIImage(color: CIColor(cgColor: fill)).cropped(to: extent)
        let image = try renderFallback(source, intensity: 1, gamut: gamut)
        try expectClose(pixel(image, at: center), to: oracle(fill))
    }

    @Test(arguments: [RenderColorSpace.sRGB, .displayP3])
    func perCharacterAberrationPreservesGlyphInterior(gamut: RenderColorSpace) throws {
        let font = ASCIIFont.system(size: 64)
        let background = CGColor(gray: 0, alpha: 0)
        let glyph = grid(gamut, character: "█", alpha: 0.5)
        let composition = CompositionOptions(
            perCharacter: PerCharacterEffects(chromaticAberration: AberrationOptions(intensity: 1)))
        let baseline = glyph.renderImage(font: font, backgroundColor: background, scale: 1)
        let image = glyph.renderImage(font: font, backgroundColor: background, scale: 1, composition: composition)
        let sample = CGPoint(x: image.width / 2, y: image.height / 2)
        let expected = try pixel(baseline, at: sample)
        #expect(abs(expected[3] - 128) <= 1)
        try expectClose(pixel(image, at: sample), to: expected)
    }

    @Test func zeroIntensityKeepsTheInput() throws {
        let fill = try color(.sRGB, alpha: 0.5)
        let font = ASCIIFont.system(size: 64)
        let input = grid(.sRGB)
        let control = input.renderImage(
            font: font, backgroundColor: fill, scale: 1,
            effects: EffectChain([.blur(radius: 0)]))
        let aberration = input.renderImage(
            font: font, backgroundColor: fill, scale: 1,
            effects: EffectChain([.chromaticAberration(intensity: 0)]))
        let source = CIImage(color: CIColor(cgColor: fill)).cropped(to: extent)
        let rgbSplit = try renderFallback(source, intensity: 0, gamut: .sRGB)
        let sample = CGPoint(x: control.width / 2, y: control.height / 2)
        let baseline = try pixel(control, at: sample)
        #expect(try pixel(aberration, at: sample) == baseline)
        try expectClose(baseline, to: oracle(fill))
        try expectClose(pixel(rgbSplit, at: center), to: oracle(fill))
    }

    @Test(arguments: [1.0, -1.0])
    func shiftedChannelsKeepLocalCoverage(intensity: Double) throws {
        let white = CIImage(color: .white).cropped(to: CGRect(x: 16, y: 0, width: 32, height: 64))
        let clear = CIImage(color: .clear).cropped(to: extent)
        let image = try renderFallback(white.composited(over: clear), intensity: intensity, gamut: .sRGB)
        let yellow = [255, 255, 0, 255]
        let cyan = [0, 255, 255, 255]
        let (left, right) = intensity > 0 ? (yellow, cyan) : (cyan, yellow)
        try expectClose(pixel(image, at: CGPoint(x: 14, y: 32)), to: [0, 0, 0, 0])
        try expectClose(pixel(image, at: CGPoint(x: 16, y: 32)), to: left)
        try expectClose(pixel(image, at: CGPoint(x: 47, y: 32)), to: right)
        try expectClose(pixel(image, at: CGPoint(x: 49, y: 32)), to: [0, 0, 0, 0])
    }

    private func grid(_ gamut: RenderColorSpace, character: Character = " ", alpha: Float = 1) -> ASCIIGrid {
        ASCIIGrid(
            cells: [[ASCIICell(character: character, displayColor: SIMD3(0.6, 0.4, 0.2), alpha: alpha, brightness: 0.5)]],
            colorSpace: gamut)
    }

    private func color(_ gamut: RenderColorSpace, alpha: Double) throws -> CGColor {
        try #require(CGColor(colorSpace: gamut.encodedCGColorSpace, components: components + [CGFloat(alpha)]))
    }

    private func renderFallback(_ input: CIImage, intensity: Double, gamut: RenderColorSpace) throws -> CGImage {
        let workingSpace = WorkingColorSpace.extendedLinearSRGB
        let context = EffectContext(
            workingColorSpace: workingSpace, outputExtent: extent, renderColorSpace: gamut,
            deviceCapability: .reducedQuality(.metallibUnsupported))
        let output = EffectsRenderEngine.runEffectChainSync(
            input, effects: EffectChain([.rgbSplit(intensity: intensity)]), in: context)
        #expect(output.extent == extent)
        let renderer = CIContext(options: [.workingColorSpace: workingSpace])
        return try #require(renderer.createCGImage(output, from: extent, format: .RGBA8, colorSpace: gamut.encodedCGColorSpace))
    }

    private func oracle(_ color: CGColor) throws -> [Int] {
        let context = try bitmap(width: 1, height: 1, colorSpace: #require(color.colorSpace))
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return try read(context, offset: 0)
    }

    private func pixel(_ image: CGImage, at point: CGPoint) throws -> [Int] {
        let context = try bitmap(width: image.width, height: image.height, colorSpace: #require(image.colorSpace))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return try read(context, offset: Int(point.y) * context.bytesPerRow + Int(point.x) * 4)
    }

    private func bitmap(width: Int, height: Int, colorSpace: CGColorSpace) throws -> CGContext {
        try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    }

    private func read(_ context: CGContext, offset: Int) throws -> [Int] {
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<4).map { Int(bytes[offset + $0]) }
    }

    private func expectClose(_ actual: [Int], to expected: [Int]) {
        #expect(zip(actual, expected).allSatisfy { abs($0 - $1) <= 1 }, "actual \(actual), expected \(expected)")
    }
}
