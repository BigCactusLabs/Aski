import AVFoundation
import AudioToolbox
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import Testing
@testable import Aski

@Suite struct AskiVideoCarrierTests {
    @Test func renderedVideoFrameExposesPublicInit() {
        let image = solidFrame(level: 128, width: 4, height: 4)
        let frame = RenderedVideoFrame(image: image, time: CMTime(value: 3, timescale: 30))
        #expect(frame.time == CMTime(value: 3, timescale: 30))
        #expect(frame.image.width == 4)
    }

    @Test func videoExportOptionsDefaultsToH264() {
        let options = VideoExportOptions()
        #expect(options.codec == .h264)
    }
}

// MARK: - Shared test helpers (used by every suite in this file)

/// A deterministic solid-gray RGBA8 `CGImage`. Distinct `level` values produce
/// distinct frames so a silent drop/dedup in encode or decode changes the count.
func solidFrame(level: UInt8, width: Int, height: Int) -> CGImage {
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
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}

/// Wraps a finite array of rendered frames as a `Sendable` async sequence for
/// the encoder. Bounded N, so the eager `yield` form is safe here.
func frameSequence(_ frames: [RenderedVideoFrame]) -> AsyncThrowingStream<RenderedVideoFrame, Error> {
    AsyncThrowingStream { continuation in
        for frame in frames { continuation.yield(frame) }
        continuation.finish()
    }
}

/// Independent oracle: counts decoded frames using Apple's `AVAssetReader`
/// directly (not Aski's decoder), so encoder tests don't depend on our decoder.
func countFrames(in url: URL) async throws -> Int {
    let asset = AVURLAsset(url: url)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    guard let track = tracks.first else { return 0 }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    )
    reader.add(output)
    reader.startReading()
    var count = 0
    while let sample = output.copyNextSampleBuffer() {
        count += 1
        _ = sample
    }
    return count
}

/// A decoded 32BGRA frame indexed in the pixel buffer's top-left memory order.
/// The encoder's padding contract is observable here without going through
/// Aski's decoder or renderer again.
private struct DecodedVideoRaster: Sendable {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let bytes: [UInt8]

    func meanLuminance(x: Int, y: Int, width: Int, height: Int) -> Double {
        precondition(x >= 0 && y >= 0 && x + width <= self.width && y + height <= self.height)
        var total = 0
        for row in y..<(y + height) {
            for column in x..<(x + width) {
                let pixel = row * bytesPerRow + column * 4
                total += Int(bytes[pixel]) + Int(bytes[pixel + 1]) + Int(bytes[pixel + 2])
            }
        }
        return Double(total) / Double(width * height * 3)
    }
}

private enum VideoRasterReadbackError: Error {
    case unavailable
}

/// Reads the first encoded frame through AVFoundation directly so the padding
/// assertions remain independent from Aski's video-decoding path.
private func firstDecodedVideoRaster(in url: URL) async throws -> DecodedVideoRaster {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
        throw VideoRasterReadbackError.unavailable
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    )
    reader.add(output)
    guard reader.startReading(), let sample = output.copyNextSampleBuffer(),
        let buffer = CMSampleBufferGetImageBuffer(sample)
    else {
        throw reader.error ?? VideoRasterReadbackError.unavailable
    }

    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
        throw VideoRasterReadbackError.unavailable
    }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let bytes = Array(
        UnsafeRawBufferPointer(start: baseAddress, count: bytesPerRow * height)
    )
    return DecodedVideoRaster(width: width, height: height, bytesPerRow: bytesPerRow, bytes: bytes)
}

/// Produces an opaque `ASCIIGrid.renderImage` fixture. Transparent cells leave
/// its white background visible, giving the video assertions a stable raster
/// signal at every source pixel.
private func opaqueGridImage(columns: Int, rows: Int, fontSize: CGFloat) -> CGImage {
    let transparentCell = ASCIICell(
        character: " ",
        displayColor: .init(0, 0, 0),
        alpha: 0,
        brightness: 0
    )
    let grid = ASCIIGrid(
        cells: Array(repeating: Array(repeating: transparentCell, count: columns), count: rows),
        colorSpace: .sRGB
    )
    return grid.renderImage(
        font: .system(size: fontSize),
        backgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        scale: 1
    )
}

