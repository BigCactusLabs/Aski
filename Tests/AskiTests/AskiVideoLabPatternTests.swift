import ArgumentParser
import AskiToolSupport
import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import Aski
@testable import AskiVideoLab

@Suite struct AskiVideoLabPatternArgumentsTests {
    private let base = ["--input", "clip.mp4", "--output-dir", "/tmp/out"]

    @Test func absentPatternResolvesToNil() throws {
        #expect(try VideoLabCommand.parse(base).resolvedPattern == nil)
    }

    @Test func parsesWavePatternWithKnobs() throws {
        let command = try VideoLabCommand.parse(
            base + ["--pattern", "wave", "--pattern-amplitude", "0.3", "--pattern-frequency", "2"])
        #expect(command.resolvedPattern == .wave(amplitude: 0.3, frequency: 2, direction: .horizontal))
    }

    @Test func parsesPulsePatternWithKnobs() throws {
        let command = try VideoLabCommand.parse(
            base + ["--pattern", "pulse", "--pattern-period", "2", "--pattern-depth", "0.5"])
        #expect(command.resolvedPattern == .pulse(period: 2, depth: 0.5))
    }

    @Test func rejectsUnknownPattern() {
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--pattern", "spiral"]) }
    }

    // Finding #2: `--pattern-frequency`/`--pattern-period` hit hard `precondition`s
    // in `PatternEvaluator.ongoingAlpha`, so a non-finite or non-positive value
    // must be rejected at parse time, not trapped at render time.
    @Test(arguments: ["0", "nan", "inf"])
    func rejectsNonPositiveOrNonFiniteFrequency(_ value: String) {
        #expect(throws: (any Error).self) {
            try VideoLabCommand.parse(base + ["--pattern-frequency", value])
        }
    }

    @Test(arguments: ["0", "nan", "inf"])
    func rejectsNonPositiveOrNonFinitePeriod(_ value: String) {
        #expect(throws: (any Error).self) {
            try VideoLabCommand.parse(base + ["--pattern-period", value])
        }
    }
}

@Suite struct ASCIIVideoFramePatternTests {
    private func grid() -> ASCIIGrid {
        let cell = ASCIICell(
            character: "X", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.9, coverage: 1)
        return ASCIIGrid(cells: [[cell, cell]], colorSpace: .sRGB)
    }

    @Test func appliesPatternAtPresentationTimeAndPreservesTimestamp() {
        let t = CMTime(value: 1, timescale: 2)  // 0.5s
        let frame = ASCIIVideoFrame(grid: grid(), time: t)
        // pulse(period: 1, depth: 1) at t = 0.5 evaluates to a 0 multiplier.
        let out = frame.applyingOngoingPattern(.pulse(period: 1, depth: 1))
        #expect(out.time == t)
        #expect(out.grid.cells.flatMap { $0 }.allSatisfy { $0.alpha == 0 })
    }

    @Test func nilPatternIsIdentity() {
        let frame = ASCIIVideoFrame(grid: grid(), time: .zero)
        #expect(frame.applyingOngoingPattern(nil).grid.cells == frame.grid.cells)
    }
}

/// End-to-end coverage that the pattern overlay actually reaches the rendered
/// output on every AskiVideoLab path. Each test runs the same source twice —
/// once plain, once with a depth-1 pulse — and asserts the patterned output is
/// dimmer (alpha modulated against the black background). A path that forgot to
/// thread the pattern would produce identical brightness and fail here; this is
/// the guard for the four-path-drift risk in the design.
@Suite struct AskiVideoLabPatternE2ETests {
    // Strong, spatially uniform overlay so the mean-brightness drop is large
    // relative to codec noise.
    private let dimming = ["--pattern", "pulse", "--pattern-depth", "1", "--pattern-period", "0.3"]

    @Test func cappedMP4PatternDimsAndPreservesFrameCount() async throws {
        try await withTempDir { dir in
            let source = dir.appendingPathComponent("source.mp4")
            try await writeSourceMP4(to: source, frames: 6)

            let plain = try await runMP4(source: source, dir: dir, name: "plain", extra: ["--max-frames", "6"])
            let lit = try await runMP4(source: source, dir: dir, name: "lit", extra: ["--max-frames", "6"] + dimming)

            #expect(try await countVideoFrames(plain) == 6)
            #expect(try await countVideoFrames(lit) == 6)
            #expect(try await meanVideoBrightness(lit, columns: 16) < meanVideoBrightness(plain, columns: 16) * 0.95)
        }
    }

    @Test func uncappedMP4PatternDimsOutput() async throws {
        try await withTempDir { dir in
            let source = dir.appendingPathComponent("source.mp4")
            try await writeSourceMP4(to: source, frames: 6)

            let plain = try await runMP4(source: source, dir: dir, name: "plain", extra: [])
            let lit = try await runMP4(source: source, dir: dir, name: "lit", extra: dimming)

            #expect(try await meanVideoBrightness(lit, columns: 16) < meanVideoBrightness(plain, columns: 16) * 0.95)
        }
    }

    @Test func resampleMP4PatternDimsOutput() async throws {
        try await withTempDir { dir in
            let source = dir.appendingPathComponent("source.mp4")
            try await writeSourceMP4(to: source, frames: 6)

            let plain = try await runMP4(source: source, dir: dir, name: "plain", extra: ["--target-fps", "8"])
            let lit = try await runMP4(source: source, dir: dir, name: "lit", extra: ["--target-fps", "8"] + dimming)

            #expect(try await meanVideoBrightness(lit, columns: 16) < meanVideoBrightness(plain, columns: 16) * 0.95)
        }
    }

