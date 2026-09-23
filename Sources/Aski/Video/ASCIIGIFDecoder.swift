import CoreGraphics
import Foundation
import ImageIO

/// Decodes an animated GIF via ImageIO and yields a pull-based
/// `AsyncThrowingStream<ASCIIGIFFrame, Error>`. ImageIO returns fully composed,
/// full-canvas frames (offset placement + disposal already applied — addendum
/// §Verification), so there is NO compositor: each
/// `CGImageSourceCreateImageAtIndex` output goes straight to `transform`.
///
/// Mirrors `ASCIIVideoDecoder`: the non-`Sendable` `CGImageSource` is confined to
/// an actor over a `DispatchSerialQueue` `SerialExecutor`; only the `Sendable`
/// `ASCIIGIFFrame` escapes. No `columns` parameter — `transform` owns conversion.
public struct ASCIIGIFDecoder: Sendable {
    public init() {}

    /// Count-only container metadata. Synchronous: the `CGImageSource` is created,
    /// read, and released entirely within this call (it never escapes), so no actor.
    public func containerHeader(ofGIFAt url: URL) throws -> GIFContainerInfo.Header {
        let source = try Self.openSource(url)
        return Self.containerHeader(from: source)
    }

    /// Full container metadata. Synchronous: the `CGImageSource` is created, read,
    /// and released entirely within this call (it never escapes), so no actor.
    public func containerInfo(ofGIFAt url: URL) throws -> GIFContainerInfo {
        let source = try Self.openSource(url)
        let header = Self.containerHeader(from: source)
        // Properties-only per-index scan for the unclamped per-frame delays. No
        // image decode — reuses the same `unclampedDelay` rule as `grids`.
        var frameDelays: [TimeInterval] = []
        frameDelays.reserveCapacity(header.frameCount)
        for index in 0..<header.frameCount {
            frameDelays.append(GIFDecodeSession.unclampedDelay(source: source, index: index))
        }
        return GIFContainerInfo(
            frameCount: header.frameCount,
            loopCount: header.loopCount,
            canvasSize: header.canvasSize,
            frameDelays: frameDelays
        )
    }

    public func grids(
        fromGIFAt url: URL,
        transform: @escaping @Sendable (CGImage) -> ASCIIGrid
    ) -> AsyncThrowingStream<ASCIIGIFFrame, Error> {
        let session = GIFDecodeSession(url: url, transform: transform)
        // MUST be `unfolding:` — the unfolding closure is `@Sendable` and captures
        // only the `session` actor reference (Sendable), so it compiles under strict
        // 6. Pull-based: one decoded frame per `next()`; nil ends the stream.
        return AsyncThrowingStream(unfolding: {
            try await session.next()
        })
    }

    private static func openSource(_ url: URL) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw GIFDecodeError.cannotOpenSource(url.path)
        }
        return source
    }

    private static func containerHeader(from source: CGImageSource) -> GIFContainerInfo.Header {
        let frameCount = CGImageSourceGetCount(source)
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        // Absent loop extension reads as 1 (play once) on the target SDK; default to
        // 1 if the key is missing entirely. NEVER synthesize 0 (infinite).
        let loopCount = (gif?[kCGImagePropertyGIFLoopCount] as? Int) ?? 1
        let width = (gif?[kCGImagePropertyGIFCanvasPixelWidth] as? Int) ?? 0
        let height = (gif?[kCGImagePropertyGIFCanvasPixelHeight] as? Int) ?? 0
        return GIFContainerInfo.Header(
            frameCount: frameCount,
            loopCount: loopCount,
            canvasSize: CGSize(width: width, height: height)
        )
    }
}

/// Confines the non-`Sendable` `CGImageSource` to a serial executor. The per-frame
/// read + `transform(CGImage) -> ASCIIGrid` happen INSIDE this isolation; only the
/// `Sendable` `ASCIIGIFFrame` ever crosses out. There is NO compositing canvas
/// state (the prior draft's extra state is gone), so this is strictly simpler than
/// `DecodeSession`.
private actor GIFDecodeSession {
    private let queue = DispatchSerialQueue(label: "art.aski.gif.decode")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let url: URL
    private let transform: @Sendable (CGImage) -> ASCIIGrid
    private var source: CGImageSource?
    private var index = 0
    private var count = 0
    private var started = false
    private var finished = false

    init(url: URL, transform: @escaping @Sendable (CGImage) -> ASCIIGrid) {
        self.url = url
        self.transform = transform
    }

    func next() async throws -> ASCIIGIFFrame? {
        if finished { return nil }
        if Task.isCancelled {
            teardown()
            throw CancellationError()
        }
        if !started { try start() }
        guard let source, index < count else {
            finished = true
            teardown()
            return nil
        }
        let frameIndex = index
        index += 1
        guard let image = CGImageSourceCreateImageAtIndex(source, frameIndex, nil) else {
            teardown()
            throw GIFDecodeError.frameDecodeFailed(frameIndex)
        }
        let delay = Self.unclampedDelay(source: source, index: frameIndex)
        let grid = transform(image)  // converter runs inside isolation
        return ASCIIGIFFrame(grid: grid, delay: delay)
    }

    private func start() throws {
        started = true
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            finished = true
            throw GIFDecodeError.cannotOpenSource(url.path)
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            finished = true
            throw GIFDecodeError.noFrames
        }
        self.source = source
        self.count = frameCount
    }

    /// Reads the UNCLAMPED per-frame delay (raw value). Falls back to the clamped
    /// delay, then a documented 0.1s default.
    static func unclampedDelay(source: CGImageSource, index: Int) -> TimeInterval {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return 0.1
        }
        if let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0 {
            return unclamped
        }
        if let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double, clamped > 0 {
            return clamped
        }
        return 0.1
    }

    private func teardown() {
        source = nil
    }
}
