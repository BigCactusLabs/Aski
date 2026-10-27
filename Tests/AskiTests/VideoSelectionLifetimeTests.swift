import CoreGraphics
import CoreMedia
import Foundation
import Synchronization
import Testing
@testable import Aski

/// Tracks the owned bytes of lazily created synthetic CGImage providers.
/// This is a storage-lifetime contract for selection/prefetch, not a codec,
/// CoreGraphics internal-allocation, VideoToolbox pool, or process-RSS test.
@Suite struct VideoSelectionLifetimeTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func decodedStorageStaysBoundedAndReleasesAtTheDurationLimit(prefetch: Bool) async throws {
        let probe = SelectionImageLifetimeProbe()
        let source = LifetimeFrameSource(frameCount: 1200, timescale: 60, probe: probe)
        let stats = ResampleStats()
        let selection = try VideoFrameSelectionPump(
            source: source.stream(), targetFPS: 12, sourceDuration: 10, stats: stats,
            transform: { _ in
                probe.recordConversion()
                return ASCIIGrid(cells: [], colorSpace: .sRGB)
            }
        )
        var outputCount = 0
        if prefetch {
            let pump = VideoFramePrefetchPump(stream: AsyncThrowingStream(unfolding: { try await selection.next() }))
            while let _ = try await pump.next() { outputCount += 1 }
            #expect(await pump.maximumBufferedFrameCount == 1)
        } else {
            while let _ = try await selection.next() { outputCount += 1 }
        }

        // Neither source nor selection is released here: EOS itself must release
        // the selector's held/lookahead images while both actors remain alive.
        await probe.waitForZeroLiveBuffers()
        let counts = probe.snapshot()
        #expect(outputCount == 120)
        #expect(await stats.sourceFrameCount == 599)
        #expect(await source.framesCreated == 599)  // 601 source frames remain unread
        #expect(counts.created == 599)
        #expect(counts.conversions == 120)
        #expect(counts.live == 0)
        #expect(counts.released == counts.created)
        // At conversion boundaries the selector owns at most held+lookahead.
        // Permit one additional replacement/return temporary during creation;
        // outer prefetch must not add a queue of decoded source images.
        #expect(counts.maximumAtConversion <= 2)
        #expect(counts.maximumLive <= 3)
        #expect(try await selection.next() == nil)
        #expect(await source.framesCreated == 599)
    }

    @Test(.timeLimit(.minutes(1)))
    func sourceFailureReleasesDecodedStorageAfterConversion() async throws {
        let probe = SelectionImageLifetimeProbe()
        let source = LifetimeFrameSource(frameCount: 20, timescale: 12, probe: probe, failureIndex: 2)
        let selection = try VideoFrameSelectionPump(
            source: source.stream(), targetFPS: 12, sourceDuration: 1, stats: ResampleStats(),
            transform: { _ in
                probe.recordConversion()
                return ASCIIGrid(cells: [], colorSpace: .sRGB)
            }
        )
        _ = try #require(await selection.next())
        await #expect(throws: LifetimeSourceFailure.self) { _ = try await selection.next() }

        await probe.waitForZeroLiveBuffers()
        let counts = probe.snapshot()
        #expect(counts.created == 2)
        #expect(counts.released == 2)
        #expect(counts.conversions == 1)
        #expect(try await selection.next() == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationDuringLookaheadReleasesDecodedStorage() async throws {
        let probe = SelectionImageLifetimeProbe()
        let gate = SelectionLifetimeCancellationGate()
        let source = LifetimeFrameSource(frameCount: 20, timescale: 12, probe: probe, suspendedAt: 2, gate: gate)
        let selection = try VideoFrameSelectionPump(
            source: source.stream(), targetFPS: 12, sourceDuration: 1, stats: ResampleStats(),
            transform: { _ in
                probe.recordConversion()
                return ASCIIGrid(cells: [], colorSpace: .sRGB)
            }
        )
        _ = try #require(await selection.next())
        let task = Task { try await selection.next() }
        defer { task.cancel() }
        try await gate.waitUntilEntered()
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }

        await probe.waitForZeroLiveBuffers()
        let counts = probe.snapshot()
        #expect(counts.created == 2)
        #expect(counts.released == 2)
        #expect(counts.conversions == 1)
        #expect(try await selection.next() == nil)
    }
}

private final class SelectionImageLifetimeProbe: Sendable {
    struct Counts: Sendable {
        var created = 0
        var released = 0
        var live = 0
        var maximumLive = 0
        var conversions = 0
        var maximumAtConversion = 0
    }

    private let counts = Mutex(Counts())
    private let zeroEvents: AsyncStream<Void>
    private let zeroContinuation: AsyncStream<Void>.Continuation

