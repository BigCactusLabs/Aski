@_spi(AskiResearch) @testable import Aski
import AskiToolSupport
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

/// ASKI-104: the command-line loader decodes files at the converter's own
/// budget. Before, it kept a copy of the rule without the portrait branch, so
/// `aski render` sampled portraits at about half the intended cell width (a
/// 975×1280 photo at 60 columns decoded 91 wide, cell width 1 instead of 2).
@Suite struct ConversionThumbnailLoaderTests {
    private static let converter = DefaultConverter()

    /// Portrait shapes from near-square to a tall screenshot. 975×1280 at 60
    /// columns is the case where ImageIO, at the converter's budget of 158,
    /// decodes 119 wide instead of the 120 the budget implies; the loader's
    /// retry is what keeps that one on the width budget.
    @Test(arguments: [
        (975, 1280, 60), (975, 1280, 76), (975, 1280, 80),
        (1029, 1280, 80), (768, 1024, 76), (720, 1280, 100),
        (600, 1800, 80), (1000, 1001, 60),
    ])
    func portraitDecodesOnTheWidthBudget(width: Int, height: Int, columns: Int) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "portrait.png")
        try writeImage(gradient(width: width, height: height), to: input, type: .png)

        let image = try DemoImageIO.loadThumbnailForConversion(
            at: input.path, columns: columns, converter: Self.converter)
        let widthBudget = columns * Self.converter.oversample

        // ≥, not >: ImageIO can round a near-square portrait to square.
        #expect(image.height >= image.width)
        #expect(image.width >= widthBudget)
        let geometry = try #require(Self.converter.samplingGeometry(image, columns: columns))
        #expect(geometry.cellWidth == Self.converter.oversample)
        try expectShapeMatched(image, columns: columns)
    }

    /// The user-facing field from the bug report: `aski inspect --format json`
    /// reports `normalizedPixelWidth` at or above `columns × oversample`.
    @Test func inspectReportsAPortraitAtTheWidthBudget() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "portrait.png")
        try writeImage(gradient(width: 975, height: 1280), to: input, type: .png)

        var stdout = ""
        let command = try AskiInspectCommand.parse([input.path, "--columns", "60", "--format", "json"])
        #expect(command.execute(standardOutput: { stdout += $0 }, standardError: { _ in }) == .success)
        let report = try JSONDecoder().decode(AskiInspectionReport.self, from: Data(stdout.utf8))

        #expect(report.source.normalizedPixelWidth >= 60 * ToolArgumentBounds.defaultOversample)
        #expect(report.source.normalizedPixelHeight > report.source.normalizedPixelWidth)
        #expect(report.conversion.columns == 60)
    }

    /// A portrait stored as a landscape raster with an orientation tag, the
    /// usual layout of a phone photo. ImageIO's thumbnail applies the tag, so
    /// the loader has to size from the displayed shape, not the stored one.
    @Test(arguments: [5, 6, 7, 8])
    func rotatedPortraitDecodesOnTheWidthBudget(orientation: Int) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "rotated.jpg")
        // Stored 1280×975; displayed 975×1280 once the quarter turn applies.
        try writeImage(
            gradient(width: 1280, height: 975), to: input, type: .jpeg, orientation: orientation)

        let image = try DemoImageIO.loadThumbnailForConversion(
            at: input.path, columns: 60, converter: Self.converter)

        #expect(image.height > image.width)
        #expect(image.width >= 60 * Self.converter.oversample)
        let geometry = try #require(Self.converter.samplingGeometry(image, columns: 60))
        #expect(geometry.cellWidth == Self.converter.oversample)
        try expectShapeMatched(image, columns: 60)
    }

    /// Landscape and square decodes are unchanged: the cap still falls on the
    /// long side at `max(columns, rows) × oversample`, which is the width.
    @Test(arguments: [(1280, 975), (1920, 1080), (4000, 1000), (1000, 1000), (1001, 1000)])
    func landscapeAndSquareDecodesAreUnchanged(width: Int, height: Int) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "landscape.png")
        try writeImage(gradient(width: width, height: height), to: input, type: .png)
        let columns = 60
        let oversample = Self.converter.oversample

        let image = try DemoImageIO.loadThumbnailForConversion(
            at: input.path, columns: columns, converter: Self.converter)

        let rows = ToolArgumentBounds.gridRows(
            imageWidth: width, imageHeight: height, columns: columns, tileShape: .wide)
        let source = try #require(CGImageSourceCreateWithURL(input as CFURL, nil))
        let previous = try ImageIOThumbnail.decode(
            source: source, maxPixelSize: max(columns, rows) * oversample)
        #expect(image.width == previous.width)
        #expect(image.height == previous.height)
        #expect(image.width == columns * oversample)
    }

    /// The tile-matrix command decodes at `TileGridConverter`'s budget, so the
    /// tile converter samples the decode without downscaling it again.
    @Test func tileLoaderUsesTheTileConvertersBudget() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "landscape.png")
        try writeImage(gradient(width: 1280, height: 975), to: input, type: .png)
        let tiles = TileGridConverter()

        let image = try DemoImageIO.loadThumbnailForConversion(at: input.path, columns: 60, converter: tiles)

        let budget = try #require(tiles.preparationMaxPixelSize(sourceWidth: 1280, sourceHeight: 975, columns: 60))
        #expect(max(image.width, image.height) == budget)
    }

    /// The loader and the tile converter together give a tile-matrix portrait
    /// the intended cell width: the loader decodes at `TileGridConverter`'s
    /// portrait budget (ASKI-105) and retries past ImageIO's one-pixel width
    /// undershoot, and the tile converter samples that decode at
    /// `cellWidth == oversample`. 975×1280 at 60 columns is the geometry where
    /// ImageIO undershoots.
    @Test(arguments: [1, 2, 3])
    func tileLoaderGivesPortraitsTheIntendedCellWidth(oversample: Int) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "portrait.png")
        try writeImage(gradient(width: 975, height: 1280), to: input, type: .png)
        let tiles = TileGridConverter(oversample: oversample)

        let image = try DemoImageIO.loadThumbnailForConversion(at: input.path, columns: 60, converter: tiles)

        #expect(image.height > image.width)
        #expect(image.width >= 60 * oversample)
        let prepared = try #require(tiles.prepareLattice(image, columns: 60))
        #expect(prepared.cols == 60)
        #expect(prepared.lattice.cellWidth == oversample)
        #expect(prepared.lattice.cellHeight >= oversample)
    }

    /// The visible cost of the bug: a one-pixel-wide cell has no shape
    /// descriptor, so the log-polar matcher ranked every glyph of a CLI
    /// portrait by tone alone. Read the converter's own flag rather than
    /// restating its rule here.
    private func expectShapeMatched(_ image: CGImage, columns: Int) throws {
        let queries = try #require(Self.converter.cellQueryDescriptors(image, columns: columns))
        #expect(queries.supportsShapeDescriptor)
    }

    // MARK: - Fixtures

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ConversionThumbnailLoaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func gradient(width: Int, height: Int) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ))
        for x in 0..<width {
            let t = CGFloat(x) / CGFloat(max(1, width - 1))
            context.setFillColor(red: t, green: 0.3, blue: 1 - t, alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return try #require(context.makeImage())
    }

    private func writeImage(_ image: CGImage, to url: URL, type: UTType, orientation: Int? = nil) throws {
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [:]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
            properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFOrientation: orientation]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
