import Foundation
import Testing
@testable import BuildResearchIndex

@Suite struct ResearchManifestTests {
    @Test func frontMatterParsesResultsList() throws {
        let yaml = """
            ---
            title: T
            slug: 2026-01-01-x
            date: 2026-01-01
            status: living
            subsystem: [color-science]
            summary: s
            results: [docs/Research/Results/ray-trace-v0.4.0]
            ---
            """
        let fm = try FrontMatter.from(try FrontMatterParser.parse(yaml))
        #expect(fm.results == ["docs/Research/Results/ray-trace-v0.4.0"])
    }

    @Test func frontMatterResultsDefaultsEmpty() throws {
        let yaml = """
            ---
            title: T
            slug: 2026-01-01-x
            date: 2026-01-01
            status: living
            subsystem: [color-science]
            summary: s
            ---
            """
        let fm = try FrontMatter.from(try FrontMatterParser.parse(yaml))
        #expect(fm.results.isEmpty)
    }

    @Test func corpusManifestParsesValid() throws {
        let yaml = """
            ---
            name: portrait-100
            summary: 100 balanced portraits
            license: CC-BY-4.0
            source: unsplash
            tags: [portrait, balanced]
            asset_count: 100
            ---
            """
        let m = try CorpusManifest.from(try FrontMatterParser.parse(yaml))
        #expect(m.name == "portrait-100")
        #expect(m.tags == ["portrait", "balanced"])
        #expect(m.assetCount == "100")
    }

