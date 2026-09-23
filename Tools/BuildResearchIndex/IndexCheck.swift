import Foundation

/// Schema + vocabulary + drift validation for the research registry. Collects all
/// problems as human-readable strings rather than throwing, so the `swift test`
/// gate reports every issue at once.
enum IndexCheck {
    static let validStatuses: Set<String> = ["living", "active", "complete", "superseded", "archived"]
    static let validSubsystems: Set<String> = [
        "color-science", "shape-context", "tile-grid", "animation",
        "frontier", "meta",
    ]

    /// Public `swift run <name>` entry points backed by executable targets whose
    /// `path:` is under `Tools/`, parsed from Package.swift. Direct executable
    /// target names remain valid; explicit executable products contribute their
    /// public product name while hiding an implementation-only `*Runner` target.
    /// Source of truth for `runner` fields and `runners:` front-matter checks.
    static func executableRunnerTargets(root: URL) -> Set<String> {
        let targetPattern = #"\.executableTarget\(\s*name:\s*"([^"]+)"(?:(?!\.(?:executableTarget|testTarget|target)\()[\s\S])*?\bpath:\s*"([^"]+)""#
        let productPattern = #"\.executable\(\s*name:\s*"([^"]+)"\s*,\s*targets:\s*\[\s*"([^"]+)"\s*\]\s*\)"#
        guard
            let text = try? String(contentsOf: root.appending(path: "Package.swift"), encoding: .utf8),
            let targetRegex = try? NSRegularExpression(pattern: targetPattern),
            let productRegex = try? NSRegularExpression(pattern: productPattern)
        else { return [] }

        let range = NSRange(text.startIndex..., in: text)
        var toolTargets: Set<String> = []
        for match in targetRegex.matches(in: text, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: text),
                let pathRange = Range(match.range(at: 2), in: text),
                text[pathRange].hasPrefix("Tools/")
            else { continue }
            toolTargets.insert(String(text[nameRange]))
        }

