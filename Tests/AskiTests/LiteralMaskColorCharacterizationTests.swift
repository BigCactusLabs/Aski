import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import Aski

/// ASKI-98 characterization of the current split in solid mask-fallback and
/// visible mask-ground paint. Two candidate contracts are drawn independently
/// by Core Graphics:
///
/// - A, declared space: the caller color is color-matched from its own space
///   into the output space.
/// - B, literal in grid gamut: the color's numeric RGB components are read as
///   encoded components of the grid's sRGB or Display P3 gamut, then converted
///   to the output space.
///
/// These tests record which contract each path satisfies today. They do not
/// choose a contract.
@Suite struct LiteralMaskColorCharacterizationTests {
    private static let components: [CGFloat] = [0.8, 0.2, 0.1]
    private let clear = CGColor(gray: 0, alpha: 0)
    private let font = ASCIIFont.system(size: 40)

    enum Paint: String, CaseIterable, Sendable {
        /// `CGColor(red:green:blue:alpha:)`, Generic RGB on macOS.
        case genericRGB
        /// A calibrated RGB space with no name; the mask factory treats unnamed
        /// RGB like Generic RGB.
        case unnamedRGB
        case sRGB
        case displayP3
        case deviceRGB

        var isLiteralInFactory: Bool { self == .genericRGB || self == .unnamedRGB }

