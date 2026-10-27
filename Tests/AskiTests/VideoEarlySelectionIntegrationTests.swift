import CoreGraphics
import CoreMedia
import Foundation
import Synchronization
import Testing
@testable import Aski

/// Native codec/orientation checks against the retained convert-then-select
/// control. These run in the existing serialized media lane.
@Suite struct VideoEarlySelectionIntegrationTests {
    struct Case: Sendable {
        let name: String
        let sourceFPS: Int32
        let targetFPS: Int
        let transform: CGAffineTransform
        var sourceTicks: [Int64]? = nil
    }

    static let cases: [Case] = [
        Case(name: "60-to-12", sourceFPS: 60, targetFPS: 12, transform: .identity),
        Case(name: "30-to-12", sourceFPS: 30, targetFPS: 12, transform: .identity),
        Case(name: "12-to-12", sourceFPS: 12, targetFPS: 12, transform: .identity),
        Case(name: "12-to-30", sourceFPS: 12, targetFPS: 30, transform: .identity),
        Case(name: "variable-rate", sourceFPS: 1000, targetFPS: 12, transform: .identity, sourceTicks: [0, 10, 60, 400, 410, 900]),
        Case(name: "rotate-90", sourceFPS: 30, targetFPS: 12, transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)),
        Case(name: "rotate-270", sourceFPS: 30, targetFPS: 12, transform: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)),
        Case(name: "mirror", sourceFPS: 30, targetFPS: 12, transform: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 0, ty: 0)),
    ]

    @Test(arguments: VideoEarlySelectionIntegrationTests.cases)
    func matchesRetainedPipelineCellsTimestampsStatisticsAndRenderedPixels(fixture: Case) async throws {
        let url = tempVideoURL("early-selection-\(fixture.name).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        if let ticks = fixture.sourceTicks {
            let frames = ticks.enumerated().map { index, tick in
                RenderedVideoFrame(image: earlySelectionQualityImage(index), time: CMTime(value: tick, timescale: fixture.sourceFPS))
            }
            try await ASCIIVideoEncoder().write(frameSequence(frames), to: url, options: VideoExportOptions())
        } else {
            try await writeOrientedSource(
                frames: (0..<12).map(earlySelectionQualityImage), transform: fixture.transform,
                timescale: fixture.sourceFPS, to: url
            )
        }
        let decoder = ASCIIVideoDecoder()
        let duration = try await decoder.sourceDuration(ofVideoAt: url)
        let converter = DefaultConverter()
        let controlStats = ResampleStats()
        let candidateStats = ResampleStats()
        let candidateCalls = Mutex(0)
        // This is the pre-change order, including its source-side prefetch.
        let control = try resampledVideoFrames(
            decoder.pipelinedGrids(fromVideoAt: url, transform: { converter.convert($0, columns: 24) }),
            targetFPS: fixture.targetFPS, sourceDuration: duration, into: controlStats
        )
        let candidate = try decoder.selectedGrids(
            fromVideoAt: url, targetFPS: fixture.targetFPS, sourceDuration: duration, into: candidateStats,
            transform: { image in
                candidateCalls.withLock { $0 += 1 }
                return converter.convert(image, columns: 24)
            }
        )
        var expected: [ASCIIVideoFrame] = []
        var actual: [ASCIIVideoFrame] = []
        for try await frame in control { expected.append(frame) }
        for try await frame in candidate { actual.append(frame) }

        #expect(!expected.isEmpty)
        #expect(actual.count == expected.count)
        #expect(actual.map(\.time) == expected.map(\.time))
        #expect(actual.map(\.time.value) == expected.map(\.time.value))
        #expect(actual.allSatisfy { $0.time.timescale == Int32(fixture.targetFPS) })
        #expect(actual.map(\.grid.cells) == expected.map(\.grid.cells))
        #expect(await candidateStats.sourceFrameCount == (await controlStats.sourceFrameCount))
        #expect(await candidateStats.outputFrameCount == (await controlStats.outputFrameCount))
        #expect(await candidateStats.droppedCount == (await controlStats.droppedCount))
        #expect(await candidateStats.duplicatedCount == (await controlStats.duplicatedCount))
        let duplicated = await candidateStats.duplicatedCount
        #expect(candidateCalls.withLock { $0 } == actual.count - duplicated)

        // Compare full rendered RGBA bytes before another lossy video encode.
        // A time-varying pattern also exercises duplicate grids at output PTS.
        let pattern = OngoingPattern.pulse(period: 0.5, depth: 0.8)
        for (left, right) in zip(actual, expected) {
            let a = left.applyingOngoingPattern(pattern).grid
            let b = right.applyingOngoingPattern(pattern).grid
            #expect(a.cells == b.cells)
            let font = ASCIIFont.system(size: 10)
            let background = CGColor(gray: 0, alpha: 1)
            let imageA = a.renderImage(font: font, backgroundColor: background, scale: 1)
            let imageB = b.renderImage(font: font, backgroundColor: background, scale: 1)
            #expect(imageA.width == imageB.width && imageA.height == imageB.height)
            #expect(earlySelectionRGBA(imageA) == earlySelectionRGBA(imageB))
        }
    }

    @Test func publicDecoderTransformsStillRunForEveryFrame() async throws {
        let url = tempVideoURL("early-selection-public-transform.mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeOrientedSource(
            frames: (0..<12).map(earlySelectionQualityImage), transform: .identity, timescale: 60, to: url
        )
        let calls = Mutex(0)
        let transform: @Sendable (CGImage) -> ASCIIGrid = { _ in
            calls.withLock { $0 += 1 }
            return ASCIIGrid(cells: [], colorSpace: .sRGB)
        }
        var directTimes: [CMTime] = []
        for try await frame in ASCIIVideoDecoder().grids(fromVideoAt: url, transform: transform) {
            directTimes.append(frame.time)
        }
        #expect(calls.withLock { $0 } == 12)
        var pipelinedTimes: [CMTime] = []
        for try await frame in ASCIIVideoDecoder().pipelinedGrids(fromVideoAt: url, transform: transform) {
            pipelinedTimes.append(frame.time)
        }
        #expect(calls.withLock { $0 } == 24)
        #expect(directTimes.count == 12)
        #expect(pipelinedTimes == directTimes)
    }

    @Test(.timeLimit(.minutes(1)))
    func earlySelectionExportPropagatesEncoderSetupFailure() async throws {
        let source = tempVideoURL("early-selection-encoder-failure.mp4")
        let missingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("AskiMissing-\(UUID().uuidString)")
        let output = missingDirectory.appendingPathComponent("output.mp4")
        defer { try? FileManager.default.removeItem(at: source) }
        try await writeOrientedSource(
            frames: (0..<6).map(earlySelectionQualityImage), transform: .identity, timescale: 30, to: source
        )
        await #expect(throws: (any Error).self) {
            _ = try await convertVideo(
                at: source, to: output, using: DefaultConverter(), columns: 24,
                font: .system(size: 10), backgroundColor: CGColor(gray: 0, alpha: 1), scale: 1, targetFPS: 12
            )
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}

/// Spatially asymmetric, time-varying input exposes orientation and source
/// selection errors without depending on exact codec reconstruction values.
private func earlySelectionQualityImage(_ index: Int) -> CGImage {
    let width = 160, height = 96
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(red: 0.08, green: 0.12, blue: 0.3, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(red: 0.9, green: 0.2 + CGFloat(index) / 24, blue: 0.1, alpha: 1)
    context.fill(CGRect(x: 5 + index * 7, y: 8, width: 35, height: 30))
    context.setFillColor(red: 0.1, green: 0.85, blue: 0.45, alpha: 1)
    context.fillEllipse(in: CGRect(x: 90, y: 40 + index, width: 50, height: 30))
    return context.makeImage()!
}

private func earlySelectionRGBA(_ image: CGImage) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(
            data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return pixels
}
