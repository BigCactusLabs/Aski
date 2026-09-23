import ArgumentParser
import AskiToolSupport
import Foundation

public struct AskiPresetLabCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "AskiPresetLab",
        abstract: "A/B Vesper preset choices and run the preregistered ASKI-73 product probe.",
        version: ToolVersion.current,
        subcommands: [PresetLabABCommand.self, ProductProbeStimuliCommand.self, ProductProbeScoreCommand.self]
    )

    public init() {}

    // Match the other labs' "missing command → usage (exit 64)" contract.
    public func run() throws {
        throw ValidationError("Missing command. Use 'ab', 'probe-stimuli', or 'probe-score'. See --help.")
    }
}

public struct ProductProbeStimuliCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "probe-stimuli",
        abstract: "Generate blinded, matched Vesper product-probe stills and center-reveal motion stimuli."
    )

    @OptionGroup public var provenance: ProvenanceOptions

    @Option(name: .customLong("source-manifest"), help: "Private source-manifest JSON (schema v1).")
    public var sourceManifest: String

    @Option(name: .customLong("key-output"), help: "Private key JSON path outside --output-dir.")
    public var keyOutput: String

    @Option(help: "Deterministic arm-order and motion seed. Default: 7301.")
    public var seed: UInt64 = 7301

    @Option(help: "Center-reveal GIF frame rate. Default: 12.")
    public var fps: Int = 12

    @Option(help: "Center-reveal duration in seconds. Default: 2.")
    public var duration: Double = 2

    @Option(name: .customLong("run-kind"), help: "Evidence label: human-probe or instrument-smoke. Default: human-probe.")
    public var runKind: String = "human-probe"

    public init() {}

    public func validate() throws {
        guard fps > 0, fps <= 60 else { throw ValidationError("--fps must be in 1...60") }
        guard duration.isFinite, duration > 0, duration <= 10 else {
            throw ValidationError("--duration must be finite and in (0, 10]")
        }
        guard runKind == "human-probe" || runKind == "instrument-smoke" else {
            throw ValidationError("--run-kind must be human-probe or instrument-smoke")
        }
    }

    public func execute(
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
        date: String = PresetLabCLI.todayUTC()
    ) -> LabExitCode {
        ProductProbeCLI.generate(
            arguments: ProductProbeStimuliArguments(
                sourceManifestPath: sourceManifest,
                outputDirectory: provenance.outputDirectory,
                keyOutputPath: keyOutput,
                seed: seed,
                fps: fps,
                duration: duration,
                runKind: runKind,
                gitShaOverride: provenance.gitShaOverride
            ),
            standardOutput: standardOutput,
            standardError: standardError,
            date: date
        )
    }

    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}

public struct ProductProbeScoreCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "probe-score",
        abstract: "Validate private ASKI-73 response logs and score the preregistered product gates."
    )

    @OptionGroup public var provenance: ProvenanceOptions

    @Option(name: .customLong("stimuli-manifest"), help: "Public stimuli manifest.json from probe-stimuli.")
    public var stimuliManifest: String

    @Option(help: "Private arm/source key JSON from probe-stimuli.")
    public var key: String

    @Option(name: .customLong("session-one"), help: "Private first-session response CSV.")
    public var sessionOne: String

    @Option(name: .customLong("repeat-log"), help: "Private later-session/payment CSV.")
    public var repeatLog: String

    public init() {}

    public func execute(
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
        date: String = PresetLabCLI.todayUTC()
    ) -> LabExitCode {
        ProductProbeCLI.score(
            arguments: ProductProbeScoreArguments(
                stimuliManifestPath: stimuliManifest,
                keyPath: key,
                sessionOnePath: sessionOne,
                repeatLogPath: repeatLog,
                outputDirectory: provenance.outputDirectory,
                gitShaOverride: provenance.gitShaOverride
            ),
            standardOutput: standardOutput,
            standardError: standardError,
            date: date
        )
    }

    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}

public struct PresetLabABCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "ab",
        abstract: """
            Render one portrait across charset × column candidates through the draft Vesper preset; \
            write labeled PNGs + a contact sheet + manifest for human adjudication. Use REAL faces — \
            the point is judging legibility on real inputs before ASTSK-47 freezes the preset.
            """
    )

    @OptionGroup public var provenance: ProvenanceOptions

    @Option(name: .customLong("input"), help: "Path to a source portrait image.")
    public var input: String

    @Option(parsing: .upToNextOption, help: "Charsets to A/B (space-separated). Default: standard minimal.")
    public var charset: [Charset] = [.standard, .minimal]

    @Option(parsing: .upToNextOption, help: "Column counts to A/B (space-separated). Default: 60 72 80 96.")
    public var columns: [Int] = [60, 72, 80, 96]

    @Option(help: "Foreground 'bone' ink #RRGGBB (sRGB). Default: #E8E2D2.")
    public var ink: String = "#E8E2D2"

    @Option(help: "Accent ink #RRGGBB (Display P3). Default: #9E2B25 (crimson).")
    public var accent: String = "#9E2B25"

    @Option(help: "Charcoal background (#RRGGBB or name). Default: #161616 — never pure black (halation).")
    public var background: BackgroundColor = BackgroundColor(argument: "#161616")!

    @Option(help: "OKLAB-L contrast bump for gothic shadows, -1...1. Default: 0.15.")
    public var contrast: Float = 0.15

    @Option(help: "Render font point size. Default: 14.")
    public var fontSize: Double = 14

    @Option(help: "Render scale (@Nx). Default: 2.")
    public var scale: Double = 2

    public init() {}

    public func validate() throws {
        guard !charset.isEmpty, !columns.isEmpty else {
            throw ValidationError("Provide at least one --charset and one --columns value.")
        }
        for value in columns { try ToolValidation.requireColumns(value) }
        try ToolValidation.requireFontSize(fontSize)
        try ToolValidation.requireFontScale(scale)
    }

    public func execute(
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
        date: String = PresetLabCLI.todayUTC()
    ) -> LabExitCode {
        let arguments = PresetLabArguments(
            inputPath: input,
            outputDirectory: provenance.outputDirectory,
            charsets: charset,
            columnCounts: columns,
            inkHex: ink,
            accentHex: accent,
            background: background,
            contrast: contrast,
            fontSize: fontSize,
            scale: scale,
            gitShaOverride: provenance.gitShaOverride
        )
        return PresetLabCLI.run(
            arguments: arguments,
            standardOutput: standardOutput,
            standardError: standardError,
            date: date
        )
    }

    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}
