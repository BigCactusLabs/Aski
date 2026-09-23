import Aski
import AVFoundation
import Benchmark
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

private let videoBenchmarkFrameCount = 12
private let videoBenchmarkColumns = 80

private struct VideoBenchmarkFixture: Sendable {
    let identitySource: URL
    let rotatedSource: URL
    let renderedFrames: [RenderedVideoFrame]
}

func addVideoPipelineBenchmarks() {
    addDecodeBenchmark(name: "video-decode-720p-12frames", rotated: false, convert: false)
    addDecodeBenchmark(name: "video-decode-rotated-720p-12frames", rotated: true, convert: false)
    addDecodeBenchmark(name: "video-decode-convert-720p-80cols-12frames", rotated: false, convert: true)
    addDecodeBenchmark(name: "video-decode-convert-rotated-720p-80cols-12frames", rotated: true, convert: true)
    addEncodeBenchmark()
    addEndToEndBenchmark(name: "video-e2e-serial-720p-80cols-12frames", pipelined: false)
    addEndToEndBenchmark(name: "video-e2e-one-shot-720p-80cols-12frames", pipelined: true)
    addEndToEndBenchmark(
        name: "video-e2e-serial-rotated-720p-80cols-12frames",
        pipelined: false,
        rotated: true
    )
    addEndToEndBenchmark(
        name: "video-e2e-one-shot-rotated-720p-80cols-12frames",
        pipelined: true,
        rotated: true
    )
}

private func addDecodeBenchmark(name: String, rotated: Bool, convert: Bool) {
    let root = videoBenchmarkRoot(name)
    Benchmark(
        name,
        configuration: videoBenchmarkConfiguration(),
        closure: { benchmark, fixture in
            let source = rotated ? fixture.rotatedSource : fixture.identitySource
            let converter = DefaultConverter()
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                var count = 0
                var previousTime: CMTime?
                for try await frame in ASCIIVideoDecoder().grids(
                    fromVideoAt: source,
                    transform: { image in
                        if convert {
                            converter.convert(image, columns: videoBenchmarkColumns)
                        } else {
                            ASCIIGrid(cells: [], colorSpace: .sRGB)
                        }
                    }
                ) {
                    if let previousTime, frame.time <= previousTime {
                        benchmark.error("video decode produced out-of-order PTS")
                    }
                    previousTime = frame.time
                    count += 1
                }
                if count != videoBenchmarkFrameCount {
                    benchmark.error("video decode produced \(count) frames; expected \(videoBenchmarkFrameCount)")
                }
                blackHole(count)
            }
            benchmark.stopMeasurement()
        },
        setup: { try await makeVideoBenchmarkFixture(at: root) },
        teardown: { try? FileManager.default.removeItem(at: root) }
    )
}

private func addEncodeBenchmark() {
    let name = "video-encode-ascii-12frames"
    let root = videoBenchmarkRoot(name)
    Benchmark(
        name,
        configuration: videoBenchmarkConfiguration(),
        closure: { benchmark, fixture in
            var outputs: [URL] = []
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                let output = root.appendingPathComponent("encode-\(UUID().uuidString).mp4")
                try await ASCIIVideoEncoder().write(
                    videoFrameStream(fixture.renderedFrames),
                    to: output,
                    options: VideoExportOptions()
                )
                outputs.append(output)
            }
            benchmark.stopMeasurement()
            for output in outputs {
                try await verifyOrderedVideo(at: output)
                try? FileManager.default.removeItem(at: output)
            }
        },
        setup: { try await makeVideoBenchmarkFixture(at: root) },
        teardown: { try? FileManager.default.removeItem(at: root) }
    )
}