        var names = Set(toolTargets.filter { !$0.hasSuffix("Runner") })
        for match in productRegex.matches(in: text, range: range) {
            guard let productRange = Range(match.range(at: 1), in: text),
                let targetRange = Range(match.range(at: 2), in: text),
                toolTargets.contains(String(text[targetRange]))
            else { continue }
            names.insert(String(text[productRange]))
        }
        return names
    }

    /// Validate every note (schema, controlled vocab, filesystem references) and the
    /// generated-artifact drift. Empty result means everything is in sync.
    static func validate(root: URL) -> [String] {
        schemaFailures(root: root) + manifestFailures(root: root) + lifecycleFailures(root: root) + driftFailures(root: root)
    }

    /// Per-note front-matter problems: structure, controlled vocab, slug/date parity,
    /// and broken `related_specs`/`datasets`/`runners` references.
    static func schemaFailures(root: URL) -> [String] {
        let urls: [URL]
        do {
            urls = try ResearchRegistry.noteFileURLs(root: root)
        } catch {
            return ["could not enumerate docs/Research: \(error)"]
        }

        var failures: [String] = []
        let runners = executableRunnerTargets(root: root)
        for url in urls {
            let name = url.lastPathComponent
            do {
                let note = try ResearchRegistry.loadNote(at: url)
                failures.append(contentsOf: semanticFailures(note: note, fileName: name, root: root, runners: runners))
            } catch {
                failures.append("\(name): \(error)")
            }
        }
        return failures
    }

    private static func semanticFailures(note: ResearchNote, fileName: String, root: URL, runners: Set<String>) -> [String] {
        var failures: [String] = []
        let frontMatter = note.frontMatter
        let stem = String(fileName.dropLast(3))  // drop ".md"

        if frontMatter.slug != stem {
            failures.append("\(fileName): slug '\(frontMatter.slug)' does not match filename stem '\(stem)'")
        }
        if !validStatuses.contains(frontMatter.status) {
            failures.append("\(fileName): status '\(frontMatter.status)' not in \(validStatuses.sorted())")
        }
        for subsystem in frontMatter.subsystem where !validSubsystems.contains(subsystem) {
            failures.append("\(fileName): subsystem '\(subsystem)' not in \(validSubsystems.sorted())")
        }
        if !isISODate(frontMatter.date) {
            failures.append("\(fileName): date '\(frontMatter.date)' is not YYYY-MM-DD")
        } else {
            let prefix = String(stem.prefix(10))
            if isISODate(prefix), prefix != frontMatter.date {
                failures.append("\(fileName): date '\(frontMatter.date)' does not match filename prefix '\(prefix)'")
            }
        }
        for path in frontMatter.relatedSpecs where !exists(path, root: root) {
            failures.append("\(fileName): referenced path does not exist: \(path)")
        }
        for path in frontMatter.datasets where !path.hasPrefix("docs/Research/Corpus/") || !exists(path, root: root) {
            failures.append("\(fileName): dataset '\(path)' does not resolve under Corpus/")
        }
        for runner in frontMatter.runners where !runners.contains(runner) {
            failures.append("\(fileName): runner '\(runner)' is not a public SwiftPM executable under Tools/")
        }
        for path in frontMatter.results where !path.hasPrefix("docs/Research/Results/") || !exists(path, root: root) {
            failures.append("\(fileName): result '\(path)' does not resolve under Results/")
        }
        return failures
    }

    /// Corpus/Results store validation (spec §5): every corpus has a valid
    /// manifest with tags and a name matching its dir; every result has a valid
    /// manifest; runner (if any) is an executable Tools/ target; datasets resolve
    /// under Corpus/; and every file in a result dir except result.yaml appears in
    /// exactly one of outputs/generators.
    static func manifestFailures(root: URL) -> [String] {
        var failures: [String] = []
        let runners = executableRunnerTargets(root: root)

        let corpora = (try? ResearchRegistry.corpusDirs(root: root)) ?? []
        for dir in corpora {
            let name = "Corpus/\(dir.lastPathComponent)"
            let manifestURL = dir.appending(path: "manifest.yaml")
            guard let text = try? String(contentsOf: manifestURL, encoding: .utf8) else {
                failures.append("\(name): missing manifest.yaml")
                continue
            }
            do {
                let manifest = try CorpusManifest.from(try FrontMatterParser.parse(text))
                if manifest.name != dir.lastPathComponent {
                    failures.append("\(name): manifest name '\(manifest.name)' does not match directory '\(dir.lastPathComponent)'")
                }
            } catch { failures.append("\(name)/manifest.yaml: \(error)") }
        }

        let results = (try? ResearchRegistry.resultDirs(root: root)) ?? []
        for dir in results {
            let name = "Results/\(dir.lastPathComponent)"
            let manifestURL = dir.appending(path: "result.yaml")
            guard let text = try? String(contentsOf: manifestURL, encoding: .utf8) else {
                failures.append("\(name): missing result.yaml")
                continue
            }
            let manifest: ResultManifest
            do { manifest = try ResultManifest.from(try FrontMatterParser.parse(text)) } catch { failures.append("\(name)/result.yaml: \(error)"); continue }

            if let runner = manifest.runner, !runners.contains(runner) {
                failures.append("\(name): runner '\(runner)' is not a public SwiftPM executable under Tools/")
            }
            for dataset in manifest.datasets where !dataset.hasPrefix("docs/Research/Corpus/") || !exists(dataset, root: root) {
                failures.append("\(name): dataset '\(dataset)' does not resolve under Corpus/")
            }

            // File completeness: every file except result.yaml is in EXACTLY ONE of
            // outputs/generators, and every listed file exists.
            for both in Set(manifest.outputs).intersection(Set(manifest.generators)).sorted() {
                failures.append("\(name): file '\(both)' is listed in both outputs and generators (must be exactly one)")
            }
            let listed = Set(manifest.outputs + manifest.generators)
            let onDisk =
                (try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            for file in onDisk {
                let leaf = file.lastPathComponent
                if leaf == "result.yaml" { continue }
                let isDir = (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if isDir { continue }
                if !listed.contains(leaf) {
                    failures.append("\(name): file '\(leaf)' is not listed in outputs or generators")
                }
            }
            for listedFile in listed where !exists("docs/Research/Results/\(dir.lastPathComponent)/\(listedFile)", root: root) {
                failures.append("\(name): listed file '\(listedFile)' does not exist on disk")
            }
        }

        return failures
    }

    /// Repo lifecycle checks that sit around the registry schema: research output
    /// stores must stay structured, and execution-time placeholders must not leak
    /// into committed research notes or manifests.
    static func lifecycleFailures(root: URL) -> [String] {
        topLevelResearchFailures(root: root)
            + docsRootFailures(root: root)
            + resultStoreTopLevelFailures(root: root)
            + unresolvedPlaceholderFailures(root: root)
    }

    private static func topLevelResearchFailures(root: URL) -> [String] {
        let dir = ResearchRegistry.researchDir(root: root)
        let allowedDirectories: Set<String> = ["Corpus", "Results"]
        let allowedFiles: Set<String> = ["README.md", "Discoveries.md", "index.json"]

        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return ["could not enumerate docs/Research for lifecycle check: \(error)"]
        }

        var failures: [String] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            if name.hasPrefix(".") { continue }
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                if !allowedDirectories.contains(name) {
                    failures.append("docs/Research/\(name): unexpected top-level directory; use Corpus/ or Results/")
                }
            } else if values?.isRegularFile == true {
                if !allowedFiles.contains(name) && entry.pathExtension != "md" {
                    failures.append("docs/Research/\(name): unexpected top-level file; register research outputs under Results/")
                }
            } else {
                failures.append("docs/Research/\(name): unexpected top-level entry type")
            }
        }
        return failures
    }

    /// docs/ root is an allowlist: new top-level docs must be registered here (and, by
    /// convention, linked from the discovery hub — this gate checks only the allowlist)
    /// or they silently orphan — the 2026-07-16 audit found exactly that drift.
    /// Subdirectories own their internal conventions.
    static func docsRootFailures(root: URL) -> [String] {
        let dir = root.appending(path: "docs")
        let allowedDirectories: Set<String> = [
            "Research", "agents", "assets", "release-notes",
        ]
        let allowedFiles: Set<String> = [
            "README.md", "architecture.md",
            "research-plan.md", "repo-map.generated.md",
        ]

        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return ["could not enumerate docs/ for lifecycle check: \(error)"]
        }

        var failures: [String] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            if name.hasPrefix(".") { continue }
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                if !allowedDirectories.contains(name) {
                    failures.append("docs/\(name): unexpected top-level directory; add it to IndexCheck.docsRootFailures and the discovery hub, or relocate it")
                }
            } else if values?.isRegularFile == true {
                if !allowedFiles.contains(name) {
                    failures.append(
                        "docs/\(name): unexpected top-level file; register it in IndexCheck.docsRootFailures and link it from docs/README.md, or move it into a subdirectory")
                }
            } else {
                failures.append("docs/\(name): unexpected top-level entry type")
            }
        }
        return failures
    }

    private static func resultStoreTopLevelFailures(root: URL) -> [String] {
        let dir = ResearchRegistry.resultsDir(root: root)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return ["could not enumerate docs/Research/Results for lifecycle check: \(error)"]
        }

        var failures: [String] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            if name.hasPrefix(".") { continue }
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                continue
            }
            if values?.isRegularFile == true && name == "README.md" {
                continue
            }
            failures.append("docs/Research/Results/\(name): unexpected top-level result-store file; put outputs in a result directory with result.yaml")
        }
        return failures
    }

    private static func unresolvedPlaceholderFailures(root: URL) -> [String] {
        var urls: [URL] = []
        urls.append(contentsOf: (try? ResearchRegistry.noteFileURLs(root: root)) ?? [])
        urls.append(contentsOf: ((try? ResearchRegistry.corpusDirs(root: root)) ?? []).map { $0.appending(path: "manifest.yaml") })
        urls.append(contentsOf: ((try? ResearchRegistry.resultDirs(root: root)) ?? []).map { $0.appending(path: "result.yaml") })

        var failures: [String] = []
        for url in urls.sorted(by: { $0.path < $1.path }) where FileManager.default.fileExists(atPath: url.path) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let matches = unresolvedExecutionPlaceholders(in: String(line))
                for match in matches {
                    failures.append("\(relativePath(url, root: root)):\(offset + 1): unresolved execution placeholder '\(match)'")
                }
            }
        }
        return failures
    }

    /// Build the Codable store projections from disk. Skips dirs whose manifest is
    /// missing/invalid (those are reported by `manifestFailures`); the drift check
    /// is about shape, the manifest check is about validity.
    static func storeEntries(root: URL) -> (corpora: [CorpusEntry], results: [ResultEntry]) {
        var corpora: [CorpusEntry] = []
        for dir in (try? ResearchRegistry.corpusDirs(root: root)) ?? [] {
            guard let text = try? String(contentsOf: dir.appending(path: "manifest.yaml"), encoding: .utf8),
                let m = try? CorpusManifest.from(try FrontMatterParser.parse(text))
            else { continue }
            corpora.append(
                CorpusEntry(
                    path: "docs/Research/Corpus/\(dir.lastPathComponent)", name: m.name, summary: m.summary,
                    license: m.license, source: m.source, tags: m.tags, created: m.created, assetCount: m.assetCount))
        }
        var results: [ResultEntry] = []
        for dir in (try? ResearchRegistry.resultDirs(root: root)) ?? [] {
            guard let text = try? String(contentsOf: dir.appending(path: "result.yaml"), encoding: .utf8),
                let m = try? ResultManifest.from(try FrontMatterParser.parse(text))
            else { continue }
            results.append(
                ResultEntry(
                    path: "docs/Research/Results/\(dir.lastPathComponent)", schemaVersion: m.schemaVersion,
                    date: m.date, askiGitSha: m.askiGitSha, provenance: m.provenance, outputs: m.outputs,
                    generators: m.generators, runner: m.runner, command: m.command, runSeed: m.runSeed,
                    datasets: m.datasets, summary: m.summary))
        }
        return (corpora, results)
    }

    /// Drift between the committed generated artifacts (README index block, index.json)
    /// and a fresh render from the notes' front-matter.
    static func driftFailures(root: URL) -> [String] {
        var failures: [String] = []
        let dir = ResearchRegistry.researchDir(root: root)
        do {
            let notes = try ResearchRegistry.discover(root: root)

            let stores = storeEntries(root: root)
            let readme = try String(contentsOf: dir.appending(path: "README.md"), encoding: .utf8)
            if let committed = IndexRenderer.extractBlock(from: readme) {
                if committed != IndexRenderer.readmeIndexBlock(notes: notes, corpora: stores.corpora, results: stores.results) {
                    failures.append("docs/Research/README.md index is out of date — run `swift run BuildResearchIndex`")
                }
            } else {
                failures.append("docs/Research/README.md is missing the generated-index markers")
            }

            let expectedJSON = try IndexRenderer.indexJSON(notes: notes, corpora: stores.corpora, results: stores.results)
            let committedJSON = (try? String(contentsOf: dir.appending(path: "index.json"), encoding: .utf8)) ?? ""
            if committedJSON != expectedJSON {
                failures.append("docs/Research/index.json is out of date — run `swift run BuildResearchIndex`")
            }
        } catch {
            failures.append("drift check could not run: \(error)")
        }
        return failures
    }

    private static func exists(_ repoRelativePath: String, root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: repoRelativePath).path)
    }

    private static func relativePath(_ url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func unresolvedExecutionPlaceholders(in line: String) -> [String] {
        let pattern = #"<(date-executed|RUN_DATE|run-date|run_date|run-id|run_id|task-id|task_id|sha|SHA|[^>]*(?:SHA|sha[_:-]|[_:-]sha)[^>]*)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            Range(match.range, in: line).map { String(line[$0]) }
        }
    }

    private static func isISODate(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return false }
        return parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }
}
