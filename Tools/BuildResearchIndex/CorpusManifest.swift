import Foundation

/// A parsed, structurally-validated corpus `manifest.yaml` (datasheet-lite).
/// Reuses the constrained `FrontMatterParser` grammar — flat scalars and lists,
/// no inline comments. See the spec §2.
struct CorpusManifest {
    var name: String
    var summary: String
    var license: String
    var source: String
    var tags: [String]
    var created: String?
    var assetCount: String?

    static let allowedKeys: Set<String> = [
        "name", "summary", "license", "source", "tags", "created", "asset_count",
    ]

    static func from(_ dict: [String: FrontMatterValue]) throws -> CorpusManifest {
        for key in dict.keys where !allowedKeys.contains(key) {
            throw FrontMatterError(message: "unknown corpus-manifest key: '\(key)'")
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

        return CorpusManifest(
            name: try scalar("name", required: true)!,
            summary: try scalar("summary", required: true)!,
            license: try scalar("license", required: true)!,
            source: try scalar("source", required: true)!,
            tags: try list("tags", required: true),
            created: try scalar("created", required: false),
            assetCount: try scalar("asset_count", required: false)
        )
    }
}
