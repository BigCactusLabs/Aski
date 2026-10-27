import Foundation
import Testing
@testable import Aski

/// Exercises the actual selection actor without CoreMedia or a substitute
/// selector. The native adapter suite separately verifies exact CMTime retiming.
@Suite struct VideoFrameSelectionCoreTests {
    private static let benchmarkFixtures: [VideoFrameSelectionFixtures.Fixture] = [
        VideoFrameSelectionFixtures.Fixture(
            name: "120-to-12-benchmark-counts", sourceTicks: (0..<120).map(Int64.init), sourceTimescale: 120,
            targetFPS: 12, duration: 1,
            selectedIDs: [4, 14, 24, 34, 44, 54, 64, 74, 84, 94, 104, 114],
            outputTicks: (0..<12).map(Int64.init),
            sourceCount: 116, dropped: 103, duplicated: 0, pullRequests: 116
        ),
        VideoFrameSelectionFixtures.Fixture(
            name: "60-to-12-ten-second-benchmark-counts", sourceTicks: (0..<600).map(Int64.init), sourceTimescale: 60,
            targetFPS: 12, duration: 10,
            selectedIDs: Array(stride(from: 2, through: 597, by: 5)),
            outputTicks: (0..<120).map(Int64.init),
            sourceCount: 599, dropped: 478, duplicated: 0, pullRequests: 599
        ),
    ]

    @Test(arguments: VideoFrameSelectionFixtures.all + VideoFrameSelectionCoreTests.benchmarkFixtures)
    func preservesFrozenIdentitiesSlotsAndPullAccounting(fixture: VideoFrameSelectionFixtures.Fixture) async throws {
        let tokens = fixture.sourceTicks.enumerated().map { index, tick in
            SelectionCoreToken(
                id: index,
                start: Double(tick) / Double(fixture.sourceTimescale),
                slot: -1
            )
        }
        let source = SelectionCoreSource(tokens: tokens)
        let stats = ResampleStats()
        let endSlot = try resamplePreflight(targetFPS: fixture.targetFPS, sourceDuration: fixture.duration)
        let session = ResampleSession(
            source: source.stream(),
            timing: .absolute { $0.start },
            retime: { token, slot in
                SelectionCoreToken(id: token.id, start: token.start, slot: Int64(slot))
            },
            targetFPS: fixture.targetFPS,
            endSlot: endSlot,
            stats: stats
        )
        var output: [SelectionCoreToken] = []
        while let token = try await session.next() { output.append(token) }

        #expect(output.map(\.id) == fixture.selectedIDs)
        #expect(output.map(\.slot) == fixture.outputTicks)
        #expect(await stats.sourceFrameCount == fixture.sourceCount)
        #expect(await stats.outputFrameCount == fixture.outputTicks.count)
        #expect(await stats.droppedCount == fixture.dropped)
        #expect(await stats.duplicatedCount == fixture.duplicated)
        #expect(await source.successfulPulls == fixture.sourceCount)
        #expect(await source.pullRequests == fixture.pullRequests)
    }
}

private struct SelectionCoreToken: Sendable {
    let id: Int
    let start: Double
    let slot: Int64
}

/// Yield only when the production actor asks, including the terminal nil read.
/// Eagerly enqueueing the fixture would conceal unread source-tail behavior.
private actor SelectionCoreSource {
    private let tokens: [SelectionCoreToken]
    private(set) var successfulPulls = 0
    private(set) var pullRequests = 0

    init(tokens: [SelectionCoreToken]) {
        self.tokens = tokens
    }

    nonisolated func stream() -> AsyncThrowingStream<SelectionCoreToken, Error> {
        AsyncThrowingStream(unfolding: { try await self.next() })
    }

    private func next() throws -> SelectionCoreToken? {
        try Task.checkCancellation()
        pullRequests += 1
        guard successfulPulls < tokens.count else { return nil }
        defer { successfulPulls += 1 }
        return tokens[successfulPulls]
    }
}
