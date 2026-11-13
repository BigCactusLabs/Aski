import CoreGraphics
import CoreMedia
import Foundation
import Synchronization
import Testing
@testable import Aski

/// Exercise the actual early-conversion seam with the literal pre-change
/// selection fixtures. These images have identities, but no codec is involved.
@Suite struct VideoEarlySelectionTests {
    @Test(arguments: VideoFrameSelectionFixtures.all)
    func convertsOnlyDistinctSelectedSources(fixture: VideoFrameSelectionFixtures.Fixture) async throws {
        let frames = fixture.sourceTicks.enumerated().map { index, tick in
            DecodedVideoFrame(
                sourceID: index,
                image: solidFrame(level: UInt8(index), width: 4, height: 4),
                time: CMTime(value: tick, timescale: fixture.sourceTimescale)
            )
        }
        let identities = Dictionary(uniqueKeysWithValues: frames.map { (ObjectIdentifier($0.image), $0.sourceID) })
        let calls = Mutex<[Int]>([])
        let source = EarlySelectionSource(frames: frames)
        let stats = ResampleStats()
        let pump = try VideoFrameSelectionPump(
            source: source.stream(), targetFPS: fixture.targetFPS, sourceDuration: fixture.duration, stats: stats,
            transform: { image in
                let id = identities[ObjectIdentifier(image)]!
                calls.withLock { $0.append(id) }
                return selectionMarkerGrid(id)
            }
        )
        var output: [ASCIIVideoFrame] = []
        while let frame = try await pump.next() { output.append(frame) }

        #expect(output.map(\.grid.cells) == fixture.selectedIDs.map { selectionMarkerGrid($0).cells })
        #expect(output.map(\.time.value) == fixture.outputTicks)
        #expect(output.allSatisfy { $0.time.timescale == Int32(fixture.targetFPS) && $0.time.isNumeric && $0.time.epoch == 0 })
        #expect(
            calls.withLock { $0 }
                == fixture.selectedIDs.enumerated().compactMap { index, id in
                    index == 0 || fixture.selectedIDs[index - 1] != id ? id : nil
                })
        #expect(await stats.sourceFrameCount == fixture.sourceCount)
        #expect(await stats.outputFrameCount == fixture.outputTicks.count)
        #expect(await stats.droppedCount == fixture.dropped)
        #expect(await stats.duplicatedCount == fixture.duplicated)
        #expect(await source.pullCount == fixture.pullRequests)
        // A finished pump must remain finished without another source pull.
        #expect(try await pump.next() == nil)
        #expect(await source.pullCount == fixture.pullRequests)
    }

    @Test func duplicateSlotsKeepTheBaseGridAndEvaluatePatternsAtOutputTime() async throws {
        let calls = Mutex(0)
        let source = EarlySelectionSource(frames: [
            DecodedVideoFrame(sourceID: 0, image: solidFrame(level: 160, width: 4, height: 4), time: .zero)
        ])
        let pump = try VideoFrameSelectionPump(
            source: source.stream(), targetFPS: 4, sourceDuration: 1, stats: ResampleStats(),
            transform: { _ in
                calls.withLock { $0 += 1 }
                return selectionMarkerGrid(0)
            }
        )
        var frames: [ASCIIVideoFrame] = []
        while let frame = try await pump.next() { frames.append(frame) }
        let pattern = OngoingPattern.pulse(period: 1, depth: 1)
        let patterned = frames.map { $0.applyingOngoingPattern(pattern) }

        #expect(calls.withLock { $0 } == 1)
        try #require(frames.count == 4)
        #expect(frames.allSatisfy { $0.grid.cells == selectionMarkerGrid(0).cells })
        #expect(patterned.map(\.time) == frames.map(\.time))
        #expect(patterned[0].grid.cells[0][0].alpha == 1)
        #expect(patterned[2].grid.cells[0][0].alpha == 0)
        #expect(patterned[0].grid.cells != patterned[2].grid.cells)
    }

    @Test func sourceFailureOnLookaheadPropagatesBeforeConvertingTheHeldFrame() async throws {
        let calls = Mutex(0)
        let source = EarlySelectionSource(
            frames: [DecodedVideoFrame(sourceID: 0, image: solidFrame(level: 80, width: 4, height: 4), time: .zero)],
            failureIndex: 1
        )
        let pump = try VideoFrameSelectionPump(
            source: source.stream(), targetFPS: 12, sourceDuration: 1, stats: ResampleStats(),
            transform: { _ in
                calls.withLock { $0 += 1 }; return selectionMarkerGrid(0)
            }
        )
        await #expect(throws: EarlySelectionFailure.self) { _ = try await pump.next() }
        #expect(calls.withLock { $0 } == 0)
        #expect(await source.pullCount == 2)
        #expect(try await pump.next() == nil)
        #expect(await source.pullCount == 2)
    }

    @Test func invalidScheduleDoesNotPullOrConvert() async throws {
        let calls = Mutex(0)
        let source = EarlySelectionSource(frames: [])
        #expect(throws: ResampleError.self) {
            _ = try VideoFrameSelectionPump(
                source: source.stream(), targetFPS: 0, sourceDuration: 1, stats: ResampleStats(),
                transform: { _ in
                    calls.withLock { $0 += 1 }; return selectionMarkerGrid(0)
                }
            )
        }
        #expect(await source.pullCount == 0)
        #expect(calls.withLock { $0 } == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationDuringASuspendedSourcePullReachesTheSource() async throws {
        let probe = SuspendedSelectionSource()
        let pump = try VideoFrameSelectionPump(
            source: probe.stream(), targetFPS: 12, sourceDuration: 1, stats: ResampleStats(),
            transform: { _ in
                Issue.record("cancelled source must not convert"); return selectionMarkerGrid(0)
            }
        )
        let task = Task { try await pump.next() }
        defer { task.cancel() }
        try await probe.waitForPull()
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(await probe.cancellationObserved)
        #expect(try await pump.next() == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func prefetchAfterSelectionStopsOneOutputAhead() async throws {
        let source = EarlySelectionSource(
            frames: (0..<60).map { index in
                DecodedVideoFrame(
                    sourceID: index, image: solidFrame(level: UInt8(index), width: 4, height: 4),
                    time: CMTime(value: Int64(index), timescale: 60)
                )
            })
        let calls = Mutex(0)
        let convertedTwo = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let selection = try VideoFrameSelectionPump(
            source: source.stream(), targetFPS: 12, sourceDuration: 1, stats: ResampleStats(),
            transform: { _ in
                let count = calls.withLock {
                    $0 += 1; return $0
                }
                if count == 2 {
                    convertedTwo.continuation.yield(())
                    convertedTwo.continuation.finish()
                }
                return selectionMarkerGrid(0)
            }
        )
        let prefetch = VideoFramePrefetchPump(stream: AsyncThrowingStream(unfolding: { try await selection.next() }))
        _ = try #require(await prefetch.next())
        // Wait for the real second conversion, not an assumed scheduling delay.
        for await _ in convertedTwo.stream { break }
        #expect(calls.withLock { $0 } == 2)
        // The second selected source is 7; source 8 is its lookahead. The new
        // arrangement must not prefetch a third output or a tenth raw frame.
        #expect(await source.pullCount == 9)
        #expect(await prefetch.maximumBufferedFrameCount == 1)
        await prefetch.cancel()
    }
}

