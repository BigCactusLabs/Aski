import CoreGraphics
import Foundation
import Testing
@testable import Aski

/// Opt-in ownership evidence only. Provider releases cannot observe ImageIO's
/// internal copies, so this readout must be paired with process RSS captures.
@Suite struct AskiGIFProviderLifetimeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ASKI_GIF_PROVIDER_LIFETIME"] == "1"))
    func captureProviderLifetime() throws {
        let reportPath = try #require(ProcessInfo.processInfo.environment["ASKI_GIF_PROVIDER_REPORT"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var runs: [GIFProviderRun] = []
        for frameCount in [24, 240, 1200] {
            for retained in [false, true] {
                let counter = GIFProviderCounter()
                let mode = retained ? "retained" : "incremental"
                let output = directory.appendingPathComponent("\(mode)-\(frameCount).gif")
                var samples = try encode(
                    count: frameCount, retained: retained, counter: counter, output: output
                )
                samples.append(counter.snapshot(stage: "afterSessionReleased", appended: frameCount))
                runs.append(
                    GIFProviderRun(
                        mode: mode, frameCount: frameCount, width: 640, height: 360,
                        bytesPerRow: 640 * 4, samples: samples
                    ))
            }
        }
        let report = GIFProviderReport(schemaVersion: 1, runs: runs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // The caller selects a durable artifact path. No stdout-only evidence.
        try encoder.encode(report).write(to: URL(fileURLWithPath: reportPath), options: .atomic)
    }

    private func encode(
        count: Int, retained: Bool, counter: GIFProviderCounter, output: URL
    ) throws -> [GIFProviderSample] {
        let session = try GIFEncodeSession(frameCount: count, loopCount: 0, to: output)
        var samples = [counter.snapshot(stage: "initial", appended: 0)]
        var frames: [RenderedGIFFrame] = []
        if retained {
            for index in 0..<count {
                frames.append(autoreleasepool { makeFrame(index: index, counter: counter) })
            }
            samples.append(counter.snapshot(stage: "afterArrayCreation", appended: 0))
            for (index, frame) in frames.enumerated() {
                try autoreleasepool { try session.append(frame) }
                samples.append(counter.snapshot(stage: "afterAppend", appended: index + 1))
            }
        } else {
            for index in 0..<count {
                try autoreleasepool {
                    try session.append(makeFrame(index: index, counter: counter))
                }
                samples.append(counter.snapshot(stage: "afterAppend", appended: index + 1))
            }
        }
        samples.append(counter.snapshot(stage: "preFinalize", appended: count))
        try withExtendedLifetime(frames) {
            let report = try autoreleasepool { try session.finish() }
            #expect(report.framesWritten == count)
            samples.append(counter.snapshot(stage: "afterFinish", appended: count))
        }
        frames.removeAll()
        samples.append(counter.snapshot(stage: "afterArrayReleased", appended: count))
        return samples
    }

    private func makeFrame(index: Int, counter: GIFProviderCounter) -> RenderedGIFFrame {
        let payload = GIFProviderPayload(width: 640, height: 360, index: index, counter: counter)
        let info = Unmanaged.passRetained(payload).toOpaque()
        // The C callback owns one retained payload. It captures no Swift state;
        // payload deinit frees immutable storage and updates a locked counter.
        let provider = CGDataProvider(
            dataInfo: info, data: payload.storage, size: payload.byteCount,
            releaseData: { info, _, _ in
                guard let info else { return }
                Unmanaged<GIFProviderPayload>.fromOpaque(info).release()
            }
        )!
        let image = CGImage(
            width: 640, height: 360, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 640 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        return RenderedGIFFrame(image: image, delay: 0.04)
    }
}

private struct GIFProviderReport: Encodable {
    let schemaVersion: Int
    let runs: [GIFProviderRun]
}

private struct GIFProviderRun: Encodable {
    let mode: String
    let frameCount: Int
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let samples: [GIFProviderSample]
}

private struct GIFProviderSample: Encodable {
    let stage: String
    let appended: Int
    let created: Int
    let released: Int
    let liveCount: Int
    let maxLiveCount: Int
    let liveBytes: Int
    let maxLiveBytes: Int
}

/// Test-owned, synchronously locked because ImageIO may release a provider on
/// another thread. No Sendable assertion is used to cross the callback boundary.
private final class GIFProviderCounter {
    private let lock = NSLock()
    private var created = 0
    private var released = 0
    private var liveBytes = 0
    private var maxLiveCount = 0
    private var maxLiveBytes = 0

    func add(bytes: Int) {
        lock.lock()
        defer { lock.unlock() }
        created += 1
        liveBytes += bytes
        maxLiveCount = max(maxLiveCount, created - released)
        maxLiveBytes = max(maxLiveBytes, liveBytes)
    }

    func release(bytes: Int) {
        lock.lock()
        defer { lock.unlock() }
        released += 1
        liveBytes -= bytes
    }

    func snapshot(stage: String, appended: Int) -> GIFProviderSample {
        lock.lock()
        defer { lock.unlock() }
        return GIFProviderSample(
            stage: stage, appended: appended, created: created, released: released,
            liveCount: created - released, maxLiveCount: maxLiveCount,
            liveBytes: liveBytes, maxLiveBytes: maxLiveBytes
        )
    }
}

/// Each provider has a distinct immutable RGBA allocation. Its sole mutation is
/// initialization before publication; storage is freed only by payload deinit.
private final class GIFProviderPayload {
    let storage: UnsafeMutableRawPointer
    let byteCount: Int
    private let counter: GIFProviderCounter

    init(width: Int, height: Int, index: Int, counter: GIFProviderCounter) {
        byteCount = width * height * 4
        storage = .allocate(byteCount: byteCount, alignment: 16)
        self.counter = counter
        let bytes = storage.bindMemory(to: UInt8.self, capacity: byteCount)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                bytes[offset] = UInt8((x + index) % 256)
                bytes[offset + 1] = UInt8((y + index) % 256)
                bytes[offset + 2] = UInt8(index % 256)
                bytes[offset + 3] = 255
            }
        }
        counter.add(bytes: byteCount)
    }

    deinit {
        storage.deallocate()
        counter.release(bytes: byteCount)
    }
}
