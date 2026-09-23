import Foundation

// Regenerates the docs/Research/ index from each note's YAML front-matter:
// the README "## Index" block (between markers) and the machine-readable
// docs/Research/index.json. Run from the package root.
//
//   swift run BuildResearchIndex          # rewrite the generated artifacts
//   swift run BuildResearchIndex --check  # fail (non-zero) on drift or schema violations

let arguments = Array(CommandLine.arguments.dropFirst())
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

if arguments.contains("--check") {
    let failures = IndexCheck.validate(root: root)
    if failures.isEmpty {
        print("Research registry: OK")
        exit(0)
    }
    die("Research registry check failed:\n" + failures.map { "  - \($0)" }.joined(separator: "\n"))
}

do {
    let notes = try ResearchRegistry.discover(root: root)
    let dir = ResearchRegistry.researchDir(root: root)

    let stores = IndexCheck.storeEntries(root: root)
    let readmeURL = dir.appending(path: "README.md")
    let readme = try String(contentsOf: readmeURL, encoding: .utf8)
    let updated = try IndexRenderer.spliceREADME(readme, block: IndexRenderer.readmeIndexBlock(notes: notes, corpora: stores.corpora, results: stores.results))
    if updated != readme {
        try updated.write(to: readmeURL, atomically: true, encoding: .utf8)
        print("Updated docs/Research/README.md index block")
    }

    let jsonURL = dir.appending(path: "index.json")
    let json = try IndexRenderer.indexJSON(notes: notes, corpora: stores.corpora, results: stores.results)
    if json != ((try? String(contentsOf: jsonURL, encoding: .utf8)) ?? "") {
        try json.write(to: jsonURL, atomically: true, encoding: .utf8)
        print("Wrote docs/Research/index.json")
    }

    print("Indexed \(notes.count) research notes.")
} catch {
    die("BuildResearchIndex failed: \(error)")
}
