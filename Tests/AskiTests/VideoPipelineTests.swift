import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import Aski

@Suite struct VideoFramePrefetchPumpTests {
    @Test func preservesOrderWithOneBufferedFrameAndOneProducer() async throws {
        let probe = PrefetchSourceProbe(frameCount: 6)
        let pump = VideoFramePrefetchPump(stream: probe.stream())

        var times: [CMTime] = []
        while let frame = try await pump.next() {
            times.append(frame.time)
        }

        #expect(times == (0..<6).map { CMTime(value: Int64($0), timescale: 30) })
        #expect(await pump.maximumBufferedFrameCount == 1)
        #expect(await probe.maximumConcurrentPulls == 1)
        #expect(await probe.pullCount == 7)  // six values plus the terminal nil
    }

    @Test func earlyConsumerExitPullsAtMostOneFrameAhead() async throws {
        let probe = PrefetchSourceProbe(frameCount: 20)
        let pump = VideoFramePrefetchPump(stream: probe.stream())

        _ = try #require(await pump.next())
        try await Task.sleep(for: .milliseconds(10))

        #expect(await probe.pullCount <= 2)
        #expect(await pump.maximumBufferedFrameCount == 1)
        await pump.cancel()
    }

    @Test func producerFailureSurfacesInOrderAfterBufferedFrame() async throws {
        let probe = PrefetchSourceProbe(frameCount: 4, failureIndex: 1)
        let pump = VideoFramePrefetchPump(stream: probe.stream())

        let first = try #require(await pump.next())
        #expect(first.time == .zero)
        do {
            _ = try await pump.next()
            Issue.record("expected prefetched producer failure")
        } catch is PrefetchSourceError {
            // Expected.
        }
    }

    @Test func cancellationStopsASuspendedPrefetch() async throws {
        let source = AsyncThrowingStream<ASCIIVideoFrame, Error>(unfolding: {
            try await Task.sleep(for: .seconds(10))
            return nil
        })
        let pump = VideoFramePrefetchPump(stream: source)
        let task = Task { try await pump.next() }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected CancellationError")
        } catch is CancellationError {
            // Expected.
        }
    }

    @Test func releasingPumpCancelsASuspendedPrefetch() async throws {
        let probe = SuspendingPrefetchSourceProbe()
        var pump: VideoFramePrefetchPump? = VideoFramePrefetchPump(stream: probe.stream())
        weak let releasedPump = pump

        do {
            let livePump = try #require(pump)
            _ = try #require(await livePump.next())
        }
        for _ in 0..<100 where await probe.pullCount < 2 {
            await Task.yield()
        }
        #expect(await probe.pullCount == 2)

        pump = nil
        for _ in 0..<100 {
            let released = releasedPump == nil
            let cancellationObserved = await probe.cancellationObserved
            if released, cancellationObserved { break }
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(releasedPump == nil)
        #expect(await probe.cancellationObserved)
    }
}

@Suite struct PipelinedVideoIntegrationTests {
    @Test func siblingSequencePreservesExactPresentationOrder() async throws {
        let source = tempVideoURL("pipeline-order.mp4")
        defer { try? FileManager.default.removeItem(at: source) }
        let frames = (0..<8).map { index in
            RenderedVideoFrame(
                image: solidFrame(level: UInt8(20 + index * 20), width: 64, height: 48),
                time: CMTime(value: Int64(index * 3), timescale: 60)
            )
        }
        try await ASCIIVideoEncoder().write(
            frameSequence(frames),
            to: source,
            options: VideoExportOptions()
        )

        var decodedTimes: [CMTime] = []
        for try await frame in ASCIIVideoDecoder().pipelinedGrids(
            fromVideoAt: source,
            transform: { _ in ASCIIGrid(cells: [], colorSpace: .sRGB) }
        ) {
            decodedTimes.append(frame.time)
        }

        #expect(decodedTimes == frames.map(\.time))
    }

    @Test func pipelinedOrientationPreservesExactConvertedGrids() async throws {
        let source = tempVideoURL("pipeline-thumbnail-orientation.mp4")
        defer { try? FileManager.default.removeItem(at: source) }
        let sourceFrames = (0..<4).map(pipelineQualityFrame)
        let rotate = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)
        try await writeOrientedSource(
            frames: sourceFrames,
            transform: rotate,
            timescale: 30,
            to: source
        )

