import ArgumentParser
import AskiAccessLab
import AskiColorLab
import AskiDecolorLab
import AskiHDRLab
import AskiMotionLab
import AskiPresetLab
import AskiToolSupport
import AskiVideoLab

/// First-class product command. `render` remains the default subcommand so the
/// historical one-shot invocation stays valid while the lab tree is discoverable.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
public struct AskiCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "aski",
        abstract: "Deterministic, shape-aware ASCII rendering for images and media.",
        version: ToolVersion.current,
        subcommands: [AskiRenderCommand.self, AskiInspectCommand.self, LabCommand.self],
        defaultSubcommand: AskiRenderCommand.self
    )

    public init() {}
}

/// Namespace for repository research tools. A bare invocation is an error, just
/// like each historical replay command that requires a subcommand.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
public struct LabCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "lab",
        abstract: "Run Aski research harnesses and evidence-producing quality gates.",
        subcommands: [
            ColorLabCommand.self,
            MotionLabCommand.self,
            VideoLabCommand.self,
            AccessibilityLabCommand.self,
            DecolorLabCommand.self,
            HDRLabCommand.self,
            PresetLabCommand.self,
        ]
    )

    public init() {}

    public mutating func run() async throws {
        throw ValidationError("Missing command. See --help for the available lab subcommands.")
    }
}

public struct ColorLabCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "color",
        abstract: AskiColorLabCommand.configuration.abstract,
        version: ToolVersion.current,
        subcommands: AskiColorLabCommand.configuration.subcommands
    )

    public init() {}

    public func run() throws {
        throw ValidationError("Missing command. See --help for the available subcommands.")
    }
}

public struct MotionLabCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "motion",
        abstract: AskiMotionLab.MotionLabCommand.configuration.abstract,
        version: ToolVersion.current,
        subcommands: AskiMotionLab.MotionLabCommand.configuration.subcommands,
        defaultSubcommand: AskiMotionLab.MotionLabCommand.configuration.defaultSubcommand
    )

    public init() {}
}

/// Async adapter around the existing video lab arguments and execution path.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
public struct VideoLabCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "video",
        abstract: AskiVideoLab.VideoLabCommand.configuration.abstract,
        version: ToolVersion.current
    )

    @OptionGroup public var options: AskiVideoLab.VideoLabCommand

    public init() {}

    public mutating func run() async throws {
        let rawArguments = Array(CommandLine.arguments.dropFirst())
        let status = await options.executeAsync(codecWasProvided: rawArguments.contains("--codec"))
        guard status == .success else { throw ExitCode(status.rawValue) }
    }
}

public struct AccessibilityLabCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "accessibility",
        abstract: AskiAccessLabCommand.configuration.abstract,
        version: ToolVersion.current,
        subcommands: AskiAccessLabCommand.configuration.subcommands
    )

    public init() {}

    public func run() throws {
        throw ValidationError("Missing command. The only command is 'audit'. See --help.")
    }
}

public struct DecolorLabCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "decolor",
        abstract: AskiDecolorLabCommand.configuration.abstract,
        version: ToolVersion.current,
        subcommands: AskiDecolorLabCommand.configuration.subcommands
    )

    public init() {}

    public func run() throws {
        throw ValidationError("Missing command. Commands: evaluate, check. See --help.")
    }
}

public struct HDRLabCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "hdr",
        abstract: AskiHDRLabCommand.configuration.abstract,
        version: ToolVersion.current,
        subcommands: AskiHDRLabCommand.configuration.subcommands
    )

    public init() {}

    public func run() throws {
        throw ValidationError("Missing command. Commands: evaluate, check. See --help.")
    }
}

public struct PresetLabCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "preset",
        abstract: AskiPresetLabCommand.configuration.abstract,
        version: ToolVersion.current,
        subcommands: AskiPresetLabCommand.configuration.subcommands
    )

    public init() {}

    public func run() throws {
        throw ValidationError("Missing command. Use 'ab', 'probe-stimuli', or 'probe-score'. See --help.")
    }
}
