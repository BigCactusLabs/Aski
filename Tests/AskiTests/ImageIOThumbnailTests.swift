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

    @Test func thumbnailDecodesCGImageWithoutUpscalingSmallInput() throws {
        let source = TestImages.horizontalGradient(width: 64, height: 32)

        let thumbnail = try ImageIOThumbnail.decode(image: source, maxPixelSize: 200)

        #expect(thumbnail.width == 64)
        #expect(thumbnail.height == 32)
    }

    @Test func thumbnailDecodesCGImageThroughImageIOWhenDownscaling() throws {
        let source = TestImages.horizontalGradient(width: 800, height: 400)

        let thumbnail = try ImageIOThumbnail.decode(image: source, maxPixelSize: 160)

        #expect(thumbnail.width == 160)
        #expect(thumbnail.height == 80)
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

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ImageIOThumbnailTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
