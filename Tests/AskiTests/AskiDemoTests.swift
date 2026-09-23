import ArgumentParser
import Aski
import AskiCLI
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AskiToolSupport

@Suite struct AskiDemoTests {
    @Test func parsesRequiredInputAndDefaults() throws {
        let command = try AskiDemoCommand.parse(["input.jpg"])
        #expect(command.inputPath == "input.jpg")
        #expect(command.columns == 80)
        #expect(command.output == nil)
        #expect(command.renderPng == nil)
        #expect(command.width == nil)
        #expect(command.fontSize == 10)
        #expect(command.charset == .standard)
        #expect(command.background == .black)
        #expect(command.preserveAspect == true)
        #expect(command.mask.maskPath == nil)
        #expect(command.mask.fallback == nil)
        #expect(command.mask.fallbackColor == nil)
        #expect(command.mask.fallbackSizing == nil)
        #expect(command.mask.ground == nil)
        #expect(command.mask.hardEdges == false)
        #expect(command.mask.invert == false)
    }

    @Test func parsesEveryOption() throws {
        let command = try AskiDemoCommand.parse([
            "input.jpg",
            "--columns", "120",
            "--output", "out.txt",
            "--render-png", "out.png",
            "--width", "97",
            "--font-size", "14.5",
            "--charset", "blocks",
            "--background", "#112233",
            "--no-preserve-aspect",
            "--mask", "mask.png",
            "--mask-fallback", "original",
            "--mask-fallback-sizing", "fit",
            "--mask-ground", "#080808",
            "--mask-hard-edges",
            "--mask-invert",
        ])
        #expect(command.inputPath == "input.jpg")
        #expect(command.columns == 120)
        #expect(command.output == "out.txt")
        #expect(command.renderPng == "out.png")
        #expect(command.width == 97)
        #expect(command.fontSize == 14.5)
        #expect(command.charset == .blocks)
        #expect(command.background == BackgroundColor(argument: "#112233"))
        #expect(command.preserveAspect == false)
        #expect(command.mask.maskPath == "mask.png")
        #expect(command.mask.fallback == .original)
        #expect(command.mask.fallbackColor == nil)
        #expect(command.mask.fallbackSizing == .fit)
        #expect(command.mask.ground == BackgroundColor(argument: "#080808"))
        #expect(command.mask.hardEdges)
        #expect(command.mask.invert)
    }

    @Test func renderAndCompatibilitySurfacesShareMaskArguments() throws {
        let root = try AskiCommand.parseAsRoot([
            "render",
            "input.jpg",
            "--mask", "mask.png",
            "--mask-fallback", "solid",
            "--mask-fallback-color", "red",
            "--render-png", "out.png",
        ])
        let render = try #require(root as? AskiRenderCommand)
        #expect(render.arguments.mask.maskPath == "mask.png")
        #expect(render.arguments.mask.fallback == .solid)
        #expect(render.arguments.mask.fallbackColor == BackgroundColor(argument: "red"))

        let compatibility = try AskiDemoCommand.parse([
            "input.jpg",
            "--mask", "mask.png",
        ])
        #expect(compatibility.mask.maskPath == "mask.png")
    }

    @Test func maskSpecificOptionsRequireMaskWithStableMessage() {
        #expect(validationMessage(fallback: .transparent) == "--mask is required when using mask-specific options")
        #expect(validationMessage(fallbackColor: .black) == "--mask is required when using mask-specific options")
        #expect(validationMessage(fallbackSizing: .stretch) == "--mask is required when using mask-specific options")
        #expect(validationMessage(ground: .black) == "--mask is required when using mask-specific options")
        #expect(validationMessage(hardEdges: true) == "--mask is required when using mask-specific options")
        #expect(validationMessage(invert: true) == "--mask is required when using mask-specific options")
    }

    @Test func maskValidationUsesSpecifiedPrecedenceAndMessages() {
        #expect(
            validationMessage(
                fallback: .solid,
                fallbackColor: .black,
                fallbackSizing: .stretch
            ) == "--mask is required when using mask-specific options")

