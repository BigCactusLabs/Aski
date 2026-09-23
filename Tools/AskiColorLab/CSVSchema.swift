import Foundation
import simd

public enum CSVSchema {
    public static let schemaVersion = "1"

    public static let sharedPrefixColumns: [String] = [
        "schema_version",
        "command",
        "aski_git_sha",
        "run_seed",
        "sample_id",
        "fixture_id",
        "policy",
        "input_space",
        "input_components",
        "output_space",
        "output_components",
    ]

    public static func formatFloat(_ value: Float) -> String {
        String(format: "%.6f", value)
    }

    public static func formatComponents(_ components: [Float]) -> String {
        components.map { String(format: "%.6f", $0) }.joined(separator: ";")
    }

    public static func formatSIMD3(_ components: SIMD3<Float>) -> String {
        formatComponents([components.x, components.y, components.z])
    }
}
