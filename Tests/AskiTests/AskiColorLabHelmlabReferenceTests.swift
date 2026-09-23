import ArgumentParser
import Aski
import AskiToolSupport
import CoreGraphics
import Foundation
import Testing
@testable import AskiColorLab

@Suite struct AskiColorLabHelmlabReferenceTests {
    @Test func usageListsHelmlabReferenceCommand() {
        #expect(AskiColorLabCommand.helpMessage().contains("helmlab-reference"))
    }

    @Test func commandWritesReferenceCSVWithStableHeader() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var stderr = ""
        let status = try HelmlabReferenceSubcommand.parse(
            ["--output-dir", directory.path, "--aski-git-sha", "test-sha"]
        ).execute(standardError: { stderr += $0 })
        #expect(status == .success, "stderr: \(stderr)")

        let csv = directory.appending(path: HelmlabReferenceCommand.referenceOutputFileName)
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let expectedHeader =
            (CSVSchema.sharedPrefixColumns
            + HelmlabReferenceCommand.referenceMetricColumns).joined(separator: ",")
        #expect(contents.split(separator: "\n").first.map(String.init) == expectedHeader)
    }

    @Test func referenceCSVContainsPrimariesAndGridRows() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try HelmlabReferenceSubcommand.parse(
            ["--output-dir", directory.path, "--aski-git-sha", "test-sha"]
        ).execute(standardError: { _ in })

        let csv = directory.appending(path: HelmlabReferenceCommand.referenceOutputFileName)
        let lines = try String(contentsOf: csv, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
        // 1 header + 5 material primaries + 125 grid points.
        #expect(lines.count == 1 + 5 + 125)
        #expect(lines.contains { $0.contains("material_white") })
        #expect(lines.contains { $0.contains("gamut_grid") })
        // Provenance is recorded on every data row.
        #expect(lines.dropFirst().allSatisfy { $0.contains("v21") })
    }

    @Test func twoIdenticalRunsProduceByteIdenticalCSV() throws {
        let first = try temporaryDirectory()
        let second = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        for directory in [first, second] {
            _ = try HelmlabReferenceSubcommand.parse(
                ["--output-dir", directory.path, "--aski-git-sha", "test-sha"]
            ).execute(standardError: { _ in })
        }
        let a = try Data(contentsOf: first.appending(path: HelmlabReferenceCommand.referenceOutputFileName))
        let b = try Data(contentsOf: second.appending(path: HelmlabReferenceCommand.referenceOutputFileName))
        #expect(a == b)
    }

    @Test func recoveryCSVHasStableHeaderAndScoresThreePolicies() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var stderr = ""
        let status = try HelmlabReferenceSubcommand.parse(
            ["--output-dir", directory.path, "--aski-git-sha", "test-sha"]
        ).execute(standardError: { stderr += $0 })
        #expect(status == .success, "stderr: \(stderr)")

        let csv = directory.appending(path: HelmlabReferenceCommand.recoveryOutputFileName)
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let expectedHeader =
            (CSVSchema.sharedPrefixColumns
            + HelmlabReferenceCommand.recoveryColumns).joined(separator: ",")
        #expect(lines.first.map(String.init) == expectedHeader)
        // Every recovery case is scored under all three policies.
        #expect(contents.contains("oklabEuclidean"))
        #expect(contents.contains("helmlabEuclidean"))
        #expect(contents.contains("helmlabCompressed"))
        // `recovered` is a real boolean ground-truth column, not a sentinel.
        #expect(lines.dropFirst().allSatisfy { $0.hasSuffix(",true") || $0.hasSuffix(",false") })
    }

    @Test func twoIdenticalRunsProduceByteIdenticalRecoveryCSV() throws {
        let first = try temporaryDirectory()
        let second = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        for directory in [first, second] {
            _ = try HelmlabReferenceSubcommand.parse(
                ["--output-dir", directory.path, "--aski-git-sha", "test-sha"]
            ).execute(standardError: { _ in })
        }
        let a = try Data(contentsOf: first.appending(path: HelmlabReferenceCommand.recoveryOutputFileName))
        let b = try Data(contentsOf: second.appending(path: HelmlabReferenceCommand.recoveryOutputFileName))
        #expect(a == b)
    }

    // MARK: - Large-ΔE visual review (Task 7 Step 3b)

    @Test func visualReviewWritesAllSixStressArtifacts() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var stderr = ""
        let status = try HelmlabReferenceSubcommand.parse(
            ["--output-dir", directory.path, "--aski-git-sha", "test-sha"]
        ).execute(standardError: { stderr += $0 })
        #expect(status == .success, "stderr: \(stderr)")

        for name in HelmlabReferenceCommand.reviewFileNames {
            let url = directory.appending(path: name)
            #expect(FileManager.default.fileExists(atPath: url.path), "missing \(name)")
        }
    }

    @Test func stressReviewHTMLIsByteIdenticalAcrossRuns() throws {
        let first = try temporaryDirectory()
        let second = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        for directory in [first, second] {
            _ = try HelmlabReferenceSubcommand.parse(
                ["--output-dir", directory.path, "--aski-git-sha", "test-sha"]
            ).execute(standardError: { _ in })
        }
        let name = HelmlabReferenceCommand.reviewFileNames[0]
        let a = try Data(contentsOf: first.appending(path: name))
        let b = try Data(contentsOf: second.appending(path: name))
        #expect(a == b)
    }

    @Test func corpusReviewProducesHTMLForProvidedImage() throws {
        let output = try temporaryDirectory()
        let corpus = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: corpus)
        }
        // Tiny generated PNG → the corpus loader reads it and emits per-policy HTML.
        let pngURL = corpus.appending(path: "tiny.png")
        try writeTinyPNG(to: pngURL)

        var stderr = ""
        let status = try HelmlabReferenceSubcommand.parse(
            [
                "--output-dir", output.path,
                "--review-corpus", corpus.path,
                "--aski-git-sha", "test-sha",
            ]
        ).execute(standardError: { stderr += $0 })
        #expect(status == .success, "stderr: \(stderr)")

        let corpusHTML = try FileManager.default
            .contentsOfDirectory(atPath: output.path)
            .filter { $0.hasPrefix("helmlab-corpus-tiny-") && $0.hasSuffix(".html") }
        // One HTML per policy (oklabEuclidean / helmlabEuclidean / helmlabCompressed).
        #expect(corpusHTML.count == 3, "got \(corpusHTML.sorted())")
    }

    private func writeTinyPNG(to url: URL) throws {
        let w = 8, h = 8
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        try DemoImageIO.writePNG(ctx.makeImage()!, to: url.path)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AskiColorLabHelmlabReferenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
