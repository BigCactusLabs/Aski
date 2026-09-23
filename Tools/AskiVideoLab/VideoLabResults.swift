import Aski
import Foundation

/// Metrics common to every lab run, regardless of output medium.
struct LabRunMetrics {
    var throughputFPS: Double
    var peakMemoryBytes: UInt64
    var frameCount: Int
    var inputDescriptor: String
    var maxFrames: Int?
    var resample: ResampleReport?
}

/// Supplies the parts of the result artifacts that differ by output medium. The
/// CSV layout is: [throughput_fps, peak_memory_bytes, frame_count] + extra +
/// [input_descriptor, max_frames]. MP4's single extra column (`codec`) keeps the
/// historical header byte-for-byte.
protocol LabMediaSummary {
    var outputFileName: String { get }
    var extraColumnHeaders: [String] { get }
    var extraColumnValues: [String] { get }
    func summarySentence(_ metrics: LabRunMetrics) -> String
}

struct MP4MediaSummary: LabMediaSummary {
    var codec: String
    var outputFileName: String { "ascii.mp4" }
    var extraColumnHeaders: [String] { ["codec"] }
    var extraColumnValues: [String] { [codec] }
    func summarySentence(_ metrics: LabRunMetrics) -> String {
        "AskiVideoLab streamed \(metrics.frameCount) frame(s) of "
            + "\(metrics.inputDescriptor) through AVAssetReader → ASCIIConverter → "
            + "AVAssetWriter (\(codec)) at "
            + String(format: "%.2f", metrics.throughputFPS)
            + " frames/sec end-to-end, peak resident footprint "
            + String(metrics.peakMemoryBytes)
            + " bytes — evidence the pipeline streams rather than loading the whole asset."
    }
}

struct GIFMediaSummary: LabMediaSummary {
    var loopCount: Int
    var delayMin: Double
    var delayMax: Double
    var delayUniform: Bool
    var outputFileName: String { "ascii.gif" }
    var extraColumnHeaders: [String] { ["loop_count", "delay_min_s", "delay_max_s", "delay_uniform"] }
    var extraColumnValues: [String] {
        [
            String(loopCount),
            String(format: "%.4f", delayMin),
            String(format: "%.4f", delayMax),
            delayUniform ? "true" : "false",
        ]
    }
    func summarySentence(_ metrics: LabRunMetrics) -> String {
        let loopText = loopCount == 0 ? "infinite loop" : (loopCount == 1 ? "play once" : "\(loopCount) plays")
        return "AskiVideoLab streamed \(metrics.frameCount) frame(s) of "
            + "\(metrics.inputDescriptor) through CGImageSource → ASCIIConverter → "
            + "CGImageDestination at "
            + String(format: "%.2f", metrics.throughputFPS)
            + " frames/sec end-to-end, peak resident footprint "
            + String(metrics.peakMemoryBytes)
            + " bytes; loop semantics preserved (\(loopText)) and per-frame timing preserved (delay "
            + String(format: "%.4f", delayMin) + "–" + String(format: "%.4f", delayMax) + "s, "
            + (delayUniform ? "uniform" : "variable")
            + ")."
    }
}

enum VideoLabResultError: Error, CustomStringConvertible {
    case unsupportedManifestScalar(String)

    var description: String {
        switch self {
        case .unsupportedManifestScalar(let scalar):
            "result manifest metadata contains an unsupported control character: \(scalar.debugDescription)"
        }
    }
}

enum VideoLabResults {
    /// Numeric metrics go in `metrics.csv`; `result.yaml` carries only the closed
    /// shared-schema keys (unknown keys fail `BuildResearchIndex --check`).
    static func validateManifestMetadata(inputDescriptor: String, gitSHA: String, command: String) throws {
        _ = try yamlDoubleQuotedScalar(inputDescriptor)
        _ = try yamlDoubleQuotedScalar(gitSHA)
        _ = try yamlDoubleQuotedScalar(command)
    }

    static func writeMetricsCSV(
        _ metrics: LabRunMetrics,
        media: LabMediaSummary,
        outputDirectory: URL
    ) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let resampleHeaders = [
            "target_fps", "achieved_fps", "source_frame_count",
            "output_frame_count", "dropped_count", "duplicated_count",
        ]
        let headerColumns =
            ["throughput_fps", "peak_memory_bytes", "frame_count"]
            + media.extraColumnHeaders + ["input_descriptor", "max_frames"] + resampleHeaders
        let header = headerColumns.joined(separator: ",")
        let resampleValues: [String]
        if let r = metrics.resample {
            resampleValues = [
                String(r.requestedFPS),
                String(format: "%.4f", r.achievedFPS),
                String(r.sourceFrameCount),
                String(r.outputFrameCount),
                String(r.droppedCount),
                String(r.duplicatedCount),
            ]
        } else {
            resampleValues = ["none", "none", "none", "none", "none", "none"]
        }
        let valueColumns =
            [
                String(format: "%.3f", metrics.throughputFPS),
                String(metrics.peakMemoryBytes),
                String(metrics.frameCount),
            ] + media.extraColumnValues + [
                metrics.inputDescriptor,
                metrics.maxFrames.map(String.init) ?? "none",
            ] + resampleValues
        let row = valueColumns.map(csvField).joined(separator: ",")
        let csv = header + "\n" + row + "\n"
        try csv.write(
            to: outputDirectory.appendingPathComponent("metrics.csv"),
            atomically: true,
            encoding: .utf8
        )
    }

    static func writeManifest(
        outputDirectory: URL,
        date: String,
        gitSHA: String,
        command: String,
        metrics: LabRunMetrics,
        media: LabMediaSummary,
        outputFiles: [String]
    ) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputsList = try outputFiles.sorted().map(yamlDoubleQuotedScalar).joined(separator: ", ")
        var summary = media.summarySentence(metrics)
        if let r = metrics.resample {
            let achieved = String(format: "%.2f", r.achievedFPS)
            summary +=
                " Resampled to target \(r.requestedFPS) fps (achieved \(achieved) fps,"
                + " \(r.sourceFrameCount) source -> \(r.outputFrameCount) output frames,"
                + " dropped \(r.droppedCount), duplicated \(r.duplicatedCount))."
        }
        let yaml = """
            ---
            schema_version: 1
            date: \(date)
            aski_git_sha: \(try yamlDoubleQuotedScalar(gitSHA))
            provenance: [\(try yamlDoubleQuotedScalar("AskiVideoLab run"))]
            outputs: [\(outputsList)]
            runner: AskiVideoLab
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
                    throw VideoLabResultError.unsupportedManifestScalar(value)
                }
                escaped.unicodeScalars.append(scalar)
            }
        }
        escaped += "\""
        return escaped
    }
}