private func addEndToEndBenchmark(name: String, pipelined: Bool, rotated: Bool = false) {
    let root = videoBenchmarkRoot(name)
    Benchmark(
        name,
        configuration: videoBenchmarkConfiguration(),
        closure: { benchmark, fixture in
            var outputs: [URL] = []
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                let output = root.appendingPathComponent("e2e-\(UUID().uuidString).mp4")
                let source = rotated ? fixture.rotatedSource : fixture.identitySource
                if pipelined {
                    try await convertVideo(
                        at: source,
                        to: output,
                        using: DefaultConverter(),
                        columns: videoBenchmarkColumns,
                        font: .system(size: 10),
                        backgroundColor: videoBenchmarkBackground,
                        scale: 1
                    )
                } else {
                    try await runSerialVideoPipeline(from: source, to: output)
                }
                outputs.append(output)
            }
            benchmark.stopMeasurement()
            for output in outputs {
                try await verifyOrderedVideo(at: output)
                try? FileManager.default.removeItem(at: output)
            }
        },
        setup: { try await makeVideoBenchmarkFixture(at: root) },
        teardown: { try? FileManager.default.removeItem(at: root) }
    )
}

private func videoBenchmarkConfiguration() -> Benchmark.Configuration {
    .init(
        metrics: [
            .wallClock, .throughput, .cpuTotal, .peakMemoryResidentDelta,
            .mallocCountTotal,
        ],
        warmupIterations: 1,
        maxDuration: .seconds(3),
        maxIterations: 5
    )
}

private func videoBenchmarkRoot(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("AskiVideoBenchmarks", isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
}

private var videoBenchmarkBackground: CGColor {
    CGColor(red: 0, green: 0, blue: 0, alpha: 1)
}

private func makeVideoBenchmarkFixture(at root: URL) async throws -> VideoBenchmarkFixture {
    try? FileManager.default.removeItem(at: root)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let sourceFrames = (0..<videoBenchmarkFrameCount).map(videoBenchmarkFrame)
    let identitySource = root.appendingPathComponent("identity.mp4")
    let rotatedSource = root.appendingPathComponent("rotated.mp4")
    let sourceCarriers = sourceFrames.enumerated().map { index, image in
        RenderedVideoFrame(
            image: image,
            time: CMTime(value: Int64(index), timescale: 30)
        )
    }
    try await ASCIIVideoEncoder().write(
        videoFrameStream(sourceCarriers),
        to: identitySource,
        options: VideoExportOptions()
    )
    try await writeRotatedVideo(
        sourceFrames,
        transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0),
        to: rotatedSource
    )

    let converter = DefaultConverter()
    let renderedFrames = sourceCarriers.map { frame in
        let grid = converter.convert(frame.image, columns: videoBenchmarkColumns)
        return RenderedVideoFrame(
            image: grid.renderImage(
                font: .system(size: 10),
                backgroundColor: videoBenchmarkBackground,
                scale: 1
            ),
            time: frame.time
        )
    }
    return VideoBenchmarkFixture(
        identitySource: identitySource,
        rotatedSource: rotatedSource,
        renderedFrames: renderedFrames
    )
}

