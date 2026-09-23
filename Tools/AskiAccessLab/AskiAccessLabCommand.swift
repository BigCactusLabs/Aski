import ArgumentParser
import AskiToolSupport
import Foundation

public struct AskiAccessLabCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "AskiAccessLab",
        abstract: "Audit Aski palettes and rendered ASCII outputs for CVD distinguishability.",
        version: ToolVersion.current,
        subcommands: [AccessLabAuditCommand.self]
    )

    public init() {}

    // Preserve the legacy "missing command -> usage (exit 64)" contract (the old
    // parser threw `.missingCommand`). Without this, the default root run() shows
    // help and exits 0 on bare invocation.
    public func run() throws {
        throw ValidationError("Missing command. The only command is 'audit'. See --help.")
    }
}

public struct AccessLabAuditCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Run the accessibility audit over the palette/grid fixtures."
    )

    @OptionGroup public var provenance: ProvenanceOptions

    @Option(help: "ASCII columns for rendered-grid fixtures (1...\(ToolArgumentBounds.maxColumns)).")
    public var columns: Int = 80

    public init() {}

    public func validate() throws {
        try ToolValidation.requireColumns(columns)
    }

    public func execute(
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
        date: String = AccessLabCLI.todayUTC()
    ) -> LabExitCode {
        let arguments = AccessLabArguments(
            outputDirectory: provenance.outputDirectory,
            columns: columns,
            gitShaOverride: provenance.gitShaOverride
        )
        return AccessLabCLI.run(
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
