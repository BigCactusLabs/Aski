import Foundation

enum MotionLabResultError: Error, CustomStringConvertible {
    case unsupportedManifestScalar(String)

    public var description: String {
        switch self {
        case .unsupportedManifestScalar(let value):
            "result manifest metadata contains an unsupported control character: \(value.debugDescription)"
        }
    }
}

/// One preset's run summary, used to emit `flicker.csv`.
public struct PresetRun: Sendable {
    public let preset: MotionLabPreset
    public let frameCount: Int
    public let frameRate: Int
    public let metrics: FlickerMetrics
    public let gifBytes: Int?

    public init(preset: MotionLabPreset, frameCount: Int, frameRate: Int, metrics: FlickerMetrics, gifBytes: Int?) {
        self.preset = preset
        self.frameCount = frameCount
        self.frameRate = frameRate
        self.metrics = metrics
        self.gifBytes = gifBytes
    }
}

/// Writes MotionLab's research artifacts: canonical text frames, `flicker.csv`,
/// and the `result.yaml` run manifest. The CSV is written directly because
/// each lab's schema differs.
public enum ResultsWriter {
    public static let schemaVersion = "1"

    /// Writes `frames/<preset>/frame-NNN.txt` (zero-padded to 3 digits).
    public static func writeFrames(_ frames: [String], preset: MotionLabPreset, outputDirectory: URL) throws {
        let dir =
            outputDirectory
            .appendingPathComponent("frames")
            .appendingPathComponent(preset.rawValue)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (index, frame) in frames.enumerated() {
            let name = String(format: "frame-%03d.txt", index)
            try frame.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }

    /// Writes `flicker.csv` with one row per preset.
    public static func writeFlickerCSV(runs: [PresetRun], outputDirectory: URL) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let header = "preset,frame_rate,total_frames,mean_glyph_churn,max_glyph_churn,mean_alpha_churn,max_alpha_churn,gif_bytes"
        var lines = [header]
        for run in runs {
            lines.append(
                [
                    run.preset.rawValue,
                    String(run.frameRate),
                    String(run.frameCount),
                    formatMetric(run.metrics.meanGlyphChurn),
                    formatMetric(run.metrics.maxGlyphChurn),
                    formatMetric(run.metrics.meanAlphaChurn),
                    formatMetric(run.metrics.maxAlphaChurn),
                    run.gifBytes.map(String.init) ?? "n/a",
                ].joined(separator: ","))
        }
        let csv = lines.joined(separator: "\n") + "\n"
        try csv.write(to: outputDirectory.appendingPathComponent("flicker.csv"), atomically: true, encoding: .utf8)
    }

    /// Writes `result.yaml`. `outputFiles` must be the exact set of top-level
    /// files written (besides `result.yaml`) so the research-index completeness
    /// check passes.
    public static func writeManifest(
        outputDirectory: URL,
        date: String,
        gitSHA: String,
        command: String,
        seed: UInt64,
        outputFiles: [String]
    ) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputsList = try outputFiles.sorted().map(yamlDoubleQuotedScalar).joined(separator: ", ")
        let summary =
            "AskiMotionLab materialized deterministic ASCII frame sequences (reveal alpha-axis, cycle glyph-axis), spiked a CGImageDestination GIF export, and recorded glyph-churn and alpha-churn as an ASCII Temporal Flicker Index."
        let yaml = """
            ---
            schema_version: \(schemaVersion)
            date: \(try yamlDoubleQuotedScalar(date))
            aski_git_sha: \(try yamlDoubleQuotedScalar(gitSHA))
            provenance: [\(try yamlDoubleQuotedScalar("AskiMotionLab materialize"))]
            outputs: [\(outputsList)]
            runner: \(try yamlDoubleQuotedScalar("AskiMotionLab"))
            command: \(try yamlDoubleQuotedScalar(command))
            run_seed: \(seed)
            summary: \(try yamlDoubleQuotedScalar(summary))
            ---

            """
        try yaml.write(to: outputDirectory.appendingPathComponent("result.yaml"), atomically: true, encoding: .utf8)
    }

    private static func formatMetric(_ value: Double) -> String {
        String(format: "%.6f", value)
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
                    throw MotionLabResultError.unsupportedManifestScalar(value)
                }
                escaped.unicodeScalars.append(scalar)
            }
        }
        escaped += "\""
        return escaped
    }
}