/// Encodes an `ASCIIGrid.renderImage` and reads the first raster back directly
/// from AVFoundation. The image must remain at its top-left origin; any one-pixel
/// even-dimension expansion is black only on the bottom and/or right edge.
private func encodedVideoRaster(for image: CGImage, named name: String) async throws -> DecodedVideoRaster {
    let url = tempVideoURL(name)
    defer { try? FileManager.default.removeItem(at: url) }
    try await ASCIIVideoEncoder().write(
        frameSequence([RenderedVideoFrame(image: image, time: .zero)]),
        to: url,
        options: VideoExportOptions()
    )
    return try await firstDecodedVideoRaster(in: url)
}

/// A unique temp file URL under the system temp dir.
func tempVideoURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "AskiVideoLoopTests-\(UUID().uuidString)-\(name)")
}

// MARK: - Encoder

@Suite struct AskiVideoEncoderTests {
    @Test func encodesDistinctFramesToReadableMP4() async throws {
        let frameCount = 8
        let width = 64, height = 48
        let frames = (0..<frameCount).map { index in
            RenderedVideoFrame(
                image: solidFrame(level: UInt8(10 + index * 20), width: width, height: height),
                time: CMTime(value: Int64(index), timescale: 8)
            )
        }
        let url = tempVideoURL("encode.mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        try await ASCIIVideoEncoder().write(frameSequence(frames), to: url, options: VideoExportOptions())

        #expect(FileManager.default.fileExists(atPath: url.path))
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        #expect(size > 0)
        let decodedCount = try await countFrames(in: url)
        #expect(decodedCount == frameCount)
    }

    @Test func normalizesOddDimensionsToEven() async throws {
        // Odd natural size forces the encoder's even-normalization path.
        let frames = (0..<4).map { index in
            RenderedVideoFrame(
                image: solidFrame(level: UInt8(40 + index * 40), width: 65, height: 49),
                time: CMTime(value: Int64(index), timescale: 8)
            )
        }
        let url = tempVideoURL("odd.mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ASCIIVideoEncoder().write(frameSequence(frames), to: url, options: VideoExportOptions())
        #expect(try await countFrames(in: url) == 4)
    }

    @Test func oddWidthOnlyFramePadsRightWithoutLeadingBlackColumn() async throws {
        // One-row grid at 45 pt renders to 81 x 54: odd width only.
        let image = opaqueGridImage(columns: 3, rows: 1, fontSize: 45)
        #expect(image.width == 81)
        #expect(image.height == 54)

        let raster = try await encodedVideoRaster(for: image, named: "odd-width-padding.mp4")

        #expect(raster.width == 82)
        #expect(raster.height == 54)
        #expect(raster.meanLuminance(x: 0, y: 0, width: 1, height: image.height) > 160)
        #expect(raster.meanLuminance(x: image.width, y: 0, width: 1, height: image.height) < 96)
    }

    @Test func oddHeightOnlyFramePadsBottomWithoutLeadingBlackScanline() async throws {
        // Four-column grid at 45.5 pt renders to 110 x 55: odd height only.
        let image = opaqueGridImage(columns: 4, rows: 1, fontSize: 45.5)
        #expect(image.width == 110)
        #expect(image.height == 55)

        let raster = try await encodedVideoRaster(for: image, named: "odd-height-padding.mp4")

        #expect(raster.width == 110)
        #expect(raster.height == 56)
        #expect(raster.meanLuminance(x: 0, y: 0, width: image.width, height: 1) > 160)
        #expect(raster.meanLuminance(x: 0, y: image.height, width: image.width, height: 1) < 96)
    }

    @Test func bothOddFramePadsBottomAndRightWithoutLeadingBlackEdges() async throws {
        // One-cell grid at 44 pt renders to 27 x 53: odd width and height.
        let image = opaqueGridImage(columns: 1, rows: 1, fontSize: 44)
        #expect(image.width == 27)
        #expect(image.height == 53)

        let raster = try await encodedVideoRaster(for: image, named: "both-odd-padding.mp4")

        #expect(raster.width == 28)
        #expect(raster.height == 54)
        #expect(raster.meanLuminance(x: 0, y: 0, width: image.width, height: 1) > 160)
        #expect(raster.meanLuminance(x: 0, y: 0, width: 1, height: image.height) > 160)
        #expect(raster.meanLuminance(x: image.width, y: 0, width: 1, height: image.height) < 96)
        #expect(raster.meanLuminance(x: 0, y: image.height, width: image.width, height: 1) < 96)
    }

    /// Regression for the encoder deadlock: 64 frames (past the ~38 the writer
    /// input holds) yielded with ~8 ms spacing — the exact failure condition the
    /// old back-to-back tests (≤8 frames, no spacing) could never reach. The
    /// SDK-26 pixel-buffer receiver lost its readiness wakeup here and hung; the
    /// legacy adaptor + readiness poll completes. `.timeLimit` turns a re-regression
    /// into a fast failure instead of hanging the whole suite.
    @Test(.timeLimit(.minutes(1)))
    func encoderCompletesWithSpacedAppendsAtScale() async throws {
        let frameCount = 64
        let width = 64, height = 48
        let stream = AsyncThrowingStream<RenderedVideoFrame, Error> { continuation in
            let task = Task {
                for index in 0..<frameCount {
                    try await Task.sleep(for: .milliseconds(8))
                    continuation.yield(
                        RenderedVideoFrame(
                            image: solidFrame(level: UInt8(index * 3), width: width, height: height),
                            time: CMTime(value: Int64(index), timescale: 30)
                        ))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        let url = tempVideoURL("spaced.mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        try await ASCIIVideoEncoder().write(stream, to: url, options: VideoExportOptions())

        // Distinct input frames → count proves no silent drop and no deadlock.
        #expect(try await countFrames(in: url) == frameCount)
    }
}

// MARK: - Decoder

@Suite struct AskiVideoDecoderTests {
    @Test func roundTripsFrameCountAndOrdering() async throws {
        let frameCount = 8
        // Odd natural size exercises the encoder's even-normalization on the
        // round trip (spec §Open risks: dimension-normalization mismatch).
        let width = 65, height = 49
        let timescale: Int32 = 8
        let frames = (0..<frameCount).map { index in
            RenderedVideoFrame(
                image: solidFrame(level: UInt8(20 + index * 25), width: width, height: height),
                time: CMTime(value: Int64(index), timescale: timescale)
            )
        }
        let url = tempVideoURL("roundtrip.mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        try await ASCIIVideoEncoder().write(frameSequence(frames), to: url, options: VideoExportOptions())

        let converter = DefaultConverter()
        var decoded: [ASCIIVideoFrame] = []
        for try await frame in ASCIIVideoDecoder().grids(
            fromVideoAt: url,
            transform: { converter.convert($0, columns: 24) }
        ) {
            decoded.append(frame)
        }

        // Distinct input frames → count proves no silent drop/dedup.
        #expect(decoded.count == frameCount)
        // Strictly increasing presentation timestamps prove ordering preserved.
        for index in 1..<decoded.count {
            #expect(decoded[index].time > decoded[index - 1].time)
        }
        // Grids are non-degenerate (conversion actually ran).
        #expect(decoded.allSatisfy { $0.grid.columns > 0 && $0.grid.rows > 0 })
    }
}

// MARK: - One-shot convenience

@Suite struct AskiVideoOneShotTests {
    @Test func convertVideoProducesNonEmptyRoundTrippableMP4() async throws {
        // Fabricate a source MP4 with our encoder (its output is a valid MP4).
        let sourceCount = 6
        let source = tempVideoURL("source.mp4")
        let output = tempVideoURL("ascii-out.mp4")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }
        let sourceFrames = (0..<sourceCount).map { index in
            RenderedVideoFrame(
                image: solidFrame(level: UInt8(30 + index * 30), width: 64, height: 48),
                time: CMTime(value: Int64(index), timescale: 6)
            )
        }
        try await ASCIIVideoEncoder().write(frameSequence(sourceFrames), to: source, options: VideoExportOptions())

        try await convertVideo(
            at: source,
            to: output,
            using: DefaultConverter(),
            columns: 20,
            font: .system(size: 10),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )

        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(try await countFrames(in: output) == sourceCount)
    }

    /// Regression for the encoder deadlock through the FULL chain: a 64-frame
    /// source (past the ~38 the writer input holds) decoded → converted → rendered
    /// → re-encoded. Real per-frame conversion supplies the slow, spaced appends
    /// that surfaced the SDK-26 receiver's lost wakeup on a real clip. `.timeLimit`
    /// fails fast instead of hanging if the deadlock ever returns.
    @Test(.timeLimit(.minutes(1)))
    func convertVideoChainCompletesAtScaleWithoutDeadlock() async throws {
        let sourceCount = 64
        let source = tempVideoURL("scale-source.mp4")
        let output = tempVideoURL("scale-ascii-out.mp4")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }
        // Eager frameSequence (back-to-back appends never deadlock) builds the source.
        let sourceFrames = (0..<sourceCount).map { index in
            RenderedVideoFrame(
                image: solidFrame(level: UInt8(index * 3), width: 64, height: 48),
                time: CMTime(value: Int64(index), timescale: 30)
            )
        }
        try await ASCIIVideoEncoder().write(frameSequence(sourceFrames), to: source, options: VideoExportOptions())

        try await convertVideo(
            at: source,
            to: output,
            using: DefaultConverter(),
            columns: 20,
            font: .system(size: 10),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )

        #expect(try await countFrames(in: output) == sourceCount)
    }
}

// MARK: - Cancellation

@Suite struct AskiVideoCancellationTests {
    @Test func cancellingDecodeTearsDownCleanlyWithoutHanging() async throws {
        let source = tempVideoURL("cancel.mp4")
        defer { try? FileManager.default.removeItem(at: source) }
        let frames = (0..<30).map { index in
            RenderedVideoFrame(
                image: solidFrame(level: UInt8(index % 200), width: 64, height: 48),
                time: CMTime(value: Int64(index), timescale: 30)
            )
        }
        try await ASCIIVideoEncoder().write(frameSequence(frames), to: source, options: VideoExportOptions())

        let converter = DefaultConverter()
        let task = Task { () -> Int in
            var seen = 0
            for try await _ in ASCIIVideoDecoder().grids(
                fromVideoAt: source,
                transform: { converter.convert($0, columns: 16) }
            ) {
                seen += 1
            }
            return seen
        }
        task.cancel()

        do {
            _ = try await task.value
            // Completed before cancellation took effect — also a clean, non-hanging outcome.
        } catch is CancellationError {
            // Expected: cancellation surfaced cleanly.
        } catch {
            Issue.record("unexpected error on cancellation: \(error)")
        }
        // Reaching here without hanging is the assertion.
    }
}

// MARK: - No-video-track rejection

@Suite struct AskiVideoTrackValidationTests {
    @Test func decodingAudioOnlySourceThrowsInsteadOfEmptyStream() async throws {
        // An audio-only input must FAIL, not yield an empty stream — otherwise
        // convertVideo "succeeds" with zero frames and the lab records a manifest
        // for an ascii.mp4 it never produced.
        let url = try await audioOnlyFile(named: "audio-only.m4a")
        defer { try? FileManager.default.removeItem(at: url) }

        let converter = DefaultConverter()
        do {
            for try await _ in ASCIIVideoDecoder().grids(
                fromVideoAt: url,
                transform: { converter.convert($0, columns: 16) }
            ) {}
            Issue.record("expected VideoDecodeError.noVideoTrack; got an empty stream")
        } catch VideoDecodeError.noVideoTrack {
            // Expected.
        }
    }
}

/// Writes a tiny valid AAC `.m4a` with an audio track and NO video track — the
/// fixture for the no-video-track rejection test. The writer encodes one buffer
/// of LPCM silence to AAC.
func audioOnlyFile(named name: String) async throws -> URL {
    let url = tempVideoURL(name)
    let writer = try AVAssetWriter(url: url, fileType: .m4a)
    let input = AVAssetWriterInput(
        mediaType: .audio,
        outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
        ])
    input.expectsMediaDataInRealTime = false
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? VideoEncodeError.startFailed }
    writer.startSession(atSourceTime: .zero)

    var asbd = AudioStreamBasicDescription(
        mSampleRate: 44_100,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
        mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0
    )
    var format: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault, asbd: &asbd,
        layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
        extensions: nil, formatDescriptionOut: &format
    )

    let frames = 1024, bytes = 1024 * 2
    var block: CMBlockBuffer?
    CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
        blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
        offsetToData: 0, dataLength: bytes,
        flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block
    )
    CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: bytes)

    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 44_100),
        presentationTimeStamp: .zero, decodeTimeStamp: .invalid
    )
    var sample: CMSampleBuffer?
    CMSampleBufferCreate(
        allocator: kCFAllocatorDefault, dataBuffer: block, dataReady: true,
        makeDataReadyCallback: nil, refcon: nil, formatDescription: format,
        sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
        sampleSizeEntryCount: 1, sampleSizeArray: [2], sampleBufferOut: &sample
    )

    while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
    input.append(sample!)
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? VideoEncodeError.finishFailed }
    return url
}

