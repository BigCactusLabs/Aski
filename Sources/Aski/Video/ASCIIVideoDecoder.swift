import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// Decodes an MP4's frames via `AVAssetReader`, converts each to an `ASCIIGrid`
/// through the caller-supplied `transform`, and yields a pull-based
/// `AsyncThrowingStream<ASCIIVideoFrame, Error>` — never buffering the whole
/// asset. Each `next()` triggers exactly one `copyNextSampleBuffer()`.
///
/// No `columns` parameter: the `transform` owns conversion (and downscaling)
/// end to end, keeping the converter's generic parameters out of the Video API.
///
/// The source track's `preferredTransform` is applied on decode so portrait /
/// rotated / front-camera-mirrored footage (the standard iPhone capture is
/// stored landscape plus a 90° transform) converts upright and the re-encoded
/// MP4 inherits the correct orientation. Reorientation is a per-frame Core Image
/// pass over the already-decoded `CGImage` — *not* an `AVAssetReaderVideo`
/// `CompositionOutput`: a composition output resamples to a fixed `frameDuration`
/// (breaking this decoder's "source PTS preserved, no fps resampling" contract)
/// and `copyNextSampleBuffer()` is reported to stall when a video composition is
/// attached. The per-frame pass keeps the 1:1 frame/PTS mapping and the plain
/// reader loop, and lets Core Image own the rotation+mirror affine math.
public struct ASCIIVideoDecoder: Sendable {
    public init() {}

    public func grids(
        fromVideoAt url: URL,
        transform: @escaping @Sendable (CGImage) -> ASCIIGrid
    ) -> AsyncThrowingStream<ASCIIVideoFrame, Error> {
        gridStream(fromVideoAt: url, transform: transform)
    }

    private func gridStream(
        fromVideoAt url: URL,
        transform: @escaping @Sendable (CGImage) -> ASCIIGrid
    ) -> AsyncThrowingStream<ASCIIVideoFrame, Error> {
        let session = DecodeSession(url: url, transform: transform)
        // MUST be the `unfolding:` initializer — the `(elementType:_:)` form takes
        // a synchronous `(Continuation) -> Void` builder and rejects an async
        // closure. The unfolding closure is `@Sendable`; it captures only the
        // `session` actor reference (Sendable), so this compiles under strict 6.
        return AsyncThrowingStream(unfolding: {
            // Pull-based: one decoded frame per `next()`; nil ends the stream.
            try await session.next()
        })
    }

    /// Decodes through the same ordered sequence as ``grids(fromVideoAt:transform:)``
    /// while prefetching exactly one frame. The consumer owns the current frame
    /// and the producer may hold one next frame, so decode + conversion can overlap
    /// render + encode with a hard two-frame in-flight bound.
    ///
    /// This is a sibling path rather than a semantic change to `grids`: callers
    /// that rely on one-pull/one-decode behavior keep it, while streaming export
    /// can opt into bounded overlap. Frames are still converted serially in source
    /// order; this does not add inter-frame conversion fan-out.
    public func pipelinedGrids(
        fromVideoAt url: URL,
        transform: @escaping @Sendable (CGImage) -> ASCIIGrid
    ) -> AsyncThrowingStream<ASCIIVideoFrame, Error> {
        let pump = VideoFramePrefetchPump(
            stream: gridStream(
                fromVideoAt: url,
                transform: transform
            )
        )
        return AsyncThrowingStream(unfolding: {
            try await pump.next()
        })
    }

    /// The track's exact time-range duration in seconds (VFR-correct — the real
    /// span, not a frame-count estimate). Loads the track via the same
    /// `loadTracks` the decoder uses. Throws `.noVideoTrack` on a trackless source.
    public func sourceDuration(ofVideoAt url: URL) async throws -> TimeInterval {
        let track = try await firstVideoTrack(url: url)
        let range = try await track.load(.timeRange)
        return CMTimeGetSeconds(range.duration)
    }

    /// The track's nominal (average) frame rate. Used only by the `--max-frames`
    /// debug path to estimate a capped span; the production uncapped path uses the
    /// exact `sourceDuration`.
    public func nominalFrameRate(ofVideoAt url: URL) async throws -> Float {
        let track = try await firstVideoTrack(url: url)
        return try await track.load(.nominalFrameRate)
    }

    private func firstVideoTrack(url: URL) async throws -> AVAssetTrack {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw VideoDecodeError.noVideoTrack }
        return track
    }
}

/// Single-producer/single-consumer prefetch for the video export path. A stored
/// task is the one available producer slot; there is never more than one task or
/// one buffered next frame. Iterator ownership lives in a separate source actor,
/// so the stored task never retains this pump and `deinit` can cancel suspended
/// work after an early consumer exit.
actor VideoFramePrefetchPump {
    private let source: VideoFramePrefetchSource
    private var prefetched: Task<ASCIIVideoFrame?, Error>?
    private(set) var maximumBufferedFrameCount = 0

    init(stream: AsyncThrowingStream<ASCIIVideoFrame, Error>) {
        source = VideoFramePrefetchSource(stream: stream)
    }

    deinit {
        prefetched?.cancel()
    }

    func next() async throws -> ASCIIVideoFrame? {
        if Task.isCancelled {
            prefetched?.cancel()
            prefetched = nil
            throw CancellationError()
        }

        let current = prefetched ?? startPrefetch()
        do {
            let frame = try await withTaskCancellationHandler {
                try await current.value
            } onCancel: {
                current.cancel()
            }
            prefetched = nil
            guard let frame else { return nil }
            if !Task.isCancelled {
                prefetched = startPrefetch()
            }
            return frame
        } catch {
            prefetched = nil
            throw error
        }
    }

    func cancel() {
        prefetched?.cancel()
        prefetched = nil
    }

    private func startPrefetch() -> Task<ASCIIVideoFrame?, Error> {
        maximumBufferedFrameCount = max(maximumBufferedFrameCount, 1)
        let source = source
        return Task {
            try await source.next()
        }
    }
}

