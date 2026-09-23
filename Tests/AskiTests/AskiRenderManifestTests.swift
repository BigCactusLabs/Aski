import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AskiToolSupport

@Suite struct AskiRenderManifestTests {
    @Test func equivalentRendersWriteByteIdenticalManifests() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "input.png")
        let manifestURL = directory.appending(path: "render.json")
        try writeFixturePNG(to: input, width: 80, height: 40)

        func renderManifest() throws -> Data {
            var stderr = ""
            let command = try AskiRenderCommand.parse([
                input.path,
                "--columns", "12",
                "--charset", "blocks",
                "--write-manifest", manifestURL.path,
            ])
            let status = command.execute(standardOutput: { _ in }, standardError: { stderr += $0 })
            #expect(status == .success)
            #expect(stderr.isEmpty)
            return try Data(contentsOf: manifestURL)
        }

        let first = try renderManifest()
        let second = try renderManifest()
        #expect(first == second)
        #expect(first.last == 0x0A)

        let manifest = try JSONDecoder().decode(AskiRenderManifest.self, from: first)
        #expect(manifest.schemaVersion == 1)
        #expect(manifest.toolVersion == ToolVersion.current)
        #expect(manifest.command == "render")
        #expect(manifest.source.path == input.path)
        #expect(manifest.source.normalizedPixelWidth == 24)
        #expect(manifest.source.normalizedPixelHeight == 12)
        #expect(manifest.conversion.columns == 12)
        #expect(manifest.conversion.rows > 0)
        #expect(manifest.conversion.charset == "blocks")
    }

    @Test func manifestRecordsStdoutTextArtifactAndTransparentBackground() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "input.png")
        let manifestURL = directory.appending(path: "render.json")
        try writeFixturePNG(to: input, width: 80, height: 40)

        var stdout = ""
        var stderr = ""
        let command = try AskiRenderCommand.parse([
            input.path,
            "--columns", "12",
            "--background", "clear",
            "--write-manifest", manifestURL.path,
        ])
        let status = command.execute(
            standardOutput: { stdout += $0 },
            standardError: { stderr += $0 }
        )

        #expect(status == .success)
        #expect(stderr.isEmpty)
        #expect(stdout.isEmpty == false)

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(AskiRenderManifest.self, from: manifestData)
        #expect(manifest.artifacts.text.destination == "stdout")
        #expect(manifest.artifacts.text.utf8Bytes == Data(stdout.utf8).count)
        #expect(manifest.artifacts.png == nil)
        #expect(manifest.render.backgroundColor == "#00000000")
        #expect(manifest.render.fontSize == 10)
        #expect(manifest.render.preserveSourceAspect)
        #expect(manifest.mask == nil)
        let object = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        #expect(object.keys.contains("mask") == false)
    }

    @Test func manifestRecordsFileTextAndRenderedPNGArtifacts() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "input.png")
        let textOutput = directory.appending(path: "out.txt")
        let pngOutput = directory.appending(path: "out.png")
        let manifestURL = directory.appending(path: "render.json")
        try writeFixturePNG(to: input, width: 80, height: 40)

        var stdout = ""
        var stderr = ""
        let command = try AskiRenderCommand.parse([
            input.path,
            "--columns", "12",
            "--charset", "blocks",
            "--output", textOutput.path,
            "--render-png", pngOutput.path,
            "--font-size", "12",
            "--background", "#112233",
            "--no-preserve-aspect",
            "--write-manifest", manifestURL.path,
        ])
        let status = command.execute(
            standardOutput: { stdout += $0 },
            standardError: { stderr += $0 }
        )

        #expect(status == .success)
        #expect(stdout.isEmpty)
        #expect(stderr.isEmpty)

        let manifest = try JSONDecoder().decode(AskiRenderManifest.self, from: Data(contentsOf: manifestURL))
        let textData = try Data(contentsOf: textOutput)
        #expect(manifest.artifacts.text.destination == textOutput.path)
        #expect(manifest.artifacts.text.utf8Bytes == textData.count)
        let pngArtifact = try #require(manifest.artifacts.png)
        #expect(pngArtifact.path == pngOutput.path)

        let source = try #require(CGImageSourceCreateWithURL(pngOutput as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(pngArtifact.pixelWidth == image.width)
        #expect(pngArtifact.pixelHeight == image.height)
        #expect(manifest.render.backgroundColor == "#112233FF")
        #expect(manifest.render.fontSize == 12)
        #expect(manifest.render.preserveSourceAspect == false)
        #expect(manifest.render.targetPixelWidth == nil)
        #expect(manifest.render.derivedScale == nil)
        #expect(manifest.render.cellAdvancePixels == nil)
        #expect(manifest.render.resampleSpace == nil)
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        let render = try #require(object["render"] as? [String: Any])
        for key in ["targetPixelWidth", "derivedScale", "cellAdvancePixels", "resampleSpace"] {
            #expect(render.keys.contains(key) == false)
        }
    }

    @Test func targetWidthRendersExactPNGAndRecordsWidthSettings() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "input.png")
        let pngOutput = directory.appending(path: "out.png")
        let manifestURL = directory.appending(path: "render.json")
        try writeFixturePNG(to: input, width: 80, height: 40)

        let command = try AskiRenderCommand.parse([
            input.path,
            "--columns", "12",
            "--render-png", pngOutput.path,
            "--width", "97",
            "--write-manifest", manifestURL.path,
        ])
        #expect(command.execute(standardOutput: { _ in }, standardError: { _ in }) == .success)

        let source = try #require(CGImageSourceCreateWithURL(pngOutput as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 97)

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(AskiRenderManifest.self, from: manifestData)
        #expect(manifest.render.targetPixelWidth == 97)
        let derivedScale = try #require(manifest.render.derivedScale)
        #expect(derivedScale == 97.0 / (12.0 * 10.0 * 0.6))
        let cellAdvancePixels = try #require(manifest.render.cellAdvancePixels)
        #expect(cellAdvancePixels == 97.0 / 12.0)
        #expect(manifest.render.resampleSpace == "linear-srgb-area-average-4x")

        let object = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        let render = try #require(object["render"] as? [String: Any])
        for key in ["targetPixelWidth", "derivedScale", "cellAdvancePixels", "resampleSpace"] {
            #expect(render.keys.contains(key))
        }
    }

    @Test func fixtureManifestWithoutWidthKeepsExistingBytes() throws {
        let encoded = try StableJSON.data(for: sampleManifest())
        var fixture = Data(
            """
            {
              "artifacts" : {
                "text" : {
                  "destination" : "stdout",
                  "utf8Bytes" : 39
                }
              },
              "command" : "render",
              "conversion" : {
                "charset" : "blocks",
                "columns" : 12,
                "rows" : 3
              },
              "render" : {
                "backgroundColor" : "#112233FF",
                "fontSize" : 10,
                "preserveSourceAspect" : true
              },
              "schemaVersion" : 1,
              "source" : {
                "normalizedPixelHeight" : 40,
                "normalizedPixelWidth" : 80,
                "path" : "input.png"
              },
              "toolVersion" : "abc123"
            }
            """.utf8
        )
        fixture.append(0x0A)

        #expect(encoded == fixture)
    }

    @Test func manifestRecordsResolvedMaskSettingsWhenMaskIsSupplied() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "input.png")
        let mask = directory.appending(path: "mask.png")
        let png = directory.appending(path: "out.png")
        let manifestURL = directory.appending(path: "render.json")
        try writeFixturePNG(to: input, width: 80, height: 40)
        try writeFixturePNG(to: mask, width: 80, height: 40)

        let command = try AskiRenderCommand.parse([
            input.path,
            "--mask", mask.path,
            "--mask-fallback", "original",
            "--mask-ground", "#080808",
            "--mask-hard-edges",
            "--mask-invert",
            "--render-png", png.path,
            "--write-manifest", manifestURL.path,
        ])
        #expect(command.execute(standardOutput: { _ in }, standardError: { _ in }) == .success)

        let manifest = try JSONDecoder().decode(AskiRenderManifest.self, from: Data(contentsOf: manifestURL))
        let settings = try #require(manifest.mask)
        #expect(settings.path == mask.path)
        #expect(settings.fallback == "original")
        #expect(settings.fallbackSizing == "stretch")
        #expect(settings.fallbackColor == nil)
        #expect(settings.groundColor == "#080808FF")
        #expect(settings.hardEdges)
        #expect(settings.invert)
    }

    @Test func stableJSONWriteAtomicallyReplacesExistingDestination() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "render.json")
        let previous = Data("previous manifest\n".utf8)
        try previous.write(to: destination)

        let previousHandle = try FileHandle(forReadingFrom: destination)
        defer { try? previousHandle.close() }

        let manifest = sampleManifest()
        try StableJSON.write(manifest, to: destination)

        let retainedData = try previousHandle.readToEnd() ?? Data()
        #expect(retainedData == previous)

        let replacement = try Data(contentsOf: destination)
        let replacementManifest = try JSONDecoder().decode(AskiRenderManifest.self, from: replacement)
        #expect(replacement != previous)
        #expect(replacementManifest == manifest)
    }

    @Test func manifestWriteFailurePreservesOutputsAndSuppressesStdout() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "input.png")
        let pngOutput = directory.appending(path: "out.png")
        let previousPNG = Data("previous png\n".utf8)
        try writeFixturePNG(to: input, width: 80, height: 40)
        try previousPNG.write(to: pngOutput)

        var stdout = ""
        var stderr = ""
        let manifestPath = "/dev/null/aski-render-manifest.json"
        let command = try AskiRenderCommand.parse([
            input.path,
            "--render-png", pngOutput.path,
            "--write-manifest", manifestPath,
        ])
        let status = command.execute(
            standardOutput: { stdout += $0 },
            standardError: { stderr += $0 }
        )

        #expect(status == .failure)
        #expect(stdout.isEmpty)
        #expect(stderr.contains("could not write render manifest '\(manifestPath)'"))
        #expect(try Data(contentsOf: pngOutput) == previousPNG)
    }

    @Test func manifestPathCollidingWithAnArtifactPathIsAUsageError() throws {
        for collision in [
            ["input.png", "--output", "art.txt", "--write-manifest", "./art.txt"],
            ["input.png", "--render-png", "art.png", "--write-manifest", "art.png"],
        ] {
            do {
                _ = try AskiRenderCommand.parse(collision)
                Issue.record("collision with \(collision[1]) parsed without error")
            } catch {
                #expect(AskiRenderCommand.exitCode(for: error).rawValue == DemoExitCode.usage.rawValue)
            }
        }
    }

    @Test func committedSchemaIsDraft202012AndVersionOne() throws {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL))
        let schema = try #require(object as? [String: Any])
        #expect(schema["$schema"] as? String == "https://json-schema.org/draft/2020-12/schema")
        let properties = try #require(schema["properties"] as? [String: Any])
        let version = try #require(properties["schemaVersion"] as? [String: Any])
        #expect(version["const"] as? Int == 1)
        #expect(properties["mask"] != nil)
        let required = try #require(schema["required"] as? [String])
        #expect(required.contains("mask") == false)
    }

    @Test func committedSchemaContainsOptionalTargetWidthRenderProperties() throws {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL))
        let schema = try #require(object as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        let render = try #require(properties["render"] as? [String: Any])
        let renderProperties = try #require(render["properties"] as? [String: Any])

        for key in ["targetPixelWidth", "derivedScale", "cellAdvancePixels", "resampleSpace"] {
            #expect(renderProperties.keys.contains(key))
        }

        let targetPixelWidth = try #require(renderProperties["targetPixelWidth"] as? [String: Any])
        #expect(targetPixelWidth["type"] as? String == "integer")
        #expect(targetPixelWidth["minimum"] as? Int == 1)
        let derivedScale = try #require(renderProperties["derivedScale"] as? [String: Any])
        #expect(derivedScale["type"] as? String == "number")
        #expect(derivedScale["exclusiveMinimum"] as? Int == 0)
        let cellAdvancePixels = try #require(renderProperties["cellAdvancePixels"] as? [String: Any])
        #expect(cellAdvancePixels["type"] as? String == "number")
        #expect(cellAdvancePixels["exclusiveMinimum"] as? Int == 0)
        let resampleSpace = try #require(renderProperties["resampleSpace"] as? [String: Any])
        #expect(resampleSpace["type"] as? String == "string")
        #expect(resampleSpace["enum"] as? [String] == ["none", "linear-srgb-area-average-4x"])

        let required = try #require(render["required"] as? [String])
        for key in ["targetPixelWidth", "derivedScale", "cellAdvancePixels", "resampleSpace"] {
            #expect(required.contains(key) == false)
        }
    }

    @Test func committedSchemaCharsetsMatchSupportedCharsets() throws {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL))
        let schema = try #require(object as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        let conversion = try #require(properties["conversion"] as? [String: Any])
        let conversionProperties = try #require(conversion["properties"] as? [String: Any])
        let charset = try #require(conversionProperties["charset"] as? [String: Any])
        let schemaCharsets = try #require(charset["enum"] as? [String])

        #expect(schemaCharsets == Charset.allCases.map(\.rawValue))
    }

    private var schemaURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "docs/assets/schemas/aski-render-manifest-v1.schema.json")
    }

    private func sampleManifest() -> AskiRenderManifest {
        AskiRenderManifest(
            toolVersion: "abc123",
            command: "render",
            source: .init(path: "input.png", normalizedPixelWidth: 80, normalizedPixelHeight: 40),
            conversion: .init(columns: 12, rows: 3, charset: "blocks"),
            render: .init(backgroundColor: "#112233FF", fontSize: 10, preserveSourceAspect: true),
            artifacts: .init(text: .init(destination: "stdout", utf8Bytes: 39), png: nil),
            mask: nil
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AskiRenderManifestTests-\(UUID().uuidString)")
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
