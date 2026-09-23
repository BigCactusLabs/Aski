import ArgumentParser
import AskiToolSupport
import Foundation

public struct AskiDecolorLabCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "AskiDecolorLab",
        abstract: "Research harness for color-theory decoloring experiments.",
        version: ToolVersion.current,
        subcommands: [DecolorEvaluateCommand.self, DecolorCheckCommand.self]
    )

    public init() {}

    // Preserve the legacy "missing command -> usage (exit 64)" contract.
    // Without this, the default root run() shows help and exits 0 on bare invocation.
    public func run() throws {
        throw ValidationError("Missing command. Commands: evaluate, check. See --help.")
    }
}

public struct DecolorEvaluateCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "evaluate",
        abstract: "Evaluate decoloring quality over fixtures."
    )

    @OptionGroup public var provenance: ProvenanceOptions

    @Option(help: "ASCII columns for rendered-grid fixtures (1...\(ToolArgumentBounds.maxColumns)).")
    public var columns: Int = 80

    @Option(name: .customLong("background-hex"), help: "Background hex color for rendered fixtures.")
    public var backgroundHex: String = "#101010"

    public init() {}

    public func validate() throws {
        try ToolValidation.requireColumns(columns)
    }

    public func execute(
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
        date: String = DecolorLabCLI.todayUTC()
    ) -> LabExitCode {
        let arguments = DecolorLabArguments(
            outputDirectory: provenance.outputDirectory,
            columns: columns,
            backgroundHex: backgroundHex,
            gitShaOverride: provenance.gitShaOverride
        )
        return DecolorLabCLI.run(
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

public struct DecolorCheckCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Check decoloring fixtures against stored baselines."
    )

    @OptionGroup public var provenance: ProvenanceOptions

    @Option(help: "ASCII columns for rendered-grid fixtures (1...\(ToolArgumentBounds.maxColumns)).")
    public var columns: Int = 80

    @Option(name: .customLong("background-hex"), help: "Background hex color for rendered fixtures.")
    public var backgroundHex: String = "#101010"

    public init() {}

    public func validate() throws {
        try ToolValidation.requireColumns(columns)
    }

    public func execute(
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> LabExitCode {
        let arguments = DecolorLabArguments(
            outputDirectory: provenance.outputDirectory,
            columns: columns,
            backgroundHex: backgroundHex,
            gitShaOverride: provenance.gitShaOverride
        )
        return DecolorLabCLI.check(
            arguments: arguments,
            standardOutput: standardOutput,
            standardError: standardError
        )
    }

    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}
