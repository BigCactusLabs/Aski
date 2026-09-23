import AVFoundation
import ArgumentParser
import AskiToolSupport
import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import Aski
@testable import AskiVideoLab
@testable import BuildResearchIndex

@Suite struct AskiVideoLabCLITests {
    @Test func runWritesAsciiMp4MetricsAndManifest() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appending(path: "AskiVideoLabCLITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // Fabricate a tiny source MP4 with the encoder.
        let source = workDir.appendingPathComponent("source.mp4")
        let sourceFrames = (0..<5).map { index in
            RenderedVideoFrame(
                image: makeGray(level: UInt8(40 + index * 30), width: 64, height: 48),
                time: CMTime(value: Int64(index), timescale: 5)
            )
        }
        try await ASCIIVideoEncoder().write(stream(sourceFrames), to: source, options: VideoExportOptions())

        let outputDir = workDir.appendingPathComponent("out")
        let command = try VideoLabCommand.parse([
            "--input", source.path,
            "--output-dir", outputDir.path,
            "--columns", "24",
            "--codec", "h264",
            "--max-frames", "5",
            "--aski-git-sha", "test-sha",
        ])
        let status = await command.executeAsync(
            standardOutput: { _ in },
            standardError: { _ in },
            date: "2026-06-02"
        )

        #expect(status == .success)
        let fileManager = FileManager.default
        #expect(fileManager.fileExists(atPath: outputDir.appendingPathComponent("ascii.mp4").path))
        #expect(fileManager.fileExists(atPath: outputDir.appendingPathComponent("metrics.csv").path))
        #expect(fileManager.fileExists(atPath: outputDir.appendingPathComponent("result.yaml").path))
    }

    @Test func mp4RerunReplacesExistingAsciiMP4() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appending(path: "AskiVideoLabMP4RerunTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let source = workDir.appendingPathComponent("source.mp4")
        let sourceFrames = (0..<3).map { index in
            RenderedVideoFrame(
                image: makeGray(level: UInt8(50 + index * 40), width: 64, height: 48),
                time: CMTime(value: Int64(index), timescale: 3)
            )
        }
        try await ASCIIVideoEncoder().write(stream(sourceFrames), to: source, options: VideoExportOptions())

        let outputDir = workDir.appendingPathComponent("out")
        let arguments = [
            "--input", source.path,
            "--output-dir", outputDir.path,
            "--columns", "24",
            "--codec", "h264",
            "--max-frames", "3",
            "--aski-git-sha", "test-sha",
        ]

        let command = try VideoLabCommand.parse(arguments)
        let first = await command.executeAsync(
            standardOutput: { _ in },
            standardError: { _ in },
            date: "2026-06-04"
        )
        let second = await command.executeAsync(
            standardOutput: { _ in },
            standardError: { _ in },
            date: "2026-06-04"
        )

        #expect(first == .success)
        #expect(second == .success)
        let output = outputDir.appendingPathComponent("ascii.mp4")
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(try await countFrames(in: output) == 3)
    }

