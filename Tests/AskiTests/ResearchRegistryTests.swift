import Foundation
import Testing
@testable import BuildResearchIndex

/// Enforces the docs/Research/ registry contract in `swift test` (GitHub Actions
/// are disabled for this repo, so the test suite is the real gate). Reuses the
/// `BuildResearchIndex` tool's own validation in-process — the same code path as
/// `swift run BuildResearchIndex --check` — so the gate can never drift from the tool.
@Suite struct ResearchRegistryTests {
    /// Every research note has well-formed front-matter: required fields present,
    /// controlled-vocabulary `status`/`subsystem`, slug matching the filename, a
    /// valid `date`, and `related_specs`/`datasets`/`runners` that resolve on disk.
    @Test func everyNoteHasValidFrontMatter() throws {
        let failures = IndexCheck.schemaFailures(root: try Self.packageRoot())
        if !failures.isEmpty {
            Issue.record("Research-note front-matter problems:\n\(failures.joined(separator: "\n"))")
        }
        #expect(failures.isEmpty)
    }

    /// The committed README index block and docs/Research/index.json match a fresh
    /// render from the notes' front-matter. On failure: run `swift run BuildResearchIndex`.
    @Test func generatedArtifactsAreInSync() throws {
        let failures = IndexCheck.driftFailures(root: try Self.packageRoot())
        if !failures.isEmpty {
            Issue.record("Generated research index is out of date:\n\(failures.joined(separator: "\n"))")
        }
        #expect(failures.isEmpty)
    }

    /// Every committed corpus has a valid manifest with tags, and every committed
    /// result has a valid result.yaml with accounted-for files (spec §5).
    @Test func everyCorpusAndResultHasValidManifest() throws {
        let failures = IndexCheck.manifestFailures(root: try Self.packageRoot())
        if !failures.isEmpty {
            Issue.record("Corpus/Results manifest problems:\n\(failures.joined(separator: "\n"))")
        }
        #expect(failures.isEmpty)
    }

    @Test func docsRootMatchesAllowlist() throws {
        let failures = IndexCheck.docsRootFailures(root: try Self.packageRoot())
        #expect(failures.isEmpty, "\(failures)")
    }

    private static func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appending(path: "Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
