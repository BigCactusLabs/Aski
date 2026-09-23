import ArgumentParser
import AskiToolSupport
import Testing
@testable import AskiAccessLab

@Suite struct AskiAccessLabArgumentsTests {
    // Subcommand options (no leading `audit` token — that is the root's job).
    private let base = ["--output-dir", "/tmp/aski-access"]

    @Test func rootHelpListsAuditSubcommand() {
        let help = AskiAccessLabCommand.helpMessage()
        #expect(help.contains("AskiAccessLab"))
        #expect(help.contains("audit"))
    }

    @Test func parsesValidAuditArguments() throws {
        let command = try AccessLabAuditCommand.parse(base + ["--columns", "40", "--aski-git-sha", "test-sha"])
        #expect(command.provenance.outputDirectory == "/tmp/aski-access")
        #expect(command.columns == 40)
        #expect(command.provenance.gitShaOverride == "test-sha")
    }

    @Test func defaultsColumnsToEighty() throws {
        #expect(try AccessLabAuditCommand.parse(base).columns == 80)
    }

    @Test func requiresAuditCommand() {
        // No subcommand / wrong subcommand is rejected by the root.
        #expect(throws: (any Error).self) { _ = try AskiAccessLabCommand.parseAsRoot(["--output-dir", "/tmp/out"]) }
        #expect(throws: (any Error).self) { _ = try AskiAccessLabCommand.parseAsRoot(["render", "--output-dir", "/tmp/out"]) }
    }

    @Test func emptyInvocationIsAMissingCommandError() {
        // Bare invocation runs the root's run(), which must throw (exit 64).
        let command = AskiAccessLabCommand()
        #expect(throws: (any Error).self) { try command.run() }
    }

    @Test func requiresOutputDirectory() {
        #expect(throws: (any Error).self) { try AccessLabAuditCommand.parse([]) }
    }

    @Test(arguments: ["0", "-1", "abc"])
    func rejectsNonPositiveColumns(_ value: String) {
        #expect(throws: (any Error).self) { try AccessLabAuditCommand.parse(base + ["--columns", value]) }
    }

    @Test func rejectsColumnsAboveSharedCap() {
        #expect(throws: (any Error).self) { try AccessLabAuditCommand.parse(base + ["--columns", "513"]) }
    }

    @Test func rejectsSeedFlag() {
        // AccessLab has no --seed; SAP rejects it as an unknown option.
        #expect(throws: (any Error).self) { try AccessLabAuditCommand.parse(base + ["--seed", "0"]) }
    }

    @Test func rejectsUnsafeGitShaMetadata() {
        #expect(throws: (any Error).self) { try AccessLabAuditCommand.parse(base + ["--aski-git-sha", "bad,sha"]) }
        #expect(throws: (any Error).self) { try AccessLabAuditCommand.parse(base + ["--aski-git-sha", "bad\nsha"]) }
    }
}
