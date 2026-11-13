import Foundation

/// Frozen ASKI-93 identity, timing, and pull-accounting fixtures shared by the
/// Foundation-only core and native video adapter tests.
enum VideoFrameSelectionFixtures {
    struct Fixture: Sendable {
        let name: String
        let sourceTicks: [Int64]
        let sourceTimescale: Int32
        let targetFPS: Int
        let duration: Double
        let selectedIDs: [Int]
        let outputTicks: [Int64]
        let sourceCount: Int
        let dropped: Int
        let duplicated: Int
        let pullRequests: Int
    }

    static let all: [Fixture] = [
        Fixture(
            name: "60-to-12-with-unread-tail", sourceTicks: (0..<60).map(Int64.init), sourceTimescale: 60,
            targetFPS: 12, duration: 1,
            selectedIDs: [2, 7, 12, 17, 22, 27, 32, 37, 42, 47, 52, 57],
            outputTicks: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
            sourceCount: 59, dropped: 46, duplicated: 0, pullRequests: 59
        ),
        Fixture(
            name: "30-to-12-with-final-lookahead", sourceTicks: (0..<30).map(Int64.init), sourceTimescale: 30,
            targetFPS: 12, duration: 1,
            selectedIDs: [1, 3, 6, 8, 11, 13, 16, 18, 21, 23, 26, 28],
            outputTicks: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
            sourceCount: 30, dropped: 17, duplicated: 0, pullRequests: 30
        ),
        Fixture(
            name: "variable-rate-collisions-and-gaps", sourceTicks: [0, 10, 60, 400, 410, 900], sourceTimescale: 1000,
            targetFPS: 12, duration: 1,
            selectedIDs: [1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 4, 5],
            outputTicks: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
            sourceCount: 6, dropped: 2, duplicated: 8, pullRequests: 7
        ),
        Fixture(
            name: "rate-increase-reuses-source-identities", sourceTicks: [0, 1, 2], sourceTimescale: 2,
            targetFPS: 4, duration: 1.5,
            selectedIDs: [0, 0, 1, 1, 2, 2], outputTicks: [0, 1, 2, 3, 4, 5],
            sourceCount: 3, dropped: 0, duplicated: 3, pullRequests: 4
        ),
        Fixture(
            name: "unchanged-rate", sourceTicks: [0, 1, 2, 3, 4, 5], sourceTimescale: 12,
            targetFPS: 12, duration: 0.5,
            selectedIDs: [0, 1, 2, 3, 4, 5], outputTicks: [0, 1, 2, 3, 4, 5],
            sourceCount: 6, dropped: 0, duplicated: 0, pullRequests: 7
        ),
        Fixture(
            name: "nonzero-origin-and-fractional-end-slot", sourceTicks: [600, 601, 602, 603, 604, 605], sourceTimescale: 30,
            targetFPS: 12, duration: 0.2,
            selectedIDs: [1, 3, 5], outputTicks: [0, 1, 2],
            sourceCount: 6, dropped: 3, duplicated: 0, pullRequests: 7
        ),
        Fixture(
            name: "binary-exact-half-slot-ties", sourceTicks: [0, 1, 3, 5, 7], sourceTimescale: 8,
            targetFPS: 4, duration: 1,
            selectedIDs: [0, 1, 2, 3], outputTicks: [0, 1, 2, 3],
            sourceCount: 5, dropped: 0, duplicated: 0, pullRequests: 5
        ),
        Fixture(
            name: "last-frame-fills-declared-duration", sourceTicks: [0, 1], sourceTimescale: 12,
            targetFPS: 12, duration: 0.25,
            selectedIDs: [0, 1, 1], outputTicks: [0, 1, 2],
            sourceCount: 2, dropped: 0, duplicated: 1, pullRequests: 3
        ),
        Fixture(
            name: "zero-duration-single-frame-floor", sourceTicks: [7], sourceTimescale: 1,
            targetFPS: 12, duration: 0,
            selectedIDs: [0], outputTicks: [0],
            sourceCount: 1, dropped: 0, duplicated: 0, pullRequests: 2
        ),
        Fixture(
            name: "empty-source-does-not-invent-a-frame", sourceTicks: [], sourceTimescale: 1,
            targetFPS: 12, duration: 1,
            selectedIDs: [], outputTicks: [],
            sourceCount: 0, dropped: 0, duplicated: 0, pullRequests: 1
        ),
    ]
}
