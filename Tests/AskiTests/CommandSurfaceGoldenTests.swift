import ArgumentParser
import Foundation
import Testing

import AskiAccessLab
import AskiCLI
import AskiColorLab
import AskiDecolorLab
import AskiHDRLab
import AskiMotionLab
import AskiPresetLab
import AskiToolSupport
import AskiVideoLab

/// Guards the ASTSK-59 / PR #62 drift class A: the CLI command surface of the
/// Aski tools (subcommands, options, flags) silently diverging from what the
/// prose docs describe. The audit added several then-missing `AskiColorLab` /
/// `AskiMotionLab` subcommands to README and `architecture.md` by hand, with no
/// guard to catch the omission.
///
/// Each tool's structured help — ArgumentParser's `_dumpHelp()` JSON, the machine
/// -readable form behind `--experimental-dump-help` — is normalized and byte
/// -compared to a committed golden. Any subcommand / option / flag change fails
/// this test, surfacing the drift so the author updates the prose docs. It does
/// **not** assert the docs mention each command; it makes surface changes visible
/// and reviewed, the same tripwire role as the `repo-map` byte-diff.
///
/// The published `aski` product owns the complete canonical tree. Historical
/// `Aski*Lab` products remain replay-only executables over the same importable lab
/// modules. Both canonical namespaces and replay roots stay in this golden.
///
/// Regenerate with `ASKI_RECORD_COMMAND_SURFACE=1` **only** for an intentional,
/// reviewed CLI change (after updating the prose docs to match).
@Suite struct CommandSurfaceGoldenTests {
    /// Command-surface name → backing executable target → help dumper. A target
    /// can expose more than one surface, as `AskiCLIRunner` does for the root and
    /// its canonical namespaces. Kept honest against `Package.swift` by
    /// `toolListMatchesPackageManifest`.
    static var tools: [(name: String, targetName: String, dumpHelp: () -> String)] {
        [
            ("AskiAccessLab", "AskiAccessLabRunner", AskiAccessLabCommand._dumpHelp),
            ("AskiColorLab", "AskiColorLabRunner", AskiColorLabCommand._dumpHelp),
            ("AskiDecolorLab", "AskiDecolorLabRunner", AskiDecolorLabCommand._dumpHelp),
            ("aski", "AskiCLIRunner", AskiCLI.AskiCommand._dumpHelp),
            ("aski lab", "AskiCLIRunner", AskiCLI.LabCommand._dumpHelp),
            ("aski lab accessibility", "AskiCLIRunner", AskiCLI.AccessibilityLabCommand._dumpHelp),
            ("aski lab color", "AskiCLIRunner", AskiCLI.ColorLabCommand._dumpHelp),
            ("aski lab decolor", "AskiCLIRunner", AskiCLI.DecolorLabCommand._dumpHelp),
            ("aski lab hdr", "AskiCLIRunner", AskiCLI.HDRLabCommand._dumpHelp),
            ("aski lab motion", "AskiCLIRunner", AskiCLI.MotionLabCommand._dumpHelp),
            ("aski lab preset", "AskiCLIRunner", AskiCLI.PresetLabCommand._dumpHelp),
            ("aski lab video", "AskiCLIRunner", AskiCLI.VideoLabCommand._dumpHelp),
            ("AskiDemo", "AskiDemo", AskiDemoCommand._dumpHelp),
            ("AskiHDRLab", "AskiHDRLabRunner", AskiHDRLabCommand._dumpHelp),
            ("AskiMotionLab", "AskiMotionLabRunner", AskiMotionLab.MotionLabCommand._dumpHelp),
            ("AskiPresetLab", "AskiPresetLabRunner", AskiPresetLabCommand._dumpHelp),
            ("AskiTileMatrix", "AskiTileMatrix", TileMatrixCommand._dumpHelp),
            ("AskiVideoLab", "AskiVideoLabRunner", AskiVideoLab.VideoLabCommand._dumpHelp),
        ]
    }

    static var goldenURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Goldens/command-surface.json")
    }

    static var packageManifestURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/AskiTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Package.swift")
    }

    /// Build the normalized, deterministic surface: each tool's dump-help JSON
    /// parsed and re-serialized with sorted keys (arrays keep ArgumentParser's
    /// declaration order, which is stable). Also asserts every tool's
    /// `serializationVersion` is 0 so an ArgumentParser help-schema bump fails
    /// loudly here instead of silently rewriting the golden.
    static func currentSurface() throws -> Data {
        var root: [String: Any] = [:]
        for tool in tools {
            let object = try JSONSerialization.jsonObject(with: Data(tool.dumpHelp().utf8))
            let dict = try #require(object as? [String: Any], "\(tool.name): dump-help was not a JSON object")
            let version = dict["serializationVersion"] as? Int
            #expect(
                version == 0,
                """
                \(tool.name): ArgumentParser dump-help serializationVersion is \(String(describing: version)), \
                not 0 — the help schema changed. Review the new shape before re-recording the golden.
                """
            )
            root[tool.name] = object
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .prettyPrinted])
    }

    @Test func commandSurfaceMatchesGolden() throws {
        let current = try Self.currentSurface()
        let url = Self.goldenURL

        if ProcessInfo.processInfo.environment["ASKI_RECORD_COMMAND_SURFACE"] == "1" {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try current.write(to: url)
            return
        }

        let golden = try Data(contentsOf: url)
        #expect(
            current == golden,
            """
            Aski tool command surface drifted from the committed golden. If this is an intentional CLI \
            change, update the prose docs (README.md / docs/architecture.md) to match, then re-record: \
            ASKI_RECORD_COMMAND_SURFACE=1 xcrun swift test --filter CommandSurfaceGoldenTests
            """
        )
    }

    /// A new `Aski*` executable target must not enter the repo without also
    /// entering the surface check. Every `.executableTarget` named `Aski*` (bar
    /// the benchmark harness) must back at least one entry in `tools`.
    @Test func toolListMatchesPackageManifest() throws {
        let manifest = try String(contentsOf: Self.packageManifestURL, encoding: .utf8)
        let declared = Self.executableAskiToolTargets(in: manifest)
        let coveredTargets = Set(Self.tools.map(\.targetName))

        #expect(
            declared == coveredTargets,
            """
            Command-surface target map is out of sync with Package.swift executable targets.
            Declared in manifest: \(declared.sorted())
            Covered by this test:  \(coveredTargets.sorted())
            Add a surface with its backing target to CommandSurfaceGoldenTests.tools, then re-record the golden.
            """
        )
    }

    /// Names of every `.executableTarget(name: "Aski…")` in the manifest, minus the
    /// non-CLI benchmark harness. `AskiToolSupport` is a library target, so it never
    /// matches `.executableTarget`.
    static func executableAskiToolTargets(in manifest: String) -> Set<String> {
        let pattern = #"\.executableTarget\(\s*name:\s*"(Aski[A-Za-z0-9]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(manifest.startIndex..<manifest.endIndex, in: manifest)
        var names: Set<String> = []
        for match in regex.matches(in: manifest, range: range) {
            guard let r = Range(match.range(at: 1), in: manifest) else { continue }
            names.insert(String(manifest[r]))
        }
        names.remove("AskiBenchmarks")  // a Benchmark harness, not a CLI tool
        return names
    }
}
