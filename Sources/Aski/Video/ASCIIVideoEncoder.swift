import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

/// Encodes a `Sendable` async sequence of `RenderedVideoFrame` to an H.264 (or
/// HEVC) MP4. Owns the `AVAssetWriter` lifecycle and backpressure end to end.
///
/// Output dimensions are derived from the **first** frame and normalized to even
/// (AVAssetWriter requires consistent, even dimensions for 4:2:0 codecs); every
/// frame is drawn into that fixed canvas.
///
/// The output gamut also comes from the first frame's color space: Display P3
/// (including its linear and extended variants) encodes as P3, and everything
/// else, including an untagged image, encodes as sRGB. Frames are drawn in that
/// gamut's encoded (non-linear) space, and the track is tagged to match: color
/// primaries BT.709 or P3 D65, the IEC 61966-2-1 sRGB transfer function, and the
/// BT.709 Y'CbCr matrix, at the encoder's default video range.
public struct ASCIIVideoEncoder: Sendable {
    public init() {}

    public func write<S: AsyncSequence & Sendable>(
        _ frames: S,
        to url: URL,
        options: VideoExportOptions
    ) async throws where S.Element == RenderedVideoFrame {
        let session = EncodeSession(url: url, options: options)
        do {
            for try await frame in frames {
                try Task.checkCancellation()
                try await session.append(frame)
            }
        } catch {
            await session.cancel()
            throw error
        }
        try await session.finish()
    }
}

/// All `AVAssetWriter` state is confined to this actor's serial executor (a
/// `DispatchSerialQueue`). Only `Sendable` values cross in/out.
private actor EncodeSession {
    private let queue = DispatchSerialQueue(label: "art.aski.video.encode")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let url: URL
    private let options: VideoExportOptions
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var canvasWidth = 0
    private var canvasHeight = 0
    private var gamut = VideoOutputGamut.sRGB

    init(url: URL, options: VideoExportOptions) {
        self.url = url
        self.options = options
    }

    func append(_ frame: RenderedVideoFrame) async throws {
        if writer == nil {
            try startWriting(firstFrame: frame)
        }
        guard let adaptor else { throw VideoEncodeError.noAdaptor }
        let input = adaptor.assetWriterInput
        let buffer = try makePixelBuffer(from: frame.image)
        // Poll readiness instead of bridging `requestMediaDataWhenReady` through a
        // continuation: a poll re-reads the real flag each tick, so it can't lose a
        // wakeup when the writer's input fills (the SDK-26 receiver did — see the
        // encoder-fix findings). Upstream shape-matching conversion dwarfs the ~5 ms
        // tick, so this rarely spins more than once. The `writer.status` check is
        // load-bearing: on a writer failure `isReadyForMoreMediaData` stays false with
        // no task cancellation, so without it the loop would sleep forever.
        while !input.isReadyForMoreMediaData {
            try Task.checkCancellation()
            if let writer, writer.status == .failed || writer.status == .cancelled {
                throw writer.error ?? VideoEncodeError.appendFailed
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        guard adaptor.append(buffer, withPresentationTime: frame.time) else {
            throw writer?.error ?? VideoEncodeError.appendFailed
        }
    }

    func finish() async throws {
        guard let writer, let input else { return }  // no frames written
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw writer.error ?? VideoEncodeError.finishFailed
        }
    }

    func cancel() {
        writer?.cancelWriting()
    }

    private func startWriting(firstFrame frame: RenderedVideoFrame) throws {
        let width = even(frame.image.width)
        let height = even(frame.image.height)
        canvasWidth = width
        canvasHeight = height
        gamut = VideoOutputGamut(imageColorSpace: frame.image.colorSpace)
        let tags = gamut.tags

        let writer = try AVAssetWriter(url: url, fileType: .mp4)
        let codec: AVVideoCodecType = options.codec == .hevc ? .hevc : .h264
        var outputSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: tags.primaries as String,
                AVVideoTransferFunctionKey: tags.transferFunction as String,
                AVVideoYCbCrMatrixKey: tags.matrix as String,
            ],
        ]
        if let fps = options.expectedFrameRate {
            // MUST nest under AVVideoCompressionPropertiesKey — the top-level
            // AVVideoExpectedSourceFrameRateKey crashes AVAssetWriterInput on the
            // target SDK ("invalid keys: ExpectedFrameRate"). A rate-control HINT
            // only; the per-frame CMTime PTS stamps determine actual timing.
            outputSettings[AVVideoCompressionPropertiesKey] = [
                AVVideoExpectedSourceFrameRateKey: fps
            ]
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false
        if let fps = options.expectedFrameRate {
            input.mediaTimeScale = CMTimeScale(fps)  // CFR hint; only when resampling
        }
        guard writer.canAdd(input) else { throw VideoEncodeError.cannotAddInput }
        writer.add(input)

        // 32BGRA is the recommended RGB-domain source format (AVAssetWriterInput.h);
        // the encoder converts to YUV internally. The legacy adaptor owns the
        // CVPixelBufferPool we draw frames into and applies writer backpressure.
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )

        guard writer.startWriting() else {
            throw writer.error ?? VideoEncodeError.startFailed
        }
        writer.startSession(atSourceTime: frame.time)
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
    }

    /// Allocates a 32BGRA `CVPixelBuffer` from the adaptor's pool and draws
    /// `image` into it. The buffer is created and appended within one
    /// actor-isolated span and never crosses a `Sendable` boundary, so a plain
    /// `CVPixelBuffer` (no sealed read-only wrapper) is fine.
    private func makePixelBuffer(from image: CGImage) throws -> CVPixelBuffer {
        guard let pool = adaptor?.pixelBufferPool else { throw VideoEncodeError.noPool }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
            let buf = buffer
        else {
            throw VideoEncodeError.noPool
        }
        let tags = gamut.tags
        CVBufferSetAttachment(buf, kCVImageBufferColorPrimariesKey, tags.primaries, .shouldPropagate)
        CVBufferSetAttachment(buf, kCVImageBufferTransferFunctionKey, tags.transferFunction, .shouldPropagate)
        CVBufferSetAttachment(buf, kCVImageBufferYCbCrMatrixKey, tags.matrix, .shouldPropagate)
        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }
        // 32BGRA is a single packed plane.
        guard
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buf),
                width: canvasWidth,
                height: canvasHeight,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
                space: gamut.drawColorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue  // 32BGRA
            )
        else {
            throw VideoEncodeError.contextCreationFailed
        }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        // Anchor at the top-left: CGBitmapContext memory row 0 is the canvas top,
        // so even-dimension padding stays on the codec-cropped bottom and right.
        context.draw(
            image,
            in: CGRect(x: 0, y: canvasHeight - image.height, width: image.width, height: image.height)
        )
        return buf
    }

    private func even(_ value: Int) -> Int {
        value + (value & 1)
    }
}

