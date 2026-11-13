import CoreGraphics
import CoreMedia
import Foundation

/// An oriented decoded image with a source identity independent of its PTS.
/// CGImage and CMTime are Sendable, as in RenderedVideoFrame. Direct access to
/// CVPixelBuffer and the reader stays in DecodeSession, but VideoToolbox may
/// retain the pixel buffer as immutable backing for the CGImage's lifetime.
struct DecodedVideoFrame: Sendable {
    let sourceID: Int
    let image: CGImage
    let time: CMTime
}

/// Selects source images using the existing resampler before converting them.
/// One selected identity owns one cached grid; duplicate output slots reuse
/// that grid while keeping their own CFR timestamps. No image cache or clip-wide
/// collection is added. Like ResampleSession, this has one serial consumer.
actor VideoFrameSelectionPump {
    // Keep synchronous conversion on a dedicated serial executor, as it was
    // inside DecodeSession before selection moved ahead of conversion.
    private let queue = DispatchSerialQueue(label: "art.aski.video.selection")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private var selector: ResampleSession<DecodedVideoFrame>?
    private let transform: @Sendable (CGImage) -> ASCIIGrid
    private var cached: (sourceID: Int, grid: ASCIIGrid)?

    init(
        source: AsyncThrowingStream<DecodedVideoFrame, Error>,
        targetFPS: Int,
        sourceDuration: TimeInterval,
        stats: ResampleStats,
        transform: @escaping @Sendable (CGImage) -> ASCIIGrid
    ) throws {
        let endSlot = try resamplePreflight(targetFPS: targetFPS, sourceDuration: sourceDuration)
        self.transform = transform
        self.selector = ResampleSession(
            source: source,
            timing: .absolute { CMTimeGetSeconds($0.time) },
            retime: { frame, slot in
                DecodedVideoFrame(
                    sourceID: frame.sourceID,
                    image: frame.image,
                    time: CMTime(value: Int64(slot), timescale: Int32(targetFPS))
                )
            },
            targetFPS: targetFPS,
            endSlot: endSlot,
            stats: stats
        )
    }

    func next() async throws -> ASCIIVideoFrame? {
        guard let selector else { return nil }
        do {
            try Task.checkCancellation()
            guard let frame = try await selector.next() else {
                finish()
                return nil
            }
            try Task.checkCancellation()

            let grid: ASCIIGrid
            if let cached, cached.sourceID == frame.sourceID {
                grid = cached.grid
            } else {
                grid = transform(frame.image)
                cached = (frame.sourceID, grid)
            }
            try Task.checkCancellation()
            return ASCIIVideoFrame(grid: grid, time: frame.time)
        } catch {
            finish()
            throw error
        }
    }

    private func finish() {
        // Release held/lookahead images and the source iterator even when the
        // duration bound leaves unread source frames. The stream's ownership
        // chain then releases its decoder when no in-flight pull remains.
        selector = nil
        cached = nil
    }
}
