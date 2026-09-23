import Foundation
import Testing
@testable import AskiColorLab

@Suite struct AskiColorLabCSVTests {
    @Test func sharedPrefixHasExactOrderedColumnNames() {
        #expect(
            CSVSchema.sharedPrefixColumns == [
                "schema_version",
                "command",
                "aski_git_sha",
                "run_seed",
                "sample_id",
                "fixture_id",
                "policy",
                "input_space",
                "input_components",
                "output_space",
                "output_components",
            ])
    }

    @Test func formatComponentsJoinsWithSemicolonAndSixDecimalPlaces() {
        let formatted = CSVSchema.formatComponents([1.0, 0.5, 0.0])
        #expect(formatted == "1.000000;0.500000;0.000000")
    }

    @Test func formatFloatUsesSixDecimalPlaces() {
        #expect(CSVSchema.formatFloat(0.1234567) == "0.123457")
        #expect(CSVSchema.formatFloat(-1.0) == "-1.000000")
        #expect(CSVSchema.formatFloat(.zero) == "0.000000")
    }

    @Test func writerEmitsHeaderOnInitAndOneLinePerRow() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "out.csv")

        let writer = try CSVWriter(
            url: url,
            columns: CSVSchema.sharedPrefixColumns + ["extra_metric"]
        )
        try writer.writeRow([
            "1", "sampling-ablation", "deadbeef", "0", "0",
            "fixture-a", "encodedAverageLegacy",
            "sRGB", "0.500000;0.500000;0.500000",
            "linearSRGB", "0.214041;0.214041;0.214041",
            "1.234567",
        ])
        try writer.writeRow([
            "1", "sampling-ablation", "deadbeef", "0", "1",
            "fixture-a", "linearLightAverage",
            "sRGB", "0.500000;0.500000;0.500000",
            "linearSRGB", "0.214041;0.214041;0.214041",
            "1.234567",
        ])
        try writer.close()

        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 4)  // header + 2 rows + trailing newline → 3 newline-separated chunks plus empty tail
        #expect(lines[0].hasPrefix("schema_version,command,"))
        #expect(lines[0].hasSuffix(",extra_metric"))
        #expect(lines[1].contains(",encodedAverageLegacy,"))
        #expect(lines[2].contains(",linearLightAverage,"))
        #expect(lines.last == "")
    }

    @Test func writerRejectsColumnCountMismatch() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "out.csv")

        let writer = try CSVWriter(url: url, columns: ["a", "b", "c"])
        #expect(throws: CSVWriterError.self) {
            try writer.writeRow(["one", "two"])
        }
        try writer.close()
    }

    @Test func writerRejectsExistingDirectoryWithoutDeletingContents() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "out.csv")
        let sentinel = url.appending(path: "keep.txt")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try "keep".write(to: sentinel, atomically: true, encoding: .utf8)

        #expect(throws: CSVWriterError.outputPathIsDirectory(url.path)) {
            _ = try CSVWriter(url: url, columns: ["a"])
        }
        #expect(FileManager.default.fileExists(atPath: sentinel.path))
    }

    @Test func writerRejectsValuesContainingForbiddenCharacters() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "out.csv")

        let writer = try CSVWriter(url: url, columns: ["a", "b"])
        #expect(throws: CSVWriterError.self) {
            try writer.writeRow(["safe", "has,comma"])
        }
        #expect(throws: CSVWriterError.self) {
            try writer.writeRow(["has\nnewline", "safe"])
        }
        #expect(throws: CSVWriterError.self) {
            try writer.writeRow(["has\"quote", "safe"])
        }
        try writer.close()
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AskiColorLabCSVTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
