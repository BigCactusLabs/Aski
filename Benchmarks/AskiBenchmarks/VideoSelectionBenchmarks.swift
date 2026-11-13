import Aski
import AVFoundation
import Benchmark
import CoreGraphics
import CoreMedia
import CoreVideo
import CryptoKit
import Foundation

/// ASKI-93 instruments, not regression budgets. Both worktrees run these same
/// public calls on the same cached MP4 bytes. Source creation, verification and
/// output inspection are outside wall/CPU/allocation measurement. Peak RSS still
/// describes the whole benchmark process, including setup and warmup.
func addVideoSelectionBenchmarks() {
    let cases: [VideoSelectionCase] = [
        .init(name: "source-30fps", sourceFPS: 30, targetFPS: nil, counts: nil),
        .init(name: "60to12", sourceFPS: 60, targetFPS: 12, counts: [59, 12, 46, 0]),
        .init(name: "120to12", sourceFPS: 120, targetFPS: 12, counts: [116, 12, 103, 0]),
        .init(name: "30to12", sourceFPS: 30, targetFPS: 12, counts: [30, 12, 17, 0]),
        .init(name: "12to12", sourceFPS: 12, targetFPS: 12, counts: [12, 12, 0, 0]),
        .init(name: "12to30", sourceFPS: 12, targetFPS: 30, counts: [12, 30, 0, 18]),
        .init(name: "vfrto12", sourceFPS: 0, targetFPS: 12, counts: [6, 12, 2, 8]),
        .init(name: "60to12-rotated", sourceFPS: 60, targetFPS: 12, counts: [59, 12, 46, 0], rotated: true),
        .init(name: "60to12-10s", sourceFPS: 60, targetFPS: 12, counts: [599, 120, 478, 0], seconds: 10),
    ]
    for spec in cases {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("Aski93Run-\(UUID().uuidString)", isDirectory: true)
        Benchmark(
            "aski93-video-\(spec.name)-720p-80cols",
            configuration: .init(
                metrics: [.wallClock, .cpuTotal, .mallocCountTotal, .peakMemoryResident],
                warmupIterations: 1, scalingFactor: .one,
                maxDuration: .seconds(3), maxIterations: 5
            ),
            closure: { benchmark, fixture in
                var outputs: [(URL, ResampleReport?)] = []
                benchmark.startMeasurement()
                for _ in benchmark.scaledIterations {
                    let output = fixture.scratch.appendingPathComponent("output-\(UUID().uuidString).mp4")
                    let report = try await convertVideo(
                        at: fixture.source, to: output, using: DefaultConverter(), columns: 80,
                        font: .system(size: 10), backgroundColor: CGColor(gray: 0, alpha: 1), scale: 1,
                        targetFPS: spec.targetFPS
                    )
                    outputs.append((output, report))
                }
                benchmark.stopMeasurement()
                for (output, report) in outputs {
                    try spec.verify(report)
                    try await verifySelectionTimes(at: output, expected: spec.outputTimes)
                    try FileManager.default.removeItem(at: output)
                }
            },
            setup: { try await makeVideoSelectionFixture(spec, scratch: scratch) },
            teardown: { try? FileManager.default.removeItem(at: scratch) }
        )
    }
}

private struct VideoSelectionCase: Sendable {
    let name: String
    let sourceFPS: Int  // zero selects the literal VFR timestamp fixture
    let targetFPS: Int?
    // Frozen selector counts: pulled source, output, dropped, duplicated.
    // They are not decoder/converter-call counts: lookahead and prefetch differ.
    let counts: [Int]?
    var rotated = false
    var seconds = 1

    var timescale: Int32 { sourceFPS == 0 ? 1000 : Int32(sourceFPS) }
    var ticks: [Int64] { sourceFPS == 0 ? [0, 10, 60, 400, 410, 900] : (0..<(sourceFPS * seconds)).map(Int64.init) }
    var sourceTimes: [CMTime] { ticks.map { CMTime(value: $0, timescale: timescale) } }
    var outputTimes: [CMTime] {
        guard let targetFPS else { return sourceTimes }
        return (0..<(targetFPS * seconds)).map { CMTime(value: Int64($0), timescale: Int32(targetFPS)) }
    }
    var transform: CGAffineTransform {
        rotated ? CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0) : .identity
    }
    var sourceName: String {
        let timing = sourceFPS == 0 ? "vfr" : "\(sourceFPS)fps"
        return "source-v1-\(timing)-\(seconds)s-\(rotated ? "rotated" : "identity").mp4"
    }

    func verify(_ report: ResampleReport?) throws {
        guard let targetFPS, let counts else {
            guard report == nil else { throw VideoSelectionError.invalid("unexpected resample report") }
            return
        }
        guard let report,
            report.requestedFPS == targetFPS, report.achievedFPS == Double(targetFPS),
            [report.sourceFrameCount, report.outputFrameCount, report.droppedCount, report.duplicatedCount] == counts
        else { throw VideoSelectionError.invalid("resample report disagrees with frozen \(name) counts") }
    }
}

private struct VideoSelectionFixture: Sendable {
    let source: URL
    let scratch: URL
}

private enum VideoSelectionError: Error {
    case invalid(String)
}

