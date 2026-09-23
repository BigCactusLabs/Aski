import Foundation

/// One record in the generated machine-readable registry (docs/Research/index.json).
struct IndexEntry: Codable {
    let slug: String
    let title: String
    let date: String
    let status: String
    let subsystem: [String]
    let summary: String
    let path: String
    let relatedSpecs: [String]
    let nextAction: String?
    let datasets: [String]
    let runners: [String]
    let results: [String]

    enum CodingKeys: String, CodingKey {
        case slug, title, date, status, subsystem, summary, path
        case relatedSpecs = "related_specs"
        case nextAction = "next_action"
        case datasets, runners, results
    }
}

/// Renders the two generated artifacts from parsed notes: the README index block
/// (human-facing) and index.json (machine-readable). Both are deterministic so the
/// drift check is a stable byte comparison.
enum IndexRenderer {
    static let beginMarker = "<!-- BEGIN GENERATED INDEX -->"
    static let endMarker = "<!-- END GENERATED INDEX -->"

    // Fixed, non-front-matter index entry kept in the README for human use:
    // the Discoveries triage log is not a research note but is useful to surface.
    private static let discoveriesBullet =
        "- [Discoveries — triage queue for cross-cutting insights](Discoveries.md) — append-only log of out-of-scope findings worth revisiting later."

    /// The generated README index block (the lines between the markers, exclusive).
    static func readmeIndexBlock(notes: [ResearchNote], corpora: [CorpusEntry], results: [ResultEntry]) -> String {
        var lines = [discoveriesBullet]
        for note in notes {
            let fm = note.frontMatter
            lines.append("- [\(fm.date) — \(fm.title)](\(note.fileName)) — \(fm.summary)")
        }
        for corpus in corpora {
            let leaf = (corpus.path as NSString).lastPathComponent  // dir is the link target, not manifest name
            lines.append("- [Corpus/\(leaf)/](Corpus/\(leaf)/) — \(corpus.summary)")
        }
        for result in results {
            let leaf = (result.path as NSString).lastPathComponent
            lines.append("- [Results/\(leaf)/](Results/\(leaf)/) — \(result.summary ?? "experiment results")")
        }
        return lines.joined(separator: "\n")
    }

    /// The generated machine-readable registry JSON (deterministic; trailing newline).
    static func indexJSON(notes: [ResearchNote], corpora: [CorpusEntry], results: [ResultEntry]) throws -> String {
        let noteEntries = notes.map { note -> IndexEntry in
            let fm = note.frontMatter
            return IndexEntry(
                slug: fm.slug, title: fm.title, date: fm.date, status: fm.status,
                subsystem: fm.subsystem, summary: fm.summary, path: note.repoRelativePath,
                relatedSpecs: fm.relatedSpecs, nextAction: fm.nextAction,
                datasets: fm.datasets, runners: fm.runners, results: fm.results)
        }
        let index = RegistryIndex(notes: noteEntries, corpora: corpora, results: results)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(index)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    /// Extract the committed block between the markers (exclusive), or nil if the
    /// markers are missing or out of order.
    static func extractBlock(from readme: String) -> String? {
        let lines = readme.components(separatedBy: "\n")
        guard let begin = lines.firstIndex(of: beginMarker),
            let end = lines.firstIndex(of: endMarker),
            begin < end
        else { return nil }
        guard begin + 1 <= end - 1 else { return "" }
        return lines[(begin + 1)...(end - 1)].joined(separator: "\n")
    }

    /// Splice the generated block into README text between the markers. Throws if
    /// the markers are missing or out of order, protecting the surrounding prose.
    static func spliceREADME(_ readme: String, block: String) throws -> String {
        let lines = readme.components(separatedBy: "\n")
        guard let begin = lines.firstIndex(of: beginMarker) else {
            throw FrontMatterError(message: "README is missing the '\(beginMarker)' marker")
        }
        guard let end = lines.firstIndex(of: endMarker) else {
            throw FrontMatterError(message: "README is missing the '\(endMarker)' marker")
        }
        guard begin < end else {
            throw FrontMatterError(message: "README index markers are out of order")
        }
        let head = Array(lines[...begin])
        let tail = Array(lines[end...])
        return (head + block.components(separatedBy: "\n") + tail).joined(separator: "\n")
    }
}
