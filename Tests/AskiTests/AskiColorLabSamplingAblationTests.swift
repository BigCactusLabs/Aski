import ArgumentParser
import AskiToolSupport
import Foundation
import Testing
@testable import AskiColorLab

@Suite struct AskiColorLabSamplingAblationTests {
    @Test func runsAndProducesExpectedHeader() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var stderr = ""
        let status = try SamplingAblationSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { stderr += $0 })

        #expect(status == .success, "stderr was: \(stderr)")

        let csv = directory.appending(path: "sampling-ablation.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let expectedHeader = [
            "schema_version", "command", "aski_git_sha", "run_seed",
            "sample_id", "fixture_id", "policy",
            "input_space", "input_components",
            "output_space", "output_components",
            "fixture_width", "fixture_height",
            "input_alpha_mean", "output_alpha",
            "oklab_l", "oklab_a", "oklab_b",
        ].joined(separator: ",")
        #expect(lines.first.map(String.init) == expectedHeader)
    }

    @Test func emitsOneRowPerFixturePerPolicy() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let status = try SamplingAblationSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        #expect(status == .success)

        let csv = directory.appending(path: "sampling-ablation.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        // header + (fixtures * 2 policies) rows
        let expectedRows = SamplingFixtures.all.count * 2 + 1
        #expect(lines.count == expectedRows)
    }

    @Test func twoIdenticalRunsProduceByteIdenticalCSVs() throws {
        let directoryA = try temporaryDirectory()
        let directoryB = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryA)
            try? FileManager.default.removeItem(at: directoryB)
        }

        for dir in [directoryA, directoryB] {
            let status = try SamplingAblationSubcommand.parse([
                "--output-dir", dir.path,
                "--aski-git-sha", "test-sha",
                "--seed", "7",
            ]).execute(standardError: { _ in })
            #expect(status == .success)
        }

        let csvA = try Data(contentsOf: directoryA.appending(path: "sampling-ablation.csv"))
        let csvB = try Data(contentsOf: directoryB.appending(path: "sampling-ablation.csv"))
        #expect(csvA == csvB)
    }

    @Test func firstFixtureRowEncodedAverageLegacyHasExpectedColumns() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let status = try SamplingAblationSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        #expect(status == .success)

        let csv = directory.appending(path: "sampling-ablation.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let firstRow = String(lines[1]).split(separator: ",").map(String.init)
        #expect(firstRow[0] == "1")  // schema_version
        #expect(firstRow[1] == "sampling-ablation")  // command
        #expect(firstRow[2] == "test-sha")  // aski_git_sha
        #expect(firstRow[3] == "0")  // run_seed default
        #expect(firstRow[4] == "0")  // sample_id starts at 0
        #expect(firstRow[5] == "2x2_opaque_primaries")  // fixture_id
        #expect(firstRow[6] == "encodedAverageLegacy")  // policy
        #expect(firstRow[7] == "sRGB")  // input_space
        #expect(firstRow[9] == "linearSRGB")  // output_space
        #expect(firstRow[11] == "2")  // fixture_width
        #expect(firstRow[12] == "2")  // fixture_height
        #expect(firstRow[13] == "1.000000")  // input_alpha_mean
    }

    @Test func sampleIDIsSharedAcrossPoliciesForSameFixture() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let status = try SamplingAblationSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        #expect(status == .success)

        let csv = directory.appending(path: "sampling-ablation.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let row0 = String(lines[1]).split(separator: ",").map(String.init)
        let row1 = String(lines[2]).split(separator: ",").map(String.init)

        #expect(row0[4] == row1[4], "sample_id should be shared across policy rows for the same fixture")
        #expect(row0[5] == row1[5], "fixture_id should match for the same fixture")
        #expect(row0[6] == "encodedAverageLegacy")
        #expect(row1[6] == "linearLightAverage")
        let row2 = String(lines[3]).split(separator: ",").map(String.init)
        #expect(row2[4] == "1", "sample_id should increment per input fixture, not per row")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AskiColorLabSamplingAblationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
