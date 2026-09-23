import Testing
import CoreImage
import CoreGraphics
@testable import Aski

@Suite struct BackgroundResolverTests {
    private let extent = CGRect(x: 0, y: 0, width: 64, height: 32)

    private func testCGImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 100,
            height: 50,
            bitsPerComponent: 8,
            bytesPerRow: 100 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
        return context.makeImage()!
    }

    @Test func transparentReturnsNil() {
        let resolver = BackgroundResolver()
        let result = resolver.resolve(.transparent, outputExtent: extent)
        #expect(result == nil)
    }

    @Test func solidReturnsImageWithExtent() {
        let resolver = BackgroundResolver()
        let background: Background = .solid(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        let result = resolver.resolve(background, outputExtent: extent)
        #expect(result != nil)
        #expect(result?.extent == extent)
    }

    @Test func originalFillExtentMatchesOutput() {
        let resolver = BackgroundResolver()
        let background: Background = .original(testCGImage(), sizing: .fill)
        let result = resolver.resolve(background, outputExtent: extent)
        #expect(result != nil)
        #expect(result?.extent == extent)
    }

    @Test func originalStretchExtentMatchesOutput() {
        let resolver = BackgroundResolver()
        let background: Background = .original(testCGImage(), sizing: .stretch)
        let result = resolver.resolve(background, outputExtent: extent)
        #expect(result?.extent == extent)
    }

    @Test func blurredAppliesGaussian() {
        let resolver = BackgroundResolver()
        let background: Background = .blurred(testCGImage(), radius: 8, opacity: 0.8, sizing: .fill)
        let result = resolver.resolve(background, outputExtent: extent)
        #expect(result != nil)
    }

    @Test func degenerateExtentReturnsNil() {
        let resolver = BackgroundResolver()
        let background: Background = .solid(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        let result = resolver.resolve(background, outputExtent: .zero)
        #expect(result == nil)
    }
}
