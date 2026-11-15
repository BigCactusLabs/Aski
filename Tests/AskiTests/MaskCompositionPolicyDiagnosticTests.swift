import CoreGraphics
import CoreImage
import Foundation
import Testing
@_spi(AskiResearch) @testable import Aski

/// Opt-in ASKI-103 matrix. See Scripts/research/aski103-2026-11-15/PROTOCOL.md.
@Suite struct MaskCompositionPolicyDiagnosticTests {
    private typealias Harness = MaskColorContractTests
    private let harness = Harness()
    private let gamuts: [RenderColorSpace] = [.sRGB, .displayP3]
    private let policies: [RenderCompositionPolicy] = [.encodedDisplay8Bit, .extendedLinearPerGamut]
    private let clear = CGColor(gray: 0, alpha: 0)

    private enum Fixture: String {
        case fallback, ground, glyph
    }

    private enum Blend: String {
        case encoded, linear

        func predict(_ whiteFraction: Double) -> Double {
            255 * (self == .linear ? Self.encode(whiteFraction) : whiteFraction)
        }

        static func encode(_ value: Double) -> Double {
            value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
        }

        static func decode(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
    }

    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]
        let sourceTag: String

        init(_ image: CGImage, encodedSpace: CGColorSpace) throws {
            width = image.width
            height = image.height
            let sourceSpace = try #require(image.colorSpace)
            sourceTag = try #require(sourceSpace.name) as String
            let context = try #require(
                CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: encodedSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            // Copy at 1:1 into an encoded tagged bitmap. ColorSync handles transfer and
            // gamut conversion on premultiplied data; alpha stays a coverage value.
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let data = try #require(context.data)
            bytes = Array(UnsafeRawBufferPointer(start: data, count: width * height * 4))
        }

        var center: [Int] {
            let offset = (height / 2 * width + width / 2) * 4
            return (0..<4).map { Int(bytes[offset + $0]) }
        }

        var centerPatch: [Int] {
            ((height / 2 - 1)...(height / 2 + 1)).flatMap { y in
                ((width / 2 - 1)...(width / 2 + 1)).map { x in y * width + x }
            }
        }

        func channel(_ channel: Int, at pixel: Int) -> Double {
            Double(bytes[pixel * 4 + channel])
        }

