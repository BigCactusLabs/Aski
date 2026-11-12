import CoreGraphics
import Foundation
import ImageIO

/// Wrapper around `CGImageSourceCreateThumbnailAtIndex` for source-backed
/// inputs (encoded `Data` or an open `CGImageSource`). For JPEG sources this can
/// use decoder-level scaled output instead of decode-full + resize, and the
/// source's orientation metadata is applied.
///
/// An already-decoded `CGImage` does not come through here: pass it straight to
/// the converter, which resamples it to the conversion size itself (ASKI-1).
public enum ImageIOThumbnail {
    public enum DecodeError: Error, Equatable {
        case cannotOpenSource
        case cannotCreateThumbnail
    }

    /// Decodes image data into a thumbnail whose longest side is at most
    /// `maxPixelSize` pixels.
    public static func decode(data: Data, maxPixelSize: Int) throws -> CGImage {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            throw DecodeError.cannotOpenSource
        }
        guard CGImageSourceGetCount(source) > 0 else {
            throw DecodeError.cannotOpenSource
        }
        return try makeThumbnail(source: source, maxPixelSize: maxPixelSize)
    }

    /// Decodes an existing ImageIO source into a thumbnail whose longest side is
    /// at most `maxPixelSize` pixels.
    public static func decode(source: CGImageSource, maxPixelSize: Int) throws -> CGImage {
        try makeThumbnail(source: source, maxPixelSize: maxPixelSize)
    }

    private static func makeThumbnail(source: CGImageSource, maxPixelSize: Int) throws -> CGImage {
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        let factor = subsampleFactor(source: source, maxPixelSize: maxPixelSize)
        if factor > 1 {
            options[kCGImageSourceSubsampleFactor] = factor
        }
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw DecodeError.cannotCreateThumbnail
        }
        return thumbnail
    }

    internal static func subsampleFactor(source: CGImageSource, maxPixelSize: Int) -> Int {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = pixelDimension(properties[kCGImagePropertyPixelWidth]),
            let height = pixelDimension(properties[kCGImagePropertyPixelHeight])
        else {
            return 1
        }
        return subsampleFactor(longestSide: max(width, height), maxPixelSize: maxPixelSize)
    }

    internal static func subsampleFactor(longestSide: Int, maxPixelSize: Int) -> Int {
        guard maxPixelSize > 0, longestSide > maxPixelSize else {
            return 1
        }

        var factor = 1
        while factor < 8, longestSide / (factor * 2) >= maxPixelSize {
            factor *= 2
        }
        return factor
    }

    private static func pixelDimension(_ value: Any?) -> Int? {
        if let dimension = value as? Int {
            return dimension
        }
        if let dimension = value as? NSNumber {
            return dimension.intValue
        }
        return nil
    }
}
