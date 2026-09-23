import Foundation

struct RepoMapError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// Source-scan repo map: extracts top-level declarations from `Sources/Aski/**/*.swift`
/// by lightweight tokenization — no build, no SwiftSyntax dependency — so the in-process
/// drift test (`RepoMapRegistryTests`) can regenerate and byte-compare cheaply. Everything
/// is sorted by a stable key, so the rendered artifact is deterministic and the drift
/// check is a plain byte comparison.
enum RepoMap {
    /// Directory scanned and reflected in the generated map.
    static let sourceRelativeRoot = "Sources/Aski"
    /// Committed generated artifact (repo-root-relative).
    static let outputRelativePath = "docs/repo-map.generated.md"
    /// Subtrees with no navigable Swift declarations.
    private static let excludedTopDirs: Set<String> = ["Resources", "Aski.docc"]

    static func outputURL(root: URL) -> URL { root.appending(path: outputRelativePath) }

    /// A top-level declaration: its keyword and name (e.g. `struct ASCIIGrid`).
    struct Symbol: Comparable {
        let keyword: String
        let name: String
        var rendered: String { "\(keyword) \(name)" }
        static func < (lhs: Symbol, rhs: Symbol) -> Bool {
            (lhs.name, lhs.keyword) < (rhs.name, rhs.keyword)
        }
    }

    /// One scanned source file and its top-level declarations.
    struct FileEntry {
        let directory: String  // path under Sources/Aski, "" for the root
        let fileName: String
        let symbols: [Symbol]
    }

    // MARK: - Scan

    /// Walk `Sources/Aski`, returning one `FileEntry` per `.swift` file (excluded
    /// subtrees skipped). Order is irrelevant — `render` groups and sorts.
    static func scan(root: URL) throws -> [FileEntry] {
        let base = root.appending(path: sourceRelativeRoot)
        guard
            let enumerator = FileManager.default.enumerator(
                at: base, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        else {
            throw RepoMapError("could not enumerate \(sourceRelativeRoot)")
        }

        var entries: [FileEntry] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let components = relativeComponents(url, base: base)
            guard !components.isEmpty else { continue }
            if let top = components.first, components.count > 1, excludedTopDirs.contains(top) { continue }

            let fileName = components.last!
            let directory = components.dropLast().joined(separator: "/")
            let source = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            entries.append(FileEntry(directory: directory, fileName: fileName, symbols: topLevelSymbols(in: source)))
        }
        return entries
    }

    private static func relativeComponents(_ url: URL, base: URL) -> [String] {
        let basePath = base.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(basePath + "/") else { return [] }
        return String(path.dropFirst(basePath.count + 1)).split(separator: "/").map(String.init)
    }

    // MARK: - Declaration tokenizer

    private static let declKeywords: Set<String> = [
        "struct", "class", "enum", "protocol", "actor", "extension", "typealias", "func", "var", "let",
    ]
    private static let modifiers: Set<String> = [
        "public", "internal", "private", "fileprivate", "open", "package", "final", "indirect",
        "dynamic", "override", "convenience", "required", "lazy", "weak", "unowned", "static",
        "prefix", "postfix", "infix", "nonisolated", "mutating", "nonmutating",
    ]

    /// Top-level declarations in source order, deduplicated by rendered form (so repeated
    /// `extension Foo` blocks collapse, while `struct Foo` + `extension Foo` both survive),
    /// then sorted. Only column-0 lines are considered — nested members are indented.
    static func topLevelSymbols(in source: String) -> [Symbol] {
        var symbols: [Symbol] = []
        var seen: Set<String> = []
        var inBlockComment = false

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if inBlockComment {
                if line.contains("*/") { inBlockComment = false }
                continue
            }
            // Top-level only: first character is non-whitespace.
            guard let first = line.first, !first.isWhitespace else {
                continue
            }
            if let symbol = declaration(in: line), seen.insert(symbol.rendered).inserted {
                symbols.append(symbol)
            }
            if line.contains("/*"), !line.contains("*/") { inBlockComment = true }
        }
        return symbols.sorted()
    }

    private static func declaration(in line: String) -> Symbol? {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token.hasPrefix("@") { index += 1; continue }  // attribute, possibly @foo(bar)
            let bare = token.split(separator: "(").first.map(String.init) ?? token  // private(set)
            if modifiers.contains(bare) { index += 1; continue }
            break
        }
        guard index < tokens.count, declKeywords.contains(tokens[index]), index + 1 < tokens.count else {
            return nil
        }
        let keyword = tokens[index]
        let name = cleanName(tokens[index + 1])
        guard isIdentifier(name) else { return nil }  // drops operators and malformed names
        return Symbol(keyword: keyword, name: name)
    }

    /// Trim a name token down to its identifier: cut at the first generic/paren/colon/etc.
    private static func cleanName(_ token: String) -> String {
        if let cut = token.firstIndex(where: { "<({:=,".contains($0) }) {
            return String(token[..<cut])
        }
        return token
    }

    private static func isIdentifier(_ value: String) -> Bool {
        guard let first = value.first, first == "_" || first.isLetter else { return false }
        return value.dropFirst().allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }

    // MARK: - Render

    /// Deterministic markdown: a generated-by header, then `## Sources/Aski[/dir]` sections
    /// (root first), each listing files alphabetically with their top-level symbols.
    static func render(entries: [FileEntry]) -> String {
        var out = "<!-- GENERATED by BuildRepoMap — do not edit; run `just regen-repo-map` -->\n"
        out += "# Aski source map\n\n"
        out +=
            "Auto-generated index of top-level declarations in `Sources/Aski/`, grouped by directory then file. "
            + "Regenerate with `just regen-repo-map`; `just doctor` and the test suite fail on drift. "
            + "For subsystem roles and orientation, see [AGENTS.md](../AGENTS.md).\n"

        let byDirectory = Dictionary(grouping: entries, by: { $0.directory })
        for directory in byDirectory.keys.sorted(by: directorySort) {
            let heading = directory.isEmpty ? "Sources/Aski (root)" : "Sources/Aski/\(directory)"
            out += "\n## \(heading)\n\n"
            for file in byDirectory[directory]!.sorted(by: { $0.fileName < $1.fileName }) {
                if file.symbols.isEmpty {
                    out += "- `\(file.fileName)`\n"
                } else {
                    out += "- `\(file.fileName)` — \(file.symbols.map(\.rendered).joined(separator: ", "))\n"
                }
            }
        }
        return out
    }

    /// Root (`""`) sorts first; the rest alphabetically.
    private static func directorySort(_ lhs: String, _ rhs: String) -> Bool {
        if lhs.isEmpty != rhs.isEmpty { return lhs.isEmpty }
        return lhs < rhs
    }
}