    @Test func corpusManifestRejectsMissingTags() throws {
        let yaml = """
            ---
            name: x
            summary: s
            license: synthetic
            source: generated
            ---
            """
        #expect(throws: FrontMatterError.self) {
            _ = try CorpusManifest.from(try FrontMatterParser.parse(yaml))
        }
    }

    @Test func corpusManifestRejectsEmptyTags() throws {
        let yaml = """
            ---
            name: x
            summary: s
            license: synthetic
            source: generated
            tags: []
            ---
            """
        #expect(throws: FrontMatterError.self) {
            _ = try CorpusManifest.from(try FrontMatterParser.parse(yaml))
        }
    }

    @Test func resultManifestParsesValid() throws {
        let yaml = """
            ---
            schema_version: 1
            date: 2026-05-28
            aski_git_sha: abc123
            provenance: [AskiColorLab gamut-sweep, swiftc generate-review-artifacts.swift]
            outputs: [a.csv, b.png]
            generators: [generate-review-artifacts.swift]
            ---
            """
        let m = try ResultManifest.from(try FrontMatterParser.parse(yaml))
        #expect(m.provenance.count == 2)
        #expect(m.outputs == ["a.csv", "b.png"])
        #expect(m.generators == ["generate-review-artifacts.swift"])
        #expect(m.runner == nil)
    }

    @Test func resultManifestRejectsMissingProvenance() throws {
        let yaml = """
            ---
            schema_version: 1
            date: 2026-05-28
            aski_git_sha: abc123
            outputs: [a.csv]
            ---
            """
        #expect(throws: FrontMatterError.self) {
            _ = try ResultManifest.from(try FrontMatterParser.parse(yaml))
        }
    }

    @Test func resultManifestRejectsEmptyOutputs() throws {
        let yaml = """
            ---
            schema_version: 1
            date: 2026-05-28
            aski_git_sha: abc123
            provenance: [x]
            outputs: []
            ---
            """
        #expect(throws: FrontMatterError.self) {
            _ = try ResultManifest.from(try FrontMatterParser.parse(yaml))
        }
    }

    private func makeTempRoot() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "aski-research-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: base.appending(path: "docs/Research/Corpus/portrait-100"),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: base.appending(path: "docs/Research/Results/run-a"),
            withIntermediateDirectories: true)
        // Stub Package.swift so executableRunnerTargets(root:) resolves in fixtures:
        // AskiColorLab is a public product backed by a Tools/ replay runner;
        // AskiBenchmarks is under Benchmarks/ (NOT a valid runner); AskiToolSupport
        // and the importable AskiColorLab implementation are plain targets.
        try """
        .executable(name: "AskiColorLab", targets: ["AskiColorLabRunner"])
        .target(
            name: "AskiColorLab",
            dependencies: ["Aski", "AskiToolSupport"],
            path: "Tools/AskiColorLab"
        )
        .executableTarget(
            name: "AskiColorLabRunner",
            dependencies: ["AskiColorLab"],
            path: "Tools/AskiColorLabRunner"
        )
        .executableTarget(
            name: "AskiBenchmarks",
            dependencies: ["Aski", .product(name: "Benchmark", package: "package-benchmark")],
            path: "Benchmarks/AskiBenchmarks"
        )
        .target(
            name: "AskiToolSupport",
            path: "Tools/AskiToolSupport"
        )
        """.write(to: base.appending(path: "Package.swift"), atomically: true, encoding: .utf8)
        return base
    }

    /// Walk up from the working directory to the package root (where Package.swift lives).
    private func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appending(path: "Package.swift").path) { return url }
            url.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    @Test func discoversCorpusAndResultDirs() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try ResearchRegistry.corpusDirs(root: root).map(\.lastPathComponent) == ["portrait-100"])
        #expect(try ResearchRegistry.resultDirs(root: root).map(\.lastPathComponent) == ["run-a"])
    }

    @Test func executableRunnersIncludeLabsNotSupportLibs() throws {
        let runners = IndexCheck.executableRunnerTargets(root: try packageRoot())
        for runner in [
            "aski", "AskiColorLab", "AskiMotionLab", "AskiVideoLab", "AskiAccessLab",
            "AskiDecolorLab", "AskiHDRLab", "AskiPresetLab",
        ] {
            #expect(runners.contains(runner), "missing public runner: \(runner)")
        }
        #expect(runners.contains("BuildResearchIndex"))
        #expect(!runners.contains(where: { $0.hasSuffix("Runner") }))
        #expect(!runners.contains("AskiToolSupport"))  // a plain .target, not executable
        #expect(!runners.contains("AskiBenchmarks"))  // executable but path is Benchmarks/, not Tools/
    }

    @Test func executableRunnersRequireToolsPath() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let runners = IndexCheck.executableRunnerTargets(root: root)
        #expect(runners.contains("AskiColorLab"))  // public product backed by a Tools/ executable
        #expect(!runners.contains("AskiColorLabRunner"))  // implementation-only target name
        #expect(!runners.contains("AskiBenchmarks"))  // executable, but path under Benchmarks/
        #expect(!runners.contains("AskiToolSupport"))  // plain .target
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func manifestFailuresFlagsCorpusWithoutTags() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            """
            ---
            name: portrait-100
            summary: s
            license: synthetic
            source: generated
            ---
            """, to: root.appending(path: "docs/Research/Corpus/portrait-100/manifest.yaml"))
        // run-a result dir has no result.yaml either
        let failures = IndexCheck.manifestFailures(root: root)
        #expect(failures.contains { $0.contains("portrait-100") })
        #expect(failures.contains { $0.contains("run-a") })
    }

    @Test func manifestFailuresFlagsMissingResultManifest() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            """
            ---
            name: portrait-100
            summary: s
            license: synthetic
            source: generated
            tags: [x]
            ---
            """, to: root.appending(path: "docs/Research/Corpus/portrait-100/manifest.yaml"))

        let failures = IndexCheck.manifestFailures(root: root)
        #expect(failures.contains { $0.contains("Results/run-a") && $0.contains("missing result.yaml") })
    }

    @Test func manifestFailuresFlagsUntrackedFileAndBadRunner() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            """
            ---
            name: portrait-100
            summary: s
            license: synthetic
            source: g
            tags: [x]
            ---
            """, to: root.appending(path: "docs/Research/Corpus/portrait-100/manifest.yaml"))
        try write(
            """
            ---
            schema_version: 1
            date: 2026-01-01
            aski_git_sha: abc
            provenance: [x]
            outputs: [a.csv]
            runner: AskiToolSupport
            ---
            """, to: root.appending(path: "docs/Research/Results/run-a/result.yaml"))
        try write("col", to: root.appending(path: "docs/Research/Results/run-a/a.csv"))
        try write("x", to: root.appending(path: "docs/Research/Results/run-a/stray.txt"))
        let failures = IndexCheck.manifestFailures(root: root)
        #expect(failures.contains { $0.contains("stray.txt") })  // untracked file
        #expect(failures.contains { $0.contains("AskiToolSupport") })  // not an executable runner
    }

    @Test func manifestFailuresPassesCleanFixture() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            """
            ---
            name: portrait-100
            summary: s
            license: synthetic
            source: g
            tags: [x]
            ---
            """, to: root.appending(path: "docs/Research/Corpus/portrait-100/manifest.yaml"))
        try write(
            """
            ---
            schema_version: 1
            date: 2026-01-01
            aski_git_sha: abc
            provenance: [AskiColorLab gamut-sweep]
            outputs: [a.csv]
            runner: AskiColorLab
            datasets: [docs/Research/Corpus/portrait-100]
            ---
            """, to: root.appending(path: "docs/Research/Results/run-a/result.yaml"))
        try write("col", to: root.appending(path: "docs/Research/Results/run-a/a.csv"))
        #expect(IndexCheck.manifestFailures(root: root).isEmpty)
    }

    @Test func lifecycleFailuresPassesCleanFixture() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            """
            ---
            name: portrait-100
            summary: s
            license: synthetic
            source: g
            tags: [x]
            ---
            """, to: root.appending(path: "docs/Research/Corpus/portrait-100/manifest.yaml"))
        try write(
            """
            ---
            schema_version: 1
            date: 2026-01-01
            aski_git_sha: abc
            provenance: [AskiColorLab gamut-sweep]
            outputs: [a.csv]
            runner: AskiColorLab
            datasets: [docs/Research/Corpus/portrait-100]
            ---
            """, to: root.appending(path: "docs/Research/Results/run-a/result.yaml"))
        try write("col", to: root.appending(path: "docs/Research/Results/run-a/a.csv"))

        #expect(IndexCheck.lifecycleFailures(root: root).isEmpty)
    }

    @Test func lifecycleFailuresFlagsNonHiddenTopLevelResearchOutput() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("stray", to: root.appending(path: "docs/Research/stray.csv"))

        let failures = IndexCheck.lifecycleFailures(root: root)
        #expect(failures.contains { $0.contains("docs/Research/stray.csv") })
    }

    @Test func lifecycleFailuresFlagsNonHiddenTopLevelResultOutput() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("metric,value", to: root.appending(path: "docs/Research/Results/metrics.csv"))

        let failures = IndexCheck.lifecycleFailures(root: root)
        #expect(failures.contains { $0.contains("docs/Research/Results/metrics.csv") })
    }

    @Test func lifecycleFailuresIgnoresHiddenLocalClutter() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("local", to: root.appending(path: "docs/Research/.DS_Store"))
        try write("local", to: root.appending(path: "docs/Research/Results/.DS_Store"))

        #expect(IndexCheck.lifecycleFailures(root: root).isEmpty)
    }

    @Test func lifecycleFailuresFlagsResearchNoteExecutionPlaceholder() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            """
            ---
            title: Placeholder
            slug: 2026-01-01-placeholder
            date: 2026-01-01
            status: active
            subsystem: [meta]
            summary: "Placeholder"
            ---

            Generated on <date-executed>.
            """, to: root.appending(path: "docs/Research/2026-01-01-placeholder.md"))

        let failures = IndexCheck.lifecycleFailures(root: root)
        #expect(failures.contains { $0.contains("<date-executed>") })
    }

    @Test func lifecycleFailuresFlagsManifestExecutionPlaceholder() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            """
            ---
            schema_version: 1
            date: 2026-01-01
            aski_git_sha: <V040_SHA>
            provenance: [x]
            outputs: [a.csv]
            ---
            """, to: root.appending(path: "docs/Research/Results/run-a/result.yaml"))

        let failures = IndexCheck.lifecycleFailures(root: root)
        #expect(failures.contains { $0.contains("<V040_SHA>") })
    }

    @Test func manifestFailuresFlagsFileInBothOutputsAndGenerators() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            """
            ---
            name: portrait-100
            summary: s
            license: synthetic
            source: g
            tags: [x]
            ---
            """, to: root.appending(path: "docs/Research/Corpus/portrait-100/manifest.yaml"))
        try write(
            """
            ---
            schema_version: 1
            date: 2026-01-01
            aski_git_sha: abc
            provenance: [x]
            outputs: [a.csv]
            generators: [a.csv]
            ---
            """, to: root.appending(path: "docs/Research/Results/run-a/result.yaml"))
        try write("col", to: root.appending(path: "docs/Research/Results/run-a/a.csv"))
        let failures = IndexCheck.manifestFailures(root: root)
        #expect(failures.contains { $0.contains("a.csv") && $0.contains("both") })
    }
}
