import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Aski

@Suite struct AskiGIFConverterTests {
    private func write(_ fixture: GIF89aFixture) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AskiGIFConverterTests-src-\(UUID().uuidString).gif")
        try fixture.encode().write(to: url)
        return url
    }

    private func tempOutput() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AskiGIFConverterTests-out-\(UUID().uuidString).gif")
    }

    private func convert(_ source: URL, to output: URL, loopCount: Int? = nil) async throws -> GIFEncodeReport {
        try await convertGIF(
            at: source,
            to: output,
            using: DefaultConverter(),
            columns: 4,
            font: .system(size: 10),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1,
            loopCount: loopCount
        )
    }

    private func decodedDelays(_ url: URL) async throws -> [TimeInterval] {
        var delays: [TimeInterval] = []
        for try await frame in ASCIIGIFDecoder().grids(
            fromGIFAt: url,
            transform: { _ in ASCIIGrid(cells: [], colorSpace: .sRGB) }
        ) {
            delays.append(frame.delay)
        }
        return delays
    }

    private func variableDelayFixture(loop: Int?) -> GIF89aFixture {
        GIF89aFixture(
            canvasWidth: 8, canvasHeight: 8,
            colorTable: GIFFixturePalette.table, backgroundColorIndex: 3, netscapeLoop: loop,
            frames: [
                .init(
                    left: 0, top: 0, width: 8, height: 8,
                    indices: [UInt8](repeating: 0, count: 64), delayCentiseconds: 2, disposal: 1),
                .init(
                    left: 0, top: 0, width: 8, height: 8,
                    indices: [UInt8](repeating: 1, count: 64), delayCentiseconds: 20, disposal: 1),
            ]
        )
    }

    /// Per-frame UNCLAMPED delays survive decode -> encode -> re-decode.
    @Test func timingRoundTripPreservesPerFrameDelays() async throws {
        let source = try write(variableDelayFixture(loop: 0))
        let output = tempOutput()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }

        // Decode side: unclamped survives (0.02s, not 0.1s).
        let inputDelays = try await decodedDelays(source)
        #expect(inputDelays.count == 2)
        #expect(abs(inputDelays[0] - 0.02) < 0.005)
        #expect(abs(inputDelays[1] - 0.2) < 0.005)

        _ = try await convert(source, to: output)

        let outputDelays = try await decodedDelays(output)
        #expect(outputDelays.count == 2)
        #expect(abs(outputDelays[0] - 0.02) < 0.005)
        #expect(abs(outputDelays[1] - 0.2) < 0.005)
    }

    /// Loop-count preservation: absent -> 1 (once), 0 -> 0 (infinite), finite stable.
    /// Comparison is reported-to-reported (via ImageIO read on both sides), which is
    /// robust to the raw-Netscape N->N+1 read quirk.
    @Test(arguments: [
        (nil as Int?, 1),  // absent Netscape extension reads as play-once
        (0, 0),  // explicit infinite stays infinite
        (3, 4),  // raw Netscape 3 reads as 4 plays; must round-trip as 4
    ])
    func loopCountRoundTripPreservesReportedValue(rawLoop: Int?, expectedReported: Int) async throws {
        let source = try write(variableDelayFixture(loop: rawLoop))
        let output = tempOutput()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }

        let sourceInfo = try ASCIIGIFDecoder().containerInfo(ofGIFAt: source)
        #expect(sourceInfo.loopCount == expectedReported)

        let report = try await convert(source, to: output)  // loopCount nil => preserve
        #expect(report.loopCount == expectedReported)

        let outputInfo = try ASCIIGIFDecoder().containerInfo(ofGIFAt: output)
        #expect(outputInfo.loopCount == expectedReported)  // stable on round-trip
    }

    @Test func convertGIFRejectsSourceOverMaximumFrameCountBeforeRendering() async throws {
        let source = try write(variableDelayFixture(loop: 0))
        let output = tempOutput()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }

        await #expect {
            try await convertGIF(
                at: source,
                to: output,
                using: DefaultConverter(),
                columns: 4,
                font: .system(size: 10),
                backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                scale: 1,
                maximumFrameCount: 1
            )
        } throws: { error in
            guard case GIFDecodeError.frameCountExceedsLimit(let count, let limit) = error else {
                return false
            }
            return count == 2 && limit == 1
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}
