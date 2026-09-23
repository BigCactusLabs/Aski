import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Aski

@Suite struct AskiGIFEncoderTests {
    private func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8, size: Int = 4) -> CGImage {
        var buffer = [UInt8](repeating: 0, count: size * size * 4)
        for pixel in 0..<(size * size) {
            buffer[pixel * 4 + 0] = r
            buffer[pixel * 4 + 1] = g
            buffer[pixel * 4 + 2] = b
            buffer[pixel * 4 + 3] = 255
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data(buffer) as CFData)!
        return CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: size * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    private func tempGIF() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AskiGIFEncoderTests-\(UUID().uuidString).gif")
    }

    private func unclampedDelays(_ url: URL) throws -> [Double] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try (0..<CGImageSourceGetCount(source)).map { index in
            let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])
            let gif = try #require(props[kCGImagePropertyGIFDictionary] as? [CFString: Any])
            return (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif[kCGImagePropertyGIFDelayTime] as? Double) ?? -1
        }
    }

    @Test func emptyFramesThrowsNoFrames() {
        let url = tempGIF()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: GIFEncodeError.self) {
            try ASCIIGIFEncoder().write([], loopCount: 0, to: url)
        }
    }

    @Test func nonFiniteAndNonPositiveDelaysNormalizeToDefault() throws {
        let url = tempGIF()
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = [Double.nan, -1, 0].map { RenderedGIFFrame(image: solid(10, 20, 30), delay: $0) }

        let report = try ASCIIGIFEncoder().write(frames, loopCount: 0, to: url)
        #expect(report.framesWritten == 3)
        #expect(report.subFloorDelayCount == 0)  // normalized 0.1s is not sub-floor
        #expect(abs(report.minDelay - 0.1) < 1e-6)

        let delays = try unclampedDelays(url)
        #expect(delays.allSatisfy { abs($0 - 0.1) < 0.005 })  // no written 0/neg/NaN
    }

    @Test func validSubFloorDelayIsWrittenRawAndCounted() throws {
        let url = tempGIF()
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = [
            RenderedGIFFrame(image: solid(255, 0, 0), delay: 0.01),  // valid but below 0.02 floor
            RenderedGIFFrame(image: solid(0, 255, 0), delay: 0.2),
        ]
        let report = try ASCIIGIFEncoder().write(frames, loopCount: 0, to: url)
        #expect(report.subFloorDelayCount == 1)
        #expect(abs(report.minDelay - 0.01) < 1e-6)

        let delays = try unclampedDelays(url)
        #expect(abs(delays[0] - 0.01) < 0.005)  // written RAW, not normalized
    }
}
