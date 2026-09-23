import ArgumentParser
import AskiToolSupport
import Testing
@testable import AskiMotionLab

@Suite struct AskiMotionLabCLITests {
    @Test func helpListsCommandName() {
        #expect(MotionLabCommand.helpMessage().contains("AskiMotionLab"))
    }

    @Test func helpListsSubcommands() {
        let help = MotionLabCommand.helpMessage()
        #expect(help.contains("animate"))
        #expect(help.contains("temporal-prior"))
    }

    @Test func legacyNoSubcommandRoutesToAnimate() throws {
        let parsed = try MotionLabCommand.parseAsRoot(["--output-dir", "/tmp/x", "--preset", "all"])
        let animate = try #require(parsed as? AnimateSubcommand)
        #expect(animate.preset.presets == [.reveal, .cycle])
        #expect(animate.provenance.outputDirectory == "/tmp/x")
    }
}