// MARK: - Orientation (preferredTransform applied on decode)

@Suite struct AskiVideoOrientationTests {
    /// A 90° track transform must match Apple's display-orientation oracle in
    /// both axes, not only swap width/height.
    @Test func ninetyDegreeTrackTransformMatchesPreferredTransformOracle() async throws {
        let storedWidth = 64, storedHeight = 48
        let frames = (0..<4).map { _ in quadrantFrame(width: storedWidth, height: storedHeight) }
        let url = tempVideoURL("rotated-source.mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        // 90° rotation: linear part maps (x, y) → (−y, x), so the extent swaps to 48×64.
        let rotate = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)
        try await writeOrientedSource(frames: frames, transform: rotate, timescale: 8, to: url)

        try await assertDecoderMatchesPreferredTransformOracle(for: url)
    }

    /// 270° rotation is the inverse portrait orientation; it must not silently
    /// pass with only the 90° case covered.
    @Test func twoHundredSeventyDegreeTrackTransformMatchesPreferredTransformOracle() async throws {
        let storedWidth = 64, storedHeight = 48
        let frames = (0..<4).map { _ in quadrantFrame(width: storedWidth, height: storedHeight) }
        let url = tempVideoURL("rotated-270-source.mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let rotate = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)
        try await writeOrientedSource(frames: frames, transform: rotate, timescale: 8, to: url)

        try await assertDecoderMatchesPreferredTransformOracle(for: url)
    }

    /// A front-camera mirror (a negative-determinant horizontal flip) must be
    /// undone on decode in both axes, not only checked with a left/right sample.
    @Test func frontCameraMirrorTransformMatchesPreferredTransformOracle() async throws {
        let width = 64, height = 48
        let frames = (0..<4).map { _ in quadrantFrame(width: width, height: height) }
        let url = tempVideoURL("mirrored-source.mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
        try await writeOrientedSource(frames: frames, transform: mirror, timescale: 8, to: url)

        try await assertDecoderMatchesPreferredTransformOracle(for: url)
    }
}

// MARK: - Orientation test helpers

/// Captures decoded (post-reorientation) `CGImage`s out of the decoder's
/// `@Sendable` transform closure so orientation can be asserted. The decoder
/// runs the closure on its serial executor; the lock guards the cross-isolation
/// hand-off.
final class DecodedImageCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [CGImage] = []
    func record(_ image: CGImage) { lock.lock(); images.append(image); lock.unlock() }
    var first: CGImage? { lock.lock(); defer { lock.unlock() }; return images.first }
}

/// An RGBA8 frame with four distinct quadrant gray levels. This catches vertical
/// flips, horizontal flips, and 180° inversions after video compression.
func quadrantFrame(width: Int, height: Int) -> CGImage {
    var buffer = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let level: UInt8
            switch (x < width / 2, y < height / 2) {
            case (true, true): level = 36
            case (false, true): level = 96
            case (true, false): level = 164
            case (false, false): level = 224
            }
            let p = (y * width + x) * 4
            buffer[p + 0] = level
            buffer[p + 1] = level
            buffer[p + 2] = level
            buffer[p + 3] = 255
        }
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

func assertDecoderMatchesPreferredTransformOracle(for url: URL) async throws {
    let decoded = try await firstDecodedImage(from: url)
    let oracle = try await preferredTransformOracleImage(from: url)

    #expect(decoded.width == oracle.width)
    #expect(decoded.height == oracle.height)

    let decodedSamples = orientationSamples(in: decoded)
    let oracleSamples = orientationSamples(in: oracle)
    #expect(decodedSamples.count == oracleSamples.count)
    for index in decodedSamples.indices {
        let delta = abs(decodedSamples[index] - oracleSamples[index])
        #expect(delta <= 24, "sample \(index) mismatch: decoded \(decodedSamples), oracle \(oracleSamples)")
    }
}

func firstDecodedImage(from url: URL) async throws -> CGImage {
    let collector = DecodedImageCollector()
    let converter = DefaultConverter()
    for try await _ in ASCIIVideoDecoder().grids(
        fromVideoAt: url,
        transform: { image in
            collector.record(image); return converter.convert(image, columns: 24)
        }
    ) {}
    return try #require(collector.first, "decoder yielded no frames")
}

func preferredTransformOracleImage(from url: URL) async throws -> CGImage {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    return try await withCheckedThrowingContinuation { continuation in
        generator.generateCGImageAsynchronously(for: .zero) { image, _, error in
            if let image {
                continuation.resume(returning: image)
            } else {
                continuation.resume(throwing: error ?? VideoDecodeError.conversionFailed)
            }
        }
    }
}

func orientationSamples(in image: CGImage) -> [Int] {
    let leftX = max(1, image.width / 4)
    let rightX = min(image.width - 2, (image.width * 3) / 4)
    let lowerY = max(1, image.height / 4)
    let upperY = min(image.height - 2, (image.height * 3) / 4)
    return [
        grayMean(in: image, centerX: leftX, centerY: lowerY),
        grayMean(in: image, centerX: rightX, centerY: lowerY),
        grayMean(in: image, centerX: leftX, centerY: upperY),
        grayMean(in: image, centerX: rightX, centerY: upperY),
    ]
}

func grayMean(in image: CGImage, centerX: Int, centerY: Int, radius: Int = 3) -> Int {
    let width = image.width, height = image.height
    var data = [UInt8](repeating: 0, count: width * height * 4)
    data.withUnsafeMutableBytes { raw in
        let context = CGContext(
            data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    let minX = max(0, centerX - radius)
    let maxX = min(width - 1, centerX + radius)
    let minY = max(0, centerY - radius)
    let maxY = min(height - 1, centerY + radius)
    var total = 0
    var count = 0
    for y in minY...maxY {
        for x in minX...maxX {
            let offset = (y * width + x) * 4
            total += (Int(data[offset]) + Int(data[offset + 1]) + Int(data[offset + 2])) / 3
            count += 1
        }
    }
    return total / max(count, 1)
}

/// Writes a real MP4 whose video track carries `transform` as its
/// `preferredTransform` — the fixture the orientation tests reorient on decode.
/// `ASCIIVideoEncoder` intentionally has no transform parameter (no app need),
/// so this test-local writer sets `AVAssetWriterInput.transform` directly.
func writeOrientedSource(
    frames: [CGImage], transform: CGAffineTransform, timescale: Int32, to url: URL
) async throws {
    let width = frames[0].width, height = frames[0].height  // even in every caller
    let writer = try AVAssetWriter(url: url, fileType: .mp4)
    let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
    input.expectsMediaDataInRealTime = false
    input.transform = transform
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
    )
    guard writer.canAdd(input) else { throw VideoEncodeError.cannotAddInput }
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? VideoEncodeError.startFailed }
    writer.startSession(atSourceTime: .zero)
    guard let pool = adaptor.pixelBufferPool else { throw VideoEncodeError.noPool }

    for (index, frame) in frames.enumerated() {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        let buffer = bgraBuffer(from: frame, pool: pool, width: width, height: height)
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: timescale)) else {
            throw writer.error ?? VideoEncodeError.appendFailed
        }
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? VideoEncodeError.finishFailed }
}

/// Draws `image` into a fresh 32BGRA buffer from `pool` (mirrors the encoder's
/// drawing path so the fixture is a valid source frame).
private func bgraBuffer(from image: CGImage, pool: CVPixelBufferPool, width: Int, height: Int) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
    let buf = buffer!
    CVPixelBufferLockBaseAddress(buf, [])
    defer { CVPixelBufferUnlockBaseAddress(buf, []) }
    let context = CGContext(
        data: CVPixelBufferGetBaseAddress(buf),
        width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return buf
}
