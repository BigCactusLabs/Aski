import ArgumentParser
import AskiToolSupport
import Testing
@testable import AskiMotionLab

@Suite struct AskiMotionLabArgumentsTests {
    @Test func defaultsApplyWhenOnlyOutputDirGiven() throws {
        let command = try AnimateSubcommand.parse(["--output-dir", "/tmp/out"])
        #expect(command.provenance.outputDirectory == "/tmp/out")
        #expect(command.preset.presets == [.reveal, .cycle])
        #expect(command.image == nil)
        #expect(command.columns == 80)
        #expect(command.fps == 12)
        #expect(command.duration == 2.0)
        #expect(command.seedOption.seed == 0)
        #expect(command.gif == true)
        #expect(command.provenance.gitShaOverride == nil)
    }

    @Test func presetAllResolvesToBothInDeterministicOrder() throws {
        #expect(try AnimateSubcommand.parse(["--output-dir", "x", "--preset", "all"]).preset.presets == [.reveal, .cycle])
        #expect(try AnimateSubcommand.parse(["--output-dir", "x", "--preset", "reveal"]).preset.presets == [.reveal])
        #expect(try AnimateSubcommand.parse(["--output-dir", "x", "--preset", "cycle"]).preset.presets == [.cycle])
    }

    @Test func parsesEveryOption() throws {
        let command = try AnimateSubcommand.parse([
            "--output-dir", "/tmp/out", "--preset", "cycle", "--image", "/p.png",
            "--columns", "40", "--fps", "8", "--duration", "1.5", "--seed", "7",
            "--gif", "false", "--aski-git-sha", "deadbeef",
        ])
        #expect(command.image == "/p.png")
        #expect(command.columns == 40)
        #expect(command.fps == 8)
        #expect(command.duration == 1.5)
        #expect(command.seedOption.seed == 7)
        #expect(command.gif == false)
        #expect(command.provenance.gitShaOverride == "deadbeef")
    }

    @Test func missingOutputDirThrows() {
        #expect(throws: (any Error).self) { try AnimateSubcommand.parse(["--preset", "all"]) }
    }

    @Test func invalidPresetThrows() {
        #expect(throws: (any Error).self) { try AnimateSubcommand.parse(["--output-dir", "x", "--preset", "wiggle"]) }
    }

    @Test func oversizedColumnsFPSDurationThrowBeforeMaterialization() {
        #expect(throws: (any Error).self) { try AnimateSubcommand.parse(["--output-dir", "x", "--columns", "0"]) }
        #expect(throws: (any Error).self) { try AnimateSubcommand.parse(["--output-dir", "x", "--columns", "513"]) }
        #expect(throws: (any Error).self) { try AnimateSubcommand.parse(["--output-dir", "x", "--fps", "121"]) }
        #expect(throws: (any Error).self) { try AnimateSubcommand.parse(["--output-dir", "x", "--duration", "61"]) }
    }

    @Test func materializedFrameCountGuardRejectsOverflowProneCombinations() {
        #expect(ToolArgumentBounds.materializedFrameCountIsValid(duration: 60, fps: 120))
        #expect(!ToolArgumentBounds.materializedFrameCountIsValid(duration: 100, fps: 120))
        #expect(!ToolArgumentBounds.materializedFrameCountIsValid(duration: .greatestFiniteMagnitude, fps: 120))
    }

    @Test func unknownOptionThrows() {
        #expect(throws: (any Error).self) { try AnimateSubcommand.parse(["--output-dir", "x", "--bogus"]) }
    }

    @Test func invalidGitShaWithCommaThrows() {
        #expect(throws: (any Error).self) { try AnimateSubcommand.parse(["--output-dir", "x", "--aski-git-sha", "a,b"]) }
    }

    @Test func temporalPriorDefaultsToFullDiagnosticGrid() throws {
        let command = try TemporalPriorSubcommand.parse(["--output-dir", "/tmp/out"])
        #expect(command.provenance.outputDirectory == "/tmp/out")
        #expect(command.stimulus.stimuli == [.s1, .s2])
        #expect(command.columns.columns == [64, 80])
    }

    @Test func temporalPriorParsesSingleStimulusAndColumn() throws {
        let command = try TemporalPriorSubcommand.parse([
            "--output-dir", "/tmp/out", "--stimulus", "s1", "--columns", "64",
        ])
        #expect(command.stimulus.stimuli == [.s1])
        #expect(command.columns.columns == [64])
    }
}