        func color(alpha: CGFloat = 1) -> CGColor {
            let rgba = LiteralMaskColorCharacterizationTests.components + [alpha]
            switch self {
            case .genericRGB:
                return CGColor(red: rgba[0], green: rgba[1], blue: rgba[2], alpha: alpha)
            case .unnamedRGB:
                let space = CGColorSpace(
                    calibratedRGBWhitePoint: [0.9505, 1, 1.089], blackPoint: nil,
                    gamma: [1.8, 1.8, 1.8], matrix: nil)!
                return CGColor(colorSpace: space, components: rgba)!
            case .sRGB:
                return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: rgba)!
            case .displayP3:
                return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!, components: rgba)!
            case .deviceRGB:
                return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: rgba)!
            }
        }
    }

    enum MaskPaint: String, CaseIterable, Sendable {
        /// `.solid` fallback in a fully masked-out cell.
        case fallback
        /// Visible ground in a fully active cell.
        case ground
    }

    enum Path: String, CaseIterable, Sendable {
        case directASCII, targetWidthASCII, syncEffectsASCII, asyncASCII, syncCIASCII, asyncCIASCII
        case engineSameASCII, engineCrossASCII, engineCrossCIASCII
        case directTilePixelArt, directTileMosaic, syncEffectsTile, asyncTile, syncCITile, asyncCITile
        case engineSameTile, engineCrossTile, engineCrossCITile

        var crossesGamut: Bool {
            self == .engineCrossASCII || self == .engineCrossCIASCII || self == .engineCrossTile
                || self == .engineCrossCITile
        }

        var isTile: Bool { rawValue.contains("Tile") }
    }

    enum Contract: String, Sendable {
        case declaredSpace = "A"
        case literalInGridGamut = "B"
        case indistinguishable = "A=B"
        case neither
    }

    /// The contract each path applies today to Generic RGB and unnamed RGB paint,
    /// observed on base `0cc6a90`. Explicitly named colors follow A on every path.
    static func currentLiteralContract(_ path: Path, _ paint: MaskPaint) -> Contract {
        switch (path, paint) {
        case (.directASCII, _), (.targetWidthASCII, _):
            // Core Graphics fills color-match the caller color into the context.
            return .declaredSpace
        case (.directTilePixelArt, .fallback):
            // Core Graphics fill in the direct tile overlay.
            return .declaredSpace
        default:
            // MaskFallbackImageFactory reads literal components; the engine pins
            // them to the source grid gamut. A visible ground and a partially
            // covered mosaic route the direct tile renderer through it too.
            return .literalInGridGamut
        }
    }

    // MARK: - Rendering

    private static func space(_ gamut: RenderColorSpace) -> CGColorSpace {
        CGColorSpace(name: gamut == .sRGB ? CGColorSpace.sRGB : CGColorSpace.displayP3)!
    }

    private static func opposite(_ gamut: RenderColorSpace) -> RenderColorSpace {
        gamut == .sRGB ? .displayP3 : .sRGB
    }

    private static func outputGamut(_ path: Path, grid gamut: RenderColorSpace) -> RenderColorSpace {
        path.crossesGamut ? opposite(gamut) : gamut
    }

    private func asciiGrid(
        _ gamut: RenderColorSpace, paint: CGColor, mask: MaskPaint, coverage: Float? = nil, hardEdges: Bool = false
    ) -> ASCIIGrid {
        // A zero-alpha foreground isolates the mask paint.
        ASCIIGrid(
            cells: [
                [
                    ASCIICell(
                        character: "█", displayColor: SIMD3(0.1, 0.6, 0.9), alpha: 0, brightness: 0.5,
                        coverage: coverage ?? (mask == .ground ? 1 : 0))
                ]
            ],
            colorSpace: gamut,
            maskFallback: mask == .ground ? .transparent : .solid(paint),
            maskGroundColor: mask == .ground ? paint : nil,
            maskUsesHardEdges: hardEdges)
    }

    private func tileGrid(
        _ gamut: RenderColorSpace, paint: CGColor, mask: MaskPaint, coverage: Float? = nil, hardEdges: Bool = false
    ) -> TileGrid {
        TileGrid(
            cells: [
                [
                    TileCell(
                        displayColor: SIMD3(0.1, 0.6, 0.9), alpha: 0, brightness: 0.5,
                        coverage: coverage ?? (mask == .ground ? 1 : 0))
                ]
            ],
            colorSpace: gamut,
            maskFallback: mask == .ground ? .transparent : .solid(paint),
            maskGroundColor: mask == .ground ? paint : nil,
            maskUsesHardEdges: hardEdges)
    }

    private func cgImage(_ image: CIImage, destination: CGColorSpace) throws -> CGImage {
        let context = CIContext(options: [.workingColorSpace: destination, .outputColorSpace: destination])
        return try #require(context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: destination))
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func render(
        _ path: Path, gamut: RenderColorSpace, paint: CGColor, mask: MaskPaint,
        coverage: Float? = nil, hardEdges: Bool = false
    ) async throws -> CGImage {
        let a = asciiGrid(gamut, paint: paint, mask: mask, coverage: coverage, hardEdges: hardEdges)
        let t = tileGrid(gamut, paint: paint, mask: mask, coverage: coverage, hardEdges: hardEdges)
        let gridSpace = Self.space(gamut)
        let crossSpace = Self.space(Self.opposite(gamut))
        let effectsComposition = CompositionOptions(background: .solid(clear))
        let mosaic = TileGridMode.mosaic(grout: clear, groutThickness: 0.2)
        // Nested synchronous helpers keep the synchronous overloads selected.
        func direct() -> CGImage { a.renderImage(font: font, backgroundColor: clear, scale: 1) }
        func syncEffects() -> CGImage {
            a.renderImage(font: font, backgroundColor: clear, scale: 1, composition: effectsComposition)
        }
        func syncCI() -> CIImage { a.renderCIImage(font: font, backgroundColor: clear, scale: 1) }
        func directTile(_ mode: TileGridMode) -> CGImage {
            t.renderImage(mode: mode, scale: 32, backgroundColor: clear)
        }
        func syncEffectsTile() -> CGImage {
            t.renderImage(scale: 32, backgroundColor: clear, composition: effectsComposition)
        }
        func syncCITile() -> CIImage { t.renderCIImage(scale: 32, backgroundColor: clear) }

        switch path {
        case .directASCII:
            return direct()
        case .targetWidthASCII:
            return a.renderImage(font: font, backgroundColor: clear, targetPixelWidth: 96)
        case .syncEffectsASCII:
            return syncEffects()
        case .asyncASCII:
            return try await a.renderImage(font: font, backgroundColor: clear, scale: 1)
        case .syncCIASCII:
            return try cgImage(syncCI(), destination: gridSpace)
        case .asyncCIASCII:
            let image = try await a.renderCIImage(font: font, backgroundColor: clear, scale: 1)
            return try cgImage(image, destination: gridSpace)
        case .engineSameASCII:
            return try await AskiRenderEngine(colorSpace: gamut).render(a, font: font, backgroundColor: clear, scale: 1)
        case .engineCrossASCII:
            return try await AskiRenderEngine(colorSpace: Self.opposite(gamut))
                .render(a, font: font, backgroundColor: clear, scale: 1)
        case .engineCrossCIASCII:
            let image = try await AskiRenderEngine(colorSpace: Self.opposite(gamut))
                .renderCIImage(a, font: font, backgroundColor: clear, scale: 1)
            return try cgImage(image, destination: crossSpace)
        case .directTilePixelArt:
            return directTile(.pixelArt)
        case .directTileMosaic:
            return directTile(mosaic)
        case .syncEffectsTile:
            return syncEffectsTile()
        case .asyncTile:
            return try await t.renderImage(scale: 32, backgroundColor: clear)
        case .syncCITile:
            return try cgImage(syncCITile(), destination: gridSpace)
        case .asyncCITile:
            let image = try await t.renderCIImage(scale: 32, backgroundColor: clear)
            return try cgImage(image, destination: gridSpace)
        case .engineSameTile:
            return try await AskiRenderEngine(colorSpace: gamut).render(t, scale: 32, backgroundColor: clear)
        case .engineCrossTile:
            return try await AskiRenderEngine(colorSpace: Self.opposite(gamut)).render(t, scale: 32, backgroundColor: clear)
        case .engineCrossCITile:
            let image = try await AskiRenderEngine(colorSpace: Self.opposite(gamut))
                .renderCIImage(t, scale: 32, backgroundColor: clear)
            return try cgImage(image, destination: crossSpace)
        }
    }

    // MARK: - Independent references

    /// A one-pixel Core Graphics fill of `source` into `destination`.
    private func reference(_ source: CGColor, destination: CGColorSpace) throws -> [Int] {
        let context = try #require(
            CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: destination, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(source)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<4).map { Int(data[$0]) }
    }

    /// Contract A and B references for `paint` rendered from a `gamut` grid into `output`.
    private func references(
        _ paint: CGColor, grid gamut: RenderColorSpace, output: RenderColorSpace
    ) throws -> (a: [Int], b: [Int]) {
        let destination = Self.space(output)
        let rgb = try #require(paint.components).prefix(3)
        let literal = try #require(CGColor(colorSpace: Self.space(gamut), components: Array(rgb) + [paint.alpha]))
        return (try reference(paint, destination: destination), try reference(literal, destination: destination))
    }

    /// Premultiplied bytes of the most opaque pixel, read in the image's own space.
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

    private static func near(_ lhs: [Int], _ rhs: [Int], tolerance: Int) -> Bool {
        zip(lhs, rhs).allSatisfy { abs($0 - $1) <= tolerance }
    }

    private static func classify(_ actual: [Int], a: [Int], b: [Int], tolerance: Int) -> Contract {
        switch (near(actual, a, tolerance: tolerance), near(actual, b, tolerance: tolerance)) {
        case (true, true): return .indistinguishable
        case (true, false): return .declaredSpace
        case (false, true): return .literalInGridGamut
        case (false, false): return .neither
        }
    }

    private func measure(
        _ path: Path, gamut: RenderColorSpace, paint: Paint, mask: MaskPaint,
        alpha: CGFloat = 1, coverage: Float? = nil, hardEdges: Bool = false, tolerance: Int = 1
    ) async throws -> (contract: Contract, actual: [Int], a: [Int], b: [Int], image: CGImage) {
        let output = Self.outputGamut(path, grid: gamut)
        let color = paint.color(alpha: alpha)
        let image = try await render(
            path, gamut: gamut, paint: color, mask: mask, coverage: coverage, hardEdges: hardEdges)
        // Partial coverage scales the paint's alpha; build references with the
        // expected composite alpha so both contracts include the same blend.
        let effectiveCoverage = CGFloat(coverage ?? (mask == .ground ? 1 : 0))
        let weight = mask == .ground ? effectiveCoverage : 1 - effectiveCoverage
        let refs = try references(color.copy(alpha: alpha * weight)!, grid: gamut, output: output)
        let actual = try interior(image)
        Self.record(path, gamut, paint, mask, alpha, coverage, actual, refs)
        return (Self.classify(actual, a: refs.a, b: refs.b, tolerance: tolerance), actual, refs.a, refs.b, image)
    }

    /// Set `ASKI98_PRINT=1` to print every measurement as a table row.
    private static func record(
        _ path: Path, _ gamut: RenderColorSpace, _ paint: Paint, _ mask: MaskPaint, _ alpha: CGFloat,
        _ coverage: Float?, _ actual: [Int], _ refs: (a: [Int], b: [Int])
    ) {
        guard ProcessInfo.processInfo.environment["ASKI98_PRINT"] == "1" else { return }
        let contract = classify(actual, a: refs.a, b: refs.b, tolerance: 1).rawValue
        print(
            "ASKI98|\(path.rawValue)|\(gamut)|\(paint.rawValue)|\(mask.rawValue)|alpha=\(alpha)|"
                + "coverage=\(coverage.map { "\($0)" } ?? "full")|actual=\(actual)|A=\(refs.a)|B=\(refs.b)|\(contract)")
    }

    // MARK: - Characterization

    /// The fixture discriminates the contracts: Generic RGB (0.8, 0.2, 0.1) does
    /// not land on its literal components in either gamut.
    @Test(arguments: [RenderColorSpace.sRGB, .displayP3])
    func genericRGBFixtureSeparatesTheContracts(gamut: RenderColorSpace) throws {
        for output in [gamut, Self.opposite(gamut)] {
            let refs = try references(Paint.genericRGB.color(), grid: gamut, output: output)
            #expect(!Self.near(refs.a, refs.b, tolerance: 4), "\(gamut)->\(output): A \(refs.a), B \(refs.b)")
        }
        // Independent anchors for the opaque references.
        #expect(try references(Paint.genericRGB.color(), grid: .sRGB, output: .sRGB).a == [216, 73, 32, 255])
        #expect(try references(Paint.genericRGB.color(), grid: .displayP3, output: .displayP3).a == [200, 83, 48, 255])
        #expect(try references(Paint.genericRGB.color(), grid: gamut, output: gamut).b == [204, 51, 26, 255])
    }

    /// Current split: direct ASCII, target-width ASCII and the direct tile
    /// fallback overlay follow A; every Core Image mask path, the engine, and the
    /// direct tile renderer's ground and mosaic reroutes follow B.
    @Test(
        arguments: Path.allCases,
        [Paint.genericRGB, .unnamedRGB])
    func literalMaskPaintFollowsCurrentPathSplit(path: Path, paint: Paint) async throws {
        for gamut in [RenderColorSpace.sRGB, .displayP3] {
            for mask in MaskPaint.allCases {
                let result = try await measure(path, gamut: gamut, paint: paint, mask: mask)
                #expect(result.a != result.b, "fixture must separate A and B")
                let expected = Self.currentLiteralContract(path, mask)
                #expect(
                    result.contract == expected,
                    "\(path) \(gamut) \(paint) \(mask): actual \(result.actual), A \(result.a), B \(result.b)")
                #expect(result.image.colorSpace?.name == Self.space(Self.outputGamut(path, grid: gamut)).name)
            }
        }
    }

    /// Named caller colors keep their tags on every path today.
    @Test(arguments: Path.allCases, [Paint.sRGB, .displayP3, .deviceRGB])
    func namedMaskPaintIsColorMatchedOnEveryPath(path: Path, paint: Paint) async throws {
        for gamut in [RenderColorSpace.sRGB, .displayP3] {
            for mask in MaskPaint.allCases {
                let result = try await measure(path, gamut: gamut, paint: paint, mask: mask)
                #expect(
                    result.contract == .declaredSpace || result.contract == .indistinguishable,
                    "\(path) \(gamut) \(paint) \(mask): actual \(result.actual), A \(result.a), B \(result.b)")
            }
        }
    }

    private static func unpremultiplied(_ pixel: [Int]) -> [Int] {
        guard pixel[3] > 0 else { return [0, 0, 0, 0] }
        return pixel.prefix(3).map { Int((Double($0) * 255 / Double(pixel[3])).rounded()) } + [255]
    }

    /// Partial coverage and paint alpha keep the same color split. Coverage
    /// changes the composite alpha differently by path (see
    /// `softCoverageWeightCurrentlyDependsOnPath`), so the contract is read
    /// from the un-premultiplied color against opaque references. Soft and
    /// hard edges agree for a single cell, whose coverage is uniform.
    @Test(arguments: Path.allCases, [false, true])
    func partialCoverageAndAlphaKeepTheSplit(path: Path, hardEdges: Bool) async throws {
        for gamut in [RenderColorSpace.sRGB, .displayP3] {
            for mask in MaskPaint.allCases {
                let output = Self.outputGamut(path, grid: gamut)
                let paint = Paint.genericRGB.color(alpha: 0.6)
                let image = try await render(
                    path, gamut: gamut, paint: paint, mask: mask, coverage: 0.5, hardEdges: hardEdges)
                let actual = try interior(image)
                #expect(actual[3] >= 30, "fixture paint must be visible: \(actual)")
                let refs = try references(Paint.genericRGB.color(), grid: gamut, output: output)
                Self.record(path, gamut, .genericRGB, mask, 0.6, 0.5, actual, refs)
                // Un-premultiplying an alpha near 33 amplifies 8-bit rounding to
                // about four steps; A and B differ by at least 13 steps here.
                let contract = Self.classify(Self.unpremultiplied(actual), a: refs.a, b: refs.b, tolerance: 6)
                #expect(
                    contract == Self.currentLiteralContract(path, mask),
                    "\(path) \(gamut) \(mask) hardEdges=\(hardEdges): actual \(actual), A \(refs.a), B \(refs.b)")
            }
        }
    }

    /// Not a color-contract question, recorded because ASKI-98 measured it:
    /// at coverage 0.5 and paint alpha 0.6, the Core Graphics fallback overlay
    /// weights the paint by `1 - coverage` (alpha 0.3, byte 77). The Core Image
    /// mask compositor reads the Device Gray coverage image through the sRGB
    /// transfer in its linear working space, so 0.5 becomes about 0.214: the
    /// fallback gets 0.6 x 0.786 (byte 120) and the ground 0.6 x 0.214 (byte 33).
    /// CIImage outputs are excluded because their weight depends on the
    /// consumer's working space.
    @Test(arguments: [RenderColorSpace.sRGB, .displayP3])
    func softCoverageWeightCurrentlyDependsOnPath(gamut: RenderColorSpace) async throws {
        let cgOverlay: Set<Path> = [.directASCII, .targetWidthASCII, .directTilePixelArt]
        let ciOutputs: Set<Path> = [.syncCIASCII, .asyncCIASCII, .engineCrossCIASCII, .syncCITile, .asyncCITile, .engineCrossCITile]
        for path in Path.allCases where !ciOutputs.contains(path) {
            for mask in MaskPaint.allCases {
                let image = try await render(
                    path, gamut: gamut, paint: Paint.genericRGB.color(alpha: 0.6), mask: mask, coverage: 0.5)
                let alpha = try interior(image)[3]
                let expected = mask == .fallback ? (cgOverlay.contains(path) ? 77 : 120) : 33
                #expect(abs(alpha - expected) <= 1, "\(path) \(gamut) \(mask): alpha \(alpha), expected \(expected)")
            }
        }
    }
}
