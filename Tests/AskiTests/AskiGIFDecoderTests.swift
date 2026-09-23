import CoreGraphics
import Foundation
import Testing
@testable import Aski

/// Thread-safe sink for capturing the raw composed CGImages the decoder hands to
/// `transform`, so the guard test can assert composited pixels.
private final class ImageSink: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CGImage] = []
    var images: [CGImage] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
    func append(_ image: CGImage) {
        lock.lock(); defer { lock.unlock() }
        storage.append(image)
    }
}

/// Counts how many times the decode `transform` runs — the exact signal for the
/// `--max-frames` off-by-one (the buggy break-after-pull loop converts one frame
/// past the cap, yet `frame_count` still reads N, so only this counter catches it).
private final class TransformCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
    func increment() {
        lock.lock(); defer { lock.unlock() }
        count += 1
    }
}

@Suite struct AskiGIFDecoderTests {
    private func write(_ fixture: GIF89aFixture) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AskiGIFDecoderTests-\(UUID().uuidString).gif")
        try fixture.encode().write(to: url)
        return url
    }

    /// Guard / regression sentinel: ImageIO composes placement AND disposal.
    /// 3 frames: full red (do-not-dispose) -> 2x2 green at (1,1) (restore-to-bg)
    /// -> 1x1 blue at (0,0). Frame 1 must show the green placed; frame 2 must show
    /// the green REGION cleared (restored to background), proving ImageIO applied
    /// disposal before composing frame 2 — so we must not build a compositor.
    @Test func decoderYieldsComposedFullCanvasFramesWithDisposalApplied() async throws {
        let fixture = GIF89aFixture(
            canvasWidth: 4,
            canvasHeight: 4,
            colorTable: GIFFixturePalette.table,
            backgroundColorIndex: 3,  // black background
            netscapeLoop: nil,
            frames: [
                .init(
                    left: 0, top: 0, width: 4, height: 4,
                    indices: [UInt8](repeating: 0, count: 16),
                    delayCentiseconds: 10, disposal: 1),  // do-not-dispose
                .init(
                    left: 1, top: 1, width: 2, height: 2,
                    indices: [UInt8](repeating: 1, count: 4),
                    delayCentiseconds: 10, disposal: 2),  // restore-to-background
                .init(
                    left: 0, top: 0, width: 1, height: 1,
                    indices: [2],
                    delayCentiseconds: 10, disposal: 1),
            ]
        )
        let url = try write(fixture)
        defer { try? FileManager.default.removeItem(at: url) }

        let sink = ImageSink()
        let stream = ASCIIGIFDecoder().grids(
            fromGIFAt: url,
            transform: { image in
                sink.append(image)
                return ASCIIGrid(cells: [], colorSpace: .sRGB)
            }
        )
        var frameCount = 0
        for try await _ in stream { frameCount += 1 }
        #expect(frameCount == 3)

        let images = sink.images
        #expect(images.count == 3)
        #expect(images.allSatisfy { $0.width == 4 && $0.height == 4 })  // full canvas

        expectColor(images[0], x: 0, y: 0, 255, 0, 0)
        expectColor(images[1], x: 0, y: 0, 255, 0, 0)  // prior canvas
        expectColor(images[1], x: 1, y: 1, 0, 255, 0)  // green placed at offset
        expectColor(images[1], x: 3, y: 3, 255, 0, 0)

        expectColor(images[2], x: 0, y: 0, 0, 0, 255)  // blue 1x1
        expectColor(images[2], x: 1, y: 1, 0, 0, 0)  // green region restored to background
        expectColor(images[2], x: 3, y: 3, 255, 0, 0)  // do-not-dispose red survives
    }

    @Test func decoderReadsUnclampedPerFrameDelays() async throws {
        let fixture = GIF89aFixture(
            canvasWidth: 4, canvasHeight: 4,
            colorTable: GIFFixturePalette.table, backgroundColorIndex: 3, netscapeLoop: nil,
            frames: [
                .init(
                    left: 0, top: 0, width: 4, height: 4,
                    indices: [UInt8](repeating: 0, count: 16), delayCentiseconds: 2, disposal: 1),
                .init(
                    left: 0, top: 0, width: 4, height: 4,
                    indices: [UInt8](repeating: 1, count: 16), delayCentiseconds: 20, disposal: 1),
            ]
        )
        let url = try write(fixture)
        defer { try? FileManager.default.removeItem(at: url) }

        var delays: [TimeInterval] = []
        for try await frame in ASCIIGIFDecoder().grids(
            fromGIFAt: url,
            transform: { _ in ASCIIGrid(cells: [], colorSpace: .sRGB) }
        ) {
            delays.append(frame.delay)
        }
        #expect(delays.count == 2)
        #expect(abs(delays[0] - 0.02) < 0.005)  // unclamped, NOT clamped to 0.1
        #expect(abs(delays[1] - 0.2) < 0.005)
    }

    @Test func containerInfoReportsFrameCountCanvasAndLoop() throws {
        let fixture = GIF89aFixture(
            canvasWidth: 6, canvasHeight: 4,
            colorTable: GIFFixturePalette.table, backgroundColorIndex: 3, netscapeLoop: nil,
            frames: [
                .init(
                    left: 0, top: 0, width: 6, height: 4,
                    indices: [UInt8](repeating: 0, count: 24), delayCentiseconds: 10, disposal: 1),
                .init(
                    left: 0, top: 0, width: 6, height: 4,
                    indices: [UInt8](repeating: 1, count: 24), delayCentiseconds: 10, disposal: 1),
            ]
        )
        let url = try write(fixture)
        defer { try? FileManager.default.removeItem(at: url) }

        let info = try ASCIIGIFDecoder().containerInfo(ofGIFAt: url)
        #expect(info.frameCount == 2)
        #expect(info.loopCount == 1)  // absent Netscape extension => play once
        #expect(info.canvasSize == CGSize(width: 6, height: 4))
    }

    @Test func containerHeaderReportsCountCanvasAndLoopWithoutDelays() throws {
        let fixture = GIF89aFixture(
            canvasWidth: 6, canvasHeight: 4,
            colorTable: GIFFixturePalette.table, backgroundColorIndex: 3, netscapeLoop: nil,
            frames: [
                .init(
                    left: 0, top: 0, width: 6, height: 4,
                    indices: [UInt8](repeating: 0, count: 24), delayCentiseconds: 10, disposal: 1),
                .init(
                    left: 0, top: 0, width: 6, height: 4,
                    indices: [UInt8](repeating: 1, count: 24), delayCentiseconds: 10, disposal: 1),
            ]
        )
        let url = try write(fixture)
        defer { try? FileManager.default.removeItem(at: url) }

        let header = try ASCIIGIFDecoder().containerHeader(ofGIFAt: url)
        let info = try ASCIIGIFDecoder().containerInfo(ofGIFAt: url)
        #expect(header.frameCount == info.frameCount)
        #expect(header.loopCount == info.loopCount)
        #expect(header.canvasSize == info.canvasSize)
    }

    @Test func containerInfoReportsPerFrameDelaysAndTotalDuration() throws {
        let fixture = GIF89aFixture(
            canvasWidth: 4, canvasHeight: 4,
            colorTable: GIFFixturePalette.table, backgroundColorIndex: 3, netscapeLoop: nil,
            frames: [
                .init(
                    left: 0, top: 0, width: 4, height: 4,
                    indices: [UInt8](repeating: 0, count: 16), delayCentiseconds: 2, disposal: 1),
                .init(
                    left: 0, top: 0, width: 4, height: 4,
                    indices: [UInt8](repeating: 1, count: 16), delayCentiseconds: 20, disposal: 1),
                .init(
                    left: 0, top: 0, width: 4, height: 4,
                    indices: [UInt8](repeating: 2, count: 16), delayCentiseconds: 20, disposal: 1),
            ]
        )
        let url = try write(fixture)
        defer { try? FileManager.default.removeItem(at: url) }

        let info = try ASCIIGIFDecoder().containerInfo(ofGIFAt: url)
        #expect(info.frameDelays.count == 3)
        #expect(abs(info.frameDelays[0] - 0.02) < 0.005)  // unclamped, not floored to 0.1
        #expect(abs(info.frameDelays[1] - 0.20) < 0.005)
        #expect(abs(info.frameDelays[2] - 0.20) < 0.005)
        #expect(abs(info.totalDuration - 0.42) < 0.01)  // sum of delays
    }

    /// Regression guard for the `--max-frames` off-by-one (addendum / lab cap path):
    /// `grids(...).prefix(2)` over a 4-frame GIF must run the `transform` EXACTLY
    /// twice — `.prefix` returns nil on the 3rd pull without calling the base
    /// iterator, so the converter never runs on frame index 2. A break-after-pull
    /// loop would convert a 3rd frame before stopping. `frame_count` alone cannot
    /// catch this (it reads 2 either way), so we count transform invocations.
    @Test func prefixDecodesExactlyNFramesWithoutOverPulling() async throws {
        let fixture = GIF89aFixture(
            canvasWidth: 4, canvasHeight: 4,
            colorTable: GIFFixturePalette.table, backgroundColorIndex: 3, netscapeLoop: nil,
            frames: (0..<4).map { i in
                .init(
                    left: 0, top: 0, width: 4, height: 4,
                    indices: [UInt8](repeating: UInt8(i % 4), count: 16),
                    delayCentiseconds: 10, disposal: 1)
            }
        )
        let url = try write(fixture)
        defer { try? FileManager.default.removeItem(at: url) }

        let counter = TransformCounter()
        let stream = ASCIIGIFDecoder().grids(
            fromGIFAt: url,
            transform: { _ in
                counter.increment()
                return ASCIIGrid(cells: [], colorSpace: .sRGB)
            }
        )
        var collected = 0
        for try await _ in stream.prefix(2) { collected += 1 }

        #expect(collected == 2)
        #expect(counter.value == 2)  // NOT 3 — the converter never runs on the capped frame
    }
}
