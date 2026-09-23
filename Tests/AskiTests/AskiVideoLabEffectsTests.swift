import ArgumentParser
import AskiToolSupport
import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import Aski
@testable import AskiVideoLab

/// Parse-level coverage for the cosmetic post-render effect flags (ASTSK-39
/// step b). `resolvedEffects` is a pure function of the flags, so these are fast
/// and exhaustive — the E2E suite below only has to prove the chain reaches the
/// rendered output on every path.
@Suite struct AskiVideoLabEffectsArgumentsTests {
    private let base = ["--input", "clip.mp4", "--output-dir", "/tmp/out"]

    @Test func absentEffectsResolveToEmptyChain() throws {
        #expect(try VideoLabCommand.parse(base).resolvedEffects.effects.isEmpty)
    }

    @Test func parsesBloomWithRadius() throws {
        let command = try VideoLabCommand.parse(base + ["--bloom", "0.4", "--bloom-radius", "8"])
        #expect(command.resolvedEffects.effects == [.bloom(intensity: 0.4, radius: 8)])
    }

    @Test func bloomUsesDefaultRadiusWhenOmitted() throws {
        let command = try VideoLabCommand.parse(base + ["--bloom", "0.5"])
        #expect(command.resolvedEffects.effects == [.bloom(intensity: 0.5, radius: ToolArgumentBounds.defaultBloomRadius)])
    }

    @Test func parsesScanlinesWithFrequency() throws {
        let command = try VideoLabCommand.parse(base + ["--scanlines", "0.5", "--scanline-frequency", "12"])
        #expect(command.resolvedEffects.effects == [.scanLines(intensity: 0.5, frequency: 12)])
    }

    @Test func parsesVignette() throws {
        let command = try VideoLabCommand.parse(base + ["--vignette", "0.6"])
        #expect(command.resolvedEffects.effects == [.vignette(intensity: 0.6)])
    }

    // Order is fixed bloom → scanlines → vignette regardless of flag order on the
    // command line: bloom softens glyph edges first, the CRT composite lands last.
    @Test func composesEffectsInCanonicalOrder() throws {
        let command = try VideoLabCommand.parse(
            base + ["--vignette", "0.5", "--bloom", "0.3", "--scanlines", "0.4"])
        let expected: [Effect] = [
            .bloom(intensity: 0.3, radius: ToolArgumentBounds.defaultBloomRadius),
            .scanLines(intensity: 0.4, frequency: ToolArgumentBounds.defaultScanlineFrequency),
            .vignette(intensity: 0.5),
        ]
        #expect(command.resolvedEffects.effects == expected)
    }

    @Test func zeroIntensityOmitsEffect() throws {
        // A zero intensity keeps the effect out of the chain so the render path
        // stays on the plain renderer (byte-identical to today).
        #expect(try VideoLabCommand.parse(base + ["--bloom", "0"]).resolvedEffects.effects.isEmpty)
    }

    @Test func clampsIntensityAboveOne() throws {
        let command = try VideoLabCommand.parse(base + ["--vignette", "5"])
        #expect(command.resolvedEffects.effects == [.vignette(intensity: 1)])
    }

    @Test(arguments: ["nan", "inf"])
    func rejectsNonFiniteIntensity(_ value: String) {
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--bloom", value]) }
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--scanlines", value]) }
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--vignette", value]) }
    }

    // Radius/frequency reach `CIBloom` / the scanlines kernel directly, where a
    // non-finite or non-positive value would misbehave — reject at parse time.
    @Test(arguments: ["0", "nan", "inf"])
    func rejectsNonPositiveOrNonFiniteBloomRadius(_ value: String) {
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--bloom-radius", value]) }
    }

    @Test(arguments: ["0", "nan", "inf"])
    func rejectsNonPositiveOrNonFiniteScanlineFrequency(_ value: String) {
        #expect(throws: (any Error).self) { try VideoLabCommand.parse(base + ["--scanline-frequency", value]) }
    }
}

/// End-to-end coverage that the cosmetic effect chain actually reaches the
/// rendered output on every AskiVideoLab path. Each test renders the same source
/// twice — once plain, once with a strong darkening combo (`--scanlines 1
/// --vignette 1`) — and asserts the effected output is dimmer. A path that forgot
/// to thread `effects` would produce identical brightness and fail here; this is
/// the four-path-drift guard, the analogue of the pattern E2E suite.
@Suite struct AskiVideoLabEffectsE2ETests {
    // scanlines multiplies luminance by ~0.5...1.0 per row and vignette darkens
    // the edges; together the mean brightness drop is large versus codec noise.
    private let darkening = ["--scanlines", "1", "--vignette", "1"]

    @Test func cappedMP4EffectsDimAndPreserveFrameCount() async throws {
        try await withTempDir { dir in
            let source = dir.appendingPathComponent("source.mp4")
            try await writeSourceMP4(to: source, frames: 6)

            let plain = try await runMP4(source: source, dir: dir, name: "plain", extra: ["--max-frames", "6"])
            let fx = try await runMP4(source: source, dir: dir, name: "fx", extra: ["--max-frames", "6"] + darkening)

            #expect(try await countVideoFrames(plain) == 6)
            #expect(try await countVideoFrames(fx) == 6)
            #expect(try await meanVideoBrightness(fx, columns: 16) < meanVideoBrightness(plain, columns: 16) * 0.95)
        }
    }

