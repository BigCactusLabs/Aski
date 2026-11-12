import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Aski
@testable import AskiToolSupport

@Suite struct ImageIOThumbnailTests {
    @Test func thumbnailDecodesJPEGDataToTargetSize() throws {
        let source = TestImages.horizontalGradient(width: 2000, height: 1500)
        let data = TestImages.jpegData(source)

        let thumbnail = try ImageIOThumbnail.decode(data: data, maxPixelSize: 320)

        #expect(thumbnail.width == 320)
        #expect(thumbnail.height == 240)
    }

    @Test func thumbnailRespectsLandscapeAspect() throws {
        let source = TestImages.horizontalGradient(width: 1000, height: 500)
        let data = TestImages.jpegData(source)

        let thumbnail = try ImageIOThumbnail.decode(data: data, maxPixelSize: 200)

        #expect(thumbnail.width == 200)
        #expect(thumbnail.height == 100)
    }

    /// ASKI-1 moved decoded `CGImage` input off ImageIO; source-backed input
    /// stays on it and keeps applying the source's EXIF orientation. The stored
    /// 200×100 image is red on the left and blue on the right; orientation 6
    /// displays it rotated a quarter turn clockwise, so the thumbnail is
    /// portrait with red at the top.
    @Test func thumbnailAppliesEXIFOrientationFromData() throws {
        let data = Self.rotatedSplitJPEG()

        let thumbnail = try ImageIOThumbnail.decode(data: data, maxPixelSize: 100)

        try Self.expectRotatedSplit(thumbnail)
    }

    @Test func thumbnailAppliesEXIFOrientationFromSource() throws {
        let source = try #require(CGImageSourceCreateWithData(Self.rotatedSplitJPEG() as CFData, nil))

        let thumbnail = try ImageIOThumbnail.decode(source: source, maxPixelSize: 100)

        try Self.expectRotatedSplit(thumbnail)
    }

    @Test func demoImageIOAppliesEXIFOrientationFromSourceURL() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "rotated.jpg")
        try Self.rotatedSplitJPEG().write(to: url)

        let thumbnail = try DemoImageIO.loadThumbnail(at: url.path, maxPixelSize: 100)

        try Self.expectRotatedSplit(thumbnail)
    }

    @Test func thumbnailDecodesCGImageSource() throws {
        let source = TestImages.horizontalGradient(width: 600, height: 300)
        let imageSource = TestImages.jpegSource(source)

        let thumbnail = try ImageIOThumbnail.decode(source: imageSource, maxPixelSize: 120)

        #expect(thumbnail.width == 120)
        #expect(thumbnail.height == 60)
    }

    @Test func demoImageIOLoadsThumbnailDirectlyFromSourceURL() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "large.jpg")
        try TestImages.jpegData(TestImages.horizontalGradient(width: 1_200, height: 600)).write(to: url)

        let thumbnail = try DemoImageIO.loadThumbnail(at: url.path, maxPixelSize: 160)

        #expect(thumbnail.width == 160)
        #expect(thumbnail.height == 80)
    }

    @Test func demoImageIOLoadsSmallSourceThumbnailWithoutUpscaling() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "small.jpg")
        try TestImages.jpegData(TestImages.horizontalGradient(width: 64, height: 32)).write(to: url)

        let thumbnail = try DemoImageIO.loadThumbnail(at: url.path, maxPixelSize: 160)

        #expect(thumbnail.width == 64)
        #expect(thumbnail.height == 32)
    }

    @Test func invalidDataThrowsCannotOpenSource() {
        #expect(throws: ImageIOThumbnail.DecodeError.cannotOpenSource) {
            try ImageIOThumbnail.decode(data: Data([0x41, 0x53, 0x43, 0x49, 0x49]), maxPixelSize: 64)
        }
    }

    @Test func subsampleFactorKeepsDecoderOutputAtOrAboveTarget() {
        #expect(ImageIOThumbnail.subsampleFactor(longestSide: 4_032, maxPixelSize: 320) == 8)
        #expect(ImageIOThumbnail.subsampleFactor(longestSide: 2_000, maxPixelSize: 320) == 4)
        #expect(ImageIOThumbnail.subsampleFactor(longestSide: 640, maxPixelSize: 320) == 2)
        #expect(ImageIOThumbnail.subsampleFactor(longestSide: 320, maxPixelSize: 320) == 1)
        #expect(ImageIOThumbnail.subsampleFactor(longestSide: 160, maxPixelSize: 320) == 1)
    }

    /// A 200×100 JPEG, red on the left half and blue on the right, tagged with
    /// EXIF orientation 6 (display rotated 90° clockwise).
    private static func rotatedSplitJPEG() -> Data {
        let context = CGContext(
            data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))

        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
        let properties: [CFString: Any] = [kCGImagePropertyOrientation: 6]
        CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private static func expectRotatedSplit(_ thumbnail: CGImage) throws {
        #expect(thumbnail.width == 50)
        #expect(thumbnail.height == 100)
        let bytes = TestImages.deviceRGBBytes(thumbnail)
        func pixel(x: Int, y: Int) -> (red: Int, blue: Int) {
            let offset = (y * thumbnail.width + x) * 4
            return (Int(bytes[offset]), Int(bytes[offset + 2]))
        }
        let top = pixel(x: thumbnail.width / 2, y: thumbnail.height / 4)
        let bottom = pixel(x: thumbnail.width / 2, y: thumbnail.height * 3 / 4)
        #expect(top.red > 200 && top.blue < 60, "top should be red, got \(top)")
        #expect(bottom.blue > 200 && bottom.red < 60, "bottom should be blue, got \(bottom)")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ImageIOThumbnailTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
