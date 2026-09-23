import ArgumentParser
import AskiToolSupport
import CoreGraphics
import Foundation
import Testing
@testable import Aski
@testable import AskiVideoLab

@Suite struct AskiVideoLabGIFTests {
    /// Builds a 3-frame animated-GIF source (variable delays 0.02s/0.2s/0.2s,
    /// infinite loop) via the byte-level fixture writer, runs the lab `.gif`
    /// branch, and asserts the artifacts + the GIF-specific CSV schema.
    @Test func gifBranchWritesAsciiGifMetricsAndManifest() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appending(path: "AskiVideoLabGIFTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let source = workDir.appendingPathComponent("source.gif")
        let fixture = GIF89aFixture(
            canvasWidth: 8, canvasHeight: 8,
            colorTable: GIFFixturePalette.table, backgroundColorIndex: 3, netscapeLoop: 0,
            frames: [
                .init(
                    left: 0, top: 0, width: 8, height: 8,
                    indices: [UInt8](repeating: 0, count: 64), delayCentiseconds: 2, disposal: 1),
                .init(
                    left: 0, top: 0, width: 8, height: 8,
                    indices: [UInt8](repeating: 1, count: 64), delayCentiseconds: 20, disposal: 1),
                .init(
                    left: 0, top: 0, width: 8, height: 8,
                    indices: [UInt8](repeating: 2, count: 64), delayCentiseconds: 20, disposal: 1),
            ]
        )
        try fixture.encode().write(to: source)

        let outputDir = workDir.appendingPathComponent("out")
        let command = try VideoLabCommand.parse([
            "--input", source.path,
            "--output-dir", outputDir.path,
            "--columns", "8",
            "--aski-git-sha", "test-sha",
        ])
        let status = await command.executeAsync(
            standardOutput: { _ in },
            standardError: { _ in },
            date: "2026-06-03"
        )

        #expect(status == .success)
        let fileManager = FileManager.default
        #expect(fileManager.fileExists(atPath: outputDir.appendingPathComponent("ascii.gif").path))
        #expect(fileManager.fileExists(atPath: outputDir.appendingPathComponent("metrics.csv").path))
        #expect(fileManager.fileExists(atPath: outputDir.appendingPathComponent("result.yaml").path))

        let csv = try String(contentsOf: outputDir.appendingPathComponent("metrics.csv"), encoding: .utf8)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        let header = lines[0].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(
            header == [
                "throughput_fps", "peak_memory_bytes", "frame_count",
                "loop_count", "delay_min_s", "delay_max_s", "delay_uniform",
                "input_descriptor", "max_frames",
                "target_fps", "achieved_fps", "source_frame_count",
                "output_frame_count", "dropped_count", "duplicated_count",
            ])
        let row = lines[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(row[2] == "3")  // frame_count
        #expect(row[3] == "0")  // loop_count (infinite preserved)
        #expect(row[6] == "false")  // delay_uniform (0.02 vs 0.2)

        // The output GIF re-decodes to 3 frames.
        var outFrames = 0
        for try await _ in ASCIIGIFDecoder().grids(
            fromGIFAt: outputDir.appendingPathComponent("ascii.gif"),
            transform: { _ in ASCIIGrid(cells: [], colorSpace: .sRGB) }
        ) {
            outFrames += 1
        }
        #expect(outFrames == 3)
    }

    /// Exercises the capped lab branch end-to-end: a 4-frame source with
    /// `--max-frames 2` must emit exactly 2 frames and report frame_count 2.
    /// (The precise decode-count guard lives in AskiGIFDecoderTests; this keeps
    /// the lab's capped wiring from rotting.)
    @Test func gifBranchRespectsMaxFramesCap() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appending(path: "AskiVideoLabGIFCapTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let source = workDir.appendingPathComponent("source.gif")
        let fixture = GIF89aFixture(
            canvasWidth: 8, canvasHeight: 8,
            colorTable: GIFFixturePalette.table, backgroundColorIndex: 3, netscapeLoop: 0,
            frames: (0..<4).map { i in
                .init(
                    left: 0, top: 0, width: 8, height: 8,
                    indices: [UInt8](repeating: UInt8(i % 4), count: 64),
                    delayCentiseconds: 10, disposal: 1)
            }
        )
        try fixture.encode().write(to: source)

        let outputDir = workDir.appendingPathComponent("out")
        let command = try VideoLabCommand.parse([
            "--input", source.path,
            "--output-dir", outputDir.path,
            "--columns", "8",
            "--max-frames", "2",
            "--aski-git-sha", "test-sha",
        ])
        let status = await command.executeAsync(
            standardOutput: { _ in },
            standardError: { _ in },
            date: "2026-06-03"
        )
        #expect(status == .success)

        let csv = try String(contentsOf: outputDir.appendingPathComponent("metrics.csv"), encoding: .utf8)
        let row = csv.split(separator: "\n")[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(row[2] == "2")  // frame_count capped
        #expect(row[8] == "2")  // max_frames column

        var outFrames = 0
        for try await _ in ASCIIGIFDecoder().grids(
            fromGIFAt: outputDir.appendingPathComponent("ascii.gif"),
            transform: { _ in ASCIIGrid(cells: [], colorSpace: .sRGB) }
        ) {
            outFrames += 1
        }
        #expect(outFrames == 2)
    }

    /// The spec headline: a 4-frame 0.1s GIF capped to 2 (span 0.2s) resampled to
    /// 30 fps must emit ceil(0.2 * 30) = 6 frames over the CAPPED span, not 12.
    @Test func gifCappedResampleEmitsCappedSpanFrames() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appending(path: "AskiVideoLabGIFResampleTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let source = workDir.appendingPathComponent("source.gif")
        let fixture = GIF89aFixture(
            canvasWidth: 8, canvasHeight: 8,
            colorTable: GIFFixturePalette.table, backgroundColorIndex: 3, netscapeLoop: 0,
            frames: (0..<4).map { i in
                .init(
                    left: 0, top: 0, width: 8, height: 8,
                    indices: [UInt8](repeating: UInt8(i % 4), count: 64),
                    delayCentiseconds: 10, disposal: 1)
            }
        )
        try fixture.encode().write(to: source)

        let outputDir = workDir.appendingPathComponent("out")
        let command = try VideoLabCommand.parse([
            "--input", source.path, "--output-dir", outputDir.path,
            "--columns", "8", "--max-frames", "2", "--target-fps", "30",
            "--aski-git-sha", "test-sha",
        ])
        let status = await command.executeAsync(
            standardOutput: { _ in }, standardError: { _ in }, date: "2026-06-04"
        )
        #expect(status == .success)

        let csv = try String(contentsOf: outputDir.appendingPathComponent("metrics.csv"), encoding: .utf8)
        let row = csv.split(separator: "\n")[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(row[2] == "6")  // frame_count = output
        #expect(row[9] == "30")  // target_fps
        #expect(row[11] == "2")  // source_frame_count (capped)
        #expect(row[12] == "6")  // output_frame_count

        var outFrames = 0
        for try await _ in ASCIIGIFDecoder().grids(
            fromGIFAt: outputDir.appendingPathComponent("ascii.gif"),
            transform: { _ in ASCIIGrid(cells: [], colorSpace: .sRGB) }
        ) { outFrames += 1 }
        #expect(outFrames == 6)
    }

    @Test func gifFrameBudgetRejectsOversizedUncappedInput() throws {
        let frameCount = ToolArgumentBounds.maxVideoFrames + 1

        #expect {
            try VideoLabCLI.validateGIFFrameBudget(frameCount: frameCount, maxFrames: nil)
        } throws: { error in
            guard case VideoLabRunError.uncappedGIFFrameCountExceedsLimit(let count, let limit) = error else {
                return false
            }
            return count == frameCount && limit == ToolArgumentBounds.maxVideoFrames
        }
    }

    @Test func gifFrameBudgetAllowsExplicitMaxFramesCapOnOversizedInput() throws {
        try VideoLabCLI.validateGIFFrameBudget(
            frameCount: ToolArgumentBounds.maxVideoFrames + 1,
            maxFrames: 60
        )
    }
}
