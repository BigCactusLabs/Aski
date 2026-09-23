import Aski
import ArgumentParser
import Foundation
import Testing
@testable import AskiColorLab

@Suite struct PaletteMatchAblationHelmlabTests {
    @Test func ablationCSVIncludesBothHelmlabPolicyRows() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "PaletteMatchAblationHelmlabTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let status = try PaletteMatchAblationSubcommand.parse(
            ["--output-dir", directory.path, "--aski-git-sha", "test-sha"]
        ).execute(standardError: { _ in })
        #expect(status == .success)

        let csv = directory.appending(path: PaletteMatchAblationCommand.outputFileName)
        let contents = try String(contentsOf: csv, encoding: .utf8)
        #expect(contents.contains("helmlabEuclidean"))
        #expect(contents.contains("helmlabCompressed"))
        // The pre-existing OKLab/HyAB probe rows must still be present.
        #expect(contents.contains("oklabEuclidean"))
        #expect(contents.contains("oklabHyAB"))
    }
}
