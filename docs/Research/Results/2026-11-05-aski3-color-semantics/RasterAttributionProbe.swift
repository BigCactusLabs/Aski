import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import Testing
@testable import Aski

/// TEMPORARY evidence only: the remap restores the legacy Generic RGB stimulus.
@MainActor
@Suite(.serialized) struct RasterAttributionProbe {
    @Test(arguments: ["background-blurred-fill", "background-sizing-fit", "blend-xor", "asciiCircleMaskCharacterFallback"])
    func attributeRasterAlpha(name: String) throws {
        let isMask = name == "asciiCircleMaskCharacterFallback"
        let grid = isMask ? Self.maskGrid() : Self.compositionGrid()
        let remapped = try Self.genericRGBToSRGB(grid)
        let font: ASCIIFont = isMask ? .system(size: 10) : .courierPrime(size: 12)
        let options = Self.composition(name: name)
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        func measure(_ grid: ASCIIGrid) throws -> [String: Any] {
            let rendered = grid.renderImage(
                font: font, backgroundColor: background, scale: 1, composition: options)
            let raster = CellRasterBuilder.makeASCIIRaster(grid: grid, font: font, scale: 1)
            let rasterImage = try #require(raster.image.cgImage)
            return [
                "render": try Self.measure(rendered, includePNG: true),
                "cell_raster": try Self.measure(rasterImage, includePNG: false),
            ]
        }
        let row: [String: Any] = [
            "probe": "ASKI3-raster-alpha-attribution", "case": name,
            "original": try measure(grid), "generic_rgb_to_srgb": try measure(remapped),
        ]
        let json = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        print(String(decoding: json, as: UTF8.self))
    }

    private static func compositionGrid() -> ASCIIGrid {
        var rows: [[ASCIICell]] = []
        for row in 0..<16 {
            var cells: [ASCIICell] = []
            for column in 0..<24 {
                let t = Float(column) / 23
                let y = Float(row) / 15
                cells.append(ASCIICell(
                    character: (row + column).isMultiple(of: 3) ? "@" : "#",
                    displayColor: SIMD3<Float>(1, max(0.25, t), max(0.25, 1 - y)),
                    alpha: 1, brightness: 0.5))
            }
            rows.append(cells)
        }
        return ASCIIGrid(cells: rows, colorSpace: .sRGB)
    }

    private static func maskGrid() -> ASCIIGrid {
        DefaultConverter().convert(
            TestImages.horizontalGradient(width: 240, height: 120), columns: 32,
            mask: MaskOptions(
                image: circleMask(width: 64, height: 32),
                fallback: .character("#", color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))))
    }

    private static func composition(name: String) -> CompositionOptions {
        let image = TestImages.horizontalGradient(width: 96, height: 40)
        switch name {
        case "background-blurred-fill":
            return CompositionOptions(background: .blurred(image, radius: 8, opacity: 0.8, sizing: .fill))
        case "background-sizing-fit":
            return CompositionOptions(background: .original(image, sizing: .fit))
        case "blend-xor":
            return CompositionOptions(background: .original(image, sizing: .fill), characterBlendMode: .xor)
        default:
            return CompositionOptions(background: .solid(CGColor(red: 0, green: 0, blue: 0, alpha: 1)))
        }
    }

    /// Decode the legacy Generic RGB meaning into encoded sRGB independently of
    /// production color helpers. Only displayColor changes; every other cell and
    /// grid field is retained, and the default converter's sRGB tag is unchanged.
    private static func genericRGBToSRGB(_ grid: ASCIIGrid) throws -> ASCIIGrid {
        let destination = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let cells = try grid.cells.map { row in
            try row.map { cell in
                let generic = CGColor(
                    red: CGFloat(cell.displayColor.x), green: CGFloat(cell.displayColor.y),
                    blue: CGFloat(cell.displayColor.z), alpha: 1)
                let converted = try #require(generic.converted(to: destination, intent: .defaultIntent, options: nil))
                let components = try #require(converted.components)
                return ASCIICell(
                    character: cell.character,
                    displayColor: SIMD3(Float(components[0]), Float(components[1]), Float(components[2])),
                    alpha: cell.alpha, brightness: cell.brightness, coverage: cell.coverage)
            }
        }
        return ASCIIGrid(
            cells: cells, colorSpace: grid.colorSpace, composition: grid.composition,
            maskFallback: grid.maskFallback, maskGroundColor: grid.maskGroundColor,
            maskUsesHardEdges: grid.maskUsesHardEdges)
    }

    private static func circleMask(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 1, alpha: 1)
        context.fillEllipse(in: CGRect(x: width / 6, y: height / 6, width: width * 2 / 3, height: height * 2 / 3))
        return context.makeImage()!
    }


    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func measure(_ image: CGImage, includePNG: Bool) throws -> [String: Any] {
        let provider = try #require(image.dataProvider)
        let raw = try #require(provider.data)
        let colorSpace = try #require(image.colorSpace)
        // Normalize layout only, in the image's own color space. This makes an
        // alpha-plane hash independent of raw byte order and row padding.
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let rgba = Data(bytes: pixels, count: image.width * image.height * 4)
        let alpha = Data(stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] })
        var row: [String: Any] = [
            "raw_sha256": hash(raw as Data), "rgba8_sha256": hash(rgba), "alpha8_sha256": hash(alpha),
            "width": image.width, "height": image.height, "bytes_per_row": image.bytesPerRow,
            "bits_per_component": image.bitsPerComponent, "bits_per_pixel": image.bitsPerPixel,
            "bitmap_info": image.bitmapInfo.rawValue,
            "color_space": image.colorSpace?.name.map { $0 as String } ?? "nil",
        ]
        if includePNG {
            // Same NSImage wrapping and NSBitmapImageRep PNG serialization as
            // SnapshotTesting's private NSImagePNGRepresentation implementation.
            let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            let cg = try #require(nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = nsImage.size
            let png = try #require(rep.representation(using: .png, properties: [:]))
            row["snapshot_png_sha256"] = hash(png)
            // The alpha differences were observed in serialized PNGs. Retain a
            // separate decoded PNG alpha hash to expose any serialization effect.
            let decoded = try #require(NSImage(data: png))
            let decodedCG = try #require(decoded.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let decodedMeasure = try measure(decodedCG, includePNG: false)
            row["snapshot_png_decoded_rgba8_sha256"] = decodedMeasure["rgba8_sha256"]
            row["snapshot_png_decoded_alpha8_sha256"] = decodedMeasure["alpha8_sha256"]
        }
        return row
    }
}
