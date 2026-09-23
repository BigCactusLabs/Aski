import Foundation
import CoreText
@_spi(AskiResearch) import Aski

/// Generates one Resources/ShapeData/<name>.bin per built-in set.
/// Run from the package root:
///   `swift run BuildStandardVectors`                 — regenerates all sets
///   `swift run BuildStandardVectors --charset NAME`  — regenerates only NAME
///   `swift run BuildStandardVectors --audit --output-dir DIR [--charset NAME]`
/// (The output paths are resolved relative to the current working directory.)

@main
struct BuildStandardVectors {
    struct BuiltInSetSpec { let name: String; let characters: [Character] }

    enum Invocation: Equatable {
        case regenerate(charset: String?)
        case audit(outputDirectory: String, charset: String?)
    }

    enum ArgumentError: Error, Equatable {
        case invalidArguments
        case missingOutputDirectory
    }

    static let allSets: [BuiltInSetSpec] = [
        BuiltInSetSpec(
            name: "standard",
            characters: Array(
                " !\"#$%&'()*+,-./0123456789:;<=>?@" + "ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`" + "abcdefghijklmnopqrstuvwxyz{|}~"
            )),
        BuiltInSetSpec(name: "minimal", characters: Array(" .:-=+*#%@")),
        BuiltInSetSpec(name: "blocks", characters: Array(" ░▒▓█▄▀■")),
        BuiltInSetSpec(name: "dots", characters: Array(" .·•∙◦○●")),
        BuiltInSetSpec(name: "lines", characters: Array(" ─│┌┐└┘├┤┬┴┼")),
        BuiltInSetSpec(name: "diagonal", characters: Array(" /\\X")),
        BuiltInSetSpec(name: "cross", characters: Array(" +x*†")),
        BuiltInSetSpec(name: "diamond", characters: Array(" ◇◈◆")),
        BuiltInSetSpec(name: "mixed", characters: Array(" .·•/\\+x─│◇■")),
        BuiltInSetSpec(name: "braille", characters: (0x2800...0x28FF).map { Character(UnicodeScalar($0)!) }),
    ]

    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let invocation: Invocation
        do {
            invocation = try parseArguments(args)
        } catch {
            FileHandle.standardError.write(
                Data("Usage: BuildStandardVectors [--charset NAME] | --audit --output-dir DIR [--charset NAME]\n".utf8))
            exit(64)
        }

        let filter: String?
        switch invocation {
        case .regenerate(let charset), .audit(_, let charset): filter = charset
        }

        let setsToBuild =
            filter.map { name in
                allSets.filter { $0.name == name }
            } ?? allSets

        guard !setsToBuild.isEmpty else {
            FileHandle.standardError.write(Data("Unknown charset name: \(filter ?? "")\n".utf8))
            exit(64)
        }

        let font = CTFontCreateWithName("Courier" as CFString, 32, nil)

