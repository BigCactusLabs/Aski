import ArgumentParser
import AskiCLI
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AskiToolSupport

@Suite struct AskiInspectCommandTests {
    @Test func rootHelpListsInspect() {
        #expect(AskiCommand.helpMessage().contains("inspect"))
    }

    @Test func parsesInspectOptions() throws {
        let parsed = try AskiCommand.parseAsRoot([
            "inspect", "input.png",
            "--columns", "120",
            "--charset", "blocks",
            "--format", "json",
            "--output", "inspection.json",
        ])
        let command = try #require(parsed as? AskiInspectCommand)
        #expect(command.inputPath == "input.png")
        #expect(command.columns == 120)
        #expect(command.charset == .blocks)
        #expect(command.format == .json)
        #expect(command.output == "inspection.json")
    }

    @Test func stableJSONIsDeterministicAndNewlineTerminated() throws {
        let report = AskiInspectionReport(
            toolVersion: "abc123",
            source: .init(
                path: "input.png",
                normalizedPixelWidth: 80,
                normalizedPixelHeight: 40
            ),
            conversion: .init(
                columns: 12,
                rows: 3,
                charset: "blocks",
                totalCells: 36,
                nonWhitespaceCells: 24,
                textUTF8Bytes: 39
            )
        )

        let first = try StableJSON.data(for: report)
        let second = try StableJSON.data(for: report)
        #expect(first == second)
        #expect(first.last == 0x0A)
        #expect(try JSONDecoder().decode(AskiInspectionReport.self, from: first) == report)
    }

    @Test func jsonInspectionReportsTheResolvedConversion() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "input.png")
        try writeFixturePNG(to: input, width: 80, height: 40)

        var stdout = ""
        var stderr = ""
        let command = try AskiInspectCommand.parse([
            input.path, "--columns", "12", "--charset", "blocks", "--format", "json",
        ])
        let status = command.execute(
            standardOutput: { stdout += $0 },
            standardError: { stderr += $0 }
        )

        #expect(status == .success)
        #expect(stderr.isEmpty)
        let report = try JSONDecoder().decode(AskiInspectionReport.self, from: Data(stdout.utf8))
        #expect(report.schemaVersion == 1)
        #expect(report.source.path == input.path)
        #expect(report.source.normalizedPixelWidth > 0)
        #expect(report.source.normalizedPixelHeight > 0)
        #expect(report.conversion.columns == 12)
        #expect(report.conversion.rows > 0)
        #expect(report.conversion.charset == "blocks")
        #expect(report.conversion.totalCells == report.conversion.columns * report.conversion.rows)
        #expect(report.conversion.nonWhitespaceCells >= 0)
        #expect(report.conversion.nonWhitespaceCells <= report.conversion.totalCells)
        #expect(report.conversion.textUTF8Bytes > 0)
    }

    @Test func textInspectionIsHumanReadable() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "input.png")
        try writeFixturePNG(to: input, width: 80, height: 40)

        var stdout = ""
        let command = try AskiInspectCommand.parse([input.path, "--columns", "12"])
        let status = command.execute(standardOutput: { stdout += $0 }, standardError: { _ in })

        #expect(status == .success)
        #expect(stdout.contains("input:"))
        #expect(stdout.contains("normalized pixels:"))
        #expect(stdout.contains("grid:"))
        #expect(stdout.contains("charset: standard"))
        #expect(stdout.hasSuffix("\n"))
    }

    @Test func outputFileSuppressesStdout() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "input.png")
        let output = directory.appending(path: "inspection.json")
        try writeFixturePNG(to: input, width: 80, height: 40)

        var stdout = ""
        let command = try AskiInspectCommand.parse([
            input.path, "--columns", "12", "--format", "json", "--output", output.path,
        ])
        let status = command.execute(standardOutput: { stdout += $0 }, standardError: { _ in })

        #expect(status == .success)
        #expect(stdout.isEmpty)
        let data = try Data(contentsOf: output)
        #expect(data.last == 0x0A)
        #expect(try JSONDecoder().decode(AskiInspectionReport.self, from: data).schemaVersion == 1)
    }

    @Test func missingInputUsesTheEstablishedExitCode() throws {
        var stderr = ""
        let command = try AskiInspectCommand.parse(["/definitely/missing/aski-input.png"])
        let status = command.execute(standardOutput: { _ in }, standardError: { stderr += $0 })

        #expect(status == .inputUnavailable)
        #expect(stderr.contains("could not open input image"))
    }

    @Test func committedSchemaIsDraft202012AndVersionOne() throws {
        let schemaURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "docs/assets/schemas/aski-inspect-v1.schema.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL))
        let schema = try #require(object as? [String: Any])
        #expect(schema["$schema"] as? String == "https://json-schema.org/draft/2020-12/schema")
        let properties = try #require(schema["properties"] as? [String: Any])
        let version = try #require(properties["schemaVersion"] as? [String: Any])
        #expect(version["const"] as? Int == 1)
    }

    @Test func committedSchemaCharsetsMatchSupportedCharsets() throws {
        let schemaURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "docs/assets/schemas/aski-inspect-v1.schema.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL))
        let schema = try #require(object as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        let conversion = try #require(properties["conversion"] as? [String: Any])
        let conversionProperties = try #require(conversion["properties"] as? [String: Any])
        let charset = try #require(conversionProperties["charset"] as? [String: Any])
        let schemaCharsets = try #require(charset["enum"] as? [String])

        #expect(schemaCharsets == Charset.allCases.map(\.rawValue))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AskiInspectCommandTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFixturePNG(to url: URL, width: Int, height: Int) throws {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        for x in 0..<width {
            let t = CGFloat(x) / CGFloat(width - 1)
            context.setFillColor(red: t, green: 0.2, blue: 1 - t, alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }

        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
