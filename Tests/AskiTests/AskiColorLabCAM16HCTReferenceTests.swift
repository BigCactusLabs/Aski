import ArgumentParser
import Aski
import Foundation
import Testing
@testable import AskiColorLab

@Suite struct AskiColorLabCAM16HCTReferenceTests {
    @Test func usageListsCAM16HCTReferenceCommand() {
        #expect(AskiColorLabCommand.helpMessage().contains("cam16-hct-reference"))
    }

    @Test func materialCAM16ReferencePrimariesMatchPinnedImplementation() {
        let cases: [(name: String, argb: UInt32, hue: Double, chroma: Double, j: Double, m: Double, s: Double, q: Double)] = [
            ("red", 0xffff0000, 27.408, 113.358, 46.445, 89.494, 91.890, 105.989),
            ("green", 0xff00ff00, 142.140, 108.410, 79.332, 85.588, 78.605, 138.520),
            ("blue", 0xff0000ff, 282.788, 87.231, 25.466, 68.867, 93.675, 78.481),
            ("white", 0xffffffff, 209.492, 2.869, 100.000, 2.265, 12.068, 155.521),
            ("black", 0xff000000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000),
        ]

        for testCase in cases {
            let actual = CAM16Color.fromInt(testCase.argb)
            #expect(abs(actual.hue - testCase.hue) < 0.01, "\(testCase.name) hue")
            #expect(abs(actual.chroma - testCase.chroma) < 0.01, "\(testCase.name) chroma")
            #expect(abs(actual.j - testCase.j) < 0.01, "\(testCase.name) j")
            #expect(abs(actual.m - testCase.m) < 0.01, "\(testCase.name) m")
            #expect(abs(actual.s - testCase.s) < 0.01, "\(testCase.name) s")
            #expect(abs(actual.q - testCase.q) < 0.01, "\(testCase.name) q")
        }
    }

    @Test func materialHCTReferenceValuesMatchPinnedImplementation() {
        let green = HCTColor.fromInt(0xff00ff00)
        #expect(abs(green.hue - 142.139) < 0.01)
        #expect(abs(green.chroma - 108.410) < 0.01)
        #expect(abs(green.tone - 87.737) < 0.01)

        let blue = HCTColor.fromInt(0xff0000ff)
        #expect(abs(blue.hue - 282.788) < 0.01)
        #expect(abs(blue.chroma - 87.230) < 0.01)
        #expect(abs(blue.tone - 32.302) < 0.01)

        let lightBlue = HCTColor.from(hue: 282.788, chroma: 87.230, tone: 90.0)
        #expect(abs(lightBlue.hue - 282.239) < 0.01)
        #expect(abs(lightBlue.chroma - 19.144) < 0.01)
        #expect(abs(lightBlue.tone - 90.035) < 0.01)
    }

    @Test func hctRoundTripGridPreservesOriginalARGB() {
        for red in stride(from: 0, to: 296, by: 37) {
            for green in stride(from: 0, to: 296, by: 37) {
                for blue in stride(from: 0, to: 296, by: 37) {
                    let argb = argb(red: min(255, red), green: min(255, green), blue: min(255, blue))
                    let hct = HCTColor.fromInt(argb)
                    let rebuilt = HCTColor.from(hue: hct.hue, chroma: hct.chroma, tone: hct.tone)
                    #expect(rebuilt.argb == argb, "roundtrip failed for \(hexARGB(argb))")
                }
            }
        }
    }

    @Test func commandWritesBothCSVsWithStableHeaders() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var stderr = ""
        let status = try CAM16HCTReferenceSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { stderr += $0 })

        #expect(status == .success, "stderr: \(stderr)")

        let referenceCSV = directory.appending(path: CAM16HCTReferenceCommand.referenceOutputFileName)
        let paletteCSV = directory.appending(path: CAM16HCTReferenceCommand.paletteOutputFileName)
        let referenceContents = try String(contentsOf: referenceCSV, encoding: .utf8)
        let paletteContents = try String(contentsOf: paletteCSV, encoding: .utf8)

        #expect(referenceContents.lines.first == expectedReferenceHeader)
        #expect(paletteContents.lines.first == expectedPaletteHeader)
    }

    @Test func commandWritesMaterialReferenceAndRoundTripRows() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try CAM16HCTReferenceSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })

        let csv = directory.appending(path: CAM16HCTReferenceCommand.referenceOutputFileName)
        let lines = try String(contentsOf: csv, encoding: .utf8).lines

        #expect(lines.count == 5 + 512 + 1)
        #expect(lines.contains { $0.contains("material_red") && $0.contains("ffff0000") })
        #expect(lines.dropFirst().allSatisfy { !$0.contains("false") })
    }

    @Test func paletteComparisonIncludesDisplayP3Rows() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try CAM16HCTReferenceSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })

        let csv = directory.appending(path: CAM16HCTReferenceCommand.paletteOutputFileName)
        let contents = try String(contentsOf: csv, encoding: .utf8)

        #expect(contents.contains("synthetic_displayp3"))
        #expect(contents.contains("displayP3"))
        #expect(contents.contains("cam16UCS"))
    }

    @Test func twoIdenticalRunsProduceByteIdenticalCSVs() throws {
        let first = try temporaryDirectory()
        let second = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        for directory in [first, second] {
            let status = try CAM16HCTReferenceSubcommand.parse([
                "--output-dir", directory.path,
                "--aski-git-sha", "test-sha",
            ]).execute(standardError: { _ in })
            #expect(status == .success)
        }

        let firstReference = try Data(contentsOf: first.appending(path: CAM16HCTReferenceCommand.referenceOutputFileName))
        let secondReference = try Data(contentsOf: second.appending(path: CAM16HCTReferenceCommand.referenceOutputFileName))
        let firstPalette = try Data(contentsOf: first.appending(path: CAM16HCTReferenceCommand.paletteOutputFileName))
        let secondPalette = try Data(contentsOf: second.appending(path: CAM16HCTReferenceCommand.paletteOutputFileName))

        #expect(firstReference == secondReference)
        #expect(firstPalette == secondPalette)
    }

    private var expectedReferenceHeader: String {
        (CSVSchema.sharedPrefixColumns + CAM16HCTReferenceCommand.referenceMetricColumns).joined(separator: ",")
    }

    private var expectedPaletteHeader: String {
        (CSVSchema.sharedPrefixColumns + CAM16HCTReferenceCommand.paletteMetricColumns).joined(separator: ",")
    }

    private func argb(red: Int, green: Int, blue: Int) -> UInt32 {
        (0xff << 24) | (UInt32(red) << 16) | (UInt32(green) << 8) | UInt32(blue)
    }

    private func hexARGB(_ argb: UInt32) -> String {
        String(format: "%08x", argb)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AskiColorLabCAM16HCTReferenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private extension String {
    var lines: [String] {
        split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}
