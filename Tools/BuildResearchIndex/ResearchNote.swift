import Foundation

/// A single research note under docs/Research/ with parsed front-matter.
struct ResearchNote {
    let slug: String
    let fileName: String  // e.g. 2026-05-05-color-science-deep-dive.md
    let repoRelativePath: String  // docs/Research/<fileName>
    let frontMatter: FrontMatter
}

/// Discovery over the docs/Research/ folder. Top-level markdown notes only;
/// the index README and the Discoveries log are skipped, and subdirectories
/// (Corpus/, Results/, and legacy artifact dirs) are not notes.
enum ResearchRegistry {
    static let researchDirComponents = ["docs", "Research"]
    static let skippedFiles: Set<String> = ["README.md", "Discoveries.md"]

    static func researchDir(root: URL) -> URL {
        researchDirComponents.reduce(root) { $0.appending(path: $1) }
    }

    static func corpusDir(root: URL) -> URL { researchDir(root: root).appending(path: "Corpus") }
    static func resultsDir(root: URL) -> URL { researchDir(root: root).appending(path: "Results") }

    /// Subdirectories of a store (Corpus/ or Results/), sorted by name. A missing
    /// store returns an empty array (the stores are optional until populated).
    private static func storeDirs(_ store: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: store.path) else { return [] }
        let entries = try FileManager.default.contentsOfDirectory(
            at: store, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        return
            entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func corpusDirs(root: URL) throws -> [URL] { try storeDirs(corpusDir(root: root)) }
    static func resultDirs(root: URL) throws -> [URL] { try storeDirs(resultsDir(root: root)) }

    /// Enumerate the research-note markdown files (top-level only), sorted by
    /// file name for stable iteration. Returns absolute file URLs.
    static func noteFileURLs(root: URL) throws -> [URL] {
        let entries = try FileManager.default.contentsOfDirectory(
            at: researchDir(root: root),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return
            entries
            .filter { $0.pathExtension == "md" && !skippedFiles.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Load and parse a single note. Throws on I/O or structural front-matter errors.
    static func loadNote(at url: URL) throws -> ResearchNote {
        let text = try String(contentsOf: url, encoding: .utf8)
        let frontMatter = try FrontMatter.from(try FrontMatterParser.parse(text))
        let name = url.lastPathComponent
        return ResearchNote(
            slug: frontMatter.slug,
            fileName: name,
            repoRelativePath: (researchDirComponents + [name]).joined(separator: "/"),
            frontMatter: frontMatter
        )
    }

    /// Discover and parse all notes, sorted by (date, slug). Throws on the first
    /// structural problem — used by the generator, which must fail fast.
    static func discover(root: URL) throws -> [ResearchNote] {
        try noteFileURLs(root: root).map { try loadNote(at: $0) }.sorted {
            $0.frontMatter.date != $1.frontMatter.date
                ? $0.frontMatter.date < $1.frontMatter.date
                : $0.slug < $1.slug
        }
    }
}
