import Foundation
import Testing

@Suite struct LifecycleDocumentationTests {
    @Test func researchLifecycleDocsNameAllowedTopLevelEntriesAndPlaceholders() throws {
        let root = try Self.packageRoot()
        let research = try String(contentsOf: root.appending(path: "docs/Research/README.md"), encoding: .utf8)

        #expect(research.contains("Top-level entries are limited"))
        #expect(research.contains("Execution placeholders"))
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