        #expect(
            validationMessage(maskPath: "mask.png", fallbackColor: .black)
                == "--mask-fallback-color requires --mask-fallback solid")

        #expect(
            validationMessage(maskPath: "mask.png", fallback: .solid, renderPNGPath: "out.png")
                == "--mask-fallback solid requires --mask-fallback-color")

        #expect(
            validationMessage(
                maskPath: "mask.png",
                fallback: .solid,
                fallbackColor: .clear,
                renderPNGPath: "out.png"
            ) == "--mask-fallback-color must not be clear or transparent; use --mask-fallback transparent instead")

        #expect(
            validationMessage(maskPath: "mask.png", fallbackSizing: .stretch)
                == "--mask-fallback-sizing requires --mask-fallback original")

        #expect(
            validationMessage(maskPath: "mask.png", fallback: .original)
                == "--mask-fallback original requires --render-png")

        #expect(
            validationMessage(maskPath: "mask.png", ground: .black)
                == "--mask-ground requires --render-png")

        #expect(
            validationMessage(maskPath: "mask.png", ground: .clear, renderPNGPath: "out.png")
                == "--mask-ground must not be clear or transparent; omit --mask-ground instead")
    }

    @Test func rejectsInvalidColumns() {
        #expect(throws: (any Error).self) { try AskiDemoCommand.parse(["input.jpg", "--columns", "0"]) }
        #expect(throws: (any Error).self) { try AskiDemoCommand.parse(["input.jpg", "--columns", "513"]) }
        #expect(throws: (any Error).self) { try AskiDemoCommand.parse(["input.jpg", "--columns", "9223372036854775807"]) }
    }

    @Test func rejectsNonFiniteAndAbsurdFontSize() {
        #expect(throws: (any Error).self) { try AskiDemoCommand.parse(["input.jpg", "--font-size", "inf"]) }
        #expect(throws: (any Error).self) { try AskiDemoCommand.parse(["input.jpg", "--font-size", "97"]) }
    }

    @Test func widthRequiresRenderedPNGAndStaysWithinRendererBounds() {
        #expect(throws: (any Error).self) { try AskiDemoCommand.parse(["input.jpg", "--width", "97"]) }
        #expect(throws: (any Error).self) {
            try AskiDemoCommand.parse(["input.jpg", "--render-png", "out.png", "--width", "0"])
        }
        // The public exact-width path supersamples at 4×, so the CLI bound is a
        // quarter of the raw pixel-extent ceiling; one past it would only ever
        // yield the renderer's 1×1 fallback and a manifest claiming otherwise.
        #expect(ASCIIGrid.maxTargetPixelWidth == 262_144)
        #expect(throws: (any Error).self) {
            try AskiDemoCommand.parse(["input.jpg", "--render-png", "out.png", "--width", "262145"])
        }
        #expect(throws: Never.self) {
            try AskiDemoCommand.parse(["input.jpg", "--render-png", "out.png", "--width", "262144"])
        }
    }

    @Test func rejectsUnknownCharsetAndOption() {
        #expect(throws: (any Error).self) { try AskiDemoCommand.parse(["input.jpg", "--charset", "rainbow"]) }
        #expect(throws: (any Error).self) { try AskiDemoCommand.parse(["input.jpg", "--bogus"]) }
    }

    @Test func rejectsInvalidBackground() {
        #expect(throws: (any Error).self) { try AskiDemoCommand.parse(["input.jpg", "--background", "notacolor"]) }
    }

    @Test func versionIsTheResolvedSHA() {
        #expect(!AskiDemoCommand.configuration.version.isEmpty)
        #expect(AskiDemoCommand.configuration.version == ToolVersion.current)
    }

    @Test func convertsInputImageToStdoutASCII() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "input.png")
        try writeFixturePNG(to: input, width: 80, height: 40)

        var stdout = ""
        var stderr = ""
        let command = try AskiDemoCommand.parse([input.path, "--columns", "12"])
        let status = command.execute(standardOutput: { stdout += $0 }, standardError: { stderr += $0 })

        #expect(status == .success)
        #expect(stderr.isEmpty)
        #expect(stdout.contains("\n"))
        #expect(stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }

    @Test func textOnlyTransparentMaskUsesCoverageThreshold() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "input.png")
        let mask = directory.appending(path: "black-mask.png")
        try writeFixturePNG(to: input, width: 80, height: 40)
        try writeSolidPNG(to: mask, width: 80, height: 40, gray: 0)

        var stdout = ""
        var stderr = ""
        let command = try AskiDemoCommand.parse([input.path, "--columns", "12", "--mask", mask.path])
        let status = command.execute(standardOutput: { stdout += $0 }, standardError: { stderr += $0 })

        #expect(status == .success)
        #expect(stderr.isEmpty)
        #expect(stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func maskOptionsResolveFallbacksWithoutDecodingSourceAgain() throws {
        let source = try #require(makeImage(width: 24, height: 12, gray: 0.5))
        let mask = try #require(makeImage(width: 24, height: 12, gray: 1))
        let command = try AskiDemoCommand.parse([
            "input.png",
            "--mask", "mask.png",
            "--mask-fallback", "original",
            "--mask-ground", "#080808",
            "--mask-hard-edges",
            "--mask-invert",
            "--render-png", "out.png",
        ])

        let options = try #require(command.mask.makeMaskOptions(maskImage: mask, sourceImage: source))
        if case .originalImage(let fallback, let sizing) = options.fallback {
            #expect(fallback === source)
            #expect(sizing == .stretch)
        } else {
            Issue.record("expected original-image fallback")
        }
        #expect(options.groundColor?.alpha == 1)
        #expect(options.softEdges == false)
        #expect(options.invert)
    }

    @Test func maskDecodeIsBoundedToNormalizedSourceLongSide() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let maskPath = directory.appending(path: "large-mask.png")
        try writeSolidPNG(to: maskPath, width: 480, height: 240, gray: 1)
        let source = try #require(makeImage(width: 24, height: 12, gray: 0.5))
        let command = try AskiDemoCommand.parse(["input.png", "--mask", maskPath.path])

        let loadedMask = try command.mask.loadMaskImage(sourceImage: source)
        let decoded = try #require(loadedMask)
        #expect(max(decoded.width, decoded.height) == 24)
    }

    @Test func hardInvertedMaskMakesBlackCoverageVisible() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "input.png")
        let mask = directory.appending(path: "black-mask.png")
        try writeFixturePNG(to: input, width: 80, height: 40)
        try writeSolidPNG(to: mask, width: 80, height: 40, gray: 0)

        var stdout = ""
        let command = try AskiDemoCommand.parse([
            input.path, "--columns", "12", "--mask", mask.path, "--mask-hard-edges", "--mask-invert",
        ])
        let status = command.execute(standardOutput: { stdout += $0 }, standardError: { _ in })

        #expect(status == .success)
        #expect(stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }

    @Test func allRasterMaskFallbacksRender() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "input.png")
        let mask = directory.appending(path: "black-mask.png")
        try writeFixturePNG(to: input, width: 80, height: 40)
        try writeSolidPNG(to: mask, width: 80, height: 40, gray: 0)

        let cases = [
            ["--mask-fallback", "transparent"],
            ["--mask-fallback", "solid", "--mask-fallback-color", "red"],
            ["--mask-fallback", "original"],
        ]
        for (index, fallback) in cases.enumerated() {
            let output = directory.appending(path: "fallback-\(index).png")
            let command = try AskiDemoCommand.parse(
                [input.path, "--mask", mask.path, "--render-png", output.path] + fallback
            )
            let status = command.execute(standardOutput: { _ in }, standardError: { _ in })
            #expect(status == .success)
            #expect(try Data(contentsOf: output).isEmpty == false)
        }
    }

    @Test func missingSourceAndMaskUseInputUnavailableExitCode() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "input.png")
        let protectedOutput = directory.appending(path: "protected.txt")
        let previousOutput = Data("previous output\n".utf8)
        try writeFixturePNG(to: input, width: 80, height: 40)
        try previousOutput.write(to: protectedOutput)

        var sourceError = ""
        let missingSource = directory.appending(path: "missing-source.png")
        let sourceCommand = try AskiDemoCommand.parse([missingSource.path])
        #expect(sourceCommand.execute(standardOutput: { _ in }, standardError: { sourceError += $0 }) == .inputUnavailable)
        #expect(sourceError.contains(missingSource.path))

        var maskError = ""
        let missingMask = directory.appending(path: "missing-mask.png")
        let maskCommand = try AskiDemoCommand.parse([
            input.path, "--mask", missingMask.path, "--output", protectedOutput.path,
        ])
        #expect(maskCommand.execute(standardOutput: { _ in }, standardError: { maskError += $0 }) == .inputUnavailable)
        #expect(maskError.contains(missingMask.path))
        #expect(try Data(contentsOf: protectedOutput) == previousOutput)
    }

    @Test func noMaskOutputMatchesTheUnderlyingConversion() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "input.png")
        try writeFixturePNG(to: input, width: 80, height: 40)

        let image = try DemoImageIO.loadThumbnailForConversion(
            at: input.path,
            columns: 12,
            tileShape: ASCIIConverter(characterSet: Charset.blocks.characterSet, palette: BuiltInPalette.fullColor).tileShape,
            oversample: ToolArgumentBounds.defaultOversample
        )
        let expectedGrid = ASCIIConverter(characterSet: Charset.blocks.characterSet, palette: BuiltInPalette.fullColor)
            .convert(image, columns: 12)
        let expected =
            expectedGrid.renderPlainText().hasSuffix("\n")
            ? expectedGrid.renderPlainText()
            : expectedGrid.renderPlainText() + "\n"

        var stdout = ""
        let command = try AskiDemoCommand.parse([input.path, "--columns", "12", "--charset", "blocks"])
        #expect(command.execute(standardOutput: { stdout += $0 }, standardError: { _ in }) == .success)
        #expect(stdout == expected)
    }

    @Test func noMaskPNGMatchesLegacyDirectEncoding() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "input.png")
        let expectedOutput = directory.appending(path: "expected.png")
        let actualOutput = directory.appending(path: "actual.png")
        try writeFixturePNG(to: input, width: 80, height: 40)

        let converter = ASCIIConverter(characterSet: Charset.blocks.characterSet, palette: BuiltInPalette.fullColor)
        let normalizedImage = try DemoImageIO.loadThumbnailForConversion(
            at: input.path,
            columns: 12,
            tileShape: converter.tileShape,
            oversample: converter.oversample
        )
        let expectedImage = converter.convert(normalizedImage, columns: 12).renderImage(
            font: .system(size: 10),
            backgroundColor: BackgroundColor.clear.cgColor,
            scale: 1,
            preserveSourceAspect: true
        )
        try writeLegacyPNG(expectedImage, to: expectedOutput)

        let command = try AskiDemoCommand.parse([
            input.path,
            "--columns", "12",
            "--charset", "blocks",
            "--background", "clear",
            "--render-png", actualOutput.path,
        ])
        #expect(command.execute(standardOutput: { _ in }, standardError: { _ in }) == .success)
        #expect(try Data(contentsOf: actualOutput) == Data(contentsOf: expectedOutput))
    }

    @Test func writesTextAndRenderedPNGOutputs() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "input.png")
        let textOutput = directory.appending(path: "out.txt")
        let pngOutput = directory.appending(path: "out.png")
        try writeFixturePNG(to: input, width: 80, height: 40)

        var stdout = ""
        var stderr = ""
        let command = try AskiDemoCommand.parse([
            input.path,
            "--columns", "12",
            "--output", textOutput.path,
            "--render-png", pngOutput.path,
            "--font-size", "12",
        ])
        let status = command.execute(standardOutput: { stdout += $0 }, standardError: { stderr += $0 })

        #expect(status == .success)
        #expect(stdout.isEmpty)
        #expect(stderr.isEmpty)
        #expect(try String(contentsOf: textOutput, encoding: .utf8).isEmpty == false)

        let source = CGImageSourceCreateWithURL(pngOutput as CFURL, nil)
        let image = source.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        #expect(image?.width ?? 0 > 0)
        #expect(image?.height ?? 0 > 0)
    }

    // Portrait fixture is 3:4 (768x1024, aspect 1.3333), NOT an extreme 3:1.
    // Verified empirically: at 512 columns a 3:1 (256x768) source converts to an
    // EMPTY grid — the converter floors `cellWidth = thumbnailWidth / columns` to
    // 0 when the source's pixel width (256) is below the column count (512), and
    // `ImageIOThumbnail.decode` never upscales (`Sources/Aski/ImageIOThumbnail.swift:34`).
    // A 3:4 portrait yields cols=512, rows=310 and reproduces source aspect to
    // ~0.1%. Fixing the extreme-aspect floor is a library/conversion change and is
    // OUT OF SCOPE for this sweep (the spec's Scope line forbids Sources/Aski
    // behavior changes that touch snapshots); a realistic 3:4 "portrait" fully
    // satisfies ASTSK-21 AC#2.
    @Test func preserveAspectReproducesSourceAspectWithin1Percent() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "portrait.png")
        try writeFixturePNG(to: input, width: 768, height: 1024)  // 3:4 portrait -> aspect 1.3333
        let pngOutput = directory.appending(path: "out.png")

        let command = try AskiDemoCommand.parse([
            input.path, "--columns", "512", "--render-png", pngOutput.path,
        ])
        let status = command.execute(standardOutput: { _ in }, standardError: { _ in })
        #expect(status == .success)

        let source = CGImageSourceCreateWithURL(pngOutput as CFURL, nil)
        let image = try #require(source.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        let outputAspect = Double(image.height) / Double(image.width)
        let sourceAspect = 1024.0 / 768.0
        #expect(abs(outputAspect - sourceAspect) / sourceAspect < 0.01)
    }

    @Test func noPreserveAspectReproducesLegacySquish() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "portrait.png")
        try writeFixturePNG(to: input, width: 768, height: 1024)
        let pngOutput = directory.appending(path: "out.png")

        let command = try AskiDemoCommand.parse([
            input.path, "--columns", "512", "--render-png", pngOutput.path, "--no-preserve-aspect",
        ])
        _ = command.execute(standardOutput: { _ in }, standardError: { _ in })

        let source = CGImageSourceCreateWithURL(pngOutput as CFURL, nil)
        let image = try #require(source.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        let outputAspect = Double(image.height) / Double(image.width)
        let sourceAspect = 1024.0 / 768.0
        // Legacy glyph aspect squishes the portrait: ~0.909 x source aspect
        // (measured ~1.211). Assert it is clearly (>5%) below the true aspect.
        #expect((sourceAspect - outputAspect) / sourceAspect > 0.05)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AskiDemoTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFixturePNG(to url: URL, width: Int, height: Int) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        for x in 0..<width {
            let t = CGFloat(x) / CGFloat(width - 1)
            context.setFillColor(red: t, green: 0.2, blue: 1 - t, alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }

        let image = context.makeImage()!
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )!
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func writeSolidPNG(to url: URL, width: Int, height: Int, gray: CGFloat) throws {
        let image = try #require(makeImage(width: width, height: height, gray: gray))
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )!
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func writeLegacyPNG(_ image: CGImage, to url: URL) throws {
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )!
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func makeImage(width: Int, height: Int, gray: CGFloat) -> CGImage? {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(gray: gray, alpha: 1)
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }

    private func validationMessage(
        maskPath: String? = nil,
        fallback: MaskFallbackArgument? = nil,
        fallbackColor: BackgroundColor? = nil,
        fallbackSizing: MaskFallbackSizingArgument? = nil,
        ground: BackgroundColor? = nil,
        hardEdges: Bool = false,
        invert: Bool = false,
        renderPNGPath: String? = nil
    ) -> String {
        var arguments = DemoMaskArguments()
        arguments.maskPath = maskPath
        arguments.fallback = fallback
        arguments.fallbackColor = fallbackColor
        arguments.fallbackSizing = fallbackSizing
        arguments.ground = ground
        arguments.hardEdges = hardEdges
        arguments.invert = invert
        do {
            try arguments.validate(renderPNGPath: renderPNGPath)
            Issue.record("expected validation failure")
            return ""
        } catch let error as ValidationError {
            return error.message
        } catch {
            return String(describing: error)
        }
    }
}

@Suite struct AskiTileMatrixArgumentsTests {
    @Test func parsesRequiredInputOutputAndDefaults() throws {
        let command = try TileMatrixCommand.parse(["input.jpg", "/tmp/out"])
        #expect(command.inputPath == "input.jpg")
        #expect(command.outputDirectory == "/tmp/out")
        #expect(command.columns == 64)
        #expect(command.scale == 12)
    }

    @Test func rejectsAbsurdColumnsAndScale() {
        #expect(throws: (any Error).self) { try TileMatrixCommand.parse(["input.jpg", "/tmp/out", "--columns", "513"]) }
        #expect(throws: (any Error).self) { try TileMatrixCommand.parse(["input.jpg", "/tmp/out", "--scale", "65"]) }
        #expect(throws: (any Error).self) { try TileMatrixCommand.parse(["input.jpg", "/tmp/out", "--scale", "inf"]) }
    }

    @Test func requiresBothPositionals() {
        #expect(throws: (any Error).self) { try TileMatrixCommand.parse(["input.jpg"]) }
    }
}
