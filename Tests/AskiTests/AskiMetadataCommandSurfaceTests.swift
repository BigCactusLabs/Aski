import ArgumentParser
import Foundation
import Testing

@testable import AskiCLI
import AskiToolSupport

@Suite struct AskiMetadataCommandSurfaceTests {
    private typealias JSON = [String: Any]

    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func builtMetadataMatchesLiveCommandSurface() throws {
        let output = try Self.runAski(["metadata"], in: Self.root)
        #expect(output == (try Self.runAski(["metadata"], in: Self.root)))
        #expect(output.last == 0x0A)
        #expect(output.dropLast().last != 0x0A)
        let report = try Self.object(from: output)
        let json = String(decoding: output, as: UTF8.self)
        let topLevelKeys = json.split(separator: "\n")
            .filter { $0.hasPrefix("  \"") }
            .compactMap { $0.split(separator: "\"").dropFirst().first }
        #expect(topLevelKeys == ["commands", "replayMappings", "schemaVersion", "toolVersion"])
        #expect(!json.contains("\\/"))
        #expect(report["schemaVersion"] as? Int == 1)

        let revision = GitSHA.probe(workingDirectory: Self.root.path)
        #expect(revision != "unknown")
        #expect(report["toolVersion"] as? String == revision)
        let version = try Self.runAski(["--version"], in: Self.root)
        #expect(String(decoding: version, as: UTF8.self).trimmingCharacters(in: .newlines) == revision)

        let liveHelp = try Self.help(AskiCommand.self)
        let liveCommands = try Self.flatten(liveHelp)
        let commands = try #require(report["commands"] as? [JSON])
        #expect(NSDictionary(dictionary: ["commands": commands]) == NSDictionary(dictionary: ["commands": liveCommands]))

        let paths = try commands.map { try #require($0["path"] as? [String]) }
        #expect(Set(paths).count == paths.count)
        #expect(paths.contains(["aski", "metadata"]))
        #expect(paths.contains(["aski", "help"]))
        #expect(!paths.contains { $0.count > 2 && $0.last == "help" })

        let liveDefaults = Self.configuredDefaults(AskiCommand.self)
        for command in commands {
            let path = try #require(command["path"] as? [String])
            let actual = command["defaultSubcommand"] as? String
            #expect(actual == liveDefaults[path])
            if let actual {
                #expect(paths.contains(path + [actual]))
            }
        }
        #expect(liveDefaults[["aski"]] == "render")
        #expect(liveDefaults[["aski", "lab", "motion"]] == "animate")

        try Self.checkReplayMappings(report, liveHelp: liveHelp, paths: Set(paths))
    }

    @Test func checkoutRevisionIsUnknownOutsideGit() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = try Self.runAski(["metadata"], in: directory, withoutGitOverrides: true)
        #expect(try Self.object(from: output)["toolVersion"] as? String == "unknown")
    }

    @Test func aliasesVisibilityAndImplicitDefaultFollowConfiguration() throws {
        let report = try Self.object(from: AskiMetadataCommand.documentData(root: FixtureRoot.self))
        let commands = try #require(report["commands"] as? [JSON])
        let paths = commands.compactMap { $0["path"] as? [String] }
        #expect(paths == [["aski"], ["aski", "fixture-child"], ["aski", "help"]])
        #expect(commands.first?["defaultSubcommand"] as? String == "fixture-child")
        let child = try #require(commands.first { $0["path"] as? [String] == ["aski", "fixture-child"] })
        #expect(child["aliases"] as? [String] == ["shortcut"])
        let arguments = try #require(child["arguments"] as? [JSON])
        let names = arguments.compactMap { $0["names"] as? [String] }
        #expect(names.contains(["--fixture-value"]))
        #expect(!names.joined().contains("--fixture-secret"))
        let visible = try #require(arguments.first { $0["names"] as? [String] == ["--fixture-value"] })
        #expect(visible["defaultValue"] as? String == "example/path")
        #expect(visible["isOptional"] as? Bool == true)
    }

    @Test func committedSchemaDescribesTheV1Contract() throws {
        let schemaURL = Self.root.appending(path: "docs/assets/schemas/aski-metadata-v1.schema.json")
        let schema = try Self.object(from: Data(contentsOf: schemaURL))
        #expect(schema["$schema"] as? String == "https://json-schema.org/draft/2020-12/schema")
        let properties = try #require(schema["properties"] as? [String: JSON])
        #expect(properties["schemaVersion"]?["const"] as? Int == 1)
        #expect(Set(schema["required"] as? [String] ?? []) == ["schemaVersion", "toolVersion", "commands", "replayMappings"])
        let definitions = try #require(schema["$defs"] as? [String: JSON])
        let command = try #require(definitions["command"]?["properties"] as? [String: JSON])
        #expect(command["stability"]?["enum"] as? [String] == ["stable", "research"])
        let argument = try #require(definitions["argument"]?["properties"] as? [String: JSON])
        #expect(argument["kind"]?["enum"] as? [String] == ["positional", "option", "flag"])
        #expect(argument["defaultValue"]?["type"] as? String == "string")
        for additiveObject in [schema, definitions["command"], definitions["argument"], definitions["replayMapping"]] {
            #expect(additiveObject?["additionalProperties"] as? Bool == true)
        }
    }