    @Test func uncappedMP4EffectsDimOutput() async throws {
        try await withTempDir { dir in
            let source = dir.appendingPathComponent("source.mp4")
            try await writeSourceMP4(to: source, frames: 6)

            let plain = try await runMP4(source: source, dir: dir, name: "plain", extra: [])
            let fx = try await runMP4(source: source, dir: dir, name: "fx", extra: darkening)

            #expect(try await meanVideoBrightness(fx, columns: 16) < meanVideoBrightness(plain, columns: 16) * 0.95)
        }
    }

    @Test func resampleMP4EffectsDimOutput() async throws {
        try await withTempDir { dir in
            let source = dir.appendingPathComponent("source.mp4")
            try await writeSourceMP4(to: source, frames: 6)

            let plain = try await runMP4(source: source, dir: dir, name: "plain", extra: ["--target-fps", "8"])
            let fx = try await runMP4(source: source, dir: dir, name: "fx", extra: ["--target-fps", "8"] + darkening)

            #expect(try await meanVideoBrightness(fx, columns: 16) < meanVideoBrightness(plain, columns: 16) * 0.95)
        }
    }

    // The GIF CLI path runs end-to-end with effects and preserves the frame count.
    // (A re-encoded GIF's palette quantization on a tiny saturated source makes a
    // re-decoded brightness delta noisy, so the darkening signal for the GIF render
    // path is guarded deterministically below at the `GIFRenderHelper` level.)
    @Test func gifEffectsPreserveFrameCount() async throws {
        try await withTempDir { dir in
            let source = dir.appendingPathComponent("source.gif")
            try makeSourceGIF(to: source)
            let fx = try await runGIF(source: source, dir: dir, name: "fx", extra: darkening)
            #expect(try await countGIFFrames(fx) == 3)
        }
    }

    // Deterministic 4th-path drift guard: `GIFRenderHelper.render` must thread the
    // chain into the rendered raster. Measured directly off the CGImage (no GIF
    // encode / ASCII re-conversion), so it is free of palette-quantization noise.
    @Test func gifRenderHelperDarkensRender() {
        let font = ASCIIFont.system(size: 12)
        let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let frame = ASCIIGIFFrame(grid: brightGrid(rows: 12, columns: 16), delay: 0.1)
        let plain = GIFRenderHelper.render(frame, font: font, backgroundColor: black, scale: 8)
        let fx = GIFRenderHelper.render(
            frame, font: font, backgroundColor: black, scale: 8,
            effects: EffectChain([.scanLines(intensity: 1, frequency: 4), .vignette(intensity: 1)]))
        #expect(meanLuminance(of: fx.image) < meanLuminance(of: plain.image) * 0.95)
    }

    @Test func defaultRunOmitsEffectsFromManifest() async throws {
        try await withTempDir { dir in
            let source = dir.appendingPathComponent("source.mp4")
            try await writeSourceMP4(to: source, frames: 3)
            let out = try await runMP4(source: source, dir: dir, name: "out", extra: ["--max-frames", "3"])
            let yaml = try String(
                contentsOf: out.deletingLastPathComponent().appendingPathComponent("result.yaml"), encoding: .utf8)
            #expect(!yaml.contains("--bloom"))
            #expect(!yaml.contains("--scanlines"))
            #expect(!yaml.contains("--vignette"))
        }
    }

    @Test func vignetteRecordedInManifest() async throws {
        try await withTempDir { dir in
            let source = dir.appendingPathComponent("source.mp4")
            try await writeSourceMP4(to: source, frames: 3)
            let out = try await runMP4(
                source: source, dir: dir, name: "out", extra: ["--max-frames", "3", "--vignette", "0.5"])
            let yaml = try String(
                contentsOf: out.deletingLastPathComponent().appendingPathComponent("result.yaml"), encoding: .utf8)
            #expect(yaml.contains("--vignette 0.5"))
        }
    }

    // MARK: - Harness (mirrors AskiVideoLabPatternE2ETests)

    private func withTempDir(_ body: (URL) async throws -> Void) async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "AskiVideoLabEffectsE2E-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir)
    }

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
                    indices: [UInt8](repeating: UInt8(i % 3), count: 64),
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

    /// A uniform grid of fully-covered bright white cells — a clean canvas for the
    /// raster-level darkening check (no glyph-shape variance to muddy the mean).
    private func brightGrid(rows: Int, columns: Int) -> ASCIIGrid {
        let cell = ASCIICell(
            character: "X", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 1, coverage: 1)
        return ASCIIGrid(cells: Array(repeating: Array(repeating: cell, count: columns), count: rows), colorSpace: .sRGB)
    }

    /// Mean Rec.709 luminance of a CGImage, read straight from an RGBA8 redraw —
    /// no GIF encode or ASCII re-conversion, so a cosmetic darkening shows cleanly.
    private func meanLuminance(of image: CGImage) -> Double {
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var sum = 0.0
        for pixel in 0..<(width * height) {
            let r = Double(buffer[pixel * 4 + 0])
            let g = Double(buffer[pixel * 4 + 1])
            let b = Double(buffer[pixel * 4 + 2])
            sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        return width * height > 0 ? sum / Double(width * height) : 0
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