private func selectionMarkerGrid(_ id: Int) -> ASCIIGrid {
    ASCIIGrid(
        cells: [[ASCIICell(character: "#", displayColor: SIMD3<Float>(0.2, 0.4, 0.6), alpha: 1, brightness: Float(id) / 128)]],
        colorSpace: .sRGB
    )
}

private enum EarlySelectionFailure: Error {
    case injected
}

private actor EarlySelectionSource {
    private let frames: [DecodedVideoFrame]
    private let failureIndex: Int?
    private var index = 0
    private(set) var pullCount = 0

    init(frames: [DecodedVideoFrame], failureIndex: Int? = nil) {
        self.frames = frames
        self.failureIndex = failureIndex
    }

    nonisolated func stream() -> AsyncThrowingStream<DecodedVideoFrame, Error> {
        AsyncThrowingStream(unfolding: { try await self.next() })
    }

    private func next() throws -> DecodedVideoFrame? {
        try Task.checkCancellation()
        pullCount += 1
        if index == failureIndex { throw EarlySelectionFailure.injected }
        guard index < frames.count else { return nil }
        defer { index += 1 }
        return frames[index]
    }
}

private actor SuspendedSelectionSource {
    private var entered = false
    private var waiter: CheckedContinuation<Void, Error>?
    private(set) var cancellationObserved = false

    nonisolated func stream() -> AsyncThrowingStream<DecodedVideoFrame, Error> {
        AsyncThrowingStream(unfolding: { try await self.next() })
    }

    func waitForPull() async throws {
        try Task.checkCancellation()
        if entered { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiter = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter() }
        }
    }

    private func cancelWaiter() {
        waiter?.resume(throwing: CancellationError())
        waiter = nil
    }

    private func next() async throws -> DecodedVideoFrame? {
        entered = true
        waiter?.resume()
        waiter = nil
        do {
            try await Task.sleep(for: .seconds(10))
            return nil
        } catch is CancellationError {
            cancellationObserved = true
            throw CancellationError()
        }
    }
}
