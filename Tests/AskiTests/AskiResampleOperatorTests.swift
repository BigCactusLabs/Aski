import CoreMedia
import Foundation
import Testing
@testable import Aski

@Suite struct AskiResampleOperatorTests {
    /// An empty grid is enough — the operators only retime, never inspect grids.
    private func videoFrame(seconds: Double) -> ASCIIVideoFrame {
        ASCIIVideoFrame(
            grid: ASCIIGrid(cells: [], colorSpace: .sRGB),
            time: CMTime(seconds: seconds, preferredTimescale: 600))
    }
    private func videoStream(_ seconds: [Double]) -> AsyncThrowingStream<ASCIIVideoFrame, Error> {
        AsyncThrowingStream { continuation in
            for s in seconds { continuation.yield(videoFrame(seconds: s)) }
            continuation.finish()
        }
    }
    private func gifStream(_ delays: [Double]) -> AsyncThrowingStream<ASCIIGIFFrame, Error> {
        AsyncThrowingStream { continuation in
            for d in delays {
                continuation.yield(ASCIIGIFFrame(grid: ASCIIGrid(cells: [], colorSpace: .sRGB), delay: d))
            }
            continuation.finish()
        }
    }

    @Test func videoOperatorStampsExactCMTimeGrid() async throws {
        // 4 frames at 10 fps -> 20 fps (2x upsample). sourceDuration 0.4 -> endSlot 8.
        let stats = ResampleStats()
        let resampled = try resampledVideoFrames(
            videoStream([0.0, 0.1, 0.2, 0.3]),
            targetFPS: 20, sourceDuration: 0.4, into: stats
        )
        var times: [CMTime] = []
        for try await frame in resampled { times.append(frame.time) }
        #expect(times.count == 8)
        for (k, time) in times.enumerated() {
            #expect(time == CMTime(value: Int64(k), timescale: 20))
        }
        #expect(await stats.outputFrameCount == 8)
        #expect(await stats.duplicatedCount == 4)
    }

    @Test func gifOperatorStampsQuantizedUniformDelay() async throws {
        // 3x0.1s delays -> 20 fps. centiseconds = round(100/20)=5 -> 0.05s uniform.
        let stats = ResampleStats()
        let resampled = try resampledGIFFrames(
            gifStream([0.1, 0.1, 0.1]),
            targetFPS: 20, sourceDuration: 0.3, into: stats
        )
        var delays: [Double] = []
        for try await frame in resampled { delays.append(frame.delay) }
        #expect(delays.count == 6)
        #expect(delays.allSatisfy { abs($0 - 0.05) < 1e-9 })
    }

    @Test func operatorsPreflightBeforeStreaming() {
        let stats = ResampleStats()
        #expect(throws: ResampleError.self) {
            _ = try resampledVideoFrames(videoStream([0.0]), targetFPS: 0, sourceDuration: 1.0, into: stats)
        }
        #expect(throws: ResampleError.self) {
            _ = try resampledGIFFrames(gifStream([0.1]), targetFPS: 9999, sourceDuration: 1.0, into: stats)
        }
    }

    @Test func gifQuantizationHelpersMatchSpecWorkedTargets() {
        #expect(gifDelayCentiseconds(targetFPS: 60) == 2)
        #expect(abs(gifAchievedFPS(targetFPS: 60) - 50.0) < 1e-9)
        #expect(gifDelayCentiseconds(targetFPS: 30) == 3)
        #expect(abs(gifAchievedFPS(targetFPS: 30) - 33.333333) < 1e-4)
        #expect(gifDelayCentiseconds(targetFPS: 24) == 4)
        #expect(abs(gifAchievedFPS(targetFPS: 24) - 25.0) < 1e-9)
        #expect(gifDelayCentiseconds(targetFPS: 15) == 7)
        #expect(abs(gifAchievedFPS(targetFPS: 15) - 14.2857) < 1e-3)
        #expect(gifDelayCentiseconds(targetFPS: 20) == 5)  // exact
        #expect(gifDelayCentiseconds(targetFPS: 200) == 1)  // saturates at 1 cs
    }

    @Test func gifQuantizationHelpersDoNotTrapOnInvalidRates() {
        // These public predictors may receive an unchecked user rate. 0 would make
        // 100.0/0 == .infinity and Int(.infinity) traps; a non-positive rate must
        // instead clamp to the slowest sane delay (1 fps -> 100 cs). Reaching the
        // #expect at all proves no trap (a trap would crash the test process).
        #expect(gifDelayCentiseconds(targetFPS: 0) == 100)
        #expect(gifDelayCentiseconds(targetFPS: -5) == 100)
        #expect(abs(gifAchievedFPS(targetFPS: 0) - 1.0) < 1e-9)
        #expect(abs(gifAchievedFPS(targetFPS: -5) - 1.0) < 1e-9)
    }
}
