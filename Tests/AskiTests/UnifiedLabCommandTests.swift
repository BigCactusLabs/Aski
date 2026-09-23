import ArgumentParser
import AskiCLI
import Foundation
import Testing

@Suite(.serialized) struct UnifiedLabCommandTests {
    private static let labNames = [
        "color", "motion", "video", "accessibility", "decolor", "hdr", "preset",
    ]

    private static let replayProducts = [
        "AskiColorLab", "AskiMotionLab", "AskiVideoLab", "AskiAccessLab",
        "AskiDecolorLab", "AskiHDRLab", "AskiPresetLab",
    ]

    @Test func canonicalTreeContainsEveryLabNamespace() {
        #expect(Self.commandNames(AskiCommand.configuration.subcommands) == ["render", "inspect", "lab"])
        #expect(Self.commandNames(LabCommand.configuration.subcommands) == Self.labNames)
    }

    /// Regression for the closed prototype whose synchronous entry point rejected
    /// every invocation before parsing, including `--help`.
    @Test func builtAskiBinaryLaunches() throws {
        let root = try Self.packageRoot()
        let result = try Self.run(try Self.builtExecutable(named: "aski", root: root), arguments: ["--help"])

        #expect(result.status == 0)
        #expect(result.output.contains("USAGE: aski"))
        #expect(result.output.contains("lab"))
    }

    @Test func replayProductsPreserveHelpAndBareExitBehavior() throws {
        let root = try Self.packageRoot()

        for (lab, replay) in zip(Self.labNames, Self.replayProducts) {
            let replayURL = try Self.builtExecutable(named: replay, root: root)
            let replayHelp = try Self.run(replayURL, arguments: ["--help"])
            #expect(replayHelp.status == 0, "\(replay) --help failed: \(replayHelp.output)")
            #expect(replayHelp.output.contains("USAGE:"), "\(replay) did not render help")

            let canonicalHelp = try Self.run(
                try Self.builtExecutable(named: "aski", root: root),
                arguments: ["lab", lab, "--help"]
            )
            #expect(canonicalHelp.status == 0, "aski lab \(lab) --help failed: \(canonicalHelp.output)")
            #expect(canonicalHelp.output.contains("USAGE:"), "aski lab \(lab) did not render help")

            let replayVersion = try Self.run(replayURL, arguments: ["--version"])
            let canonicalVersion = try Self.run(
                try Self.builtExecutable(named: "aski", root: root),
                arguments: ["lab", lab, "--version"]
            )
            #expect(replayVersion.status == 0, "\(replay) --version failed: \(replayVersion.output)")
            #expect(canonicalVersion.status == replayVersion.status, "aski lab \(lab) --version failed")
            #expect(canonicalVersion.output == replayVersion.output, "aski lab \(lab) version diverged")

            let canonicalBare = try Self.run(
                try Self.builtExecutable(named: "aski", root: root),
                arguments: ["lab", lab]
            )
            let replayBare = try Self.run(replayURL, arguments: [])

            #expect(canonicalBare.status == 64, "aski lab \(lab) unexpectedly succeeded")
            #expect(replayBare.status == canonicalBare.status, "\(replay) exit behavior diverged")
            #expect(canonicalBare.output.lowercased().contains("usage:"), "aski lab \(lab) omitted usage")
            #expect(replayBare.output.lowercased().contains("usage:"), "\(replay) omitted usage")
        }
    }

    @Test func replayTargetsAreByteThinEntrypoints() throws {
        let root = try Self.packageRoot()
        let syncCommands = [
            "AskiColorLab": "AskiColorLabCommand",
            "AskiMotionLab": "MotionLabCommand",
            "AskiAccessLab": "AskiAccessLabCommand",
            "AskiDecolorLab": "AskiDecolorLabCommand",
            "AskiHDRLab": "AskiHDRLabCommand",
            "AskiPresetLab": "AskiPresetLabCommand",
        ]

        for (module, command) in syncCommands {
            let source = try String(
                contentsOf: root.appending(path: "Tools/\(module)Runner/main.swift"),
                encoding: .utf8
            )
            #expect(source == "import ArgumentParser\nimport \(module)\n\n\(command).main()\n")
        }

        let video = try String(
            contentsOf: root.appending(path: "Tools/AskiVideoLabRunner/main.swift"),
            encoding: .utf8
        )
        #expect(
            video
                == "import AskiToolSupport\nimport AskiVideoLab\n\nawait AsyncCommandRunner.main(VideoLabCommand.self)\n"
        )

        for module in Self.replayProducts {
            #expect(
                !FileManager.default.fileExists(
                    atPath: root.appending(path: "Tools/\(module)/main.swift").path
                ),
                "\(module) implementation target still contains an executable entry point"
            )
        }
    }

    @Test func packageUsesImportableLabModulesAndExplicitReplayProducts() throws {
        let manifest = try String(
            contentsOf: try Self.packageRoot().appending(path: "Package.swift"),
            encoding: .utf8
        )

        for module in Self.replayProducts {
            #expect(
                manifest.contains(".executable(name: \"\(module)\", targets: [\"\(module)Runner\"])")
            )
            #expect(manifest.contains(".target(\n            name: \"\(module)\","))
            #expect(!manifest.contains(".executableTarget(\n            name: \"\(module)\","))
        }
        #expect(manifest.contains(".target(\n            name: \"AskiCLI\","))
        #expect(
            manifest.contains(".executable(name: \"aski\", targets: [\"AskiCLIRunner\"])")
        )
    }

    @Test func canonicalTreeGeneratesBashZshAndFishCompletions() throws {
        let root = try Self.packageRoot()
        let executable = try Self.builtExecutable(named: "aski", root: root)

        for shell in ["bash", "zsh", "fish"] {
            let result = try Self.run(executable, arguments: ["--generate-completion-script", shell])
            #expect(result.status == 0, "\(shell) completion generation failed: \(result.output)")
            #expect(!result.output.isEmpty, "\(shell) completion generation was empty")
            for lab in Self.labNames {
                #expect(result.output.contains(lab), "\(shell) completions omitted \(lab)")
            }
        }
    }

    private static func commandNames(_ commands: [ParsableCommand.Type]) -> [String] {
        commands.map { $0.configuration.commandName ?? String(describing: $0) }
    }

    private static func builtExecutable(named name: String, root: URL) throws -> URL {
        let url = root.appending(path: ".build/debug/\(name)")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        return url
    }

    private static func run(_ executable: URL, arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private static func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appending(path: "Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
