import Foundation

/// A parsed, structurally-validated `result.yaml` run manifest — the cross-lab
/// shared result schema. Reuses the constrained `FrontMatterParser` grammar.
/// See the spec §3.
struct ResultManifest {
    var schemaVersion: String
    var date: String
    var askiGitSha: String
    var provenance: [String]
    var outputs: [String]
    var generators: [String]
    var runner: String?
    var command: String?
    var runSeed: String?
    var datasets: [String]
    var summary: String?

    static let allowedKeys: Set<String> = [
        "schema_version", "date", "aski_git_sha", "provenance", "outputs",
        "generators", "runner", "command", "run_seed", "datasets", "summary",
        "calibration_units", "calibration_families", "jnd75_contains_point_estimate",
    ]

    static func from(_ dict: [String: FrontMatterValue]) throws -> ResultManifest {
        for key in dict.keys where !allowedKeys.contains(key) {
            throw FrontMatterError(message: "unknown result-manifest key: '\(key)'")
        }

        func scalar(_ key: String, required: Bool) throws -> String? {
            guard let value = dict[key] else {
                if required { throw FrontMatterError(message: "missing required field: '\(key)'") }
                return nil
            }
            guard case .scalar(let string) = value else {
                throw FrontMatterError(message: "field '\(key)' must be a scalar, not a list")
            }
            if required && string.trimmingCharacters(in: .whitespaces).isEmpty {
                throw FrontMatterError(message: "required field '\(key)' is empty")
            }
            return string
        }

        func list(_ key: String, required: Bool) throws -> [String] {
            guard let value = dict[key] else {
                if required { throw FrontMatterError(message: "missing required field: '\(key)'") }
                return []
            }
            guard case .list(let items) = value else {
                throw FrontMatterError(message: "field '\(key)' must be a list")
            }
            if required && items.isEmpty {
                throw FrontMatterError(message: "required list '\(key)' is empty")
            }
            return items
        }

        return ResultManifest(
            schemaVersion: try scalar("schema_version", required: true)!,
            date: try scalar("date", required: true)!,
            askiGitSha: try scalar("aski_git_sha", required: true)!,
            provenance: try list("provenance", required: true),
            outputs: try list("outputs", required: true),
            generators: try list("generators", required: false),
            runner: try scalar("runner", required: false),
            command: try scalar("command", required: false),
            runSeed: try scalar("run_seed", required: false),
            datasets: try list("datasets", required: false),
            summary: try scalar("summary", required: false)
        )
    }
}
