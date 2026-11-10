import Aski
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum DemoImageIO {
    public static func loadImage(at path: String) throws -> CGImage {
        let url = URL(fileURLWithPath: path)
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw DemoRuntimeError.inputUnavailable(path)
        }
        return image
    }

    public static func loadThumbnail(at path: String, maxPixelSize: Int) throws -> CGImage {
        guard maxPixelSize > 0 else {
            throw DemoRuntimeError.inputUnavailable(path)
        }
        let source = try openSource(at: path)
        do {
            return try ImageIOThumbnail.decode(source: source, maxPixelSize: maxPixelSize)
        } catch {
            throw DemoRuntimeError.inputUnavailable(path)
        }
    }

    /// Decodes the image at `path` at the size `converter` prepares it at for
    /// `columns`, so the converter samples the decoded pixels without a second
    /// downscale. EXIF orientation is applied.
    public static func loadThumbnailForConversion<C: ASCIICharacterSet, P: ASCIIPalette>(
        at path: String,
        columns: Int,
        converter: ASCIIConverter<C, P>
    ) throws -> CGImage {
        try loadThumbnailForConversion(at: path) { width, height in
            converter.preparationMaxPixelSize(sourceWidth: width, sourceHeight: height, columns: columns)
        }
    }

    /// `TileGridConverter` counterpart of
    /// `loadThumbnailForConversion(at:columns:converter:)`.
    public static func loadThumbnailForConversion(
        at path: String,
        columns: Int,
        converter: TileGridConverter
    ) throws -> CGImage {
        try loadThumbnailForConversion(at: path) { width, height in
            converter.preparationMaxPixelSize(sourceWidth: width, sourceHeight: height, columns: columns)
        }
    }

    /// Decodes at the longest side `budget` returns for the source's displayed
    /// size: its stored size with EXIF orientation applied, which is the size
    /// ImageIO's thumbnail comes out at. The budget is the converter's own
    /// (`preparationMaxPixelSize`), not a copy of its rule. The copy this
    /// loader used to keep lacked the converter's portrait branch and sized
    /// from the stored dimensions, so portraits, including phone photos stored
    /// landscape with an orientation tag, decoded at about half the intended
    /// cell width (ASKI-104).
    private static func loadThumbnailForConversion(
        at path: String,
        budget: (_ width: Int, _ height: Int) -> Int?
    ) throws -> CGImage {
        let source = try openSource(at: path)
        guard let size = displayedPixelSize(source) else {
            throw DemoRuntimeError.inputUnavailable(path)
        }
        // `nil` only where the converter returns an empty grid for this
        // geometry anyway, so decode the smallest thumbnail rather than fail.
        var maxPixelSize = budget(size.width, size.height) ?? 1
        do {
            var thumbnail = try ImageIOThumbnail.decode(source: source, maxPixelSize: maxPixelSize)
            // In a portrait the width is the short side, and ImageIO derives it
            // by flooring through a power-of-two subsample before it scales, so
            // it can land a pixel under the floor of its proportional size: a
            // 975×1280 JPEG decoded at 158 comes out 119 wide, not 120, and the
            // converter's cell width floors from 2 to 1. The budget sets the
            // portrait cap so that proportional width is at least
            // `columns * oversample`; retry one pixel larger until the decode
            // reaches its floor. The shortfall is at most one pixel, so it is
            // made up within `ceil(height / width)` steps. In landscape and
            // square sources the width is the long side, which ImageIO meets
            // exactly.
            if size.height > size.width, size.height > maxPixelSize {
                let widthFloor = Int(Double(maxPixelSize) * Double(size.width) / Double(size.height))
                let lastAttempt = min(
                    size.height,
                    maxPixelSize + Int((Double(size.height) / Double(size.width)).rounded(.up))
                )
                while thumbnail.width < widthFloor, maxPixelSize < lastAttempt {
                    maxPixelSize += 1
                    thumbnail = try ImageIOThumbnail.decode(source: source, maxPixelSize: maxPixelSize)
                }
            }
            return thumbnail
        } catch {
            throw DemoRuntimeError.inputUnavailable(path)
        }
    }

    public static func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw DemoRuntimeError.cannotEncodePNG
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw DemoRuntimeError.cannotEncodePNG
        }
        return data as Data
    }

    public static func writePNG(_ image: CGImage, to path: String) throws {
        let data = try encodePNG(image)
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            throw DemoRuntimeError.cannotWritePNG(path)
        }
    }

    private static func openSource(at path: String) throws -> CGImageSource {
        let url = URL(fileURLWithPath: path)
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            CGImageSourceGetCount(source) > 0
        else {
            throw DemoRuntimeError.inputUnavailable(path)
        }
        return source
    }

    /// The source's pixel size as ImageIO's thumbnail presents it:
    /// orientations 5–8 turn the stored raster a quarter turn, so they swap
    /// width and height.
    private static func displayedPixelSize(_ source: CGImageSource) -> (width: Int, height: Int)? {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = pixelDimension(properties[kCGImagePropertyPixelWidth]),
            let height = pixelDimension(properties[kCGImagePropertyPixelHeight])
        else {
            return nil
        }
        let orientation = pixelDimension(properties[kCGImagePropertyOrientation])
            .flatMap { CGImagePropertyOrientation(rawValue: UInt32(clamping: $0)) }
        switch orientation {
        case .leftMirrored, .right, .rightMirrored, .left:
            return (height, width)
        default:
            return (width, height)
        }
    }

    private static func pixelDimension(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }
}

public enum DemoRuntimeError: Error, CustomStringConvertible {
    case inputUnavailable(String)
    case cannotEncodePNG
    case cannotWritePNG(String)

    public var description: String {
        switch self {
        case .inputUnavailable(let path):
            "could not open input image '\(path)'"
        case .cannotEncodePNG:
            "could not encode PNG"
        case .cannotWritePNG(let path):
            "could not write PNG '\(path)'"
        }
    }
}
