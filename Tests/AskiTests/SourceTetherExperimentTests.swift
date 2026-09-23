import ArgumentParser
import Foundation
import Testing

@testable import AskiMotionLab

@Suite struct SourceTetherExperimentTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SourceTetherExperimentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // Note: `SourceTetherExperiment.measureCell` runs the real converter over all N=48 frames ×
    // 6 sweeps, which is a release-mode operation (~minutes in a debug test build) — as with
    // ASTSK-41's `TemporalPriorExperiment`, it is exercised for real by the decisive release run
    // (spec §9), not the unit suite. The rho hook itself is covered by TemporalPriorHookTests; the
    // gate by SourceTetherGateTests; the subcommand wiring by the injected-fake tests below.

    @Test func sourceTetherRunWritesReport() throws {
        let dir = try temporaryDirectory()
        let command = try SourceTetherSubcommand.parse([
            "--output-dir", dir.path,
            "--stimulus", "s1",
            "--columns", "64",
        ])
        var seenStimuli: [TemporalStimulus] = []
        var seenColumns: [Int] = []

        try command.execute(
            runExperiment: { stimuli, columns in
                seenStimuli = stimuli
                seenColumns = columns
                return (cells: [], verdict: nil, sharedRho: nil)
            },
            standardOutput: { _ in }
        )

        let report = try String(
            contentsOf: dir.appendingPathComponent("source-tether-report.txt"), encoding: .utf8)
        #expect(seenStimuli == [.s1])
        #expect(seenColumns == [64])
        #expect(report.contains("ASTSK-45 source-tether gate"))
        #expect(report.contains("VERDICT: (diagnostic only"))
    }

    @Test func helpListsSourceTetherSubcommand() {
        #expect(MotionLabCommand.helpMessage().contains("source-tether"))
    }

    @Test func formatRendersPassVerdict() {
        let report = SourceTetherExperiment.format(cells: [], verdict: .pass(rho: 0.5), sharedRho: 0.5)
        #expect(report.contains("VERDICT: PASS"))
        #expect(report.contains("rho*=0.5"))
    }
}