private func videoBenchmarkFrame(_ index: Int) -> CGImage {
    let width = 1280
    let height = 720
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let phase = CGFloat(index) / CGFloat(videoBenchmarkFrameCount)
    context.setFillColor(red: 0.08 + phase * 0.3, green: 0.12, blue: 0.2 + phase * 0.4, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(red: 0.9, green: 0.3 + phase * 0.5, blue: 0.15, alpha: 1)
    context.fill(
        CGRect(
            x: CGFloat(index * 73 % 900),
            y: CGFloat(index * 41 % 420),
            width: 320,
            height: 220
        )
    )
    context.setStrokeColor(CGColor(gray: 0.95, alpha: 1))
    context.setLineWidth(18)
    context.strokeEllipse(
        in: CGRect(
            x: CGFloat(940 - index * 29),
            y: CGFloat(440 - index * 17),
            width: 180,
            height: 180
        )
    )
    return context.makeImage()!
}

private func videoFrameStream(
    _ frames: [RenderedVideoFrame]
) -> AsyncThrowingStream<RenderedVideoFrame, Error> {
    AsyncThrowingStream { continuation in
        for frame in frames { continuation.yield(frame) }
        continuation.finish()
    }
}

private func runSerialVideoPipeline(from source: URL, to output: URL) async throws {
    let converter = DefaultConverter()
    let decoded = ASCIIVideoDecoder().grids(
        fromVideoAt: source,
        transform: { converter.convert($0, columns: videoBenchmarkColumns) }
    )
    let pump = VideoBenchmarkRenderPump(stream: decoded)
    let rendered = AsyncThrowingStream(unfolding: { try await pump.next() })
    try await ASCIIVideoEncoder().write(rendered, to: output, options: VideoExportOptions())
}

private actor VideoBenchmarkRenderPump {
    private var iterator: AsyncThrowingStream<ASCIIVideoFrame, Error>.AsyncIterator

    init(stream: AsyncThrowingStream<ASCIIVideoFrame, Error>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> RenderedVideoFrame? {
        var localIterator = iterator
        let frame = try await localIterator.next(isolation: #isolation)
        iterator = localIterator
        guard let frame else { return nil }
        return render(frame)
    }

    private func render(_ frame: ASCIIVideoFrame) -> RenderedVideoFrame {
        return RenderedVideoFrame(
            image: frame.grid.renderImage(
                font: .system(size: 10),
                backgroundColor: videoBenchmarkBackground,
                scale: 1
            ),
            time: frame.time
        )
    }
}

private func verifyOrderedVideo(at url: URL) async throws {
    var count = 0
    var previousTime: CMTime?
    for try await frame in ASCIIVideoDecoder().grids(
        fromVideoAt: url,
        transform: { _ in ASCIIGrid(cells: [], colorSpace: .sRGB) }
    ) {
        if let previousTime, frame.time <= previousTime {
            throw VideoBenchmarkError.outOfOrder
        }
        previousTime = frame.time
        count += 1
    }
    guard count == videoBenchmarkFrameCount else {
        throw VideoBenchmarkError.unexpectedFrameCount(count)
    }
}

private enum VideoBenchmarkError: Error {
    case outOfOrder
    case unexpectedFrameCount(Int)
    case writerSetupFailed
    case pixelBufferFailed
    case appendFailed
}

private func writeRotatedVideo(
    _ frames: [CGImage],
    transform: CGAffineTransform,
    to url: URL
) async throws {
    guard let first = frames.first else { return }
    let writer = try AVAssetWriter(url: url, fileType: .mp4)
    let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: first.width,
            AVVideoHeightKey: first.height,
        ]
    )
    input.expectsMediaDataInRealTime = false
    input.transform = transform
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: first.width,
            kCVPixelBufferHeightKey as String: first.height,
        ]
    )
    guard writer.canAdd(input) else { throw VideoBenchmarkError.writerSetupFailed }
    writer.add(input)
    guard writer.startWriting() else {
        throw writer.error ?? VideoBenchmarkError.writerSetupFailed
    }
    writer.startSession(atSourceTime: .zero)
    guard let pool = adaptor.pixelBufferPool else { throw VideoBenchmarkError.pixelBufferFailed }

    for (index, frame) in frames.enumerated() {
        while !input.isReadyForMoreMediaData {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(5))
        }
        let buffer = try videoPixelBuffer(
            from: frame,
            pool: pool,
            width: first.width,
            height: first.height
        )
        guard
            adaptor.append(
                buffer,
                withPresentationTime: CMTime(value: Int64(index), timescale: 30)
            )
        else {
            throw writer.error ?? VideoBenchmarkError.appendFailed
        }
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else {
        throw writer.error ?? VideoBenchmarkError.appendFailed
    }
}

private func videoPixelBuffer(
    from image: CGImage,
    pool: CVPixelBufferPool,
    width: Int,
    height: Int
) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
        let buffer
    else {
        throw VideoBenchmarkError.pixelBufferFailed
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )
    else {
        throw VideoBenchmarkError.pixelBufferFailed
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return buffer
}
