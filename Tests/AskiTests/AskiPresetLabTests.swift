import CoreGraphics
import Foundation
import Testing
import Aski
@testable import AskiPresetLab
import AskiToolSupport

@Suite struct AskiPresetLabTests {

    // MARK: - Candidate matrix

    @Test func expandProducesCharsetMajorCartesianProduct() {
        let matrix = PresetABMatrix.expand(charsets: [.standard, .minimal], columnCounts: [60, 80])
        #expect(
            matrix == [
                PresetCandidate(charset: .standard, columns: 60),
                PresetCandidate(charset: .standard, columns: 80),
                PresetCandidate(charset: .minimal, columns: 60),
                PresetCandidate(charset: .minimal, columns: 80),
            ])
    }

    @Test func expandDedupesRepeatedPairs() {
        let matrix = PresetABMatrix.expand(charsets: [.standard, .standard], columnCounts: [80, 80])
        #expect(matrix == [PresetCandidate(charset: .standard, columns: 80)])
    }

    // MARK: - Draft preset knobs (the one-way-door locks)

    @Test func draftPresetSetsOnlyItsProductionOptions() {
        let options = testPreset(contrast: 0.15).renderingOptions()
        #expect(options.contrast == 0.15)
        #expect(options.brightness == 0)
        #expect(options.coverage == 0)
        #expect(options.density == 0)
        #expect(options.edgeEmphasis == 0)
    }

    @Test func draftPresetConverterUsesFixedDuotoneInDisplayP3() {
        let converter = testPreset().makeConverter(charset: .standard)
        #expect(converter.colorSpace == .displayP3)
        #expect(converter.palette.content.isPassThrough == false)
        #expect(converter.palette.content.colors?.count == 2)
    }

    // MARK: - Descriptive stats

    @Test func candidateStatsCountsDistinctGlyphsAndCells() {
        let cell: (Character) -> ASCIICell = { character in
            ASCIICell(character: character, displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
        }
        let grid = ASCIIGrid(
            cells: [
                [cell("@"), cell("."), cell("@")],
                [cell(" "), cell("@"), cell(".")],
            ],
            colorSpace: .sRGB
        )
        let stats = CandidateStats.from(grid: grid)
        #expect(stats.columns == 3)
        #expect(stats.rows == 2)
        #expect(stats.cellCount == 6)
        #expect(stats.distinctGlyphs == 3)  // '@', '.', ' '
    }

    // MARK: - End-to-end run

    @Test func runWritesCandidatePNGsContactSheetAndManifest() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("portrait.png")
        try DemoImageIO.writePNG(syntheticImage(width: 48, height: 64), to: input.path)
        let outDir = dir.appendingPathComponent("out")

        var output = ""
        let status = PresetLabCLI.run(
            arguments: baseArguments(
                inputPath: input.path,
                outputDirectory: outDir.path,
                charsets: [.standard, .minimal],
                columnCounts: [24, 32]
            ),
            standardOutput: { output += $0 },
            standardError: { _ in },
            date: "2026-07-06"
        )

        #expect(status == .success)
        for slug in ["standard_cols-24", "standard_cols-32", "minimal_cols-24", "minimal_cols-32"] {
            #expect(
                FileManager.default.fileExists(
                    atPath: outDir.appendingPathComponent("candidate_\(slug).png").path),
                "missing candidate render for \(slug)")
        }
        #expect(
            FileManager.default.fileExists(atPath: outDir.appendingPathComponent("contact-sheet.png").path))
        #expect(
            FileManager.default.fileExists(atPath: outDir.appendingPathComponent("manifest.json").path))
    }

    @Test func runRejectsInvalidInkHexAsUsageError() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("portrait.png")
        try DemoImageIO.writePNG(syntheticImage(width: 16, height: 16), to: input.path)

        var stderr = ""
        var args = baseArguments(
            inputPath: input.path,
            outputDirectory: dir.appendingPathComponent("out").path,
            charsets: [.standard],
            columnCounts: [24]
        )
        args.inkHex = "notahexcolor"
        let status = PresetLabCLI.run(
            arguments: args,
            standardOutput: { _ in },
            standardError: { stderr += $0 },
            date: "2026-07-06"
        )

        #expect(status == .usage)
        #expect(!stderr.isEmpty)
    }

    @Test func runReportsIOErrorForMissingInput() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let status = PresetLabCLI.run(
            arguments: baseArguments(
                inputPath: dir.appendingPathComponent("does-not-exist.png").path,
                outputDirectory: dir.appendingPathComponent("out").path,
                charsets: [.standard],
                columnCounts: [24]
            ),
            standardOutput: { _ in },
            standardError: { _ in },
            date: "2026-07-06"
        )
        #expect(status == .ioError)
    }

    // MARK: - Helpers

    private func testPreset(contrast: Float = 0.15) -> DraftVesperPreset {
        DraftVesperPreset(
            ink: PaletteColor(SIMD3<Float>(0.90, 0.88, 0.82), colorSpace: .sRGB),
            accent: PaletteColor(SIMD3<Float>(0.62, 0.17, 0.14), colorSpace: .displayP3),
            contrast: contrast
        )
    }

    private func baseArguments(
        inputPath: String,
        outputDirectory: String,
        charsets: [Charset],
        columnCounts: [Int]
    ) -> PresetLabArguments {
        PresetLabArguments(
            inputPath: inputPath,
            outputDirectory: outputDirectory,
            charsets: charsets,
            columnCounts: columnCounts,
            inkHex: "#E8E2D2",
            accentHex: "#9E2B25",
            background: BackgroundColor(argument: "#161616")!,
            contrast: 0.15,
            fontSize: 8,
            scale: 1,
            gitShaOverride: "test-sha"
        )
    }

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AskiPresetLabTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func syntheticImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.9, green: 0.85, blue: 0.8, alpha: 1))
        context.fillEllipse(in: CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        return context.makeImage()!
    }
}
