import Foundation
import Testing
@testable import AskiDecolorLab
@testable import BuildResearchIndex
import Aski

@Suite struct AskiDecolorLabRunTests {

    // MARK: - Task A7: Results writers

    @Test func csvHeaderMatchesLockedSchema() {
        #expect(
            DecolorLabResults.csvHeader == [
                "schema_version", "command", "aski_git_sha", "fixture_id",
                "palette_id", "row", "col", "character", "ink_fraction",
                "ink_model", "fg_hex", "bg_hex", "perceived_hex", "source_hex",
                "deficiency", "l_fidelity", "chroma_fidelity", "oklab_delta",
            ])
    }

    @Test func csvRoundTripsOracleRow() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        var row = OracleRow.zero
        row.schemaVersion = "1"
        row.command = "swift run AskiDecolorLab evaluate"
        row.askiGitSHA = "abc123"
        row.fixtureID = "hue-stripes"
        row.paletteID = "monochrome"
        row.row = 0
        row.col = 1
        row.character = "@"
        row.inkFraction = 0.5
        row.inkModel = "relative_ramp"
        row.fgHex = "#FFFFFF"
        row.bgHex = "#101010"
        row.perceivedHex = "#888888"
        row.sourceHex = "#777777"
        row.deficiency = "none"
        row.lFidelity = 0.123456
        row.chromaFidelity = 0.654321
        row.oklabDelta = 0.111111

        try DecolorLabResults.writeCSV(rows: [row], outputDirectory: dir)

        let csv = try String(
            contentsOf: dir.appendingPathComponent("perceived_fidelity.csv"),
            encoding: .utf8
        )
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // header + 1 data line + trailing newline produces 3 split elements,
        // or the trailing newline might cause an empty last element — just check counts
        #expect(lines.count >= 2)
        #expect(lines[0] == DecolorLabResults.csvHeader.joined(separator: ","))

        // Split the data line on commas and assert values at the correct column indices,
        // so a header/body transposition would fail this test.
        let header = DecolorLabResults.csvHeader
        let dataFields = lines[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(dataFields.count == header.count)
        func col(_ name: String) -> Int { header.firstIndex(of: name)! }
        #expect(dataFields[col("schema_version")] == "1")
        #expect(dataFields[col("aski_git_sha")] == "abc123")
        #expect(dataFields[col("fixture_id")] == "hue-stripes")
        #expect(dataFields[col("palette_id")] == "monochrome")
        #expect(dataFields[col("row")] == "0")
        #expect(dataFields[col("col")] == "1")
        #expect(dataFields[col("character")] == "@")
        #expect(dataFields[col("ink_model")] == "relative_ramp")
        #expect(dataFields[col("deficiency")] == "none")
        // Floats must be 6-decimal formatted
        #expect(dataFields[col("l_fidelity")] == "0.123456")
        #expect(dataFields[col("chroma_fidelity")] == "0.654321")
        #expect(dataFields[col("oklab_delta")] == "0.111111")
    }

    @Test func csvLineQuotesSpecialCharacterField() {
        // OracleRow whose character field is a CSV delimiter or a quote.
        // RFC-4180: comma → `","`, double-quote → `""""`

        var commaRow = OracleRow.zero
        commaRow.character = ","
        let commaLine = DecolorLabResults.csvLine(commaRow)
        let commaFields = commaLine.components(separatedBy: ",")
        // The header tells us which field index "character" occupies.
        let charIdx = DecolorLabResults.csvHeader.firstIndex(of: "character")!
        // The comma field is RFC-4180 quoted, so the raw CSV text at that position
        // is `","` — three chars that straddle two comma-splits. We verify the full
        // line contains the quoted form and that splitting on comma gives the right count.
        #expect(commaLine.contains("\",\""))
        // The total comma-count for an 18-column row where one field is `","` is 17+1=18,
        // so splitting on "," yields 19 parts (header.count + 1).
        #expect(commaFields.count == DecolorLabResults.csvHeader.count + 1)
        _ = charIdx  // used above for documentation; suppress unused-variable warning

        var quoteRow = OracleRow.zero
        quoteRow.character = "\""
        let quoteLine = DecolorLabResults.csvLine(quoteRow)
        // The `"` field must be emitted as `""""` (open-quote, escaped-quote, close-quote)
        #expect(quoteLine.contains("\"\"\"\""))
    }

    @Test func manifestParsesThroughResultManifest() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try DecolorLabResults.writeManifest(
            outputDirectory: dir,
            date: "2026-06-08",
            gitSHA: "abc",
            command: "swift run AskiDecolorLab evaluate --output-dir x",
            summary: "10 rows. monochrome mean_l=0.2000. ansi16 mean_l=0.1000. fullColor mean_l=0.0500. Gate: PASS."
        )

        let text = try String(
            contentsOf: dir.appendingPathComponent("result.yaml"),
            encoding: .utf8
        )
        let manifest = try ResultManifest.from(try FrontMatterParser.parse(text))
        #expect(manifest.runner == "AskiDecolorLab")
        #expect(manifest.outputs.contains("perceived_fidelity.csv"))
        #expect(manifest.schemaVersion == "1")
        #expect(manifest.date == "2026-06-08")
        #expect(manifest.askiGitSha == "abc")
        #expect(manifest.provenance == ["AskiDecolorLab evaluate"])
    }

    // MARK: - Task A8: CLI run + check

    @Test func evaluateWritesArtifacts() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // columns >= 48: no-downscale invariant for 96px fixtures
        let args = DecolorLabArguments(
            outputDirectory: dir.path,
            columns: 64,
            backgroundHex: "#101010",
            gitShaOverride: "test-sha"
        )
        let status = DecolorLabCLI.run(
            arguments: args,
            standardOutput: { _ in },
            standardError: { _ in },
            date: "2026-06-08"
        )

        #expect(status == .success)
        #expect(
            FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("perceived_fidelity.csv").path))
        #expect(
            FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("result.yaml").path))
    }

    /// Verify that `check` runs end-to-end without crashing and returns either
    /// `.success` (PASS) or `.failure` (KILL) — both are valid designed outcomes.
    /// The gate verdict depends on real oracle data; a KILL is NOT a bug.
    @Test func checkRunsEndToEndWithoutError() throws {
        // columns >= 48 to satisfy no-downscale invariant for 96px fixtures
        let args = DecolorLabArguments(
            outputDirectory: "/tmp/unused",
            columns: 64,
            backgroundHex: "#101010",
            gitShaOverride: "test-sha"
        )
        var output = ""
        let status = DecolorLabCLI.check(
            arguments: args,
            standardOutput: { output += $0 },
            standardError: { _ in }
        )
        // Must be one of the two designed outcomes — not .usage or .ioError
        #expect(status == .success || status == .failure)
        // Output must contain gate detail (discrimination + 2AFC sections)
        #expect(output.contains("discrimination:"))
        #expect(output.contains("2AFC:"))
        #expect(output.contains("gate verdict:"))
    }

    @Test func runRejectsInvalidBackgroundHex() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        var stderr = ""
        let args = DecolorLabArguments(
            outputDirectory: dir.path,
            columns: 64,
            backgroundHex: "notahex",
            gitShaOverride: "test-sha"
        )
        let status = DecolorLabCLI.run(
            arguments: args,
            standardOutput: { _ in },
            standardError: { stderr += $0 },
            date: "2026-06-08"
        )
        #expect(status == .usage)
        #expect(!stderr.isEmpty)
        #expect(
            !FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("perceived_fidelity.csv").path))
    }

    @Test func checkRejectsInvalidBackgroundHex() {
        var stderr = ""
        let args = DecolorLabArguments(
            outputDirectory: "/tmp/unused",
            columns: 64,
            backgroundHex: "GGGGGG",
            gitShaOverride: "test-sha"
        )
        let status = DecolorLabCLI.check(
            arguments: args,
            standardOutput: { _ in },
            standardError: { stderr += $0 }
        )
        #expect(status == .usage)
        #expect(!stderr.isEmpty)
    }

    // MARK: - Helpers

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AskiDecolorLabRunTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
