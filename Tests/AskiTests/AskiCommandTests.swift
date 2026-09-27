import ArgumentParser
import Foundation
import Testing
@testable import AskiCLI
import AskiToolSupport

@Suite struct AskiCommandTests {
    @Test func helpIdentifiesTheProductAndListsRender() {
        let help = AskiCommand.helpMessage()
        #expect(help.contains("aski"))
        #expect(help.contains("render"))
    }

    @Test func explicitRenderSubcommandParsesCurrentWorkflow() throws {
        let parsed = try AskiCommand.parseAsRoot([
            "render", "input.jpg", "--columns", "120", "--charset", "blocks", "--write-manifest", "render.json",
        ])
        let command = try #require(parsed as? AskiRenderCommand)
        #expect(command.arguments.inputPath == "input.jpg")
        #expect(command.arguments.columns == 120)
        #expect(command.arguments.charset == .blocks)
        #expect(command.writeManifest == "render.json")
        #expect(command.arguments.algorithm == .logPolar)
        #expect(command.arguments.coverage == 0)
        #expect(command.arguments.palette == .fullColor)
    }

    @Test func renderParsesConversionChoicesAndCoverageBounds() throws {
        for value in ["0", "0.5", "1"] {
            let command = try AskiRenderCommand.parse([
                "input.jpg", "--algorithm", "dotMatrix", "--coverage", value,
                "--palette", "monochrome",
            ])
            #expect(command.arguments.algorithm == .dotMatrix)
            #expect(command.arguments.coverage == Float(value))
            #expect(command.arguments.palette == .monochrome)
        }

        // Coverage is accepted for logPolar even though that matcher ignores it.
        let logPolar = try AskiRenderCommand.parse(["input.jpg", "--coverage", "1"])
        #expect(logPolar.arguments.coverage == 1)

        for value in ["-0.01", "1.01", "nan"] {
            do {
                _ = try AskiRenderCommand.parse(["input.jpg", "--coverage=\(value)"])
                Issue.record("coverage \(value) parsed without error")
            } catch {
                #expect(AskiRenderCommand.exitCode(for: error).rawValue == DemoExitCode.usage.rawValue)
                #expect(String(describing: error).contains("coverage must be finite and in 0...1"))
            }
        }

        for option in ["--algorithm", "--palette"] {
            #expect(throws: (any Error).self) {
                try AskiRenderCommand.parse(["input.jpg", option, "unknown"])
            }
        }
    }

    @Test func legacyCompatibilityWrapperDoesNotParseManifestOption() {
        #expect(throws: (any Error).self) {
            try AskiDemoCommand.parse(["input.jpg", "--write-manifest", "render.json"])
        }
    }

    @Test func omittedSubcommandRoutesToRenderForCompatibility() throws {
        let parsed = try AskiCommand.parseAsRoot([
            "input.jpg", "--render-png", "out.png", "--no-preserve-aspect",
        ])
        let command = try #require(parsed as? AskiRenderCommand)
        #expect(command.arguments.inputPath == "input.jpg")
        #expect(command.arguments.renderPng == "out.png")
        #expect(command.arguments.preserveAspect == false)
    }

    @Test func packagePublishesLowercaseExecutableProduct() throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Package.swift")
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        #expect(manifest.contains(#".executable(name: "aski", targets: ["AskiCLIRunner"])"#))
    }
}
