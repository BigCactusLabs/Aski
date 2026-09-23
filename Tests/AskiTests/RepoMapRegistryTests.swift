import Foundation
import Testing

@testable import BuildRepoMap

/// Enforces the docs/repo-map.generated.md freshness contract in `swift test` (GitHub
/// Actions are disabled for this repo, so the test suite is the real gate). Reuses the
/// `BuildRepoMap` tool's own drift check in-process — the same code path as
/// `swift run BuildRepoMap --check` — so the gate can never drift from the tool, and it
/// stays a pure-IO source scan (no nested build).
@Suite struct RepoMapRegistryTests {
    /// The committed map matches a fresh render from the current `Sources/Aski` tree.
    /// On failure: run `swift run BuildRepoMap` (or `just regen-repo-map`) and commit.
    @Test func generatedMapIsInSync() throws {
        let failures = IndexCheck.driftFailures(root: try Self.packageRoot())
        if !failures.isEmpty {
            Issue.record("Generated repo map is out of date:\n\(failures.joined(separator: "\n"))")
        }
        #expect(failures.isEmpty)
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
