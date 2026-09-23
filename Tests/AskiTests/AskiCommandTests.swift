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
