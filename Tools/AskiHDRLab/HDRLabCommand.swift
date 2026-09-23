import ArgumentParser
import AskiToolSupport
import Foundation

public struct AskiHDRLabCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "AskiHDRLab",
        abstract: "HDR/EDR emissive render spike: gain-map Adaptive HDR HEIC + decisive verdict.",
        version: ToolVersion.current,
        subcommands: [HDREvaluateCommand.self, HDRCheckCommand.self]
    )

    public init() {}

    // Bare invocation -> usage (exit 64), matching the other multi-command labs.
    public func run() throws {
        throw ValidationError("Missing command. Commands: evaluate, check. See --help.")
    }
}

public struct HDREvaluateCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "evaluate",
        abstract: "Render SDR + HDR-emissive fixtures, author gain-map HEICs, write hdr.csv + result.yaml + verdict."
    )

    @OptionGroup public var provenance: ProvenanceOptions

    @Option(help: "ASCII columns for rendered fixtures (1...\(ToolArgumentBounds.maxColumns)).")
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
        date: String = HDRLabCLI.todayUTC()
    ) -> LabExitCode {
        HDRLabCLI.evaluate(
            arguments: HDRLabArguments(
                outputDirectory: provenance.outputDirectory,
                columns: columns,
                backgroundHex: backgroundHex,
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

public struct HDRCheckCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Fail-fast gate over G1–G4. Nonzero exit on KILL."
    )

    @OptionGroup public var provenance: ProvenanceOptions

    @Option(help: "ASCII columns for rendered fixtures (1...\(ToolArgumentBounds.maxColumns)).")
    public var columns: Int = 80

    @Option(name: .customLong("background-hex"), help: "Background hex color for rendered fixtures.")
    public var backgroundHex: String = "#101010"

    @Flag(name: .customLong("selftest-force-kill"), help: .private)
    public var selftestForceKill: Bool = false

    public init() {}

    public func validate() throws {
        try ToolValidation.requireColumns(columns)
    }

    public func execute(
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) -> LabExitCode {
        HDRLabCLI.check(
            arguments: HDRLabArguments(
                outputDirectory: provenance.outputDirectory,
                columns: columns,
                backgroundHex: backgroundHex,
                gitShaOverride: provenance.gitShaOverride,
                selftestForceKill: selftestForceKill
            ),
            standardOutput: standardOutput,
            standardError: standardError
        )
    }

    public func run() throws {
        let status = execute()
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}
