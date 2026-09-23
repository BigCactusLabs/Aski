import AskiToolSupport
import CoreGraphics
import Foundation
import SnapshotTesting
import Testing
@testable import Aski

#if canImport(AppKit)
    import AppKit

    @MainActor
    @Suite(.serialized) struct MaskSnapshotTests {
        @Test func asciiCircleMaskSolidFallback() {
            let grid = DefaultConverter().convert(
                TestImages.horizontalGradient(width: 240, height: 120),
                columns: 32,
                mask: MaskOptions(
                    image: Self.circleMask(width: 64, height: 32),
                    fallback: .solid(CGColor(red: 0.8, green: 0.05, blue: 0.02, alpha: 1))
                )
            )
            let image = grid.renderImage(
                font: .system(size: 10),
                backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                scale: 1
            )
            assertSnapshot(of: Self.nsImage(from: image), as: .image, named: "ascii-circle-solid")
        }

        @Test func asciiCircleMaskCharacterFallback() {
            let grid = DefaultConverter().convert(
                TestImages.horizontalGradient(width: 240, height: 120),
                columns: 32,
                mask: MaskOptions(
                    image: Self.circleMask(width: 64, height: 32),
                    fallback: .character("#", color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
                )
            )
            let image = grid.renderImage(
                font: .system(size: 10),
                backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                scale: 1,
                composition: CompositionOptions(background: .solid(CGColor(red: 0, green: 0, blue: 0, alpha: 1)))
            )
            assertSnapshot(of: Self.nsImage(from: image), as: .image, named: "ascii-circle-character")
        }

        @Test func tilePixelArtCircleMaskSolidFallback() {
            let grid = TileGridConverter(palette: .adaptive(maxColors: 8)).convert(
                TestImages.horizontalGradient(width: 160, height: 160),
                columns: 16,
                mask: MaskOptions(
                    image: Self.circleMask(width: 32, height: 32),
                    fallback: .solid(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
                )
            )
            let image = grid.renderImage(
                mode: .pixelArt,
                cellShape: .circle,
                scale: 10,
                backgroundColor: CGColor(red: 0, green: 1, blue: 0, alpha: 1)
            )
            assertSnapshot(of: Self.nsImage(from: image), as: .image, named: "tile-pixelart-circle-solid")
        }

        @Test func tileBrickCircleMaskSolidFallback() {
            let grid = TileGridConverter(palette: .adaptive(maxColors: 8)).convert(
                TestImages.horizontalGradient(width: 160, height: 160),
                columns: 16,
                mask: MaskOptions(
                    image: Self.circleMask(width: 32, height: 32),
                    fallback: .solid(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
                )
            )
            let image = grid.renderImage(
                mode: .brick,
                cellShape: .circle,
                scale: 10,
                backgroundColor: CGColor(red: 0, green: 1, blue: 0, alpha: 1)
            )
            assertSnapshot(of: Self.nsImage(from: image), as: .image, named: "tile-brick-circle-solid")
        }

        @Test func tilePixelArtOriginalImageFallbackOrientation() {
            let grid = TileGridConverter(palette: .adaptive(maxColors: 8)).convert(
                TestImages.horizontalGradient(width: 160, height: 160),
                columns: 16,
                mask: MaskOptions(
                    image: Self.circleMask(width: 32, height: 32),
                    fallback: .originalImage(Self.verticalSplitImage(width: 80, height: 80), sizing: .stretch)
                )
            )
            let image = grid.renderImage(
                mode: .pixelArt,
                cellShape: .square,
                scale: 10,
                backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            )
            assertSnapshot(of: Self.nsImage(from: image), as: .image, named: "tile-pixelart-original-orientation")
        }

        @Test func tileMosaicCircleMaskSolidFallback() {
            let grid = TileGridConverter(palette: .adaptive(maxColors: 8)).convert(
                TestImages.horizontalGradient(width: 160, height: 160),
                columns: 16,
                mask: MaskOptions(
                    image: Self.circleMask(width: 32, height: 32),
                    fallback: .solid(CGColor(red: 0.9, green: 0, blue: 0, alpha: 1))
                )
            )
            let image = grid.renderImage(
                mode: .mosaic(grout: CGColor(red: 0, green: 0, blue: 0, alpha: 1), groutThickness: 0.2),
                cellShape: .square,
                scale: 10,
                backgroundColor: CGColor(red: 0, green: 0.2, blue: 0, alpha: 1)
            )
            assertSnapshot(of: Self.nsImage(from: image), as: .image, named: "tile-mosaic-circle-solid")
        }

        @Test func hardMaskVsSoftMask() {
            let image = TestImages.horizontalGradient(width: 240, height: 120)
            let mask = Self.circleMask(width: 64, height: 32)
            let soft = DefaultConverter().convert(
                image,
                columns: 32,
                mask: MaskOptions(image: mask, fallback: .solid(CGColor(red: 0, green: 0, blue: 1, alpha: 1)), softEdges: true)
            )
            let hard = DefaultConverter().convert(
                image,
                columns: 32,
                mask: MaskOptions(image: mask, fallback: .solid(CGColor(red: 0, green: 0, blue: 1, alpha: 1)), softEdges: false)
            )
            let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            assertSnapshot(
                of: Self.nsImage(from: soft.renderImage(font: .system(size: 10), backgroundColor: background, scale: 1)),
                as: .image,
                named: "ascii-soft-edge"
            )
            assertSnapshot(
                of: Self.nsImage(from: hard.renderImage(font: .system(size: 10), backgroundColor: background, scale: 1)),
                as: .image,
                named: "ascii-hard-edge"
            )
        }

        @Test func sameSourceOriginalImageFallbackGroundComparison() {
            let source = TestImages.horizontalGradient(width: 240, height: 160)
            let mask = Self.circleMask(width: 60, height: 40)
            let before = Self.renderSameSourceMask(source: source, mask: mask, groundColor: nil)
            let after = Self.renderSameSourceMask(
                source: source,
                mask: mask,
                groundColor: CGColor(red: 8 / 255, green: 8 / 255, blue: 8 / 255, alpha: 1)
            )

            assertSnapshot(of: Self.nsImage(from: before), as: .image, named: "same-source-before")
            assertSnapshot(of: Self.nsImage(from: after), as: .image, named: "same-source-ground-080808")
        }

        @Test func sameSourceCorpusGroundComparison() throws {
            let source = try DemoImageIO.loadImage(at: Self.corpusPortraitURL.path)
            let mask = Self.circleMask(width: 60, height: 80)
            let before = Self.renderSameSourceMask(source: source, mask: mask, groundColor: nil)
            let after = Self.renderSameSourceMask(
                source: source,
                mask: mask,
                groundColor: CGColor(red: 8 / 255, green: 8 / 255, blue: 8 / 255, alpha: 1)
            )

            if ProcessInfo.processInfo.environment["ASKI_RECORD_MASK_GROUND_DOCC"] == "1" {
                try FileManager.default.createDirectory(
                    at: Self.doccResourcesURL,
                    withIntermediateDirectories: true
                )
                try DemoImageIO.writePNG(before, to: Self.doccResourcesURL.appending(path: "mask-ground-before.png").path)
                try DemoImageIO.writePNG(after, to: Self.doccResourcesURL.appending(path: "mask-ground-after.png").path)
                try DemoImageIO.writePNG(mask, to: Self.doccResourcesURL.appending(path: "mask-ground-circle.png").path)
            }

            assertSnapshot(of: Self.nsImage(from: before), as: .image, named: "docc-mask-ground-before")
            assertSnapshot(of: Self.nsImage(from: after), as: .image, named: "docc-mask-ground-after")
        }

        private static func renderSameSourceMask(
            source: CGImage,
            mask: CGImage,
            groundColor: CGColor?
        ) -> CGImage {
            let grid = DefaultConverter().convert(
                source,
                columns: 60,
                mask: MaskOptions(
                    image: mask,
                    fallback: .originalImage(source, sizing: .fill),
                    groundColor: groundColor
                )
            )
            return grid.renderImage(
                font: .courierPrime(size: 8),
                backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                scale: 1,
                composition: CompositionOptions(background: .original(source, sizing: .fill))
            )
        }

        private static var packageRootURL: URL {
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }

        private static var corpusPortraitURL: URL {
            packageRootURL.appending(path: "docs/Research/Corpus/nasa-occupancy-v1/assets/james-lovell-portrait.jpg")
        }

        private static var doccResourcesURL: URL {
            packageRootURL.appending(path: "Sources/Aski/Aski.docc/Resources")
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

        private static func verticalSplitImage(width: Int, height: Int) -> CGImage {
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
            context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
            return context.makeImage()!
        }

        private static func nsImage(from image: CGImage) -> NSImage {
            NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }
#endif
