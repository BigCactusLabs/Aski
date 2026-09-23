import Aski
import AskiToolSupport
import CoreGraphics
import Foundation
import simd

/// The A/B run engine: renders one portrait across the charset × column
/// candidate matrix through the draft Vesper preset, writing labeled candidate
/// PNGs + a contact sheet + a descriptive manifest for human adjudication.
public enum PresetLabCLI {
    public static func run(
        arguments: PresetLabArguments,
        standardOutput: (String) -> Void = { print($0, terminator: "") },
        standardError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
        date: String = PresetLabCLI.todayUTC()
    ) -> LabExitCode {
        guard let inkComponents = HexColor.components(arguments.inkHex) else {
            standardError("error: invalid --ink '\(arguments.inkHex)' (expected #RRGGBB)\n")
            return .usage
        }
        guard let accentComponents = HexColor.components(arguments.accentHex) else {
            standardError("error: invalid --accent '\(arguments.accentHex)' (expected #RRGGBB)\n")
            return .usage
        }

        let preset = DraftVesperPreset(
            ink: PaletteColor(inkComponents, colorSpace: .sRGB),
            accent: PaletteColor(accentComponents, colorSpace: .displayP3),
            contrast: arguments.contrast,
            colorSpace: .displayP3,
            oversample: 2,
            fontSize: CGFloat(arguments.fontSize),
            scale: CGFloat(arguments.scale)
        )

        let image: CGImage
        do {
            image = try DemoImageIO.loadImage(at: arguments.inputPath)
        } catch {
            standardError("error: \(error)\n")
            return .ioError
        }

        let outputURL = URL(fileURLWithPath: arguments.outputDirectory)
        do {
            try FileManager.default.createDirectory(
                at: outputURL, withIntermediateDirectories: true)
        } catch {
            standardError("error: cannot create output directory '\(outputURL.path)': \(error)\n")
            return .ioError
        }

        let candidates = PresetABMatrix.expand(
            charsets: arguments.charsets, columnCounts: arguments.columnCounts)
        let backgroundColor = arguments.background.cgColor
        let inkColor = CGColor(
            red: CGFloat(inkComponents.x), green: CGFloat(inkComponents.y),
            blue: CGFloat(inkComponents.z), alpha: 1)

        var sheetItems: [ContactSheet.Item] = []
        var manifestCandidates: [CandidateRecord] = []
        do {
            for candidate in candidates {
                let converter = preset.makeConverter(charset: candidate.charset)
                let grid = converter.convert(image, columns: candidate.columns)
                let rendered = grid.renderImage(
                    font: preset.font,
                    backgroundColor: backgroundColor,
                    scale: preset.scale,
                    preserveSourceAspect: true
                )
                let filename = "candidate_\(candidate.slug).png"
                try DemoImageIO.writePNG(
                    rendered, to: outputURL.appendingPathComponent(filename).path)

                let stats = CandidateStats.from(grid: grid)
                sheetItems.append(
                    ContactSheet.Item(
                        label:
                            "\(candidate.charset.rawValue) · \(candidate.columns) col · \(stats.distinctGlyphs) glyphs",
                        image: rendered))
                manifestCandidates.append(
                    CandidateRecord(
                        slug: candidate.slug,
                        charset: candidate.charset.rawValue,
                        columns: candidate.columns,
                        gridColumns: stats.columns,
                        gridRows: stats.rows,
                        cellCount: stats.cellCount,
                        distinctGlyphs: stats.distinctGlyphs,
                        png: filename))
            }
        } catch {
            standardError("error: \(error)\n")
            return .ioError
        }

        // Contact sheet: one row per charset ⇒ columns = distinct column counts.
        var uniqueColumns: [Int] = []
        for value in arguments.columnCounts where !uniqueColumns.contains(value) {
            uniqueColumns.append(value)
        }
        var contactSheetFile: String?
        if let sheet = ContactSheet.compose(
            items: sheetItems,
            columns: max(1, uniqueColumns.count),
            background: backgroundColor,
            ink: inkColor)
        {
            let filename = "contact-sheet.png"
            do {
                try DemoImageIO.writePNG(sheet, to: outputURL.appendingPathComponent(filename).path)
                contactSheetFile = filename
            } catch {
                standardError("error: \(error)\n")
                return .ioError
            }
        }

        let manifest = PresetLabManifest(
            schemaVersion: "1",
            runner: "AskiPresetLab",
            date: date,
            askiGitSHA: GitSHA.resolve(override: arguments.gitShaOverride),
            command: commandLine(arguments),
            preset: PresetRecord(
                inkHex: arguments.inkHex,
                accentHex: arguments.accentHex,
                backgroundHex: hexString(arguments.background),
                contrast: arguments.contrast,
                colorSpace: "displayP3",
                tileShape: "wide",
                preserveSourceAspect: true,
                fontSize: arguments.fontSize,
                scale: arguments.scale,
                lockedResearchKnobs: "all zero (ASTSK-7/29/31/35/41/42/43/45)"),
            contactSheet: contactSheetFile,
            candidates: manifestCandidates)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            try data.write(to: outputURL.appendingPathComponent("manifest.json"))
        } catch {
            standardError("error: cannot write manifest.json: \(error)\n")
            return .ioError
        }

        standardOutput(
            "wrote \(candidates.count) candidate renders + contact-sheet.png + manifest.json to \(outputURL.path)\n"
        )
        standardOutput(
            "advisory: stats are descriptive only (grid dims, glyph diversity). Pick by EYE — legibility of the face at phone scale beats any metric.\n"
        )
        return .success
    }

    public static func todayUTC() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func hexString(_ color: BackgroundColor) -> String {
        func channel(_ value: Double) -> String {
            String(format: "%02X", max(0, min(255, Int((value * 255).rounded()))))
        }
        return "#\(channel(color.red))\(channel(color.green))\(channel(color.blue))"
    }

    private static func commandLine(_ arguments: PresetLabArguments) -> String {
        var parts = [
            "swift run AskiPresetLab ab",
            "--input \(arguments.inputPath)",
            "--output-dir \(arguments.outputDirectory)",
            "--charset \(arguments.charsets.map(\.rawValue).joined(separator: " "))",
            "--columns \(arguments.columnCounts.map(String.init).joined(separator: " "))",
        ]
        if let gitShaOverride = arguments.gitShaOverride {
            parts.append("--aski-git-sha \(gitShaOverride)")
        }
        return parts.joined(separator: " ")
    }
}

private struct PresetLabManifest: Codable {
    let schemaVersion: String
    let runner: String
    let date: String
    let askiGitSHA: String
    let command: String
    let preset: PresetRecord
    let contactSheet: String?
    let candidates: [CandidateRecord]
}

private struct PresetRecord: Codable {
    let inkHex: String
    let accentHex: String
    let backgroundHex: String
    let contrast: Float
    let colorSpace: String
    let tileShape: String
    let preserveSourceAspect: Bool
    let fontSize: Double
    let scale: Double
    let lockedResearchKnobs: String
}

private struct CandidateRecord: Codable {
    let slug: String
    let charset: String
    let columns: Int
    let gridColumns: Int
    let gridRows: Int
    let cellCount: Int
    let distinctGlyphs: Int
    let png: String
}
