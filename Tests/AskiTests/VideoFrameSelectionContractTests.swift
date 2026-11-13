import CoreMedia
import Foundation
import Testing
@testable import Aski

/// ASKI-93: freeze the selection/retiming boundary before moving conversion
/// downstream of it. These are synthetic grids, not codec or rendered-pixel tests.
@Suite struct VideoFrameSelectionContractTests {
    @Test(arguments: VideoFrameSelectionFixtures.all)
    func preservesSelectedIdentityRetimingAndPullAccounting(fixture: VideoFrameSelectionFixtures.Fixture) async throws {
        let sourceFrames = fixture.sourceTicks.enumerated().map { index, tick in
            // Binary-exact, in-range brightness marks a source identity without
            // rendering a glyph or relying on codec quantization.
            let cell = ASCIICell(
                character: "#", displayColor: SIMD3<Float>(0.2, 0.4, 0.6),
                alpha: 1, brightness: Float(index) / 128
            )
            return ASCIIVideoFrame(
                grid: ASCIIGrid(cells: [[cell]], colorSpace: .sRGB),
                time: CMTime(value: tick, timescale: fixture.sourceTimescale)
            )
        }
        let source = SelectionContractSource(frames: sourceFrames)
        let stats = ResampleStats()
        // This public adapter constructs the actual generic ResampleSession;
        // its production retime closure supplies the CMTime values under test.
        let stream = try resampledVideoFrames(
            source.stream(), targetFPS: fixture.targetFPS, sourceDuration: fixture.duration, into: stats
        )
        var output: [ASCIIVideoFrame] = []
        for try await frame in stream { output.append(frame) }

        #expect(output.map(\.grid.cells) == fixture.selectedIDs.map { sourceFrames[$0].grid.cells })
        #expect(output.map(\.time.value) == fixture.outputTicks)
        #expect(output.allSatisfy { $0.time.timescale == Int32(fixture.targetFPS) })
        #expect(output.allSatisfy { $0.time.isNumeric && $0.time.epoch == 0 })
        #expect(await stats.sourceFrameCount == fixture.sourceCount)
        #expect(await stats.outputFrameCount == fixture.outputTicks.count)
        #expect(await stats.droppedCount == fixture.dropped)
        #expect(await stats.duplicatedCount == fixture.duplicated)
        #expect(await source.successfulPulls == fixture.sourceCount)
        #expect(await source.pullRequests == fixture.pullRequests)
    }
}

/// An unfolding source makes reads observable. An eager continuation would
/// enqueue the whole fixture before selection and hide unnecessary tail reads.
private actor SelectionContractSource {
    private let frames: [ASCIIVideoFrame]
    private(set) var successfulPulls = 0
    private(set) var pullRequests = 0

    init(frames: [ASCIIVideoFrame]) {
        self.frames = frames
    }

    nonisolated func stream() -> AsyncThrowingStream<ASCIIVideoFrame, Error> {
        AsyncThrowingStream(unfolding: { try await self.next() })
    }

    private func next() throws -> ASCIIVideoFrame? {
        try Task.checkCancellation()
        pullRequests += 1
        guard successfulPulls < frames.count else { return nil }
        defer { successfulPulls += 1 }
        return frames[successfulPulls]
    }
}
