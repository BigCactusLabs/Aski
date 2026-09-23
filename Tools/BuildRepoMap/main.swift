import Foundation

// Regenerates docs/repo-map.generated.md — a source-scanned index of top-level
// declarations in Sources/Aski/, grouped by directory and file. Run from the package root.
//
//   swift run BuildRepoMap          # rewrite the generated artifact
//   swift run BuildRepoMap --check  # fail (non-zero) on drift

let arguments = Array(CommandLine.arguments.dropFirst())
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

if arguments.contains("--check") {
    let failures = IndexCheck.driftFailures(root: root)
    if failures.isEmpty {
        print("Repo map: OK")
        exit(0)
    }
    die("Repo map check failed:\n" + failures.map { "  - \($0)" }.joined(separator: "\n"))
}

do {
    let entries = try RepoMap.scan(root: root)
    let rendered = RepoMap.render(entries: entries)
    let url = RepoMap.outputURL(root: root)
    if (try? String(contentsOf: url, encoding: .utf8)) != rendered {
        try rendered.write(to: url, atomically: true, encoding: .utf8)
        print("Wrote \(RepoMap.outputRelativePath)")
    }
    print("Indexed \(entries.count) source files.")
} catch {
    die("BuildRepoMap failed: \(error)")
}
