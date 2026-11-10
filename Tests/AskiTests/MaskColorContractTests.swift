import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import Aski

/// ASKI-98 contract for solid mask-fallback and visible mask-ground paint: a
/// caller `CGColor` is interpreted in its declared color space and color-matched
/// into the render output, on every raster path. Generic RGB is no exception.
/// Two references are drawn independently by Core Graphics:
///
/// - A, declared space (the contract): the caller color filled into the output
///   space.
/// - B, literal in grid gamut (the retired behavior of the Core Image mask
///   paths): the same numeric components tagged with the grid's sRGB or Display
///   P3 space, then filled into the output space.
///
/// Keeping B lets a regression to literal interpretation fail by name.
@Suite struct MaskColorContractTests {
    private static let components: [CGFloat] = [0.8, 0.2, 0.1]
    private let clear = CGColor(gray: 0, alpha: 0)
    private let font = ASCIIFont.system(size: 40)

    enum Paint: String, CaseIterable, Sendable {
        /// `CGColor(red:green:blue:alpha:)`, Generic RGB on macOS.
        case genericRGB
        /// A calibrated RGB space with no name.
        case unnamedRGB
        case sRGB
        case displayP3
        case deviceRGB

        func color(alpha: CGFloat = 1) -> CGColor {
            let rgba = MaskColorContractTests.components + [alpha]
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

        /// The six paths that return a `CIImage`, whose consumer chooses the working
        /// space. Listed explicitly: "ASCII" contains "CI", so a name match would
        /// include every ASCII path.
        var isCIOutput: Bool {
            [.syncCIASCII, .asyncCIASCII, .engineCrossCIASCII, .syncCITile, .asyncCITile, .engineCrossCITile]
                .contains(self)
        }
    }

    enum Contract: String, Sendable {
        case declaredSpace = "A"
        case literalInGridGamut = "B"
        case indistinguishable = "A=B"
        case neither
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

    /// The working space a consumer's `CIContext` uses to read a `renderCIImage` output.
    enum CIConsumer: String, CaseIterable, Sendable {
        /// The output space itself, an encoded (nonlinear) working space.
        case encoded
        /// Extended linear sRGB, the Core Image default.
        case linear
    }

    private func cgImage(_ image: CIImage, destination: CGColorSpace, consumer: CIConsumer = .encoded) throws -> CGImage {
        let working =
            consumer == .linear ? CGColorSpace(name: CGColorSpace.extendedLinearSRGB)! : destination
        let context = CIContext(options: [.workingColorSpace: working, .outputColorSpace: destination])
        return try #require(context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: destination))
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func render(
        _ path: Path, gamut: RenderColorSpace, paint: CGColor, mask: MaskPaint,
        coverage: Float? = nil, hardEdges: Bool = false, consumer: CIConsumer = .encoded
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
            return try cgImage(syncCI(), destination: gridSpace, consumer: consumer)
        case .asyncCIASCII:
            let image = try await a.renderCIImage(font: font, backgroundColor: clear, scale: 1)
            return try cgImage(image, destination: gridSpace, consumer: consumer)
        case .engineSameASCII:
            return try await AskiRenderEngine(colorSpace: gamut).render(a, font: font, backgroundColor: clear, scale: 1)
        case .engineCrossASCII:
            return try await AskiRenderEngine(colorSpace: Self.opposite(gamut))
                .render(a, font: font, backgroundColor: clear, scale: 1)
        case .engineCrossCIASCII:
            let image = try await AskiRenderEngine(colorSpace: Self.opposite(gamut))
                .renderCIImage(a, font: font, backgroundColor: clear, scale: 1)
            return try cgImage(image, destination: crossSpace, consumer: consumer)
        case .directTilePixelArt:
            return directTile(.pixelArt)
        case .directTileMosaic:
            return directTile(mosaic)
        case .syncEffectsTile:
            return syncEffectsTile()
        case .asyncTile:
            return try await t.renderImage(scale: 32, backgroundColor: clear)
        case .syncCITile:
            return try cgImage(syncCITile(), destination: gridSpace, consumer: consumer)
        case .asyncCITile:
            let image = try await t.renderCIImage(scale: 32, backgroundColor: clear)
            return try cgImage(image, destination: gridSpace, consumer: consumer)
        case .engineSameTile:
            return try await AskiRenderEngine(colorSpace: gamut).render(t, scale: 32, backgroundColor: clear)
        case .engineCrossTile:
            return try await AskiRenderEngine(colorSpace: Self.opposite(gamut)).render(t, scale: 32, backgroundColor: clear)
        case .engineCrossCITile:
            let image = try await AskiRenderEngine(colorSpace: Self.opposite(gamut))
                .renderCIImage(t, scale: 32, backgroundColor: clear)
            return try cgImage(image, destination: crossSpace, consumer: consumer)
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

    // MARK: - Contract

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

    /// Generic RGB and unnamed RGB paint is color-matched from its declared
    /// space on every path, including the Core Image mask factory, engine gamut
    /// adaptation, and the direct tile renderer's ground and mosaic reroutes.
    @Test(
        arguments: Path.allCases,
        [Paint.genericRGB, .unnamedRGB])
    func genericAndUnnamedRGBMaskPaintIsColorMatchedOnEveryPath(path: Path, paint: Paint) async throws {
        for gamut in [RenderColorSpace.sRGB, .displayP3] {
            for mask in MaskPaint.allCases {
                let result = try await measure(path, gamut: gamut, paint: paint, mask: mask)
                #expect(result.a != result.b, "fixture must separate A and B")
                #expect(
                    result.contract == .declaredSpace,
                    "\(path) \(gamut) \(paint) \(mask): actual \(result.actual), A \(result.a), B \(result.b)")
                #expect(result.image.colorSpace?.name == Self.space(Self.outputGamut(path, grid: gamut)).name)
            }
        }
    }

    /// Named caller colors keep their tags on every path. Where the tag equals
    /// the output space, A and B coincide.
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

    /// Partial coverage, paint alpha, and hard or soft edges keep contract A.
    /// The color contract is read from the un-premultiplied color against
    /// opaque references, so it holds apart from the coverage weight, which
    /// `softCoverageIsALinearWeightOnEveryPath` pins.
    @Test(arguments: Path.allCases, [false, true])
    func partialCoverageAndAlphaKeepDeclaredSpace(path: Path, hardEdges: Bool) async throws {
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
                // Un-premultiplying an alpha near 77 amplifies 8-bit rounding to
                // about four steps; A and B differ by at least 13 steps here.
                let contract = Self.classify(Self.unpremultiplied(actual), a: refs.a, b: refs.b, tolerance: 6)
                #expect(
                    contract == .declaredSpace,
                    "\(path) \(gamut) \(mask) hardEdges=\(hardEdges): actual \(actual), A \(refs.a), B \(refs.b)")
            }
        }
    }

