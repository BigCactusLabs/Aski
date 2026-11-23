import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import Testing
@_spi(AskiResearch) @testable import Aski

@Suite(.serialized) struct ASKI94FallbackParityTests {
    private static let outputVariable = "ASKI94_PARITY_OUTPUT"

    @Test(.enabled(if: ProcessInfo.processInfo.environment[ASKI94FallbackParityTests.outputVariable] != nil))
    func exportNativeFallbackRasters() throws {
        let path = try #require(ProcessInfo.processInfo.environment[Self.outputVariable])
        try #require(path.hasPrefix("/"), "Capture needs an absolute output path")
        let output = URL(fileURLWithPath: path, isDirectory: true)
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Scripts/research/aski94-2026-11-15/parity-cases.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        let cases = try manifest.cases()
        let sources = try [
            "partialSRGB": Self.makeSource(spaceName: CGColorSpace.sRGB, opaque: false),
            "opaqueSRGB": Self.makeSource(spaceName: CGColorSpace.sRGB, opaque: true),
            "partialP3": Self.makeSource(spaceName: CGColorSpace.displayP3, opaque: false),
        ]
        let result = output.path.withCString { mkdir($0, 0o700) }
        try #require(result == 0, "Capture requires a new output directory with an existing parent")

        let font = ASCIIFont.system(size: 20)
        var records: [[String: Any]] = []
        for settings in cases {
            let id = try manifest.axes.map { key in try #require(settings[key]) }.joined(separator: "-")
            let image = try Self.render(settings, sources: sources, font: font)
            if settings["shape"] == "empty" {
                try #require(image.width == 1 && image.height == 1, "Expected a 1×1 sentinel for \(id)")
            } else {
                try #require(image.width > 1 && image.height > 1, "Unexpected sentinel for \(id)")
                if settings["route"] == "width97" || settings["route"] == "direct97" {
                    try #require(image.width == 97)
                }
            }
            var metadata = try Self.writeRaster(image, file: output.appendingPathComponent(id + ".bin"))
            metadata["id"] = id
            records.append(metadata)
        }

        let capture: [String: Any] = [
            "schemaVersion": 1,
            "manifestSHA256": Self.hash(manifestData),
            "cases": records,
        ]
        try JSONSerialization.data(withJSONObject: capture, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("metadata.json"), options: .atomic)
    }

    private struct Manifest: Decodable {
        let schemaVersion: Int
        let axes: [String]
        let profiles: [[String: [String]]]

        func cases() throws -> [[String: String]] {
            try #require(schemaVersion == 1)
            try #require(axes == ["shape", "sizing", "edges", "gamut", "composition", "ground", "route", "aspect", "source", "canvas"])
            try #require(!profiles.isEmpty)
            var seen: Set<String> = []
            var cases: [[String: String]] = []
            for profile in profiles {
                try #require(Set(profile.keys) == Set(axes))
                var combinations: [[String: String]] = [[:]]
                for key in axes {
                    let options = try #require(profile[key])
                    try #require(!options.isEmpty && Set(options).count == options.count)
                    combinations = combinations.flatMap { previous in
                        options.map { option in
                            var settings = previous
                            settings[key] = option
                            return settings
                        }
                    }
                }
                for settings in combinations {
                    let id = try axes.map { key in try #require(settings[key]) }.joined(separator: "-")
                    let inserted = seen.insert(id).inserted
                    try #require(inserted, "Duplicate manifest case: \(id)")
                    cases.append(settings)
                }
            }
            return cases
        }
    }

    private static func render(_ settings: [String: String], sources: [String: CGImage], font: ASCIIFont) throws -> CGImage {
        let lengths = try #require(["rect": [5, 5, 5, 5, 5], "ragged": [0, 2, 5, 0, 1], "single": [0, 1, 0], "empty": [0, 0, 0]][settings["shape"] ?? ""])
        let sizing = try #require(["fill": BackgroundSizing.fill, "fit": .fit, "stretch": .stretch][settings["sizing"] ?? ""])
        let hardEdges = try #require(["hard": true, "soft": false][settings["edges"] ?? ""] as Bool?)
        let gamut = try #require(["sRGB": RenderColorSpace.sRGB, "p3": .displayP3][settings["gamut"] ?? ""])
        let composition = try #require(["encoded": RenderCompositionPolicy.encodedDisplay8Bit, "linear": .extendedLinearPerGamut][settings["composition"] ?? ""])
        let ground = try #require(["none": -1.0, "clear": 0.0, "partial": 0.45, "opaque": 1.0][settings["ground"] ?? ""])
        let backgroundAlpha = try #require(["clear": 0.0, "partial": 0.35, "opaque": 1.0][settings["canvas"] ?? ""])
        let aspect = try #require(["legacy": false, "source": true][settings["aspect"] ?? ""] as Bool?)
        let source = try #require(sources[settings["source"] ?? ""])
        let background = CGColor(srgbRed: 0.12, green: 0.27, blue: 0.48, alpha: backgroundAlpha)
        let coverage: [Float] = [0, 0.25, 0.75, 1]
        let cells = lengths.enumerated().map { row, count in
            (0..<count).map { column in
                ASCIICell(
                    character: (row + column).isMultiple(of: 2) ? " " : "#",
                    displayColor: SIMD3<Float>(0.2, 0.5, 0.8), alpha: 0.8,
                    brightness: 0.5, coverage: coverage[(row + column) % 4])
            }
        }
        let grid = ASCIIGrid(
            cells: cells, colorSpace: gamut, composition: composition,
            maskFallback: .originalImage(source, sizing: sizing),
            maskGroundColor: ground < 0 ? nil : CGColor(gray: 0.25, alpha: ground),
            maskUsesHardEdges: hardEdges)
        switch settings["route"] {
        case "scale1":
            return grid.renderImage(font: font, backgroundColor: background, scale: 1, preserveSourceAspect: aspect)
        case "scale125":
            return grid.renderImage(font: font, backgroundColor: background, scale: 1.25, preserveSourceAspect: aspect)
        case "width97":
            return grid.renderImage(font: font, backgroundColor: background, targetPixelWidth: 97, preserveSourceAspect: aspect)
        case "direct97":
            return grid.renderImage(font: font, backgroundColor: background, targetPixelWidth: 97, preserveSourceAspect: aspect, resample: .direct)
        default:
            throw CocoaError(.coderInvalidValue)
        }
    }

    private static func makeSource(spaceName: CFString, opaque: Bool) throws -> CGImage {
        let space = try #require(CGColorSpace(name: spaceName))
        let context = try #require(
            CGContext(
                data: nil, width: 17, height: 11, bitsPerComponent: 8, bytesPerRow: 68,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let bands: [(CGRect, [CGFloat])] = [
            (CGRect(x: 0, y: 0, width: 3, height: 11), [0.10, 0.85, 0.20, 0]),
            (CGRect(x: 3, y: 0, width: 5, height: 11), [0.80, 0.10, 0.50, 0.33]),
            (CGRect(x: 8, y: 0, width: 9, height: 4), [0.15, 0.25, 0.95, 0.67]),
            (CGRect(x: 8, y: 4, width: 9, height: 7), [1.00, 0.60, 0.10, 1]),
        ]
        for (rect, sourceComponents) in bands {
            var components = sourceComponents
            if opaque { components[3] = 1 }
            context.setFillColor(try #require(CGColor(colorSpace: space, components: components)))
            context.fill(rect)
        }
        return try #require(context.makeImage())
    }

    private static func writeRaster(_ image: CGImage, file: URL) throws -> [String: Any] {
        try #require(image.width > 0 && image.height > 0 && image.bitsPerComponent == 8 && image.bitsPerPixel == 32)
        let activeBytes = image.width * 4
        try #require(image.bytesPerRow >= activeBytes)
        let providerData = try #require(image.dataProvider?.data)
        try #require(CFDataGetLength(providerData) >= image.bytesPerRow * image.height)
        let base = try #require(CFDataGetBytePtr(providerData))
        var pixels = Data(capacity: activeBytes * image.height)
        for y in 0..<image.height {
            pixels.append(base + y * image.bytesPerRow, count: activeBytes)
        }
        try pixels.write(to: file)

        let space = try #require(image.colorSpace)
        let spaceName = space.name.map { $0 as String }
        let icc = space.copyICCData().map { ($0 as Data).base64EncodedString() }
        return [
            "width": image.width, "height": image.height, "bytesPerRow": image.bytesPerRow,
            "bitsPerComponent": image.bitsPerComponent, "bitsPerPixel": image.bitsPerPixel,
            "alphaInfo": image.alphaInfo.rawValue, "bitmapInfo": image.bitmapInfo.rawValue,
            "renderingIntent": image.renderingIntent.rawValue, "interpolate": image.shouldInterpolate,
            "colorSpaceModel": space.model.rawValue, "colorSpaceComponents": space.numberOfComponents,
            "colorSpaceName": (spaceName as Any?) ?? NSNull(), "iccBase64": (icc as Any?) ?? NSNull(),
            "activeSHA256": hash(pixels),
        ]
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