    @Test func gifPatternDimsAndPreservesFrameCount() async throws {
        try await withTempDir { dir in
            let source = dir.appendingPathComponent("source.gif")
            try makeSourceGIF(to: source)

            let plain = try await runGIF(source: source, dir: dir, name: "plain", extra: [])
            let lit = try await runGIF(source: source, dir: dir, name: "lit", extra: dimming)

            #expect(try await countGIFFrames(plain) == 3)
            #expect(try await countGIFFrames(lit) == 3)
            #expect(try await meanGIFBrightness(lit, columns: 8) < meanGIFBrightness(plain, columns: 8) * 0.95)
        }
    }

    @Test func defaultRunOmitsPatternFromManifest() async throws {
        try await withTempDir { dir in
            let source = dir.appendingPathComponent("source.mp4")
            try await writeSourceMP4(to: source, frames: 3)
            let out = try await runMP4(source: source, dir: dir, name: "out", extra: ["--max-frames", "3"])
            let yaml = try String(contentsOf: out.deletingLastPathComponent().appendingPathComponent("result.yaml"), encoding: .utf8)
            #expect(!yaml.contains("--pattern"))
        }
    }

    @Test func wavePatternRecordedInManifest() async throws {
        try await withTempDir { dir in
            let source = dir.appendingPathComponent("source.mp4")
            try await writeSourceMP4(to: source, frames: 3)
            let out = try await runMP4(
                source: source, dir: dir, name: "out",
                extra: ["--max-frames", "3", "--pattern", "wave"])
            let yaml = try String(contentsOf: out.deletingLastPathComponent().appendingPathComponent("result.yaml"), encoding: .utf8)
            #expect(yaml.contains("--pattern wave"))
        }
    }

    // MARK: - Harness

    private func withTempDir(_ body: (URL) async throws -> Void) async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "AskiVideoLabPatternE2E-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir)
    }

    /// Runs the lab into `dir/name` and returns the `ascii.mp4` URL.
    private func runMP4(source: URL, dir: URL, name: String, extra: [String]) async throws -> URL {
        let outDir = dir.appendingPathComponent(name)
        let command = try VideoLabCommand.parse(
            ["--input", source.path, "--output-dir", outDir.path, "--columns", "16", "--aski-git-sha", "test-sha"] + extra)
        let status = await command.executeAsync(standardOutput: { _ in }, standardError: { _ in }, date: "2026-06-23")
        #expect(status == .success)
        return outDir.appendingPathComponent("ascii.mp4")
    }

    private func runGIF(source: URL, dir: URL, name: String, extra: [String]) async throws -> URL {
        let outDir = dir.appendingPathComponent(name)
        let command = try VideoLabCommand.parse(
            ["--input", source.path, "--output-dir", outDir.path, "--columns", "8", "--aski-git-sha", "test-sha"] + extra)
        let status = await command.executeAsync(standardOutput: { _ in }, standardError: { _ in }, date: "2026-06-23")
        #expect(status == .success)
        return outDir.appendingPathComponent("ascii.gif")
    }

    private func writeSourceMP4(to url: URL, frames: Int) async throws {
        let rendered = (0..<frames).map { index in
            RenderedVideoFrame(
                image: makeGray(level: 230, width: 64, height: 48),
                time: CMTime(value: Int64(index), timescale: Int32(frames)))
        }
        try await ASCIIVideoEncoder().write(stream(rendered), to: url, options: VideoExportOptions())
    }

    private func makeSourceGIF(to url: URL) throws {
        let fixture = GIF89aFixture(
            canvasWidth: 8, canvasHeight: 8,
            colorTable: GIFFixturePalette.table, backgroundColorIndex: 3, netscapeLoop: 0,
            frames: (0..<3).map { i in
                .init(
                    left: 0, top: 0, width: 8, height: 8,
                    indices: [UInt8](repeating: UInt8(i % 3), count: 64),  // 0/1/2 = red/green/blue
                    delayCentiseconds: 10, disposal: 1)
            })
        try fixture.encode().write(to: url)
    }

    private func meanVideoBrightness(_ url: URL, columns: Int) async throws -> Double {
        let converter = DefaultConverter()
        var sum = 0.0
        var count = 0
        for try await frame in ASCIIVideoDecoder().grids(
            fromVideoAt: url, transform: { converter.convert($0, columns: columns) }
        ) {
            for line in frame.grid.cells {
                for cell in line {
                    sum += Double(cell.brightness)
                    count += 1
                }
            }
        }
        return count > 0 ? sum / Double(count) : 0
    }

    private func meanGIFBrightness(_ url: URL, columns: Int) async throws -> Double {
        let converter = DefaultConverter()
        var sum = 0.0
        var count = 0
        for try await frame in ASCIIGIFDecoder().grids(
            fromGIFAt: url, transform: { converter.convert($0, columns: columns) }
        ) {
            for line in frame.grid.cells {
                for cell in line {
                    sum += Double(cell.brightness)
                    count += 1
                }
            }
        }
        return count > 0 ? sum / Double(count) : 0
    }

    private func countVideoFrames(_ url: URL) async throws -> Int {
        var count = 0
        for try await _ in ASCIIVideoDecoder().grids(
            fromVideoAt: url, transform: { _ in ASCIIGrid(cells: [], colorSpace: .sRGB) }
        ) { count += 1 }
        return count
    }

    private func countGIFFrames(_ url: URL) async throws -> Int {
        var count = 0
        for try await _ in ASCIIGIFDecoder().grids(
            fromGIFAt: url, transform: { _ in ASCIIGrid(cells: [], colorSpace: .sRGB) }
        ) { count += 1 }
        return count
    }

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
}
