import ArgumentParser
import AskiToolSupport
import Foundation

struct AskiMetadataCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "metadata",
        abstract: "Print versioned JSON describing the Aski command-line interface."
    )

    func run() throws {
        try FileHandle.standardOutput.write(contentsOf: Self.documentData())
    }

    static func documentData(root: ParsableCommand.Type = AskiCommand.self) throws -> Data {
        let dump = Data(root._dumpHelp().utf8)
        let decoder = JSONDecoder()
        let header = try Self.decode(HelpHeader.self, from: dump, using: decoder)
        guard header.serializationVersion == 0 else {
            throw MetadataError.unsupportedHelpVersion(header.serializationVersion)
        }

        let help = try Self.decode(HelpDocument.self, from: dump, using: decoder)
        var commands: [MetadataCommand] = []
        try help.command.appendCommands(configured: root, parentPath: [], to: &commands)
        return try StableJSON.data(for: MetadataDocument(toolVersion: ToolVersion.current, commands: commands))
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from dump: Data,
        using decoder: JSONDecoder
    ) throws -> Value {
        do {
            return try decoder.decode(type, from: dump)
        } catch {
            throw MetadataError.invalidHelp(error)
        }
    }
}

private struct MetadataDocument: Encodable {
    let schemaVersion = 1
    let toolVersion: String
    let commands: [MetadataCommand]

    // Each product replaces the executable prefix. The remainder of argv is unchanged.
    let replayMappings = [
        ReplayMapping(product: "AskiAccessLab", lab: "accessibility"),
        ReplayMapping(product: "AskiColorLab", lab: "color"),
        ReplayMapping(product: "AskiDecolorLab", lab: "decolor"),
        ReplayMapping(product: "AskiHDRLab", lab: "hdr"),
        ReplayMapping(product: "AskiMotionLab", lab: "motion"),
        ReplayMapping(product: "AskiPresetLab", lab: "preset"),
        ReplayMapping(product: "AskiVideoLab", lab: "video"),
    ]
}

private struct ReplayMapping: Encodable {
    let product: String
    let canonicalPath: [String]

    init(product: String, lab: String) {
        self.product = product
        canonicalPath = ["aski", "lab", lab]
    }
}

private struct MetadataCommand: Encodable {
    enum Stability: String, Encodable {
        case stable
        case research
    }

    let path: [String]
    let aliases: [String]
    let stability: Stability
    let arguments: [MetadataArgument]
    let defaultSubcommand: String?
}

private struct MetadataArgument: Encodable {
    enum Kind: String, Codable {
        case positional
        case option
        case flag
    }

    let kind: Kind
    let names: [String]
    let isOptional: Bool
    let isRepeating: Bool
    let valueName: String?
    let defaultValue: String?
}

// ArgumentParser's experimental dump is only an input to the Aski v1 contract.
private struct HelpHeader: Decodable {
    let serializationVersion: Int
}

private struct HelpDocument: Decodable {
    let command: HelpCommand
}

private struct HelpCommand: Decodable {
    let commandName: String
    let shouldDisplay: Bool
    let aliases: [String]?
    let arguments: [HelpArgument]?
    let subcommands: [HelpCommand]?

    func appendCommands(
        configured: ParsableCommand.Type?,
        parentPath: [String],
        to commands: inout [MetadataCommand]
    ) throws {
        let path = parentPath + [commandName]
        if let configured, configured._commandName != commandName {
            throw MetadataError.commandMismatch(path)
        }
        guard shouldDisplay else { return }

        let configuration = configured?.configuration
        commands.append(
            MetadataCommand(
                path: path,
                aliases: aliases ?? [],
                stability: path.starts(with: ["aski", "lab"]) ? .research : .stable,
                arguments: (arguments ?? []).filter(\.shouldDisplay).map { $0.metadata() },
                defaultSubcommand: configuration?.defaultSubcommand?._commandName
            )
        )

        let configuredChildren = configuration?.subcommands ?? []
        var dumpedChildren = subcommands ?? []
        if parentPath.isEmpty {
            // The v0 dump appends one built-in help node after the configured root children.
            guard dumpedChildren.popLast()?.commandName == "help" else {
                throw MetadataError.commandMismatch(path)
            }
        }
        guard configuredChildren.map({ $0._commandName }) == dumpedChildren.map(\.commandName) else {
            throw MetadataError.commandMismatch(path)
        }
        for (child, type) in zip(dumpedChildren, configuredChildren) {
            try child.appendCommands(configured: type, parentPath: path, to: &commands)
        }
        if parentPath.isEmpty, !configuredChildren.isEmpty, let help = subcommands?.last {
            try help.appendCommands(configured: nil, parentPath: path, to: &commands)
        }
    }
}

private struct HelpArgument: Decodable {
    struct Name: Decodable {
        enum Kind: String, Decodable {
            case long
            case short
            case longWithSingleDash
        }

        let kind: Kind
        let name: String

        var spelling: String {
            (kind == .long ? "--" : "-") + name
        }
    }

    let kind: MetadataArgument.Kind
    let shouldDisplay: Bool
    let names: [Name]?
    let isOptional: Bool
    let isRepeating: Bool
    let valueName: String?
    let defaultValue: String?

    func metadata() -> MetadataArgument {
        MetadataArgument(
            kind: kind,
            names: (names ?? []).map(\.spelling),
            isOptional: isOptional,
            isRepeating: isRepeating,
            valueName: valueName,
            defaultValue: defaultValue
        )
    }
}

private enum MetadataError: LocalizedError {
    case invalidHelp(any Error)
    case unsupportedHelpVersion(Int)
    case commandMismatch([String])

    var errorDescription: String? {
        switch self {
        case .invalidHelp(let error):
            return "Aski metadata cannot decode ArgumentParser help: \(error)."
        case .unsupportedHelpVersion(let version):
            return "Aski metadata cannot read ArgumentParser help version \(version)."
        case .commandMismatch(let path):
            return "Aski metadata found a mismatch between ArgumentParser help and configuration at '\(path.joined(separator: " "))'."
        }
    }
}
