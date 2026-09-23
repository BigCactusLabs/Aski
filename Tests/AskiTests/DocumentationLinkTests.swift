import Foundation
import Testing

@Suite struct DocumentationLinkTests {
    @Test func localMarkdownLinksResolveOutsideFencedCodeBlocks() throws {
        let root = try Self.packageRoot()
        let markdownFiles = try Self.documentationFiles(relativeTo: root)
        var failures: [String] = []

        for file in markdownFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            let stripped = Self.strippingFencedCodeBlocks(from: text)
            for link in Self.markdownLinks(in: stripped) where Self.shouldCheck(link.target) {
                let target = Self.pathTarget(from: link.target)
                guard !target.isEmpty else { continue }

                let resolved = URL(fileURLWithPath: target, relativeTo: file.deletingLastPathComponent())
                    .standardizedFileURL
                if !FileManager.default.fileExists(atPath: resolved.path) {
                    failures.append("\(Self.relativePath(file, from: root)):\(link.line): \(link.target)")
                }
            }
        }

        if !failures.isEmpty {
            Issue.record("Broken local markdown links:\n\(failures.joined(separator: "\n"))")
        }
        #expect(failures.isEmpty)
    }

    private static func documentationFiles(relativeTo root: URL) throws -> [URL] {
        let roots = [
            "README.md",
            "CONTRIBUTING.md",
            "DESIGN.md",
            "AGENTS.md",
            "CLAUDE.md",
            "Sources/Aski/Aski.docc",
            "docs",
        ]

        var files: [URL] = []
        for path in roots {
            let url = root.appending(path: path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                while let item = enumerator?.nextObject() as? URL {
                    guard item.pathExtension == "md" else { continue }
                    files.append(item)
                }
            } else if url.pathExtension == "md" {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func strippingFencedCodeBlocks(from text: String) -> String {
        var output = ""
        var inFence = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                output.append("\n")
            } else if inFence {
                output.append("\n")
            } else {
                output.append(contentsOf: line)
                output.append("\n")
            }
        }
        return output
    }

    private static func markdownLinks(in text: String) -> [(target: String, line: Int)] {
        let pattern = #"(?<!!)(?<!\\)\[[^\]\n]+\]\(([^\)\n]+)\)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            let target = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            let line = text[..<range.lowerBound].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            return (target, line)
        }
    }

    private static func shouldCheck(_ target: String) -> Bool {
        let lowercased = target.lowercased()
        return !lowercased.hasPrefix("http://")
            && !lowercased.hasPrefix("https://")
            && !lowercased.hasPrefix("mailto:")
            && !lowercased.hasPrefix("app://")
            && !lowercased.hasPrefix("file://")
            && !target.hasPrefix("#")
            && !target.hasPrefix("<doc:")
    }

    private static func pathTarget(from rawTarget: String) -> String {
        let withoutFragment =
            rawTarget.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""
        let unwrapped: String
        if withoutFragment.hasPrefix("<"), withoutFragment.hasSuffix(">") {
            unwrapped = String(withoutFragment.dropFirst().dropLast())
        } else {
            unwrapped = withoutFragment
        }
        return unwrapped.removingPercentEncoding ?? unwrapped
    }

    private static func relativePath(_ url: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appending(path: "Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
