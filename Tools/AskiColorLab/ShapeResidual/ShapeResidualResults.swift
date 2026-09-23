import Foundation

// MARK: - Manifest writer

enum ShapeResidualResultError: Error, CustomStringConvertible {
    case unsupportedManifestScalar(String)
    var description: String {
        switch self {
        case .unsupportedManifestScalar(let v):
            "result manifest metadata contains an unsupported control character: \(v.debugDescription)"
        }
    }
}

/// Writes `result.yaml` for `shape-residual-map`, mirroring the cross-lab schema
/// other labs emit (AccessLab/DecolorLab). `outputs` enumerates the per-cell CSV,
/// the Spearman summary CSV, and one residual heatmap per battery fixture at the
/// canonical column (caller-computed, so a sweep over any battery lists exactly the
/// files it emits — IndexCheck rejects unlisted files). `datasets` references the
/// committed corpus for natural-pool batteries. `runner` is `"AskiColorLab"`.
enum ShapeResidualResults {
    static func writeManifest(
        outputDirectory: URL,
        date: String,
        gitSHA: String,
        command: String,
        summary: String,
        outputs: [String],
        datasets: [String]
    ) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputsList =
            try outputs
            .map { try yamlDoubleQuotedScalar($0) }
            .joined(separator: ", ")
        // Omit the `datasets` key entirely when empty (a synthetic-only run has no
        // corpus dependency; an empty list would still parse but adds noise).
        let datasetsLine: String
        if datasets.isEmpty {
            datasetsLine = ""
        } else {
            let list = try datasets.map { try yamlDoubleQuotedScalar($0) }.joined(separator: ", ")
            datasetsLine = "datasets: [\(list)]\n"
        }
        let yaml = """
            ---
            schema_version: "1"
            date: \(try yamlDoubleQuotedScalar(date))
            aski_git_sha: \(try yamlDoubleQuotedScalar(gitSHA))
            provenance: [\(try yamlDoubleQuotedScalar("AskiColorLab shape-residual-map"))]
            outputs: [\(outputsList)]
            runner: \(try yamlDoubleQuotedScalar("AskiColorLab"))
            command: \(try yamlDoubleQuotedScalar(command))
            \(datasetsLine)summary: \(try yamlDoubleQuotedScalar(summary))
            ---

            """
        try yaml.write(
            to: outputDirectory.appendingPathComponent("result.yaml"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func yamlDoubleQuotedScalar(_ value: String) throws -> String {
        var escaped = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default:
                guard scalar.value >= 0x20 else {
                    throw ShapeResidualResultError.unsupportedManifestScalar(value)
                }
                escaped.unicodeScalars.append(scalar)
            }
        }
        escaped += "\""
        return escaped
    }
}

// MARK: - Date helper

enum ISO8601DateOnly {
    static func today() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