    @Test func mp4TargetFPSDownsamplesAndRecordsResampleColumns() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appending(path: "AskiVideoLabMP4ResampleTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // 8 frames at timescale 8 (~1s) -> 4 fps downsample.
        let source = workDir.appendingPathComponent("source.mp4")
        let sourceFrames = (0..<8).map { index in
            RenderedVideoFrame(
                image: makeGray(level: UInt8(20 + index * 20), width: 64, height: 48),
                time: CMTime(value: Int64(index), timescale: 8)
            )
        }
        try await ASCIIVideoEncoder().write(stream(sourceFrames), to: source, options: VideoExportOptions())

        let outputDir = workDir.appendingPathComponent("out")
        let command = try VideoLabCommand.parse([
            "--input", source.path, "--output-dir", outputDir.path,
            "--columns", "24", "--target-fps", "4", "--aski-git-sha", "test-sha",
        ])
        let status = await command.executeAsync(
            standardOutput: { _ in }, standardError: { _ in }, date: "2026-06-04"
        )
        #expect(status == .success)

        let csv = try String(contentsOf: outputDir.appendingPathComponent("metrics.csv"), encoding: .utf8)
        let row = csv.split(separator: "\n")[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(row[6] == "4")  // target_fps
        #expect(Int(row[9])! < Int(row[8])!)  // output_frame_count < source_frame_count
        #expect(row[2] == row[9])  // frame_count == output_frame_count
    }

    @Test func unsafeInputBasenameDoesNotCorruptMetricsOrManifest() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appending(path: "AskiVideoLabUnsafeMetadataTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let source = workDir.appendingPathComponent("source\ncomma,\"quote\".mp4")
        try await writeTinySourceMP4(to: source)

        let outputDir = workDir.appendingPathComponent("out")
        let command = try VideoLabCommand.parse([
            "--input", source.path,
            "--output-dir", outputDir.path,
            "--columns", "24",
            "--codec", "h264",
            "--max-frames", "2",
            "--aski-git-sha", "test: #sha",
        ])
        let status = await command.executeAsync(
            standardOutput: { _ in },
            standardError: { _ in },
            date: "2026-06-03"
        )

        #expect(status == .success)

        let csv = try String(contentsOf: outputDir.appendingPathComponent("metrics.csv"), encoding: .utf8)
        let records = parseCSVRecords(csv)
        #expect(records.count == 2)
        #expect(
            records[0] == [
                "throughput_fps", "peak_memory_bytes", "frame_count", "codec",
                "input_descriptor", "max_frames",
                "target_fps", "achieved_fps", "source_frame_count",
                "output_frame_count", "dropped_count", "duplicated_count",
            ])
        #expect(records[1][4] == source.lastPathComponent)

        let manifestText = try String(contentsOf: outputDir.appendingPathComponent("result.yaml"), encoding: .utf8)
        let manifest = try ResultManifest.from(try FrontMatterParser.parse(manifestText))
        #expect(manifest.runner == "AskiVideoLab")
        #expect(manifest.askiGitSha == "test: #sha")
        #expect(manifest.command?.contains(source.path) == true)
    }

    @Test func unsupportedManifestMetadataFailsBeforeWritingArtifacts() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appending(path: "AskiVideoLabUnsupportedMetadataTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let source = workDir.appendingPathComponent("source\u{1}.mp4")
        try await writeTinySourceMP4(to: source)

        let outputDir = workDir.appendingPathComponent("out")
        let stderr = SendableStringSink()
        let command = try VideoLabCommand.parse([
            "--input", source.path,
            "--output-dir", outputDir.path,
            "--columns", "24",
            "--codec", "h264",
            "--max-frames", "2",
            "--aski-git-sha", "test-sha",
        ])
        let status = await command.executeAsync(
            standardOutput: { _ in },
            standardError: { stderr.append($0) },
            date: "2026-06-03"
        )

        #expect(status == .usage)
        #expect(stderr.text.contains("unsupported control character"))
        #expect(!FileManager.default.fileExists(atPath: outputDir.path))
    }

    private final class SendableStringSink: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = ""

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func append(_ value: String) {
            lock.lock()
            defer { lock.unlock() }
            storage += value
        }
    }

    // Local helpers (kept separate from AskiVideoLoopTests to avoid cross-file coupling).
    private func makeGray(level: UInt8, width: Int, height: Int) -> CGImage {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        for pixel in 0..<(width * height) {
            buffer[pixel * 4 + 0] = level
            buffer[pixel * 4 + 1] = level
            buffer[pixel * 4 + 2] = level
            buffer[pixel * 4 + 3] = 255
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data(buffer) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    private func stream(_ frames: [RenderedVideoFrame]) -> AsyncThrowingStream<RenderedVideoFrame, Error> {
        AsyncThrowingStream { continuation in
            for frame in frames { continuation.yield(frame) }
            continuation.finish()
        }
    }

    private func writeTinySourceMP4(to url: URL) async throws {
        let frames = (0..<2).map { index in
            RenderedVideoFrame(
                image: makeGray(level: UInt8(60 + index * 80), width: 64, height: 48),
                time: CMTime(value: Int64(index), timescale: 2)
            )
        }
        try await ASCIIVideoEncoder().write(stream(frames), to: url, options: VideoExportOptions())
    }

    private func countFrames(in url: URL) async throws -> Int {
        var count = 0
        for try await _ in ASCIIVideoDecoder().grids(
            fromVideoAt: url,
            transform: { _ in ASCIIGrid(cells: [], colorSpace: .sRGB) }
        ) {
            count += 1
        }
        return count
    }

    private func parseCSVRecords(_ csv: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = csv.makeIterator()

        while let character = iterator.next() {
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            if next == "," {
                                record.append(field)
                                field = ""
                            } else if next == "\n" {
                                record.append(field)
                                field = ""
                                records.append(record)
                                record = []
                            } else {
                                field.append(next)
                            }
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                case ",":
                    record.append(field)
                    field = ""
                case "\n":
                    record.append(field)
                    field = ""
                    records.append(record)
                    record = []
                default:
                    field.append(character)
                }
            }
        }

        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records
    }
}

