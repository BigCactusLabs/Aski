import ArgumentParser
import AskiToolSupport
import Foundation

/// The ASKI-56 perceptual arbiter's command surface:
/// `AskiColorLab arbiter <stimuli|judge|score>`.
///
/// The three subcommands are the three phases of one run and are deliberately
/// separate processes. `stimuli` must finish and the rater must answer before
/// `score` is ever run, because the moment scoring is available in the same
/// invocation as generation, the blinding is one flag away from being lost.
public struct ArbiterSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "arbiter",
        abstract:
            "Human-arbitrated, VLM pre-screened pairwise adjudication for ASCII renders (protocol v2, frozen at docs/Research/2026-09-04-aski62-arbiter-v2-protocol.md). The human owner is the arbiter; the VLM leg is a pre-screen and tie-breaker that counts for nothing until it passes the section 5.1 validation gate.",
        subcommands: [
            ArbiterStimuliSubcommand.self,
            ArbiterJudgeSubcommand.self,
            ArbiterScoreSubcommand.self,
        ]
    )

    public init() {}

    public func run() throws {
        throw ValidationError("Missing command. See --help for the available subcommands.")
    }
}

public struct ArbiterStimuliSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "stimuli",
        abstract:
            "Materialize the blinded reference/left/right triplets (protocol v2 section 3). Converter arms render their own full grids; selection arms share the inverted production scaffold. Identity and every per-pair metric delta live in key.json and nowhere else: do not open it before submitting answers."
    )

    @OptionGroup public var provenance: ProvenanceOptions
    @OptionGroup public var seedOption: SeedOption

    @Option(
        name: .customLong("corpus"),
        help:
            "Source corpus directory, repeatable. Defaults to the protocol's six sources: the nasa-steerable-v1 and nasa-structure-v1 asset dirs. Sources are corpus-qualified, because the two corpora share two asset filenames."
    )
    public var corpus: [String] = []

    @Option(
        name: .customLong("columns"),
        help:
            "Column count. The protocol fixes 80 — the shipping regime every standing verdict was measured at. Changing it makes this run incomparable with them."
    )
    public var columns: Int = 80

    @Option(
        name: .customLong("oversample"),
        help: "Sampling oversample. The protocol fixes 2, with the same caveat as --columns.")
    public var oversample: Int = 2

    @Option(
        name: .customLong("footprint"),
        help: "Per-cell scoring footprint in px (default 24, matching selection-ceiling).")
    public var footprint: Int = 24

    public init() {}

    public func execute(
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> LabExitCode {
        Arbiter.CLI.stimuli(
            arguments: Arbiter.CLI.StimuliArguments(
                outputDirectory: provenance.outputDirectory,
                seed: seedOption.seed,
                gitShaOverride: provenance.gitShaOverride,
                corpora: corpus.isEmpty ? Arbiter.CLI.defaultCorpora : corpus,
                columns: columns,
                oversample: oversample,
                footprint: footprint),
            standardOutput: standardOutput,
            standardError: standardError)
    }

    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}

public struct ArbiterJudgeSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "judge",
        abstract:
            "Run the VLM leg over a stimuli directory (protocol section 2.2). Each pair is judged in BOTH presentation orders, K times each, and decides for a side only when both order-majorities agree — a judge with a position bias ties instead of winning. Writes judge.json (the reproducibility pin) and judge-results.json (every raw vote)."
    )

    @OptionGroup public var provenance: ProvenanceOptions

    @Option(
        name: .customLong("stimuli-dir"),
        help: "Directory a previous `arbiter stimuli` run wrote its triplets and key.json to.")
    public var stimuliDirectory: String

    @Option(
        name: .customLong("runner"),
        help:
            "Executable to shell out to per call, replacing the section 2.2 default pin (codex exec -m gpt-5.6-terra at xhigh effort). Any judge change is a NEW judge config and must re-pass the section 5.1 validation gate before its verdicts count."
    )
    public var runner: String?

    @Option(
        name: .customLong("runner-arg"),
        help:
            "One argument for --runner, repeatable and order-preserving. The placeholders {reference}, {first}, {second} and {prompt} are substituted per call."
    )
    public var runnerArgument: [String] = []

    @Flag(
        name: .customLong("include-calibration"),
        help:
            "Also judge the C ladder. Off by default: v2 section 3 scopes the VLM leg to V + D + X + M, and the ladder is twenty more pairs at six calls each."
    )
    public var includeCalibration: Bool = false

    @Option(
        name: .customLong("samples-per-order"),
        help:
            "K, the repeated samples per presentation order (default 3, so 6 calls per pair). Repeated sampling is what stands in for the temperature control the 2026 APIs no longer expose."
    )
    public var samplesPerOrder: Int = Arbiter.Judge.defaultSamplesPerOrder

    public init() {}

    public func validate() throws {
        guard samplesPerOrder >= 1 else {
            throw ValidationError("--samples-per-order must be at least 1.")
        }
        guard runner != nil || runnerArgument.isEmpty else {
            throw ValidationError("--runner-arg needs --runner.")
        }
    }

    /// Internal rather than public only because `ArbiterJudgeRunner` is: the
    /// injection seam exists for the in-target tests, which reach it through
    /// `@testable`, and a public transport protocol would be SDK surface with no
    /// caller outside this lab.
    func execute(
        runner injectedRunner: ArbiterJudgeRunner? = nil,
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> LabExitCode {
        Arbiter.CLI.judge(
            arguments: Arbiter.CLI.JudgeArguments(
                outputDirectory: provenance.outputDirectory,
                stimuliDirectory: stimuliDirectory,
                gitShaOverride: provenance.gitShaOverride,
                runnerExecutable: runner,
                runnerArguments: runnerArgument,
                includeCalibration: includeCalibration,
                samplesPerOrder: samplesPerOrder),
            runner: injectedRunner,
            standardOutput: standardOutput,
            standardError: standardError)
    }

    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}

public struct ArbiterScoreSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "score",
        abstract:
            "Join the human answers and/or the judge results against key.json and apply the frozen rules (protocol sections 2.3 and 5.1). FAIL-FAST: a failed HUMAN validation gate exits nonzero, because nothing downstream of a failed gate means anything. A failed VLM gate does not — that leg is reported invalid and the human leg stands alone."
    )

    @OptionGroup public var provenance: ProvenanceOptions

    @Option(
        name: .customLong("stimuli-dir"),
        help: "Directory holding the key.json this run is joined against.")
    public var stimuliDirectory: String

    @Option(
        name: .customLong("answers"),
        help:
            "Filled-in answers CSV (pairID,choice with choice in L, R, tie). Omit for a VLM-only run; the human gate is then reported not-evaluated rather than failed."
    )
    public var answers: String?

    @Option(
        name: .customLong("judge-results"),
        help: "judge-results.json from an `arbiter judge` run. Omit for a human-only run.")
    public var judgeResults: String?

    public init() {}

    public func execute(
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> LabExitCode {
        Arbiter.CLI.score(
            arguments: Arbiter.CLI.ScoreArguments(
                outputDirectory: provenance.outputDirectory,
                stimuliDirectory: stimuliDirectory,
                answersPath: answers,
                judgeResultsPath: judgeResults,
                gitShaOverride: provenance.gitShaOverride),
            standardOutput: standardOutput,
            standardError: standardError)
    }

    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}
