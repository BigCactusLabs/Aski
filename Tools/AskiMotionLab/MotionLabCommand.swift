import ArgumentParser
import AskiToolSupport
import Foundation

/// CLI selector for the `--preset` flag: `all` resolves to both presets.
public enum MotionPresetSelection: String, CaseIterable, ExpressibleByArgument {
    case all
    case reveal
    case cycle

    public var presets: [MotionLabPreset] {
        switch self {
        case .all: MotionLabPreset.allCases
        case .reveal: [.reveal]
        case .cycle: [.cycle]
        }
    }
}

public struct MotionLabCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "AskiMotionLab",
        abstract:
            "Deterministic ASCII motion frames, GIF spike, and the ASTSK-41 temporal-prior / ASTSK-45 source-tether gates.",
        version: ToolVersion.current,
        subcommands: [AnimateSubcommand.self, TemporalPriorSubcommand.self, SourceTetherSubcommand.self],
        defaultSubcommand: AnimateSubcommand.self
    )

    public init() {}
}

/// The original single-command behavior (animation + GIF spike), now an explicit
/// subcommand and the default so `AskiMotionLab --preset all ...` keeps working.
public struct AnimateSubcommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "animate",
        abstract: "Materialize deterministic ASCII motion frames and a GIF spike."
    )

    @OptionGroup public var provenance: ProvenanceOptions
    @OptionGroup public var seedOption: SeedOption

    @Option(help: "Preset to run: all | reveal | cycle.")
    public var preset: MotionPresetSelection = .all

    @Option(help: "Input image. Default: a deterministic synthetic image.")
    public var image: String?

    @Option(help: "ASCII columns (1...\(ToolArgumentBounds.maxColumns)).")
    public var columns: Int = 80

    @Option(help: "Frames per second (1...\(ToolArgumentBounds.maxFPS)).")
    public var fps: Int = 12

    @Option(help: "Animation duration in seconds (0 < n <= \(ToolArgumentBounds.maxDuration)).")
    public var duration: Double = 2.0

    @Option(name: .long, help: "Emit per-preset GIF (true/false).")
    public var gif: Bool = true

    public init() {}

    public func validate() throws {
        try ToolValidation.requireColumns(columns)
        try ToolValidation.requireFPS(fps)
        try ToolValidation.requireDuration(duration)
        try ToolValidation.requireMaterializedFrameCount(duration: duration, fps: fps)
    }

    public func execute(
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
        date: String = MotionLabCLI.todayUTC()
    ) -> LabExitCode {
        let arguments = MotionLabArguments(
            outputDirectory: provenance.outputDirectory,
            presets: preset.presets,
            imagePath: image,
            columns: columns,
            fps: fps,
            duration: duration,
            seed: seedOption.seed,
            emitGIF: gif,
            gitShaOverride: provenance.gitShaOverride
        )
        return MotionLabCLI.run(
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