/// The encoded gamut an MP4 is drawn and tagged in (ASKI-100). The three tags
/// describe the drawn bytes exactly, so AVFoundation performs no conversion
/// between the pixel buffers and the output settings.
enum VideoOutputGamut: Sendable {
    case sRGB
    case displayP3

    struct Tags {
        let primaries: CFString
        let transferFunction: CFString
        let matrix: CFString
    }

    /// Maps a rendered frame's color space to its encoded gamut by name. The
    /// renderer tags frames with sRGB or Display P3, or with their linear
    /// variants under `extendedLinearPerGamut`; any other or missing space
    /// falls back to sRGB and is color-matched into it when drawn.
    init(imageColorSpace: CGColorSpace?) {
        let displayP3Names = [
            CGColorSpace.displayP3, CGColorSpace.linearDisplayP3,
            CGColorSpace.extendedDisplayP3, CGColorSpace.extendedLinearDisplayP3,
        ].map { $0 as String }
        if let name = imageColorSpace?.name as String?, displayP3Names.contains(name) {
            self = .displayP3
        } else {
            self = .sRGB
        }
    }

    /// The per-gamut tag triple written to every pixel buffer and to the
    /// writer's `AVVideoColorPropertiesKey`.
    var tags: Tags {
        switch self {
        case .sRGB:
            Tags(
                primaries: kCVImageBufferColorPrimaries_ITU_R_709_2,
                transferFunction: kCVImageBufferTransferFunction_sRGB,
                matrix: kCVImageBufferYCbCrMatrix_ITU_R_709_2
            )
        case .displayP3:
            Tags(
                primaries: kCVImageBufferColorPrimaries_P3_D65,
                transferFunction: kCVImageBufferTransferFunction_sRGB,
                matrix: kCVImageBufferYCbCrMatrix_ITU_R_709_2
            )
        }
    }

    /// The encoded, non-linear space frames are drawn into.
    var drawColorSpace: CGColorSpace {
        switch self {
        case .sRGB: Self.sRGBSpace
        case .displayP3: Self.displayP3Space
        }
    }

    private static let sRGBSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let displayP3Space = CGColorSpace(name: CGColorSpace.displayP3)!
}

enum VideoEncodeError: Error {
    case cannotAddInput
    case startFailed
    case finishFailed
    case noAdaptor
    case noPool
    case contextCreationFailed
    case appendFailed
}