@Suite struct AskiVideoLabArgumentsTests {
    private let base = ["--input", "clip.mp4", "--output-dir", "/tmp/out"]

    @Test func parsesValidArguments() throws {
        let command = try VideoLabCommand.parse(base + ["--columns", "40", "--codec", "hevc", "--font-scale", "1.5", "--max-frames", "30"])
        #expect(command.columns == 40)
        #expect(command.codec == .hevc)
        #expect(command.fontScale == 1.5)
        #expect(command.maxFrames == 30)
    }

    @Test func parsesTargetFPS() throws {
        #expect(try VideoLabCommand.parse(base + ["--target-fps", "24"]).targetFPS == 24)
    }

    @Test func absentTargetFPSIsNil() throws {
        #expect(try VideoLabCommand.parse(base).targetFPS == nil)
    }

    @Test(arguments: ["0", "-1", "abc"])
    func rejectsNonPositiveTargetFPS(_ value: String) {
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--target-fps", value]) }
    }

    @Test func rejectsTargetFPSAboveCap() {
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--target-fps", "\(maxTargetFPS + 1)"]) }
    }

    @Test func requiresInputAndOutputDir() {
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(["--output-dir", "/tmp/out"]) }
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(["--input", "clip.mp4"]) }
    }

    @Test(arguments: ["0", "-1", "abc"])
    func rejectsNonPositiveColumns(_ value: String) {
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--columns", value]) }
    }

    @Test func rejectsAbsurdColumnsBeforeAllocation() {
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--columns", "9223372036854775807"]) }
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--columns", "513"]) }
    }

    @Test(arguments: ["0", "-1", "abc"])
    func rejectsNonPositiveMaxFrames(_ value: String) {
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--max-frames", value]) }
    }

    @Test func rejectsAbsurdMaxFramesBeforeRendering() {
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--max-frames", "10001"]) }
    }

    @Test(arguments: ["0", "-0.5", "nan", "inf", "abc"])
    func rejectsNonPositiveOrNonFiniteFontScale(_ value: String) {
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--font-scale", value]) }
    }

    @Test func rejectsAbsurdFontScaleBeforeRendering() {
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--font-scale", "9"]) }
    }

    @Test func rejectsUnknownCodec() {
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--codec", "av1"]) }
    }

    @Test func parsesQualityLevers() throws {
        let command = try VideoLabCommand.parse(
            base + [
                "--charset", "blocks", "--oversample", "4",
                "--brightness", "0.2", "--contrast", "-0.1",
                "--density", "0.5", "--edge-emphasis", "0.3",
            ])
        #expect(command.charset == .blocks)
        #expect(command.oversample == 4)
        #expect(command.brightness == 0.2)
        #expect(command.contrast == -0.1)
        #expect(command.density == 0.5)
        #expect(command.edgeEmphasis == 0.3)
    }

    @Test func qualityLeverDefaultsPreserveCurrentBehavior() throws {
        let command = try VideoLabCommand.parse(base)
        #expect(command.charset == .standard)
        #expect(command.oversample == ToolArgumentBounds.defaultOversample)
        #expect(command.brightness == 0)
        #expect(command.contrast == 0)
        #expect(command.density == 0)
        #expect(command.edgeEmphasis == 0)
    }

    @Test func rejectsUnknownCharset() {
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--charset", "nope"]) }
    }

    @Test(arguments: ["0", "-1", "abc", "\(ToolArgumentBounds.maxOversample + 1)"])
    func rejectsInvalidOversample(_ value: String) {
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--oversample", value]) }
    }

    @Test(arguments: ["nan", "inf", "-inf"])
    func rejectsNonFiniteTonalLevers(_ value: String) {
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--brightness", value]) }
    }
}