    /// ASKI-101 contract: soft mask coverage is a linear weight. A cell with
    /// coverage `c` shows the ground at `c` and the fallback at `1 - c` of the
    /// paint's alpha on every path. CIImage outputs are read by a consumer in an
    /// encoded and in a linear working space, and the weight must not depend on
    /// that choice. The reference is a Core Graphics fill of the paint at the
    /// weighted alpha (CSS Masking 1, "Mask processing": the mask value
    /// multiplies alpha; PNG 3, section 4.3: alpha is a linear fraction of
    /// opacity).
    ///
    /// The retired behavior read the Device Gray coverage image through the sRGB
    /// transfer in Core Image's linear working space, weighting by the sRGB
    /// EOTF of `c` (0.5 became about 0.216): fallback alpha 120 and ground 33
    /// at `c = 0.5` and paint alpha 0.6, against 77 here.
    @Test(arguments: Path.allCases)
    func softCoverageIsALinearWeightOnEveryPath(path: Path) async throws {
        let paintAlpha: CGFloat = 0.6
        for gamut in [RenderColorSpace.sRGB, .displayP3] {
            let destination = Self.space(Self.outputGamut(path, grid: gamut))
            for coverage: Float in [0.25, 0.5, 0.75] {
                for mask in MaskPaint.allCases {
                    let weight = CGFloat(mask == .ground ? coverage : 1 - coverage)
                    let paint = Paint.genericRGB.color(alpha: paintAlpha)
                    let linear = try reference(paint.copy(alpha: paintAlpha * weight)!, destination: destination)[3]
                    let retired = Self.retiredWeight(Double(coverage), mask: mask)
                    let encoded = Int((Double(paintAlpha) * retired * 255).rounded())
                    // The fixture separates the two interpretations by at least 15 steps.
                    #expect(abs(linear - encoded) >= 15, "fixture \(mask) c=\(coverage): \(linear) vs \(encoded)")
                    for consumer in path.isCIOutput ? CIConsumer.allCases : [.encoded] {
                        let image = try await render(
                            path, gamut: gamut, paint: paint, mask: mask, coverage: coverage, consumer: consumer)
                        let alpha = try interior(image)[3]
                        #expect(
                            abs(alpha - linear) <= 1,
                            "\(path) \(gamut) \(mask) c=\(coverage) \(consumer): alpha \(alpha), linear \(linear), retired \(encoded)")
                    }
                }
            }
        }
    }

    /// The weight the retired Core Image path applied: coverage decoded by the
    /// sRGB EOTF before it weighted the ground, the rest going to the fallback.
    private static func retiredWeight(_ coverage: Double, mask: MaskPaint) -> Double {
        let decoded = coverage <= 0.04045 ? coverage / 12.92 : pow((coverage + 0.055) / 1.055, 2.4)
        return mask == .ground ? decoded : 1 - decoded
    }
}
