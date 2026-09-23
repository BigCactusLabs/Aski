import Foundation

enum HDRResultError: Error, CustomStringConvertible {
    case unsupportedManifestScalar(String)
    var description: String {
        switch self {
        case .unsupportedManifestScalar(let value):
            "result manifest metadata contains an unsupported control character: \(value.debugDescription)"
        }
    }
}

/// Writes AskiHDRLab's research artifacts: `hdr.csv` (one row per `(fixture, k)`
/// sample) and the `result.yaml` run manifest. Per-fixture HEICs and TIFFs live
/// in `heic/` and `tiff/` subdirectories; the research-index completeness check
/// validates only top-level files, so `hdr.csv` is the sole listed output.
enum HDRResultsWriter {
    static let schemaVersion = "1"

    static func writeCSV(rows: [HDRMeasurement], displayEDRHeadroom: Double?, outputDirectory: URL) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let edr = displayEDRHeadroom.map { String(format: "%.4f", $0) } ?? "n/a"
        let header = "fixture,gamut,expectation,k,threshold,max_headroom,content_headroom,hdr_max_channel,g1_mean_diff,g2_mean_diff,float_clean,heic_bytes,display_edr_headroom"
        var lines = [header]
        for row in rows {
            lines.append(
                [
                    row.fixtureID,
                    row.gamut,
                    row.expectation,
                    fmt4(row.k),
                    fmt4(row.threshold),
                    fmt4(row.maxHeadroom),
                    fmt4(row.contentHeadroom),
                    fmt4(row.hdrMaxChannel),
                    fmt6(row.g1MeanDiff),
                    fmt6(row.g2MeanDiff),
                    row.floatClean ? "true" : "false",
                    String(row.heicBytes),
                    edr,
                ].joined(separator: ","))
        }
        let csv = lines.joined(separator: "\n") + "\n"
        try csv.write(to: outputDirectory.appendingPathComponent("hdr.csv"), atomically: true, encoding: .utf8)
    }

    static func writeManifest(
        outputDirectory: URL,
        date: String,
        gitSHA: String,
        command: String,
        summary: String
    ) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let yaml = """
            ---
            schema_version: \(schemaVersion)
            date: \(try yamlScalar(date))
            aski_git_sha: \(try yamlScalar(gitSHA))
            provenance: [\(try yamlScalar("AskiHDRLab emissive-spike"))]
            outputs: [\(try yamlScalar("hdr.csv"))]
            runner: \(try yamlScalar("AskiHDRLab"))
            command: \(try yamlScalar(command))
            summary: \(try yamlScalar(summary))
            ---

            """
        try yaml.write(to: outputDirectory.appendingPathComponent("result.yaml"), atomically: true, encoding: .utf8)
    }

    /// Reject control characters in metadata before they reach the manifest.
    static func validatedManifestMetadata(gitSHA: String, command: String) throws {
        _ = try yamlScalar(gitSHA)
        _ = try yamlScalar(command)
    }

    private static func fmt4(_ value: Float) -> String { String(format: "%.4f", value) }
    private static func fmt6(_ value: Float) -> String { String(format: "%.6f", value) }

    private static func yamlScalar(_ value: String) throws -> String {
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
                    throw HDRResultError.unsupportedManifestScalar(value)
                }
                escaped.unicodeScalars.append(scalar)
            }
        }
        escaped += "\""
        return escaped
    }
}