private func makeVideoSelectionFixture(_ spec: VideoSelectionCase, scratch: URL) async throws -> VideoSelectionFixture {
    let files = FileManager.default
    try files.createDirectory(at: scratch, withIntermediateDirectories: true)
    // Reused across baseline/candidate processes. An explicit directory makes
    // sources and their hashes easy to retain with the paired experiment.
    let cache =
        ProcessInfo.processInfo.environment["ASKI93_FIXTURE_ROOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? files.temporaryDirectory.appendingPathComponent("Aski93Fixtures-v1", isDirectory: true)
    try files.createDirectory(at: cache, withIntermediateDirectories: true)
    let source = cache.appendingPathComponent(spec.sourceName)
    let checksum = source.appendingPathExtension("sha256")
    let needsCreation = !files.fileExists(atPath: source.path)
    do {
        if needsCreation {
            let temporary = scratch.appendingPathComponent("source.mp4")
            try await writeVideoSelectionSource(spec, to: temporary)
            let sha = try selectionFileHash(temporary)
            try files.moveItem(at: temporary, to: source)
            try (sha + "\n").write(to: checksum, atomically: true, encoding: .utf8)
        }
        let sha = try selectionFileHash(source)
        let recorded = try String(contentsOf: checksum, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard sha == recorded else { throw VideoSelectionError.invalid("cached source hash mismatch: \(spec.sourceName)") }
        let decoder = ASCIIVideoDecoder()
        let duration = try await decoder.sourceDuration(ofVideoAt: source)
        guard duration == Double(spec.seconds) else { throw VideoSelectionError.invalid("fixture duration \(duration) differs from \(spec.seconds)s") }
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoSelectionError.invalid("fixture has no video track") }
        let dimensions = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        guard dimensions == CGSize(width: 1280, height: 720), transform == spec.transform else {
            throw VideoSelectionError.invalid("fixture dimensions or orientation changed")
        }
        try await verifySelectionTimes(at: source, expected: spec.sourceTimes)
        // Populate every cache entry before recorded A/B captures. Creating an
        // input clip in this process can raise its peak RSS even before timing.
        print("ASKI93 source \(spec.sourceName) sha256=\(sha) duration=\(duration) frames=\(spec.ticks.count) created=\(needsCreation)")
        return VideoSelectionFixture(source: source, scratch: scratch)
    } catch {
        try? files.removeItem(at: scratch)
        throw error
    }
}

private func selectionFileHash(_ url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
}

private func verifySelectionTimes(at url: URL, expected: [CMTime]) async throws {
    var index = 0
    for try await frame in ASCIIVideoDecoder().grids(
        fromVideoAt: url, transform: { _ in ASCIIGrid(cells: [], colorSpace: .sRGB) }
    ) {
        guard index < expected.count, frame.time == expected[index],
            index == 0 || frame.time > expected[index - 1]
        else { throw VideoSelectionError.invalid("decoded frame count, order or PTS differs from frozen fixture") }
        index += 1
    }
    guard index == expected.count else { throw VideoSelectionError.invalid("decoded \(index) frames, expected \(expected.count)") }
}

private func writeVideoSelectionSource(_ spec: VideoSelectionCase, to url: URL) async throws {
    let writer = try AVAssetWriter(url: url, fileType: .mp4)
    let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1280, AVVideoHeightKey: 720,
        ])
    input.expectsMediaDataInRealTime = false
    input.transform = spec.transform
    input.mediaTimeScale = spec.timescale
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1280,
            kCVPixelBufferHeightKey as String: 720,
        ]
    )
    guard writer.canAdd(input) else { throw VideoSelectionError.invalid("fixture writer cannot add input") }
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? VideoSelectionError.invalid("fixture writer failed to start") }
    writer.startSession(atSourceTime: .zero)
    guard let pool = adaptor.pixelBufferPool else { throw VideoSelectionError.invalid("fixture writer has no buffer pool") }
    do {
        for (index, time) in spec.sourceTimes.enumerated() {
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard writer.status == .writing else { throw writer.error ?? VideoSelectionError.invalid("fixture writer stopped") }
                try await Task.sleep(for: .milliseconds(5))
            }
            // One buffer is drawn and appended at a time. No array of source
            // CGImages/rendered grids inflates the long-fixture process RSS.
            let buffer = try selectionPixelBuffer(pool: pool, index: index)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw writer.error ?? VideoSelectionError.invalid("fixture append failed")
            }
        }
        writer.endSession(atSourceTime: CMTime(value: Int64(spec.seconds) * Int64(spec.timescale), timescale: spec.timescale))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? VideoSelectionError.invalid("fixture writer did not finish") }
    } catch {
        writer.cancelWriting()
        throw error
    }
}

private func selectionPixelBuffer(pool: CVPixelBufferPool, index: Int) throws -> CVPixelBuffer {
    var created: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created) == kCVReturnSuccess, let buffer = created else {
        throw VideoSelectionError.invalid("fixture pixel buffer allocation failed")
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: 1280, height: 720,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
    else { throw VideoSelectionError.invalid("fixture bitmap context failed") }
    context.setFillColor(CGColor(gray: 0.12, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1280, height: 720))
    for stripe in 0..<20 {
        let phase = CGFloat((stripe * 7 + index * 3) % 31) / 31
        context.setFillColor(red: phase, green: 0.2, blue: 1 - phase, alpha: 1)
        context.fill(CGRect(x: CGFloat(stripe * 64), y: CGFloat((index * 13 + stripe * 17) % 240), width: 48, height: 480))
    }
    context.setStrokeColor(CGColor(gray: 0.95, alpha: 1))
    context.setLineWidth(16)
    context.strokeEllipse(in: CGRect(x: CGFloat(80 + (index * 37) % 800), y: 160, width: 240, height: 240))
    return buffer
}
