import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import Aski

/// Color expectations come from independently tagged Core Graphics source colors,
/// not from renderer conversion helpers or output tags alone.
@Suite struct RenderColorSemanticsTests {
    private let color = SIMD3<Float>(0.8, 0.2, 0.1)
    private let clear = CGColor(gray: 0, alpha: 0)
    private let font = ASCIIFont.system(size: 40)

    private func space(_ gamut: RenderColorSpace) -> CGColorSpace {
        CGColorSpace(name: gamut == .sRGB ? CGColorSpace.sRGB : CGColorSpace.displayP3)!
    }

    private func tagged(_ gamut: RenderColorSpace, alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: space(gamut), components: [0.8, 0.2, 0.1, alpha])!
    }

    private func ascii(
        _ gamut: RenderColorSpace, character: Character = "█", alpha: Float = 1,
        coverage: Float = 1, composition: RenderCompositionPolicy = .encodedDisplay8Bit,
        fallback: MaskFallback? = nil, ground: CGColor? = nil
    ) -> ASCIIGrid {
        ASCIIGrid(
            cells: [[ASCIICell(character: character, displayColor: color, alpha: alpha, brightness: 0.5, coverage: coverage)]],
            colorSpace: gamut, composition: composition, maskFallback: fallback, maskGroundColor: ground)
    }

    private func tiles(
        _ gamut: RenderColorSpace, alpha: Float = 1, coverage: Float = 1,
        fallback: MaskFallback? = nil, ground: CGColor? = nil
    ) -> TileGrid {
        TileGrid(
            cells: [[TileCell(displayColor: color, alpha: alpha, brightness: 0.5, coverage: coverage)]],
            colorSpace: gamut, maskFallback: fallback, maskGroundColor: ground)
    }

    /// A fully filled independent swatch, including destination-space compositing.
    private func oracle(_ source: CGColor, destination: CGColorSpace) throws -> [Int] {
        let context = try #require(
            CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: destination, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(source)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let image = try #require(context.makeImage())
        return try interior(image)
    }

    /// Read premultiplied bytes in the image's own space. The most opaque pixel
    /// avoids glyph antialiasing; the fixtures all have a fully covered interior.
    private func interior(_ image: CGImage) throws -> [Int] {
        let colorSpace = try #require(image.colorSpace)
        let context = try #require(
            CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var best = [0, 0, 0, 0]
        for offset in stride(from: 0, to: image.width * image.height * 4, by: 4) {
            let pixel = (0..<4).map { Int(data[offset + $0]) }
            if pixel[3] > best[3] || (pixel[3] == best[3] && pixel[0] > best[0]) { best = pixel }
        }
        return best
    }

    private func check(_ image: CGImage, expected: [Int], tag: CFString, label: String) throws {
        let actual = try interior(image)
        #expect(image.colorSpace?.name == tag, "\(label): output color-space tag")
        #expect(zip(actual, expected).allSatisfy { abs($0 - $1) <= 1 }, "\(label): actual \(actual), expected \(expected)")
    }

    private func cgImage(_ image: CIImage, destination: CGColorSpace) throws -> CGImage {
        let context = CIContext(options: [.workingColorSpace: destination, .outputColorSpace: destination])
        return try #require(context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: destination))
    }

    @Test(arguments: [RenderColorSpace.sRGB, .displayP3], [false, true])
    func explicitCharacterFallbackKeepsCallerColorSpace(gamut: RenderColorSpace, genericRGB: Bool) async throws {
        let opposite: RenderColorSpace = gamut == .sRGB ? .displayP3 : .sRGB
        let paint = genericRGB ? CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1) : tagged(opposite)
        let grid = ascii(gamut, character: " ", coverage: 0, fallback: .character("█", color: paint))
        let expected = try oracle(paint, destination: space(gamut))
        // Keep the direct overload synchronous even from this async test.
        func direct() -> CGImage {
            grid.renderImage(font: font, backgroundColor: clear, scale: 1)
        }
        let asyncImage = try await grid.renderImage(font: font, backgroundColor: clear, scale: 1)
        let engineImage = try await AskiRenderEngine(colorSpace: gamut).render(
            grid, font: font, backgroundColor: clear, scale: 1)
        for (path, image) in [("direct", direct()), ("async", asyncImage), ("engine", engineImage)] {
            try check(
                image, expected: expected, tag: space(gamut).name!,
                label: "\(gamut) explicit character fallback genericRGB=\(genericRGB) \(path)")
        }
    }

    @Test(arguments: [RenderColorSpace.sRGB, .displayP3])
    func directEncodedPathsPreserveComponents(gamut: RenderColorSpace) throws {
        let expected = try oracle(tagged(gamut), destination: space(gamut))
        #expect(expected == [204, 51, 26, 255])
        let ordinary = ascii(gamut).renderImage(font: font, backgroundColor: clear, scale: 1)
        let target = ascii(gamut).renderImage(font: font, backgroundColor: clear, targetPixelWidth: 96)
        let grounded = ascii(gamut, ground: CGColor(gray: 0, alpha: 1))
            .renderImage(font: font, backgroundColor: clear, scale: 1)
        let tile = tiles(gamut).renderImage(scale: 32, backgroundColor: clear)
        for (label, image) in [("ASCII", ordinary), ("targetWidth", target), ("active ground", grounded), ("pixelArt", tile)] {
            try check(image, expected: expected, tag: space(gamut).name!, label: "\(gamut) \(label)")
        }
    }

    @Test(arguments: [RenderColorSpace.sRGB, .displayP3])
    func effectsRastersAndAsyncRenderingPreserveComponents(gamut: RenderColorSpace) async throws {
        let expected = try oracle(tagged(gamut), destination: space(gamut))
        let asciiRaster = CellRasterBuilder.makeASCIIRaster(grid: ascii(gamut), font: font, scale: 1)
        let tileRaster = CellRasterBuilder.makeTileRaster(grid: tiles(gamut), mode: .pixelArt, cellShape: .square, scale: 32)
        let a = try #require(asciiRaster.image.cgImage)
        let t = try #require(tileRaster.image.cgImage)
        let asyncASCII = try await ascii(gamut).renderImage(font: font, backgroundColor: clear, scale: 1)
        let asyncTile = try await tiles(gamut).renderImage(scale: 32, backgroundColor: clear)
        for (label, image) in [("ASCII raster", a), ("tile raster", t), ("async ASCII", asyncASCII), ("async tile", asyncTile)] {
            try check(image, expected: expected, tag: space(gamut).name!, label: "\(gamut) \(label)")
        }
    }

    @Test(arguments: [RenderColorSpace.sRGB, .displayP3])
    func engineConvertsBothGridKindsAndCIOutput(source: RenderColorSpace) async throws {
        let output: RenderColorSpace = source == .sRGB ? .displayP3 : .sRGB
        let destination = space(output)
        let expected = try oracle(tagged(source), destination: destination)
        let engine = AskiRenderEngine(colorSpace: output)
        let a = try await engine.render(ascii(source), font: font, backgroundColor: clear, scale: 1)
        let t = try await engine.render(tiles(source), scale: 32, backgroundColor: clear)
        let aci = try await engine.renderCIImage(ascii(source), font: font, backgroundColor: clear, scale: 1)
        let tci = try await engine.renderCIImage(tiles(source), scale: 32, backgroundColor: clear)
        let inherited = ascii(source, character: " ", coverage: 0, fallback: .character("█", color: nil))
        let inheritedImage = try await engine.render(inherited, font: font, backgroundColor: clear, scale: 1)
        for (label, image) in [
            ("ASCII engine", a), ("tile engine", t),
            ("ASCII engine CI", try cgImage(aci, destination: destination)),
            ("tile engine CI", try cgImage(tci, destination: destination)),
            ("inherited character engine", inheritedImage),
        ] {
            try check(image, expected: expected, tag: destination.name!, label: "\(source)->\(output) \(label)")
        }
    }

    @Test func linearCompositionDecodesEncodedForeground() throws {
        let destination = CGColorSpace(name: CGColorSpace.linearDisplayP3)!
        let grid = ascii(.displayP3, composition: .extendedLinearPerGamut)
        let expected = try oracle(tagged(.displayP3), destination: destination)
        let direct = grid.renderImage(font: font, backgroundColor: clear, scale: 1)
        let raster = CellRasterBuilder.makeASCIIRaster(grid: grid, font: font, scale: 1)
        let rasterImage = try #require(raster.image.cgImage)
        try check(direct, expected: expected, tag: destination.name!, label: "linear direct")
        try check(rasterImage, expected: expected, tag: destination.name!, label: "linear effects raster")
    }

    @Test func coverageBrailleAndDiamondRetainEncodedColorAndAlpha() throws {
        let gamut = RenderColorSpace.displayP3
        let expected = try oracle(tagged(gamut, alpha: 0.2), destination: space(gamut))
        let grid = ascii(gamut, character: "⣿", alpha: 0.5, coverage: 0.4)
        let braille = grid.renderImage(font: font, backgroundColor: clear, scale: 1)
        let raster = CellRasterBuilder.makeASCIIRaster(grid: grid, font: font, scale: 1)
        let rasterImage = try #require(raster.image.cgImage)
        let tile = CellRasterBuilder.makeTileRaster(
            grid: tiles(gamut, alpha: 0.5, coverage: 0.4),
            mode: .pixelArt, cellShape: .diamond, scale: 40)
        let tileImage = try #require(tile.image.cgImage)
        // A flat non-square tile isolates color and coverage from mosaic bevel shading.
        #expect(expected[3] == 51)  // intrinsic alpha 0.5 × coverage 0.4 × 255
        #expect(try interior(tileImage)[3] == 51)
        for (label, image) in [("braille", braille), ("braille raster", rasterImage), ("diamond pixelArt", tileImage)] {
            try check(image, expected: expected, tag: space(gamut).name!, label: label)
        }
    }

    @Test func nilColorCharacterFallbackInheritsGridEncoding() throws {
        let gamut = RenderColorSpace.displayP3
        let grid = ascii(gamut, character: " ", coverage: 0, fallback: .character("█", color: nil))
        let image = grid.renderImage(font: font, backgroundColor: clear, scale: 1)
        let expected = try oracle(tagged(gamut), destination: space(gamut))
        try check(image, expected: expected, tag: space(gamut).name!, label: "nil-color character fallback")
    }

    @Test(arguments: [false, true], [RenderColorSpace.sRGB, .displayP3])
    func enginePreservesFallbackAndActiveGroundColorimetry(ground: Bool, source: RenderColorSpace) async throws {
        let output: RenderColorSpace = source == .sRGB ? .displayP3 : .sRGB
        let literal = CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 0.4)
        let explicit = tagged(source, alpha: 0.4)
        let engine = AskiRenderEngine(colorSpace: output)
        // Ground paints inside the mask; fallback paints outside. Suppress the
        // intrinsic foreground so each fixture isolates only its intended paint.
        func a(_ paint: CGColor) -> ASCIIGrid {
            ascii(
                source, alpha: 0, coverage: ground ? 1 : 0,
                fallback: ground ? .transparent : .solid(paint), ground: ground ? paint : nil)
        }
        func t(_ paint: CGColor) -> TileGrid {
            tiles(
                source, alpha: 0, coverage: ground ? 1 : 0,
                fallback: ground ? .transparent : .solid(paint), ground: ground ? paint : nil)
        }
        let actualASCII = try await engine.render(a(literal), font: font, backgroundColor: clear, scale: 1)
        let explicitASCII = try await engine.render(a(explicit), font: font, backgroundColor: clear, scale: 1)
        let actualTile = try await engine.render(t(literal), scale: 32, backgroundColor: clear)
        let explicitTile = try await engine.render(t(explicit), scale: 32, backgroundColor: clear)
        let expected = try oracle(explicit, destination: space(output))
        for (label, image) in [
            ("literal ASCII", actualASCII), ("tagged ASCII", explicitASCII),
            ("literal tile", actualTile), ("tagged tile", explicitTile),
        ] {
            #expect(try interior(image)[3] > 0, "\(label): fixture paint must be visible")
            try check(image, expected: expected, tag: space(output).name!, label: "\(source) ground=\(ground) \(label)")
        }
    }
}
