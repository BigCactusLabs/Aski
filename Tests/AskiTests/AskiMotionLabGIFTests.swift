import Aski
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AskiMotionLab

@Suite struct AskiMotionLabGIFTests {
    @Test func writesNonEmptyGifWithExpectedFrameCount() throws {
        let grid = DefaultConverter().convert(SyntheticImage.make(width: 16, height: 16), columns: 8)
        let frames = (0..<3).map { _ in
            RenderedGIFFrame(
                image: grid.renderImage(
                    font: .system(size: 10),
                    backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                    scale: 1
                ),
                delay: 0.1
            )
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AskiMotionLabGIFTests-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: url) }

        let report = try ASCIIGIFEncoder().write(frames, loopCount: 0, to: url)
        #expect(report.framesWritten == 3)

        #expect(FileManager.default.fileExists(atPath: url.path))
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        #expect(size > 0)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 3)
    }
}
