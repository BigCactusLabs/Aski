import ArgumentParser
import AskiToolSupport
import Testing
@testable import AskiColorLab

@Suite struct AskiColorLabCLITests {
    @Test func rootHelpListsSubcommands() {
        let help = AskiColorLabCommand.helpMessage()
        #expect(help.contains("AskiColorLab"))
        #expect(help.contains("sampling-ablation"))
        #expect(help.contains("render-matcher-challenge"))
    }

    @Test func subcommandHelpListsSharedOptions() {
        let help = SamplingAblationSubcommand.helpMessage()
        #expect(help.contains("--output-dir"))
        #expect(help.contains("--seed"))
    }

    @Test func unknownSubcommandIsRejected() {
        #expect(throws: (any Error).self) {
            _ = try AskiColorLabCommand.parseAsRoot(["bogus-command", "--output-dir", "/tmp/x"])
        }
    }

    @Test func emptyInvocationIsAMissingCommandError() {
        // Bare invocation runs the root's run(), which must throw (exit 64),
        // preserving the legacy "missing command" contract.
        let command = AskiColorLabCommand()
        #expect(throws: (any Error).self) { try command.run() }
    }

    @Test func parsesSharedArgumentsWithDefaults() throws {
        let command = try SamplingAblationSubcommand.parse(["--output-dir", "/tmp/x"])
        #expect(command.provenance.outputDirectory == "/tmp/x")
        #expect(command.seedOption.seed == 0)
        #expect(command.provenance.gitShaOverride == nil)
    }

    @Test func parsesSharedArgumentsWithOverrides() throws {
        let command = try SamplingAblationSubcommand.parse([
            "--output-dir", "/tmp/x", "--seed", "42", "--aski-git-sha", "abc123",
        ])
        #expect(command.provenance.outputDirectory == "/tmp/x")
        #expect(command.seedOption.seed == 42)
        #expect(command.provenance.gitShaOverride == "abc123")
    }

    @Test func rejectsMissingOutputDir() {
        #expect(throws: (any Error).self) { try SamplingAblationSubcommand.parse([]) }
    }

    @Test func rejectsUnknownOption() {
        #expect(throws: (any Error).self) {
            try SamplingAblationSubcommand.parse(["--output-dir", "/tmp/x", "--bogus"])
        }
    }

    @Test func rejectsInvalidSeed() {
        #expect(throws: (any Error).self) {
            try SamplingAblationSubcommand.parse(["--output-dir", "/tmp/x", "--seed", "notanint"])
        }
    }

    @Test func rejectsGitShaWithForbiddenCharacters() {
        for bad in ["with,comma", "with\nnewline", "with\"quote"] {
            #expect(throws: (any Error).self) {
                try SamplingAblationSubcommand.parse(["--output-dir", "/tmp/x", "--aski-git-sha", bad])
            }
        }
    }

    @Test func helmlabAcceptsReviewCorpus() throws {
        let command = try HelmlabReferenceSubcommand.parse([
            "--output-dir", "/tmp/x", "--review-corpus", "/tmp/corpus",
        ])
        #expect(command.reviewCorpus == "/tmp/corpus")
    }

}