    init() {
        let events = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        zeroEvents = events.stream
        zeroContinuation = events.continuation
    }

    func didCreate() {
        counts.withLock {
            $0.created += 1
            $0.live += 1
            $0.maximumLive = max($0.maximumLive, $0.live)
        }
    }

    func didRelease() {
        let isZero = counts.withLock {
            $0.released += 1
            $0.live -= 1
            return $0.live == 0
        }
        if isZero { zeroContinuation.yield(()) }
    }

    func recordConversion() {
        counts.withLock {
            $0.conversions += 1
            $0.maximumAtConversion = max($0.maximumAtConversion, $0.live)
        }
    }

    func snapshot() -> Counts {
        counts.withLock { $0 }
    }

    func waitForZeroLiveBuffers() async {
        if snapshot().live == 0 { return }
        for await _ in zeroEvents {
            if snapshot().live == 0 { return }
        }
    }
}

private enum LifetimeSourceFailure: Error {
    case injected
    case cannotCreateImage
}

/// Holds only scalar scheduling data and the probe. Each pull allocates one
/// image; no source array can accidentally keep old providers alive.
private actor LifetimeFrameSource {
    private let frameCount: Int
    private let timescale: Int32
    private let probe: SelectionImageLifetimeProbe
    private let failureIndex: Int?
    private let suspendedAt: Int?
    private let gate: SelectionLifetimeCancellationGate?
    private(set) var framesCreated = 0

    init(
        frameCount: Int, timescale: Int32, probe: SelectionImageLifetimeProbe,
        failureIndex: Int? = nil, suspendedAt: Int? = nil, gate: SelectionLifetimeCancellationGate? = nil
    ) {
        self.frameCount = frameCount
        self.timescale = timescale
        self.probe = probe
        self.failureIndex = failureIndex
        self.suspendedAt = suspendedAt
        self.gate = gate
    }

    nonisolated func stream() -> AsyncThrowingStream<DecodedVideoFrame, Error> {
        AsyncThrowingStream(unfolding: { try await self.next() })
    }

    private func next() async throws -> DecodedVideoFrame? {
        try Task.checkCancellation()
        if framesCreated == failureIndex { throw LifetimeSourceFailure.injected }
        if framesCreated == suspendedAt, let gate { try await gate.suspendUntilCancelled() }
        guard framesCreated < frameCount else { return nil }
        // Drain temporary Cocoa ownership inside the synchronous factory. Only
        // the returned CGImage should keep the provider's bytes alive.
        let image = try autoreleasepool { try makeLifetimeImage(probe: probe) }
        let frame = DecodedVideoFrame(sourceID: framesCreated, image: image, time: CMTime(value: Int64(framesCreated), timescale: timescale))
        framesCreated += 1
        return frame
    }
}

private func makeLifetimeImage(probe: SelectionImageLifetimeProbe) throws -> CGImage {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw LifetimeSourceFailure.cannotCreateImage }
    let byteCount = 4 * 4 * 4
    let storage = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 1)
    let pixels = storage.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
    for alpha in stride(from: 3, to: byteCount, by: 4) { pixels[alpha] = 255 }
    let info = Unmanaged.passRetained(probe).toOpaque()
    probe.didCreate()
    guard
        let provider = CGDataProvider(
            dataInfo: info, data: storage, size: byteCount,
            releaseData: { info, data, _ in
                let probe = Unmanaged<SelectionImageLifetimeProbe>.fromOpaque(info!).takeRetainedValue()
                UnsafeMutableRawPointer(mutating: data).deallocate()
                probe.didRelease()
            }
        )
    else {
        storage.deallocate()
        Unmanaged<SelectionImageLifetimeProbe>.fromOpaque(info).release()
        probe.didRelease()
        throw LifetimeSourceFailure.cannotCreateImage
    }
    guard
        let image = CGImage(
            width: 4, height: 4, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    else { throw LifetimeSourceFailure.cannotCreateImage }
    return image
}

/// A cancellation-aware handshake with no sleep or polling window. The actor
/// records cancellation even if it arrives before the parked continuation.
private actor SelectionLifetimeCancellationGate {
    private let entry = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private var cancelled = false
    private var parked: CheckedContinuation<Void, Error>?

    func waitUntilEntered() async throws {
        var iterator = entry.stream.makeAsyncIterator()
        _ = await iterator.next()
        try Task.checkCancellation()
    }

    func suspendUntilCancelled() async throws {
        try await withTaskCancellationHandler {
            entry.continuation.yield(())
            entry.continuation.finish()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if cancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    parked = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    private func cancel() {
        cancelled = true
        parked?.resume(throwing: CancellationError())
        parked = nil
    }
}
