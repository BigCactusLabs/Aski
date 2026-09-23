import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Aski

@Suite struct AskiResampleGIFTests {
    /// Writes a GIF with `count` frames of `delayCentiseconds` each, returns its URL.
    private func makeGIF(count: Int, delayCentiseconds: Int, name: String) throws -> URL {
        let fixture = GIF89aFixture(
            canvasWidth: 8, canvasHeight: 8,
            colorTable: GIFFixturePalette.table, backgroundColorIndex: 3, netscapeLoop: 0,
            frames: (0..<count).map { i in
                .init(
                    left: 0, top: 0, width: 8, height: 8,
                    indices: [UInt8](repeating: UInt8(i % 4), count: 64),
                    delayCentiseconds: delayCentiseconds, disposal: 1)
            }
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).gif")
        try fixture.encode().write(to: url)
        return url
    }

    /// Re-decodes the output GIF's per-frame unclamped delays.
    private func decodedDelays(_ url: URL) -> [Double] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        return (0..<CGImageSourceGetCount(source)).map { index in
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            return (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? 0
        }
    }

    private func convert(_ source: URL, to output: URL, targetFPS: Int?) async throws -> GIFEncodeReport {
        try await convertGIF(
            at: source, to: output, using: DefaultConverter(),
            columns: 8, font: .system(size: 10),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1), scale: 1,
            targetFPS: targetFPS
        )
    }

    @Test func resampleTo60QuantizesTo50fpsAnd2cs() async throws {
        let source = try makeGIF(count: 3, delayCentiseconds: 10, name: "q60")  // 0.30s total
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("q60-out-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: output) }

        let report = try await convert(source, to: output, targetFPS: 60)
        let resample = try #require(report.resample)
        #expect(resample.requestedFPS == 60)
        #expect(abs(resample.achievedFPS - 50.0) < 1e-9)
        #expect(decodedDelays(output).allSatisfy { abs($0 - 0.02) < 0.005 })  // 2 cs
    }

    @Test func resampleTo24QuantizesTo25fpsAnd4cs() async throws {
        let source = try makeGIF(count: 3, delayCentiseconds: 10, name: "q24")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("q24-out-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: output) }

        let report = try await convert(source, to: output, targetFPS: 24)
        #expect(abs(try #require(report.resample).achievedFPS - 25.0) < 1e-9)
        #expect(decodedDelays(output).allSatisfy { abs($0 - 0.04) < 0.005 })  // 4 cs
    }

    @Test func highFpsTargetTripsSubFloorDelayCount() async throws {
        let source = try makeGIF(count: 3, delayCentiseconds: 10, name: "q120")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("q120-out-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: output) }

        let report = try await convert(source, to: output, targetFPS: 120)  // 1 cs -> 0.01s < 0.02s
        #expect(abs(try #require(report.resample).achievedFPS - 100.0) < 1e-9)
        #expect(report.subFloorDelayCount > 0)
    }

    @Test func passthroughPreservesFramesAndReportsNoResample() async throws {
        let source = try makeGIF(count: 3, delayCentiseconds: 10, name: "pass")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("pass-out-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: output) }

        let report = try await convert(source, to: output, targetFPS: nil)
        #expect(report.resample == nil)
        #expect(report.framesWritten == 3)
        #expect(decodedDelays(output).count == 3)
    }
}
