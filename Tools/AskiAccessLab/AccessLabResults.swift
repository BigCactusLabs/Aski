import Foundation

public enum AccessLabResultError: Error, CustomStringConvertible {
    case unsupportedManifestScalar(String)

    public var description: String {
        switch self {
        case .unsupportedManifestScalar(let value):
            "result manifest metadata contains an unsupported control character: \(value.debugDescription)"
        }
    }
}

public enum AccessLabResults {
    public static let csvHeader = [
        "schema_version", "command", "aski_git_sha", "sample_id",
        "comparison_role", "surface", "palette_id", "candidate_id",
        "fixture_id", "deficiency", "severity", "model_id",
        "sample_a", "sample_b", "source_a_hex", "source_b_hex",
        "simulated_a_hex", "simulated_b_hex", "wcag_contrast",
        "oklab_delta", "brightness_delta", "confusion_flag",
        "luminance_threshold_met",
    ]

    public static func validatedManifestMetadata(gitSHA: String, command: String) throws {
        _ = try yamlDoubleQuotedScalar(gitSHA)
        _ = try yamlDoubleQuotedScalar(command)
    }

    public static func writeCSV(rows: [AccessScoreRow], outputDirectory: URL) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let csv = ([csvHeader.joined(separator: ",")] + rows.map(csvLine)).joined(separator: "\n") + "\n"
        try csv.write(
            to: outputDirectory.appendingPathComponent("accessibility.csv"),
            atomically: true,
            encoding: .utf8
        )
    }

    public static func csvLine(_ row: AccessScoreRow) -> String {
        [
            row.schemaVersion,
            row.command,
            row.askiGitSHA,
            row.sampleID,
            row.comparisonRole,
            row.surface,
            row.paletteID,
            row.candidateID,
            row.fixtureID,
            row.deficiency,
            row.severity,
            row.modelID,
            row.sampleA,
            row.sampleB,
            row.sourceAHex,
            row.sourceBHex,
            row.simulatedAHex,
            row.simulatedBHex,
            String(format: "%.6f", row.wcagContrast),
            String(format: "%.6f", row.oklabDelta),
            String(format: "%.6f", row.brightnessDelta),
            row.confusionFlag ? "true" : "false",
            row.luminanceThresholdMet ? "true" : "false",
        ].map(csvField).joined(separator: ",")
    }

    public static func writeManifest(
        outputDirectory: URL,
        date: String,
        gitSHA: String,
        command: String,
        rows: [AccessScoreRow]
    ) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let summary = summarySentence(rows: rows)
        try validatedManifestMetadata(gitSHA: gitSHA, command: command)
        let yaml = """
            ---
            schema_version: "1"
            date: \(try yamlDoubleQuotedScalar(date))
            aski_git_sha: \(try yamlDoubleQuotedScalar(gitSHA))
            provenance: [\(try yamlDoubleQuotedScalar("AskiAccessLab audit"))]
            outputs: [\(try yamlDoubleQuotedScalar("accessibility.csv"))]
            runner: \(try yamlDoubleQuotedScalar("AskiAccessLab"))
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

    public static func summarySentence(rows: [AccessScoreRow]) -> String {
        let confusionCount = rows.filter(\.confusionFlag).count
        let luminanceMisses = rows.filter { !$0.luminanceThresholdMet }.count
        return
            "AskiAccessLab scored \(rows.count) palette and rendered-grid color comparison rows across severity 1.0 dichromacy models; \(confusionCount) row(s) fell below OKLab delta \(String(format: "%.2f", AccessScoring.minimumOKLabDelta)) and \(luminanceMisses) row(s) fell below WCAG contrast \(String(format: "%.1f", AccessScoring.minimumWCAGContrast))."
    }

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
                    throw AccessLabResultError.unsupportedManifestScalar(value)
                }
                escaped.unicodeScalars.append(scalar)
            }
        }
        escaped += "\""
        return escaped
    }
}
