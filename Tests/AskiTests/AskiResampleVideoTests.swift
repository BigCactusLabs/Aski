import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import Aski

@Suite struct AskiVideoSourceTimingTests {
    /// Builds a clip of `count` distinct frames at `timescale` (1 frame per tick),
    /// returns its URL. Mirrors the AskiVideoLoopTests fabrication pattern.
    private func makeClip(count: Int, timescale: Int32, name: String) async throws -> URL {
        let url = tempVideoURL(name)
        let frames = (0..<count).map { index in
            RenderedVideoFrame(
                image: solidFrame(level: UInt8(20 + index * 20), width: 64, height: 48),
                time: CMTime(value: Int64(index), timescale: timescale)
            )
        }
        try await ASCIIVideoEncoder().write(frameSequence(frames), to: url, options: VideoExportOptions())
        return url
    }

    @Test func sourceDurationApproximatesTrackTimeRange() async throws {
        // 8 frames at timescale 8 ≈ 1 second of content.
        let url = try await makeClip(count: 8, timescale: 8, name: "duration.mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let duration = try await ASCIIVideoDecoder().sourceDuration(ofVideoAt: url)
        #expect(duration > 0.8 && duration < 1.3)
    }

    @Test func nominalFrameRateIsPositive() async throws {
        let url = try await makeClip(count: 8, timescale: 8, name: "nominal.mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let fps = try await ASCIIVideoDecoder().nominalFrameRate(ofVideoAt: url)
        #expect(fps > 0)
    }

    @Test func sourceDurationThrowsOnNoVideoTrack() async throws {
        let url = try await audioOnlyFile(named: "duration-audio-only.m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: VideoDecodeError.self) {
            _ = try await ASCIIVideoDecoder().sourceDuration(ofVideoAt: url)
        }
    }
}

@Suite struct AskiVideoEncoderCFRHintTests {
    /// The nested `AVVideoCompressionPropertiesKey` hint must NOT crash
    /// `AVAssetWriterInput(...)` (the top-level key does) and must still produce a
    /// readable MP4. This is the crash-regression sentinel for the hint nesting.
    @Test func encodesReadableMP4WithExpectedFrameRateHint() async throws {
        let frames = (0..<6).map { index in
            RenderedVideoFrame(
                image: solidFrame(level: UInt8(30 + index * 30), width: 64, height: 48),
                time: CMTime(value: Int64(index), timescale: 24)
            )
        }
        let url = tempVideoURL("cfr-hint.mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let options = VideoExportOptions(codec: .h264, expectedFrameRate: 24)
        try await ASCIIVideoEncoder().write(frameSequence(frames), to: url, options: options)
        #expect(try await countFrames(in: url) == 6)
    }

    @Test func defaultOptionsHaveNoExpectedFrameRate() {
        #expect(VideoExportOptions().expectedFrameRate == nil)
        #expect(VideoExportOptions(codec: .hevc).expectedFrameRate == nil)
    }
}

@Suite struct AskiResampleVideoRoundTripTests {
    private func makeClip(count: Int, timescale: Int32, name: String) async throws -> URL {
        let url = tempVideoURL(name)
        let frames = (0..<count).map { index in
            RenderedVideoFrame(
                image: solidFrame(level: UInt8(20 + index * 12), width: 64, height: 48),
                time: CMTime(value: Int64(index), timescale: timescale)
            )
        }
        try await ASCIIVideoEncoder().write(frameSequence(frames), to: url, options: VideoExportOptions())
        return url
    }

    /// Decodes the output's presentation timestamps with Apple's reader directly.
    private func decodedPTS(in url: URL) async throws -> [CMTime] {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(output)
        reader.startReading()
        var times: [CMTime] = []
        while let sample = output.copyNextSampleBuffer() {
            times.append(CMSampleBufferGetPresentationTimeStamp(sample))
        }
        return times
    }

    @Test func downsampleDropsFramesAndLandsOnTargetGrid() async throws {
        // 12 frames at timescale 12 (~1s) -> 4 fps.
        let source = try await makeClip(count: 12, timescale: 12, name: "down-src.mp4")
        let output = tempVideoURL("down-out.mp4")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: output) }

        let report = try await convertVideo(
            at: source, to: output, using: DefaultConverter(),
            columns: 16, font: .system(size: 10),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1), scale: 1,
            targetFPS: 4
        )
        let report2 = try #require(report)
        #expect(report2.requestedFPS == 4)
        #expect(report2.achievedFPS == 4.0)
        #expect(report2.outputFrameCount < report2.sourceFrameCount)
        #expect(report2.droppedCount > 0)

        let pts = try await decodedPTS(in: output)
        #expect(pts.count == report2.outputFrameCount)
        // Every decoded PTS lands on the 1/4 s grid (pts * 4 ≈ integer).
        for time in pts {
            let onGrid = CMTimeGetSeconds(time) * 4.0
            #expect(abs(onGrid - onGrid.rounded()) < 0.05)
        }
    }

    @Test func upsampleDuplicatesFrames() async throws {
        let source = try await makeClip(count: 6, timescale: 6, name: "up-src.mp4")
        let output = tempVideoURL("up-out.mp4")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: output) }

        let report = try #require(
            try await convertVideo(
                at: source, to: output, using: DefaultConverter(),
                columns: 16, font: .system(size: 10),
                backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1), scale: 1,
                targetFPS: 18
            ))
        #expect(report.outputFrameCount > report.sourceFrameCount)
        #expect(report.duplicatedCount > 0)
    }

    @Test func passthroughPreservesFrameCountAndTimestamps() async throws {
        // targetFPS nil -> the no-regression sentinel. Output PTS == source PTS.
        let source = try await makeClip(count: 6, timescale: 6, name: "pass-src.mp4")
        let output = tempVideoURL("pass-out.mp4")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: output) }

        let report = try await convertVideo(
            at: source, to: output, using: DefaultConverter(),
            columns: 16, font: .system(size: 10),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1), scale: 1
        )
        #expect(report == nil)  // no resampling requested

        let sourcePTS = try await decodedPTS(in: source)
        let outputPTS = try await decodedPTS(in: output)
        #expect(outputPTS.count == sourcePTS.count)
        for (a, b) in zip(sourcePTS, outputPTS) {
            #expect(abs(CMTimeGetSeconds(a) - CMTimeGetSeconds(b)) < 0.001)
        }
    }
}
