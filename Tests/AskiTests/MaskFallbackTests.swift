import CoreGraphics
import CoreImage
import Testing
@testable import Aski

@Suite struct MaskFallbackTests {
    @Test func transparentFallbackReturnsNil() {
        let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
        #expect(MaskFallbackImageFactory.makeTile(.transparent, extent: extent, colorSpace: .sRGB) == nil)
    }

    @Test func solidFallbackProducesCroppedPlane() {
        let extent = CGRect(x: 0, y: 0, width: 8, height: 6)
        let image = MaskFallbackImageFactory.makeTile(
            .solid(CGColor(red: 1, green: 0, blue: 0, alpha: 1)),
            extent: extent,
            colorSpace: .sRGB
        )

        #expect(image?.extent == extent)
        let red = Self.sampleRGBA(image!, x: 4, y: 3).r
        #expect(red > 240)
    }

    @Test func solidFallbackConvertsNamedRGBColorSpaceToRenderColorSpace() {
        let extent = CGRect(x: 0, y: 0, width: 4, height: 4)
        let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let target = CGColorSpace(name: CGColorSpace.sRGB)!
        let color = CGColor(colorSpace: displayP3, components: [1, 0.5, 0, 1])!
        let image = MaskFallbackImageFactory.makeTile(
            .solid(color),
            extent: extent,
            colorSpace: .sRGB
        )!

        let converted = color.converted(to: target, intent: .perceptual, options: nil)!
        let expectedGreen = Int(((converted.components ?? [0, 0, 0, 1])[1] * 255).rounded())
        let pixel = Self.sampleRGBA(image, x: 2, y: 2)

        #expect(abs(Int(pixel.g) - expectedGreen) <= 2)
        #expect(pixel.g < 124)
    }

    @Test func tileCharacterFallbackReturnsNil() {
        let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
        #expect(MaskFallbackImageFactory.makeTile(.character("#", color: nil), extent: extent, colorSpace: .sRGB) == nil)
    }

    @Test func asciiCharacterFallbackRasterizesGlyphsWithCoverageOne() {
        let cell = ASCIICell(
            character: "A",
            displayColor: SIMD3<Float>(1, 0, 0),
            alpha: 1,
            brightness: 1,
            coverage: 0
        )
        let grid = ASCIIGrid(cells: [[cell]], colorSpace: .sRGB)
        let extent = CGRect(x: 0, y: 0, width: 24, height: 24)
        let image = MaskFallbackImageFactory.makeASCII(
            .character("#", color: CGColor(red: 0, green: 1, blue: 0, alpha: 1)),
            grid: grid,
            font: .system(size: 20),
            scale: 1,
            extent: extent,
            colorSpace: .sRGB
        )

        #expect(image != nil)
        #expect(image!.extent.width > 0)
        let pixels = Self.sampleMany(image!)
        #expect(pixels.contains { $0.g > 80 && $0.a > 80 })
    }

    private static func sampleRGBA(_ image: CIImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let context = CIContext(options: nil)
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            image,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: x, y: y, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        )
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }

    private static func sampleMany(_ image: CIImage) -> [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)] {
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        let context = CIContext(options: nil)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        context.render(
            image,
            toBitmap: &bytes,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return stride(from: 0, to: bytes.count, by: 4).map { index in
            (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
        }
    }
}