    private static func checkReplayMappings(_ report: JSON, liveHelp: JSON, paths: Set<[String]>) throws {
        let manifest = try String(contentsOf: root.appending(path: "Package.swift"), encoding: .utf8)
        let replayProduct = try NSRegularExpression(pattern: #"\.executable\(\s*name:\s*"(Aski[A-Za-z0-9]*Lab)""#)
        let declaredProducts = replayProduct.matches(in: manifest, range: NSRange(manifest.startIndex..., in: manifest))
            .compactMap { Range($0.range(at: 1), in: manifest).map { String(manifest[$0]) } }

        let mappings = try #require(report["replayMappings"] as? [JSON])
        let products = try mappings.map { try #require($0["product"] as? String) }
        #expect(products == declaredProducts.sorted())
        #expect(!products.isEmpty)

        let lab = try child(named: "lab", of: liveHelp)
        let replayPaths = try mappings.map { try #require($0["canonicalPath"] as? [String]) }
        let labChildren = try #require(lab["subcommands"] as? [JSON])
        let expectedPaths = labChildren.filter { $0["shouldDisplay"] as? Bool == true }.compactMap {
            ($0["commandName"] as? String).map { ["aski", "lab", $0] }
        }
        #expect(Set(replayPaths) == Set(expectedPaths))
        for (product, canonicalPath) in zip(products, replayPaths) {
            #expect(paths.contains(canonicalPath))
            let labName = try #require(canonicalPath.last)
            let replay = try #require(CommandSurfaceGoldenTests.tools.first { $0.name == product })
            let replayDump = try object(from: Data(replay.dumpHelp().utf8))
            let replayRoot = try #require(replayDump["command"] as? JSON)
            let canonical = try child(named: labName, of: lab)
            let canonicalSurface = try relativeSurface(canonical)
            let replaySurface = try relativeSurface(replayRoot)
            #expect(NSDictionary(dictionary: ["surface": canonicalSurface]) == NSDictionary(dictionary: ["surface": replaySurface]))
        }
    }

    private static func help(_ command: ParsableCommand.Type) throws -> JSON {
        let dump = try object(from: Data(command._dumpHelp().utf8))
        #expect(dump["serializationVersion"] as? Int == 0)
        return try #require(dump["command"] as? JSON)
    }

    private static func object(from data: Data) throws -> JSON {
        try #require(JSONSerialization.jsonObject(with: data) as? JSON)
    }

    private static func child(named name: String, of node: JSON) throws -> JSON {
        try #require((node["subcommands"] as? [JSON])?.first { $0["commandName"] as? String == name })
    }

    private static func flatten(_ node: JSON, parents: [String] = []) throws -> [JSON] {
        guard node["shouldDisplay"] as? Bool == true else { return [] }
        let path = parents + [try #require(node["commandName"] as? String)]
        let arguments = (node["arguments"] as? [JSON] ?? []).filter { $0["shouldDisplay"] as? Bool == true }
        let publicArguments: [JSON] = try arguments.map { argument in
            var result = argument.filter { ["defaultValue", "isOptional", "isRepeating", "kind", "valueName"].contains($0.key) }
            result["names"] = try (argument["names"] as? [JSON] ?? []).map { name in
                let prefix = name["kind"] as? String == "long" ? "--" : "-"
                return prefix + (try #require(name["name"] as? String))
            }
            return result
        }
        var command: JSON = [
            "path": path,
            "aliases": node["aliases"] as? [String] ?? [],
            "stability": path.prefix(2).elementsEqual(["aski", "lab"]) ? "research" : "stable",
            "arguments": publicArguments,
        ]
        command["defaultSubcommand"] = node["defaultSubcommand"]
        let children = node["subcommands"] as? [JSON] ?? []
        return [command] + (try children.flatMap { try flatten($0, parents: path) })
    }

    private static func relativeSurface(_ node: JSON) throws -> [JSON] {
        try flatten(node).compactMap { command in
            let path = try #require(command["path"] as? [String])
            // Replay roots have an injected help child that is not part of the lab.
            guard path.count != 2 || path.last != "help" else { return nil }
            var relative = command
            relative["path"] = Array(path.dropFirst())
            relative["stability"] = nil
            return relative
        }
    }

    private static func configuredDefaults(
        _ type: ParsableCommand.Type,
        parents: [String] = []
    ) -> [[String]: String] {
        let configuration = type.configuration
        guard configuration.shouldDisplay else { return [:] }
        let path = parents + [type._commandName]
        var defaults: [[String]: String] = [:]
        defaults[path] = configuration.defaultSubcommand?._commandName
        for child in configuration.subcommands {
            defaults.merge(configuredDefaults(child, parents: path)) { first, _ in first }
        }
        return defaults
    }

    private static func runAski(
        _ arguments: [String],
        in directory: URL,
        withoutGitOverrides: Bool = false
    ) throws -> Data {
        let process = Process()
        process.executableURL = root.appending(path: ".build/debug/aski")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        if withoutGitOverrides {
            process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        }

        // Use a file for stderr so an unexpected large error cannot block stdout.
        let errorURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data().write(to: errorURL, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: errorURL) }
        let errorOutput = try FileHandle(forWritingTo: errorURL)
        defer { try? errorOutput.close() }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let errors = try Data(contentsOf: errorURL)
        #expect(process.terminationStatus == 0, "aski \(arguments) failed: \(String(decoding: errors, as: UTF8.self))")
        #expect(errors.isEmpty)
        return data
    }

    private struct FixtureRoot: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "aski",
            subcommands: [FixtureChild.self, HiddenChild.self],
            defaultSubcommand: FixtureChild.self
        )
    }

    private struct FixtureChild: ParsableCommand {
        static let configuration = CommandConfiguration(aliases: ["shortcut"])

        @Option(help: "A visible option.")
        var fixtureValue = "example/path"

        @Flag(help: .hidden)
        var fixtureSecret = false
    }

    private struct HiddenChild: ParsableCommand {
        static let configuration = CommandConfiguration(shouldDisplay: false, subcommands: [FixtureChild.self])
    }
}
