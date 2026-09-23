import CoreGraphics
import Testing
@testable import Aski

@Suite struct MaskFallbackCharacterTests {
    @Test func allWhiteMaskSuppressesCharacterFallback() {
        let source = TestImages.horizontalGradient(width: 100, height: 50)
        let whiteMask = Self.solidMask(value: 1, width: 8, height: 4)
        let unmasked = DefaultConverter().convert(source, columns: 8)
        let masked = DefaultConverter().convert(
            source,
            columns: 8,
            mask: MaskOptions(
                image: whiteMask,
                fallback: .character("#", color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            )
        )

        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let a = unmasked.renderImage(font: .system(size: 12), backgroundColor: background, scale: 1)
        let b = masked.renderImage(font: .system(size: 12), backgroundColor: background, scale: 1)
        #expect(Self.bytes(a) == Self.bytes(b))
    }

    @Test func allBlackMaskShowsUniformCharacterFallback() {
        let source = TestImages.horizontalGradient(width: 100, height: 50)
        let blackMask = Self.solidMask(value: 0, width: 8, height: 4)
        let grid = DefaultConverter().convert(
            source,
            columns: 8,
            mask: MaskOptions(
                image: blackMask,
                fallback: .character("#", color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            )
        )

        let image = grid.renderImage(
            font: .system(size: 12),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1,
            composition: CompositionOptions(background: .solid(CGColor(red: 0, green: 0, blue: 0, alpha: 1)))
        )
        let pixels = Self.pixels(image)
        #expect(pixels.contains { $0.r > 120 && $0.g < 60 && $0.b < 60 && $0.a > 120 })
    }

    @Test func halfCoverageCharacterFallbackIsNotAppliedTwice() {
        let cell = ASCIICell(
            character: "█",
            displayColor: SIMD3<Float>(1, 0, 0),
            alpha: 1,
            brightness: 1,
            coverage: 0.5
        )
        let grid = ASCIIGrid(
            cells: [[cell]],
            colorSpace: .sRGB,
            maskFallback: .character("#", color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        )
        let image = grid.renderImage(
            font: .system(size: 24),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1,
            composition: CompositionOptions(background: .solid(CGColor(red: 0, green: 0, blue: 0, alpha: 1)))
        )

        let strongestBlue = Self.pixels(image).map(\.b).max() ?? 0
        #expect(strongestBlue > 80)
    }

    private static func solidMask(value: CGFloat, width: Int, height: Int) -> CGImage {
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
        context.setFillColor(gray: value, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private static func bytes(_ image: CGImage) -> [UInt8] {
        pixels(image).flatMap { [$0.r, $0.g, $0.b, $0.a] }
    }

    private static func pixels(_ image: CGImage) -> [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &bytes,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 0, to: bytes.count, by: 4).map { index in
            (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
        }
    }
}
