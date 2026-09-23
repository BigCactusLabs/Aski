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

    public static func loadThumbnailForConversion(
        at path: String,
        columns: Int,
        tileShape: ASCIITileShape,
        oversample: Int = ToolArgumentBounds.defaultOversample
    ) throws -> CGImage {
        let source = try openSource(at: path)
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = pixelDimension(properties[kCGImagePropertyPixelWidth]),
            let height = pixelDimension(properties[kCGImagePropertyPixelHeight])
        else {
            throw DemoRuntimeError.inputUnavailable(path)
        }
        let maxPixelSize = ToolArgumentBounds.thumbnailMaxPixelSize(
            imageWidth: width,
            imageHeight: height,
            columns: columns,
            tileShape: tileShape,
            oversample: oversample
        )
        do {
            return try ImageIOThumbnail.decode(source: source, maxPixelSize: maxPixelSize)
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
