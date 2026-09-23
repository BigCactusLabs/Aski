import ArgumentParser
import AskiToolSupport
import Foundation
import Testing
@testable import AskiMotionLab
@testable import BuildResearchIndex

@Suite struct AskiMotionLabRunTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AskiMotionLabRunTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func run(_ outputDir: URL) throws -> LabExitCode {
        try AnimateSubcommand.parse([
            "--output-dir", outputDir.path,
            "--preset", "all",
            "--columns", "24",
            "--fps", "8",
            "--duration", "1.0",
            "--seed", "0",
            "--gif", "true",
            "--aski-git-sha", "test-sha",
        ]).execute(
            standardOutput: { _ in },
            standardError: { _ in },
            date: "2026-06-02"
        )
    }

    @Test func writesFramesGifsCsvAndManifest() throws {
        let dir = try temporaryDirectory()
        #expect(try run(dir) == .success)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("frames/reveal/frame-000.txt").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("frames/cycle/frame-000.txt").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("reveal.gif").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("cycle.gif").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("flicker.csv").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("result.yaml").path))
    }

    @Test func flickerCsvHasHeaderAndOneRowPerPreset() throws {
        let dir = try temporaryDirectory()
        _ = try run(dir)
        let csv = try String(contentsOf: dir.appendingPathComponent("flicker.csv"), encoding: .utf8)
        var lines = csv.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        #expect(lines.first == "preset,frame_rate,total_frames,mean_glyph_churn,max_glyph_churn,mean_alpha_churn,max_alpha_churn,gif_bytes")
        #expect(lines.count == 3)
        #expect(lines[1].hasPrefix("reveal,"))
        #expect(lines[2].hasPrefix("cycle,"))
    }

    @Test func resultManifestParsesAndListsEveryTopLevelOutput() throws {
        let dir = try temporaryDirectory()
        _ = try run(dir)
        let text = try String(contentsOf: dir.appendingPathComponent("result.yaml"), encoding: .utf8)
        let manifest = try ResultManifest.from(try FrontMatterParser.parse(text))
        #expect(manifest.runner == "AskiMotionLab")
        #expect(manifest.schemaVersion == "1")
        #expect(Set(manifest.outputs) == ["reveal.gif", "cycle.gif", "flicker.csv"])
        #expect(!manifest.provenance.isEmpty)
        #expect(manifest.askiGitSha == "test-sha")
        #expect(manifest.command?.contains("--aski-git-sha test-sha") == true)
    }

    @Test func resultManifestParsesWhenOutputDirectoryContainsQuote() throws {
        let parent = try temporaryDirectory()
        let dir = parent.appending(path: "quoted-\"output")
        #expect(try run(dir) == .success)

        let text = try String(contentsOf: dir.appendingPathComponent("result.yaml"), encoding: .utf8)
        #expect(text.contains("quoted-\\\"output"))
        let manifest = try ResultManifest.from(try FrontMatterParser.parse(text))
        #expect(manifest.command?.contains("quoted-\"output") == true)
    }

    @Test func canonicalFramesAreSeedStableAcrossRuns() throws {
        let a = try temporaryDirectory()
        let b = try temporaryDirectory()
        _ = try run(a)
        _ = try run(b)
        let frameA = try String(contentsOf: a.appendingPathComponent("frames/cycle/frame-002.txt"), encoding: .utf8)
        let frameB = try String(contentsOf: b.appendingPathComponent("frames/cycle/frame-002.txt"), encoding: .utf8)
        #expect(frameA == frameB)
    }

    @Test func writeFramesRemovesStaleFramesFromPriorLongerRun() throws {
        let dir = try temporaryDirectory()
        try ResultsWriter.writeFrames(["old-0", "old-1", "old-2"], preset: .reveal, outputDirectory: dir)
        try ResultsWriter.writeFrames(["new-0"], preset: .reveal, outputDirectory: dir)

        let framesDir = dir.appendingPathComponent("frames/reveal")
        let frame0 = try String(contentsOf: framesDir.appendingPathComponent("frame-000.txt"), encoding: .utf8)
        #expect(frame0 == "new-0")
        #expect(!FileManager.default.fileExists(atPath: framesDir.appendingPathComponent("frame-001.txt").path))
        #expect(!FileManager.default.fileExists(atPath: framesDir.appendingPathComponent("frame-002.txt").path))
    }

    @Test func temporalPriorRunWritesReport() throws {
        let dir = try temporaryDirectory()
        let command = try TemporalPriorSubcommand.parse([
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
                return (cells: [], verdict: nil, sharedPoint: nil)
            },
            standardOutput: { _ in }
        )

        let reportURL = dir.appendingPathComponent("temporal-prior-report.txt")
        let report = try String(contentsOf: reportURL, encoding: .utf8)
        #expect(seenStimuli == [.s1])
        #expect(seenColumns == [64])
        #expect(report.contains("ASTSK-41 temporal-prior gate"))
        #expect(report.contains("VERDICT: (diagnostic only"))
    }
}