        switch invocation {
        case .regenerate:
            for set in setsToBuild {
                try writeSingleCharsetBin(spec: set, font: font)
            }
        case .audit(let outputDirectory, _):
            let result = try VectorDriftAudit.run(
                root: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                outputDirectory: URL(fileURLWithPath: outputDirectory),
                specs: setsToBuild,
                font: font)
            print(result.consoleSummary)
            if result.triggerFired { exit(1) }
        }
    }

    static func parseArguments(_ arguments: [String]) throws -> Invocation {
        var audit = false
        var outputDirectory: String?
        var charset: String?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--audit":
                guard !audit else { throw ArgumentError.invalidArguments }
                audit = true
                index += 1
            case "--output-dir":
                guard outputDirectory == nil, index + 1 < arguments.count else {
                    throw ArgumentError.missingOutputDirectory
                }
                outputDirectory = arguments[index + 1]
                index += 2
            case "--charset":
                guard charset == nil, index + 1 < arguments.count else {
                    throw ArgumentError.invalidArguments
                }
                charset = arguments[index + 1]
                index += 2
            default:
                throw ArgumentError.invalidArguments
            }
        }
        if audit {
            guard let outputDirectory else { throw ArgumentError.missingOutputDirectory }
            return .audit(outputDirectory: outputDirectory, charset: charset)
        }
        guard outputDirectory == nil else { throw ArgumentError.invalidArguments }
        return .regenerate(charset: charset)
    }

    // Per-file binary layout (v3; each file holds exactly one set so set_count = 1):
    //   u32 magic = 0xA5C11E01
    //   u32 version = 3
    //   u32 set_count = 1
    //   u32 name_length
    //   [name bytes utf8]
    //   u32 char_count
    //   u32 dim (= 60)
    //   [char_count × u32 unicode scalar]
    //   [char_count × f32 brightness]            (normalized: densest glyph = 1.0)
    //   [char_count × 15 × (f32,f32,f32,f32) shape lanes]
    //   [char_count × f32 raw density]            (absolute ink coverage, v2+)
    //     The raw block shares the brightness sort permutation, but is sorted
    //     only up to brightness-quantization ties (distinct raws can normalize
    //     to the same brightness float → one-ulp inversions, e.g. braille).
    //     Consumers index by glyph; only `brightness` is binary-searchable.
    //   [char_count × 8 × f32 orientation histogram]   (v3+)
    //   [char_count × f32 radial peak]                  (v3+)
    //     Per-glyph structure channels at the fixed footprint, sharing the same
    //     brightness sort permutation as the lanes/raw-density blocks.
    static func generateSingleCharsetBin(spec: BuiltInSetSpec, font: CTFont) -> Data {
        let lanesPerChar = RasterizedCharacterSet.lanesPerCharacter

        let normalizedBrightness: [Float]
        let rawDensity: [Float]
        let allLanes: [SIMD4<Float>]
        let allOrientationHistograms: [Float]
        let allRadialPeaks: [Float]
        let footprint = LegacyShapeChannels.footprint
        if spec.name == "braille" {
            let rasterSize = 64
            var brightness: [Float] = []
            var lanes: [SIMD4<Float>] = []
            var hists: [Float] = []
            var peaks: [Float] = []
            for ch in spec.characters {
                let cp = ch.unicodeScalars.first!.value
                let pixels = BrailleRasterizer.rasterize(codepoint: cp, size: rasterSize)
                brightness.append(rasterPixelDensity(pixels))
                let desc = ShapeContext.histogram60(pixels, width: rasterSize, height: rasterSize)
                for i in stride(from: 0, to: 60, by: 4) {
                    lanes.append(SIMD4<Float>(desc[i], desc[i + 1], desc[i + 2], desc[i + 3]))
                }
                // Structure channels: rasterize braille natively at the footprint
                // via its OWN rasterizer (mirrors the 60D lane generation above).
                let channelPixels = BrailleRasterizer.rasterize(codepoint: cp, size: footprint)
                hists.append(
                    contentsOf: LegacyShapeChannels.orientationHistogram(
                        channelPixels, width: footprint, height: footprint))
                peaks.append(
                    LegacyShapeChannels.radialPeak(
                        channelPixels, width: footprint, height: footprint))
            }
            rawDensity = brightness
            let maxRaw = brightness.max() ?? 1
            normalizedBrightness = maxRaw > 0 ? brightness.map { $0 / maxRaw } : brightness
            allLanes = lanes
            allOrientationHistograms = hists
            allRadialPeaks = peaks
        } else {
            let rasterized = RasterizedCharacterSet(characters: spec.characters, font: font)
            normalizedBrightness = rasterized.brightnessValues
            rawDensity = rasterized.rawDensityValues
            allLanes = rasterized.shapeVectorLanes
            let channelFont = CTFontCreateCopyWithAttributes(font, CGFloat(footprint), nil, nil)
            var histograms: [Float] = []
            var peaks: [Float] = []
            for character in spec.characters {
                let pixels = LegacyShapeChannels.rasterize(
                    character, font: channelFont, size: footprint)
                histograms.append(
                    contentsOf: LegacyShapeChannels.orientationHistogram(
                        pixels, width: footprint, height: footprint))
                peaks.append(
                    LegacyShapeChannels.radialPeak(
                        pixels, width: footprint, height: footprint))
            }
            allOrientationHistograms = histograms
            allRadialPeaks = peaks
        }

        // Sort by ascending brightness so the .bin presents characters as a density ramp.
        // Matches the parent project's CHARS_BY_DENSITY convention; downstream renderers
        // can binary-search by brightness without an extra index.
        let indices = normalizedBrightness.indices.sorted { normalizedBrightness[$0] < normalizedBrightness[$1] }
        let sortedChars = indices.map { spec.characters[$0] }
        let sortedBrightness = indices.map { normalizedBrightness[$0] }
        let sortedRawDensity = indices.map { rawDensity[$0] }
        let sortedLanes = indices.flatMap { i in
            (0..<lanesPerChar).map { allLanes[i * lanesPerChar + $0] }
        }
        let sortedOrientationHistograms = indices.flatMap { i in
            (0..<8).map { allOrientationHistograms[i * 8 + $0] }
        }
        let sortedRadialPeaks = indices.map { allRadialPeaks[$0] }

        var data = Data()
        data.append(u32: 0xA5C11E01)
        data.append(u32: 3)  // version
        data.append(u32: 1)  // set_count

        let nameBytes = spec.name.data(using: .utf8)!
        data.append(u32: UInt32(nameBytes.count))
        data.append(nameBytes)
        data.append(u32: UInt32(sortedChars.count))
        data.append(u32: UInt32(RasterizedCharacterSet.shapeVectorDimension))

        for ch in sortedChars {
            precondition(
                ch.unicodeScalars.count == 1,
                "BuildStandardVectors: character '\(ch)' is not a single Unicode scalar; binary format only supports single-scalar characters.")
            data.append(u32: ch.unicodeScalars.first!.value)
        }
        for b in sortedBrightness {
            data.append(f32: b)
        }
        for lane in sortedLanes {
            data.append(f32: lane.x)
            data.append(f32: lane.y)
            data.append(f32: lane.z)
            data.append(f32: lane.w)
        }
        for r in sortedRawDensity {
            data.append(f32: r)
        }
        for h in sortedOrientationHistograms {
            data.append(f32: h)
        }
        for p in sortedRadialPeaks {
            data.append(f32: p)
        }

        return data
    }

    private static func writeSingleCharsetBin(spec: BuiltInSetSpec, font: CTFont) throws {
        let data = generateSingleCharsetBin(spec: spec, font: font)
        let outURL = URL(fileURLWithPath: "Sources/Aski/Resources/ShapeData/\(spec.name).bin")
        try data.write(to: outURL)
        print("Wrote \(data.count) bytes to \(outURL.path)")
    }

    private static func rasterPixelDensity(_ pixels: [Float]) -> Float {
        let sum = pixels.reduce(0, +)
        return sum / Float(pixels.count)
    }

}

extension Data {
    mutating func append(u32 v: UInt32) {
        var x = v.littleEndian
        Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) }
    }
    mutating func append(f32 v: Float) {
        var x = v.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) }
    }
}