@Suite struct AskiVideoLabCappedSpanTests {
    @Test func usesPrefixSpanForKnownFrameRate() throws {
        // 60 frames at 30 fps -> 2.0 s capped span (NOT the full 10 s track).
        #expect(try cappedVideoSourceSpan(trackDuration: 10.0, nominalFrameRate: 30, limit: 60) == 2.0)
    }

    @Test func clampsToTrackDurationWhenCapExceedsClip() throws {
        // N / fps (2.0 s) exceeds a 1.0 s clip -> clamp to the track duration.
        #expect(try cappedVideoSourceSpan(trackDuration: 1.0, nominalFrameRate: 30, limit: 60) == 1.0)
    }

    @Test func throwsWhenFrameRateUnavailableInsteadOfUsingFullDuration() {
        // The bug guard: a 0 nominal fps must THROW, not fall back to trackDuration
        // (which would duplicate the last capped frame across the whole asset).
        #expect(throws: VideoLabRunError.self) {
            _ = try cappedVideoSourceSpan(trackDuration: 10.0, nominalFrameRate: 0, limit: 60)
        }
    }
}

@Suite struct AskiVideoLabConverterTests {
    private func arguments(
        charset: Charset = .standard,
        oversample: Int = ToolArgumentBounds.defaultOversample,
        brightness: Double = 0,
        contrast: Double = 0,
        density: Double = 0,
        edgeEmphasis: Double = 0
    ) -> VideoLabArguments {
        VideoLabArguments(
            inputPath: "clip.mp4", outputDirectory: "/tmp/out", columns: 80,
            codec: .h264, fontScale: 1, maxFrames: nil, targetFPS: nil,
            gitShaOverride: nil, charset: charset, oversample: oversample,
            brightness: brightness, contrast: contrast, density: density, edgeEmphasis: edgeEmphasis
        )
    }

    @Test func carriesLeversIntoConverter() {
        let converter = VideoLabCLI.makeConverter(
            from: arguments(
                charset: .blocks, oversample: 4,
                brightness: 0.2, contrast: -0.1, density: 0.5, edgeEmphasis: 0.3
            ))
        #expect(converter.oversample == 4)
        #expect(converter.options.brightness == Float(0.2))
        #expect(converter.options.contrast == Float(-0.1))
        #expect(converter.options.density == Float(0.5))
        #expect(converter.options.edgeEmphasis == Float(0.3))
        #expect(converter.characterSet.characters == StandardCharacterSet.blocks.characters)
    }

    @Test func defaultsMatchDefaultConverter() {
        let converter = VideoLabCLI.makeConverter(from: arguments())
        let reference = DefaultConverter()
        #expect(converter.oversample == reference.oversample)
        #expect(converter.options.brightness == reference.options.brightness)
        #expect(converter.options.contrast == reference.options.contrast)
        #expect(converter.options.density == reference.options.density)
        #expect(converter.options.edgeEmphasis == reference.options.edgeEmphasis)
        #expect(converter.characterSet.characters == reference.characterSet.characters)
    }
}
