import Foundation

/// Drift validation for the generated repo map. Mirrors `BuildResearchIndex`'s
/// `IndexCheck`: collects problems as human-readable strings rather than throwing, so the
/// `swift test` gate (`RepoMapRegistryTests`) reports the issue in-process — the same code
/// path as `swift run BuildRepoMap --check`, so the gate can never drift from the tool.
enum IndexCheck {
    /// Freshly render the map from a source scan.
    static func render(root: URL) throws -> String {
        RepoMap.render(entries: try RepoMap.scan(root: root))
    }

    /// Drift between the committed `docs/repo-map.generated.md` and a fresh render.
    /// Empty result means in sync.
    static func driftFailures(root: URL) -> [String] {
        do {
            let expected = try render(root: root)
            guard let committed = try? String(contentsOf: RepoMap.outputURL(root: root), encoding: .utf8) else {
                return ["\(RepoMap.outputRelativePath) is missing — run `swift run BuildRepoMap`"]
            }
            if committed != expected {
                return ["\(RepoMap.outputRelativePath) is out of date — run `swift run BuildRepoMap`"]
            }
            return []
        } catch {
            return ["repo-map drift check could not run: \(error)"]
        }
    }
}