        let converter = DefaultConverter()
        var fullResolution: [ASCIIVideoFrame] = []
        for try await frame in ASCIIVideoDecoder().grids(
            fromVideoAt: source,
            transform: { converter.convert($0, columns: 40) }
        ) {
            fullResolution.append(frame)
        }

        var pipelined: [ASCIIVideoFrame] = []
        for try await frame in ASCIIVideoDecoder().pipelinedGrids(
            fromVideoAt: source,
            transform: { converter.convert($0, columns: 40) }
        ) {
            pipelined.append(frame)
        }

        #expect(pipelined.map(\.time) == fullResolution.map(\.time))
        #expect(pipelined.map(\.grid.cells) == fullResolution.map(\.grid.cells))
    }

    @Test(.timeLimit(.minutes(1)))
    func encoderSetupFailureCancelsThePipelinedExportWithoutHanging() async throws {
        let source = tempVideoURL("pipeline-encoder-failure-source.mp4")
        let missingParent = FileManager.default.temporaryDirectory
            .appendingPathComponent("AskiPipelineMissing-\(UUID().uuidString)")
        let output = missingParent.appendingPathComponent("out.mp4")
        defer { try? FileManager.default.removeItem(at: source) }
        let frames = (0..<8).map { index in
            RenderedVideoFrame(
                image: solidFrame(level: UInt8(30 + index * 20), width: 64, height: 48),
                time: CMTime(value: Int64(index), timescale: 30)
            )
        }
        try await ASCIIVideoEncoder().write(
            frameSequence(frames),
            to: source,
            options: VideoExportOptions()
        )

        do {
            try await convertVideo(
                at: source,
                to: output,
                using: DefaultConverter(),
                columns: 20,
                font: .system(size: 10),
                backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                scale: 1
            )
            Issue.record("expected encoder setup failure")
        } catch {
            #expect(!FileManager.default.fileExists(atPath: output.path))
        }
    }
}

private func pipelineQualityFrame(_ index: Int) -> CGImage {
    let width = 640
    let height = 360
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let phase = CGFloat(index) / 4
    context.setFillColor(red: 0.08, green: 0.15 + phase * 0.2, blue: 0.35, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(red: 0.9, green: 0.2, blue: 0.1 + phase * 0.5, alpha: 1)
    context.fill(CGRect(x: 60 + index * 70, y: 50, width: 220, height: 130))
    context.setStrokeColor(CGColor(red: 0.1, green: 0.9, blue: 0.5, alpha: 1))
    context.setLineWidth(12)
    context.strokeEllipse(in: CGRect(x: 350, y: 130 + index * 20, width: 180, height: 150))
    return context.makeImage()!
}

private enum PrefetchSourceError: Error {
    case injected
}

private actor PrefetchSourceProbe {
    private let frameCount: Int
    private let failureIndex: Int?
    private var index = 0
    private var activePulls = 0
    private(set) var maximumConcurrentPulls = 0
    private(set) var pullCount = 0

    init(frameCount: Int, failureIndex: Int? = nil) {
        self.frameCount = frameCount
        self.failureIndex = failureIndex
    }

    nonisolated func stream() -> AsyncThrowingStream<ASCIIVideoFrame, Error> {
        AsyncThrowingStream(unfolding: { try await self.next() })
    }

    private func next() async throws -> ASCIIVideoFrame? {
        pullCount += 1
        activePulls += 1
        maximumConcurrentPulls = max(maximumConcurrentPulls, activePulls)
        defer { activePulls -= 1 }
        try await Task.sleep(for: .milliseconds(1))

        if index == failureIndex {
            throw PrefetchSourceError.injected
        }
        guard index < frameCount else { return nil }
        defer { index += 1 }
        return ASCIIVideoFrame(
            grid: ASCIIGrid(cells: [], colorSpace: .sRGB),
            time: CMTime(value: Int64(index), timescale: 30)
        )
    }
}

private actor SuspendingPrefetchSourceProbe {
    private(set) var pullCount = 0
    private(set) var cancellationObserved = false

    nonisolated func stream() -> AsyncThrowingStream<ASCIIVideoFrame, Error> {
        AsyncThrowingStream(unfolding: { try await self.next() })
    }

    private func next() async throws -> ASCIIVideoFrame? {
        pullCount += 1
        if pullCount == 1 {
            return ASCIIVideoFrame(
                grid: ASCIIGrid(cells: [], colorSpace: .sRGB),
                time: .zero
            )
        }

        do {
            try await Task.sleep(for: .seconds(10))
            return nil
        } catch is CancellationError {
            cancellationObserved = true
            throw CancellationError()
        }
    }
}