        func matches(_ other: Self) -> Bool { width == other.width && height == other.height }
    }

    private struct Run {
        let path: Harness.Path
        let gamut: RenderColorSpace
        let policy: RenderCompositionPolicy?
        let consumer: Harness.CIConsumer?

        var rasterIsLinear: Bool { policy == .extendedLinearPerGamut }
        var direct: Bool { path == .directASCII || path == .targetWidthASCII || path == .directTilePixelArt }
        var outputGamut: RenderColorSpace { Harness.outputGamut(path, grid: gamut) }

        var columns: [String] {
            [
                path.rawValue, "\(gamut)", "\(outputGamut)", policy.map { "\($0.kind)" } ?? "N/A",
                rasterIsLinear ? "linear" : "encoded", consumer?.rawValue ?? "N/A",
            ]
        }
    }

    private struct Errors {
        var count = 0
        var sum = 0.0
        var max = 0.0

        mutating func add(_ residual: Double) {
            count += 1
            sum += residual
            max = Swift.max(max, residual)
        }

        var mean: Double { count == 0 ? 0 : sum / Double(count) }
    }

    private static let header = [
        "path", "grid_gamut", "output_gamut", "policy", "raster_space", "consumer",
        "fixture", "coverage", "space_model", "source_tag", "width", "height",
        "r", "g", "b", "a", "prediction", "alternative", "samples",
        "rgb_mae", "rgb_max", "alt_mae", "alt_max", "alpha_max", "reference_white_max", "passed",
    ].joined(separator: ",")

    @Test func captureRegisteredMatrix() async throws {
        guard let path = ProcessInfo.processInfo.environment["ASKI_103_CSV"], !path.isEmpty else { return }
        let output = URL(fileURLWithPath: path)
        try #require(!FileManager.default.fileExists(atPath: output.path))
        var rows = [Self.header]
        for gamut in gamuts {
            rows += try controls(gamut)
        }
        for path in Harness.Path.allCases {
            let arms: [RenderCompositionPolicy?] = path.isTile ? [nil] : policies.map(Optional.some)
            let consumers: [Harness.CIConsumer?] = path.isCIOutput ? [.encoded, .linear] : [nil]
            for gamut in gamuts {
                for policy in arms {
                    for consumer in consumers {
                        let run = Run(path: path, gamut: gamut, policy: policy, consumer: consumer)
                        for coverage: Float in [0.25, 0.5, 0.75] {
                            rows.append(try await maskRow(run, fixture: .fallback, coverage: coverage))
                            rows.append(try await maskRow(run, fixture: .ground, coverage: coverage))
                        }
                        rows.append(try await glyphRow(run))
                    }
                }
            }
        }
        try #require(rows.count == 1 + 16 + 504)
        // Keep complete residuals for an inconclusive result as well as a pass.
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: output, options: .withoutOverwriting)
    }

    private func space(_ gamut: RenderColorSpace) -> CGColorSpace {
        CGColorSpace(name: gamut == .sRGB ? CGColorSpace.sRGB : CGColorSpace.displayP3)!
    }

    private func neutral(_ value: CGFloat, alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: space(.sRGB), components: [value, value, value, alpha])!
    }

    private func grids(_ run: Run, fixture: Fixture, coverage: Float) -> (ASCIIGrid, TileGrid) {
        let fallback: MaskFallback? = fixture == .fallback ? .solid(neutral(1)) : nil
        let ground = fixture == .ground ? neutral(1) : nil
        let foreground = SIMD3<Float>(repeating: 1)
        return (
            ASCIIGrid(
                cells: [
                    [
                        ASCIICell(
                            character: "S", displayColor: foreground, alpha: fixture == .glyph ? 1 : 0,
                            brightness: 1, coverage: coverage)
                    ]
                ],
                colorSpace: run.gamut, composition: run.policy ?? .encodedDisplay8Bit,
                maskFallback: fallback, maskGroundColor: ground),
            TileGrid(
                cells: [[TileCell(displayColor: foreground, alpha: 0, brightness: 1, coverage: coverage)]],
                colorSpace: run.gamut, maskFallback: fallback, maskGroundColor: ground)
        )
    }

    private func render(_ run: Run, fixture: Fixture, coverage: Float, background: CGColor) async throws -> Pixels {
        let (ascii, tile) = grids(run, fixture: fixture, coverage: coverage)
        let image = try await harness.render(
            run.path, ascii: ascii, tile: tile, background: background, consumer: run.consumer ?? .encoded)
        try #require(image.width >= 3 && image.height >= 3)
        return try Pixels(image, encodedSpace: space(run.outputGamut))
    }

    private func maskRow(_ run: Run, fixture: Fixture, coverage: Float) async throws -> String {
        let measured = try await render(run, fixture: fixture, coverage: coverage, background: neutral(0))
        let blend: Blend =
            if run.direct && fixture == .fallback {
                run.rasterIsLinear ? .linear : .encoded
            } else {
                run.consumer == .encoded ? .encoded : .linear
            }
        let whiteFraction = Double(fixture == .ground ? coverage : 1 - coverage)
        return patchRow(
            run.columns, fixture: fixture.rawValue, coverage: "\(coverage)", blend: blend,
            measured: measured, whiteFraction: whiteFraction, tolerance: 4)
    }

    private func patchRow(
        _ columns: [String], fixture: String, coverage: String, blend: Blend, measured: Pixels,
        whiteFraction: Double, tolerance: Double
    ) -> String {
        let predicted = blend.predict(whiteFraction)
        let alternative = (blend == .encoded ? Blend.linear : Blend.encoded).predict(whiteFraction)
        var rgb = Errors()
        var other = Errors()
        var alpha = Errors()
        for pixel in measured.centerPatch {
            alpha.add(abs(measured.channel(3, at: pixel) - 255))
            for channel in 0..<3 {
                let actual = measured.channel(channel, at: pixel)
                rgb.add(abs(actual - predicted))
                other.add(abs(actual - alternative))
            }
        }

        let passed = rgb.max <= tolerance && other.mean >= 20 && alpha.max <= 1
        #expect(passed, "\(columns.joined(separator: " ")) \(fixture) \(coverage) expected \(blend)")
        return csv(
            columns, fixture: fixture, coverage: coverage, model: blend.rawValue, measured: measured,
            prediction: "\(predicted)", alternative: "\(alternative)",
            rgb: rgb, other: other, alpha: alpha, referenceWhite: nil, passed: passed)
    }

    private func glyphRow(_ run: Run) async throws -> String {
        if run.path.isTile {
            return (run.columns + [Fixture.glyph.rawValue] + Array(repeating: "N/A", count: 19)).joined(separator: ",")
        }
        let actual = try await render(run, fixture: .glyph, coverage: 1, background: neutral(0))
        let reference = try await render(run, fixture: .glyph, coverage: 1, background: clear)
        try #require(actual.matches(reference))
        let supersample = try targetReference(run, output: reference)
        let blend: Blend = run.direct && !run.rasterIsLinear ? .encoded : .linear
        let model = supersample == nil ? blend.rawValue : "\(blend.rawValue)+linearBox4"
        var rgb = Errors()
        var other = Errors()
        var alpha = Errors()
        var refWhite = Errors()

        for pixel in 0..<(reference.width * reference.height) {
            let a = reference.channel(3, at: pixel)
            let source = supersample.map { sourceAlpha($0, at: pixel) }
            let linearPrediction = source.map { targetPrediction($0, blend: .linear) } ?? Blend.linear.predict(a / 255)
            let encodedPrediction = source.map { targetPrediction($0, blend: .encoded) } ?? a
            if let source {
                alpha.add(abs(a - source.mean * 255))
            }
            alpha.add(abs(actual.channel(3, at: pixel) - 255))

            guard (48...208).contains(a) else { continue }
            let prediction = blend == .linear ? linearPrediction : encodedPrediction
            let alternative = blend == .linear ? encodedPrediction : linearPrediction
            for channel in 0..<3 {
                rgb.add(abs(actual.channel(channel, at: pixel) - prediction))
                other.add(abs(actual.channel(channel, at: pixel) - alternative))
                refWhite.add(abs(reference.channel(channel, at: pixel) - a))
            }
        }

        // Target-width glyphs check consistency only; the synthetic reducer control
        // below supplies the known-difference pair for the two reduction models.
        let separated = supersample != nil || other.mean >= 20
        let passed = rgb.count >= 36 && rgb.mean <= 3 && rgb.max <= 8 && alpha.max <= 1 && refWhite.max <= 2 && separated
        #expect(passed, "\(run.columns.joined(separator: " ")) glyph expected \(model)")
        return csv(
            run.columns, fixture: Fixture.glyph.rawValue, coverage: "1", model: model, measured: actual,
            prediction: "per-pixel", alternative: "per-pixel",
            rgb: rgb, other: other, alpha: alpha, referenceWhite: refWhite, passed: passed)
    }

    private func targetReference(_ run: Run, output: Pixels) throws -> Pixels? {
        guard run.path == .targetWidthASCII else { return nil }
        let (grid, _) = grids(run, fixture: .glyph, coverage: 1)
        let native = grid.renderImage(
            font: harness.font, backgroundColor: clear, targetPixelWidth: Harness.targetWidth * 4,
            preserveSourceAspect: false, resample: .direct)
        let reference = try Pixels(native, encodedSpace: space(run.outputGamut))
        try #require(reference.width == output.width * 4 && reference.height == output.height * 4)
        return reference
    }

    private func sourceAlpha(_ source: Pixels, at outputPixel: Int) -> (mean: Double, meanDecoded: Double) {
        let outputWidth = source.width / 4
        let x = outputPixel % outputWidth * 4
        let y = outputPixel / outputWidth * 4
        var alpha = 0.0
        var decoded = 0.0
        for dy in 0..<4 {
            for dx in 0..<4 {
                let sample = source.channel(3, at: (y + dy) * source.width + x + dx) / 255
                alpha += sample
                decoded += Blend.decode(sample)
            }
        }
        return (alpha / 16, decoded / 16)
    }

    private func targetPrediction(_ source: (mean: Double, meanDecoded: Double), blend: Blend) -> Double {
        Blend.linear.predict(blend == .linear ? source.mean : source.meanDecoded)
    }

    private func reducerControl(_ gamut: RenderColorSpace, tag: CGColorSpace, blend: Blend) throws -> String {
        func raster(alphaReference: Bool) throws -> CGImage {
            let context = try #require(
                CGContext(
                    data: nil, width: 12, height: 12, bitsPerComponent: 8, bytesPerRow: 48, space: tag,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            for y in 0..<12 {
                for x in 0..<12 {
                    // Each 4×4 block has eight zero and eight byte-128 samples.
                    let sample: UInt8 = y % 4 < 2 ? 0 : 128
                    let offset = (y * 12 + x) * 4
                    for channel in 0..<3 { bytes[offset + channel] = sample }
                    bytes[offset + 3] = alphaReference ? sample : 255
                }
            }
            return try #require(context.makeImage())
        }

        let reference = try Pixels(raster(alphaReference: true), encodedSpace: space(gamut))
        let reduced = try #require(
            ASCIIGrid.downsampleTargetWidthImage(
                raster(alphaReference: false), factor: 4, outputWidth: 3, outputHeight: 3,
                colorSpace: tag, sourceIsLinear: blend == .linear))
        let measured = try Pixels(reduced, encodedSpace: space(gamut))
        var rgb = Errors()
        var other = Errors()
        var alpha = Errors()
        for pixel in measured.centerPatch {
            let source = sourceAlpha(reference, at: pixel)
            let prediction = targetPrediction(source, blend: blend)
            let alternative = targetPrediction(source, blend: blend == .linear ? .encoded : .linear)
            alpha.add(abs(measured.channel(3, at: pixel) - 255))
            for channel in 0..<3 {
                rgb.add(abs(measured.channel(channel, at: pixel) - prediction))
                other.add(abs(measured.channel(channel, at: pixel) - alternative))
            }
        }
        let passed = rgb.max <= 2 && other.mean >= 20 && alpha.max <= 1
        #expect(passed, "reducer control \(gamut) \(blend)")
        let source = sourceAlpha(reference, at: 4)
        return csv(
            ["control", "N/A", "\(gamut)", "N/A", blend.rawValue, "N/A"],
            fixture: "box-raster", coverage: "N/A", model: "\(blend.rawValue)+linearBox4", measured: measured,
            prediction: "\(targetPrediction(source, blend: blend))",
            alternative: "\(targetPrediction(source, blend: blend == .linear ? .encoded : .linear))",
            rgb: rgb, other: other, alpha: alpha, referenceWhite: nil, passed: passed)
    }

    private func csv(
        _ columns: [String], fixture: String, coverage: String, model: String, measured: Pixels,
        prediction: String, alternative: String, rgb: Errors, other: Errors, alpha: Errors,
        referenceWhite: Errors?, passed: Bool
    ) -> String {
        let fields =
            columns + [
                fixture, coverage, model, measured.sourceTag, "\(measured.width)", "\(measured.height)",
            ] + measured.center.map(String.init) + [
                prediction, alternative, "\(rgb.count)", "\(rgb.mean)", "\(rgb.max)", "\(other.mean)",
                "\(other.max)", "\(alpha.max)", referenceWhite.map { "\($0.max)" } ?? "N/A", "\(passed)",
            ]
        return fields.joined(separator: ",")
    }

    private func controls(_ gamut: RenderColorSpace) throws -> [String] {
        let destination = space(gamut)
        let linearName = gamut == .sRGB ? CGColorSpace.linearSRGB : CGColorSpace.linearDisplayP3
        let linearSpace = try #require(CGColorSpace(name: linearName))
        let extent = CGRect(x: 0, y: 0, width: 4, height: 4)
        func solid(_ level: CGFloat, alpha: CGFloat = 1) -> CIImage {
            CIImage(color: CIColor(cgColor: neutral(level, alpha: alpha))).cropped(to: extent)
        }

        var rows: [String] = []
        for (tag, model) in [(destination, Blend.encoded), (linearSpace, Blend.linear)] {
            // Equal opaque bytes in different source tags must normalize differently.
            let context = try #require(
                CGContext(
                    data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16, space: tag,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            for index in 0..<64 {
                data[index] = index % 4 == 3 ? 255 : 128
            }
            let source = try #require(context.makeImage())
            let measured = try Pixels(source, encodedSpace: destination)
            rows.append(
                patchRow(
                    ["control", "N/A", "\(gamut)", "N/A", model.rawValue, "N/A"],
                    fixture: "readback", coverage: "N/A", blend: model, measured: measured,
                    whiteFraction: 128.0 / 255, tolerance: 2))
        }

        let weights = try #require(
            CGContext(
                data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        let weightBytes = try #require(weights.data).assumingMemoryBound(to: UInt8.self)
        for y in 0..<4 {
            for x in 0..<4 {
                weightBytes[y * weights.bytesPerRow + x] = 128
            }
        }
        let weightSource = try #require(weights.makeImage())
        let weight = CIImage(cgImage: weightSource, options: [.colorSpace: NSNull()])
        let filter = try #require(CIFilter(name: "CIBlendWithMask"))
        filter.setValue(solid(1), forKey: kCIInputImageKey)
        filter.setValue(solid(0), forKey: kCIInputBackgroundImageKey)
        filter.setValue(weight, forKey: kCIInputMaskImageKey)
        let mask = try #require(filter.outputImage)
        let explicitLinear = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let glyph = try #require(
            CIBlendKernel.sourceOver.apply(
                foreground: solid(1, alpha: 0.5), background: solid(0), colorSpace: explicitLinear))

        for consumer in Harness.CIConsumer.allCases {
            let columns = ["control", "N/A", "\(gamut)", "N/A", "N/A", consumer.rawValue]
            let maskImage = try harness.cgImage(mask, destination: destination, consumer: consumer)
            let glyphImage = try harness.cgImage(glyph, destination: destination, consumer: consumer)
            rows.append(
                try patchRow(
                    columns, fixture: "ci-mask", coverage: "N/A", blend: consumer == .encoded ? .encoded : .linear,
                    measured: Pixels(maskImage, encodedSpace: destination), whiteFraction: 128.0 / 255, tolerance: 2))
            rows.append(
                try patchRow(
                    columns, fixture: "ci-source-over", coverage: "N/A", blend: .linear,
                    measured: Pixels(glyphImage, encodedSpace: destination), whiteFraction: 0.5, tolerance: 2))
        }

        rows.append(try reducerControl(gamut, tag: destination, blend: .encoded))
        rows.append(try reducerControl(gamut, tag: linearSpace, blend: .linear))
        return rows
    }
}
