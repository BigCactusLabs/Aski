import Foundation

public enum DecolorLabResultError: Error, CustomStringConvertible {
    case unsupportedManifestScalar(String)

    public var description: String {
        switch self {
        case .unsupportedManifestScalar(let value):
            "result manifest metadata contains an unsupported control character: \(value.debugDescription)"
        }
    }
}

public enum DecolorLabResults {
    public static let csvHeader = [
        "schema_version", "command", "aski_git_sha", "fixture_id",
        "palette_id", "row", "col", "character", "ink_fraction",
        "ink_model", "fg_hex", "bg_hex", "perceived_hex", "source_hex",
        "deficiency", "l_fidelity", "chroma_fidelity", "oklab_delta",
    ]

    public static func validatedManifestMetadata(gitSHA: String, command: String) throws {
        _ = try yamlDoubleQuotedScalar(gitSHA)
        _ = try yamlDoubleQuotedScalar(command)
    }

    public static func writeCSV(
        rows: [OracleRow],
        outputDirectory: URL,
        fileName: String = "perceived_fidelity.csv"
    ) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let csv = ([csvHeader.joined(separator: ",")] + rows.map(csvLine)).joined(separator: "\n") + "\n"
        try csv.write(
            to: outputDirectory.appendingPathComponent(fileName),
            atomically: true,
            encoding: .utf8
        )
    }

    public static func csvLine(_ row: OracleRow) -> String {
        [
            row.schemaVersion,
            row.command,
            row.askiGitSHA,
            row.fixtureID,
            row.paletteID,
            String(row.row),
            String(row.col),
            row.character,
            String(format: "%.6f", row.inkFraction),
            row.inkModel,
            row.fgHex,
            row.bgHex,
            row.perceivedHex,
            row.sourceHex,
            row.deficiency,
            String(format: "%.6f", row.lFidelity),
            String(format: "%.6f", row.chromaFidelity),
            String(format: "%.6f", row.oklabDelta),
        ].map(csvField).joined(separator: ",")
    }

    public static func writeManifest(
        outputDirectory: URL,
        date: String,
        gitSHA: String,
        command: String,
        summary: String,
        provenance: String = "AskiDecolorLab evaluate",
        outputs: [String] = ["perceived_fidelity.csv"]
    ) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try validatedManifestMetadata(gitSHA: gitSHA, command: command)
        let outputsList = try outputs.map { try yamlDoubleQuotedScalar($0) }.joined(separator: ", ")
        let yaml = """
            ---
            schema_version: "1"
            date: \(try yamlDoubleQuotedScalar(date))
            aski_git_sha: \(try yamlDoubleQuotedScalar(gitSHA))
            provenance: [\(try yamlDoubleQuotedScalar(provenance))]
            outputs: [\(outputsList)]
            runner: \(try yamlDoubleQuotedScalar("AskiDecolorLab"))
            command: \(try yamlDoubleQuotedScalar(command))
            summary: \(try yamlDoubleQuotedScalar(summary))
            ---

            """
        try yaml.write(
            to: outputDirectory.appendingPathComponent("result.yaml"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// A human-readable summary sentence for the manifest.
    public static func summarySentence(rows: [OracleRow], gateVerdict: String) -> String {
        let total = rows.count
        let paletteIDs = ["monochrome", "ansi16", "fullColor"]
        let paletteMeans = paletteIDs.map { palette -> String in
            let values = rows.filter { $0.paletteID == palette }.map(\.lFidelity)
            guard !values.isEmpty else { return "\(palette) mean_l=n/a" }
            let mean = values.reduce(0, +) / Double(values.count)
            return "\(palette) mean_l=\(String(format: "%.4f", mean))"
        }.joined(separator: ". ")
        return "\(total) rows. \(paletteMeans). Gate: \(gateVerdict)."
    }

    // MARK: - Escaping helpers (mirrored from AccessLabResults)

    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func yamlDoubleQuotedScalar(_ value: String) throws -> String {
        var escaped = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                escaped += "\\\""
            case "\\":
                escaped += "\\\\"
            case "\n":
                escaped += "\\n"
            case "\r":
                escaped += "\\r"
            case "\t":
                escaped += "\\t"
            default:
                guard scalar.value >= 0x20 else {
                    throw DecolorLabResultError.unsupportedManifestScalar(value)
                }
                escaped.unicodeScalars.append(scalar)
            }
        }
        escaped += "\""
        return escaped
    }
}
