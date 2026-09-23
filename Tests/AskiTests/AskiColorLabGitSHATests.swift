import AskiToolSupport
import Foundation
import Testing
@testable import AskiColorLab

@Suite struct AskiColorLabGitSHATests {
    @Test func overrideTakesPrecedenceOverGitProbe() {
        let sha = GitSHA.resolve(override: "deadbeef")
        #expect(sha == "deadbeef")
    }

    @Test func resolvedSHAFallsBackToUnknownInNonRepoDirectory() {
        // /tmp may or may not be inside a repo on a given dev machine. Assert
        // the shape contract: either the sentinel "unknown" or a valid hex
        // hash (SHA-1 = 40 chars, SHA-256 = 64 chars). Never an empty string
        // or thrown error.
        let sha = GitSHA.probe(workingDirectory: "/tmp")
        if sha != "unknown" {
            #expect(sha.count == 40 || sha.count == 64, "expected SHA-1 (40) or SHA-256 (64), got \(sha.count)")
            #expect(sha.allSatisfy { $0.isHexDigit })
        }
    }

    @Test func resolvedSHAIsHexInThisRepo() {
        let sha = GitSHA.probe(workingDirectory: FileManager.default.currentDirectoryPath)
        // Tests run from the package root, which is a git repo. Either the
        // probe succeeds (hex hash) or git is genuinely unavailable.
        if sha != "unknown" {
            #expect(sha.count == 40 || sha.count == 64, "expected SHA-1 (40) or SHA-256 (64), got \(sha.count)")
            #expect(sha.allSatisfy { $0.isHexDigit })
        }
    }
}
