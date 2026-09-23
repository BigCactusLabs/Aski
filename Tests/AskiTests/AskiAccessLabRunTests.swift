import ArgumentParser
import Foundation
import Testing
@testable import AskiAccessLab
@testable import BuildResearchIndex

@Suite struct AskiAccessLabRunTests {
    @Test func auditWritesCsvAndManifest() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let status = try AccessLabAuditCommand.parse([
            "--output-dir", dir.path,
            "--columns", "24",
            "--aski-git-sha", "test-sha",
        ]).execute(
            standardOutput: { _ in },
            standardError: { _ in },
            date: "2026-06-04"
        )

        #expect(status == .success)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("accessibility.csv").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("result.yaml").path))
    }

    @Test func csvHasExpectedRowsAndNoCommaTriplets() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try AccessLabAuditCommand.parse(
            ["--output-dir", dir.path, "--columns", "24", "--aski-git-sha", "test-sha"]
        ).execute(
            standardOutput: { _ in },
            standardError: { _ in },
            date: "2026-06-04"
        )

        let csv = try String(contentsOf: dir.appendingPathComponent("accessibility.csv"), encoding: .utf8)
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines.count > 100)
        #expect(lines[0] == AccessLabResults.csvHeader.joined(separator: ","))
        #expect(csv.contains("#FF") || csv.contains("#00"))
        #expect(!lines[0].contains("run_seed"))
        #expect(!csv.contains("0.5,0.2,0.1"))
    }

    @Test func resultManifestParsesThroughResearchIndexParser() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try AccessLabAuditCommand.parse(
            ["--output-dir", dir.path, "--columns", "24", "--aski-git-sha", "test-sha"]
        ).execute(
            standardOutput: { _ in },
            standardError: { _ in },
            date: "2026-06-04"
        )

        let text = try String(contentsOf: dir.appendingPathComponent("result.yaml"), encoding: .utf8)
        let manifest = try ResultManifest.from(try FrontMatterParser.parse(text))
        #expect(manifest.schemaVersion == "1")
        #expect(manifest.date == "2026-06-04")
        #expect(manifest.runner == "AskiAccessLab")
        #expect(manifest.askiGitSha == "test-sha")
        #expect(manifest.provenance == ["AskiAccessLab audit"])
        #expect(manifest.outputs == ["accessibility.csv"])
        #expect(manifest.runSeed == nil)
        #expect(manifest.command?.contains("swift run AskiAccessLab audit") == true)
    }

    @Test func rerunReplacesTopLevelOutputs() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "stale\n".write(to: dir.appendingPathComponent("accessibility.csv"), atomically: true, encoding: .utf8)

        let first = try AccessLabAuditCommand.parse(
            ["--output-dir", dir.path, "--columns", "24", "--aski-git-sha", "test-sha"]
        ).execute(
            standardOutput: { _ in },
            standardError: { _ in },
            date: "2026-06-04"
        )
        let second = try AccessLabAuditCommand.parse(
            ["--output-dir", dir.path, "--columns", "24", "--aski-git-sha", "test-sha"]
        ).execute(
            standardOutput: { _ in },
            standardError: { _ in },
            date: "2026-06-04"
        )

        #expect(first == .success)
        #expect(second == .success)
        let csv = try String(contentsOf: dir.appendingPathComponent("accessibility.csv"), encoding: .utf8)
        #expect(!csv.hasPrefix("stale"))
    }

    @Test func unsupportedManifestMetadataFailsBeforeWritingArtifacts() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var stderr = ""
        let status = try AccessLabAuditCommand.parse(
            ["--output-dir", dir.path, "--columns", "24", "--aski-git-sha", "bad\u{1}sha"]
        ).execute(
            standardOutput: { _ in },
            standardError: { stderr += $0 },
            date: "2026-06-04"
        )
        #expect(status == .usage)
        #expect(stderr.contains("unsupported control character"))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("accessibility.csv").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("result.yaml").path))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AskiAccessLabRunTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
