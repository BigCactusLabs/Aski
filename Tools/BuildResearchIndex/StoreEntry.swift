import Foundation

/// Codable projection of a corpus manifest for index.json.
struct CorpusEntry: Codable {
    let path: String
    let name: String
    let summary: String
    let license: String
    let source: String
    let tags: [String]
    let created: String?
    let assetCount: String?

    enum CodingKeys: String, CodingKey {
        case path, name, summary, license, source, tags, created
        case assetCount = "asset_count"
    }
}

/// Codable projection of a result manifest for index.json.
struct ResultEntry: Codable {
    let path: String
    let schemaVersion: String
    let date: String
    let askiGitSha: String
    let provenance: [String]
    let outputs: [String]
    let generators: [String]
    let runner: String?
    let command: String?
    let runSeed: String?
    let datasets: [String]
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case path, date, provenance, outputs, generators, runner, command, datasets, summary
        case schemaVersion = "schema_version"
        case askiGitSha = "aski_git_sha"
        case runSeed = "run_seed"
    }
}

/// Top-level index.json shape (spec §4).
struct RegistryIndex: Codable {
    let notes: [IndexEntry]
    let corpora: [CorpusEntry]
    let results: [ResultEntry]
}