/// Owns the non-Sendable stream iterator behind actor isolation. Prefetch tasks
/// retain this source while suspended, but never retain their coordinator.
private actor VideoFramePrefetchSource {
    private var iterator: AsyncThrowingStream<ASCIIVideoFrame, Error>.AsyncIterator

    init(stream: AsyncThrowingStream<ASCIIVideoFrame, Error>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> ASCIIVideoFrame? {
        var localIterator = iterator
        let frame = try await localIterator.next(isolation: #isolation)
        iterator = localIterator
        return frame
    }
}

/// Confines the non-Sendable `AVAssetReader` / `CVPixelBuffer` to a serial
/// executor. Conversion `CVPixelBuffer → CGImage → ASCIIGrid` happens INSIDE
/// this isolation, so only the `Sendable` `ASCIIVideoFrame` ever escapes.
private actor DecodeSession {
    private let queue = DispatchSerialQueue(label: "art.aski.video.decode")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let url: URL
    private let transform: @Sendable (CGImage) -> ASCIIGrid
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var started = false
    private var finished = false

    /// The track's `preferredTransform`, applied per frame to decode upright.
    /// `.identity` (the common already-upright case) skips reorientation entirely,
    /// so those clips keep the exact `VTCreateCGImageFromCVPixelBuffer` fast path.
    private var orientation: CGAffineTransform = .identity
    /// Lazily created and reused only when reorientation actually runs — a
    /// per-frame `CIContext` would be a real perf footgun. Confined to this actor.
    private var ciContext: CIContext?

    init(url: URL, transform: @escaping @Sendable (CGImage) -> ASCIIGrid) {
        self.url = url
        self.transform = transform
    }

    func next() async throws -> ASCIIVideoFrame? {
        if finished { return nil }
        if Task.isCancelled {
            teardown()
            throw CancellationError()
        }
        if !started {
            try await start()
        }
        guard let reader, let output else {
            finished = true
            return nil
        }

        while true {
            if Task.isCancelled {
                teardown()
                throw CancellationError()
            }
            guard let sample = output.copyNextSampleBuffer() else {
                // End of stream or failure.
                if reader.status == .failed {
                    let error = reader.error
                    teardown()
                    throw error ?? VideoDecodeError.readFailed
                }
                finished = true
                teardown()
                return nil
            }
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else {
                continue  // skip non-image samples
            }
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            var cgImage: CGImage?
            let status = VTCreateCGImageFromCVPixelBuffer(imageBuffer, options: nil, imageOut: &cgImage)
            guard status == noErr, let image = cgImage else {
                throw VideoDecodeError.conversionFailed
            }
            let oriented = try reorient(image)
            let grid = transform(oriented)  // converter runs inside isolation
            return ASCIIVideoFrame(grid: grid, time: time)
        }
    }

    private func start() async throws {
        started = true
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            // Audio-only / trackless input: fail loudly. Returning an empty stream
            // here would let `convertVideo` "succeed" with zero frames and the lab
            // write a success manifest for an `ascii.mp4` it never produced.
            finished = true
            throw VideoDecodeError.noVideoTrack
        }
        // Load the display transform once; applied per frame in `next()`. A
        // negative-determinant transform (front-camera mirror) is just an affine,
        // so Core Image reorients rotation and mirror in the same pass.
        orientation = try await track.load(.preferredTransform)
        let reader = try AVAssetReader(asset: asset)
        // Request 32BGRA so VTCreateCGImageFromCVPixelBuffer converts directly.
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw VideoDecodeError.cannotAddOutput }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? VideoDecodeError.startFailed
        }
        self.reader = reader
        self.output = output
    }

    /// Applies the track's `preferredTransform` to a decoded frame so it lands
    /// upright. Reorients the already-decoded `CGImage` (not the `CVPixelBuffer`)
    /// so the color path matches the identity case exactly — only geometry
    /// changes. AVFoundation's `preferredTransform` is a display transform in a
    /// top-left coordinate space; CIImage uses bottom-left coordinates, so apply
    /// the transform through a Y-flip on each side before rendering.
    private func reorient(_ image: CGImage) throws -> CGImage {
        if orientation.isIdentity { return image }
        let naturalExtent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let displayExtent = naturalExtent.applying(orientation).standardized.integral
        let sourceToDisplay = CGAffineTransform(translationX: 0, y: naturalExtent.height)
            .scaledBy(x: 1, y: -1)
            .concatenating(orientation)
            .concatenating(CGAffineTransform(translationX: 0, y: displayExtent.height).scaledBy(x: 1, y: -1))
        let source = CIImage(cgImage: image).transformed(by: sourceToDisplay)
        let extent = source.extent.integral
        let normalized = source.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        let context = ciContext ?? CIContext()
        ciContext = context
        guard let rotated = context.createCGImage(normalized, from: CGRect(origin: .zero, size: extent.size)) else {
            throw VideoDecodeError.conversionFailed
        }
        return rotated
    }

    private func teardown() {
        if reader?.status == .reading {
            reader?.cancelReading()
        }
        reader = nil
        output = nil
    }
}

enum VideoDecodeError: Error {
    case noVideoTrack
    case cannotAddOutput
    case startFailed
    case readFailed
    case conversionFailed
}
