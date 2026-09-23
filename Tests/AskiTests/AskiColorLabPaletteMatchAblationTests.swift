import ArgumentParser
import Aski
import AskiToolSupport
import Foundation
import Testing
import simd
@testable import AskiColorLab

@Suite struct AskiColorLabPaletteMatchAblationTests {
    @Test func usageListsPaletteMatchAblationCommand() {
        #expect(AskiColorLabCommand.helpMessage().contains("palette-match-ablation"))
    }

    @Test func oklabEuclideanReturnsSquareRootedDistance() {
        let a = SIMD3<Float>(0, 0, 0)
        let b = SIMD3<Float>(0.3, 0.4, 0)
        let distance = PaletteMatchPolicies.oklabEuclidean(a, b)
        #expect(abs(distance - 0.5) < 1e-6)
    }

    @Test func oklabHyABIsCityBlockLPlusEuclideanAB() {
        let source = SIMD3<Float>(0, 0, 0)
        let candidate = SIMD3<Float>(0.3, 0.4, 0)
        // |0.3| + sqrt(0.16 + 0) = 0.3 + 0.4 = 0.7
        let distance = PaletteMatchPolicies.oklabHyAB(source, candidate)
        #expect(abs(distance - 0.7) < 1e-6)
    }

    @Test func hyabIsSymmetric() {
        let a = SIMD3<Float>(0.2, -0.1, 0.05)
        let b = SIMD3<Float>(0.7, 0.05, -0.2)
        #expect(
            abs(PaletteMatchPolicies.oklabHyAB(a, b) - PaletteMatchPolicies.oklabHyAB(b, a)) < 1e-6
        )
    }

    @Test func nearestTieIsBrokenByPaletteIndex() {
        let source = SIMD3<Float>(0, 0, 0)
        let candidates: [SIMD3<Float>] = [
            SIMD3(0.1, 0, 0),
            SIMD3(0.1, 0, 0),  // exact tie
            SIMD3(0.2, 0, 0),
        ]
        let result = PaletteMatchPolicies.nearest(
            in: candidates,
            to: source,
            using: PaletteMatchPolicies.oklabEuclidean
        )
        #expect(result.index == 0)
    }

    @Test func resolveToOKLabHandlesSRGBPaletteColor() {
        // sRGB(0.5, 0.5, 0.5) -> OKLab L ≈ 0.598, a ≈ 0, b ≈ 0.
        let color = PaletteColor(SIMD3<Float>(0.5, 0.5, 0.5), colorSpace: .sRGB)
        let resolved = PaletteMatchPolicies.resolveToOKLab(color)
        #expect(abs(resolved.x - 0.598) < 0.01)
        #expect(abs(resolved.y) < 0.005)
        #expect(abs(resolved.z) < 0.005)
    }

    @Test func resolveToOKLabHandlesDisplayP3PaletteColor() {
        // Pure-red Display P3 declaration must resolve to a non-zero chroma.
        let color = PaletteColor(SIMD3<Float>(1, 0, 0), colorSpace: .displayP3)
        let resolved = PaletteMatchPolicies.resolveToOKLab(color)
        #expect(resolved.x > 0)
        #expect(resolved.y > 0.15, "Display P3 red should land far from the achromatic axis in OKLab")
    }

    @Test func paletteGroupsAreEmittedInSpecOrder() {
        let groupIDs = PaletteMatchFixtures.all.map(\.id)
        #expect(groupIDs == ["ansi16", "monochrome", "synthetic_srgb", "synthetic_displayp3"])
    }

    @Test func everyPaletteGroupHasAtLeastOneSource() {
        for group in PaletteMatchFixtures.all {
            #expect(!group.sources.isEmpty, "palette group \(group.id) has no source fixtures")
            #expect(!group.colors.isEmpty, "palette group \(group.id) has no palette colors")
        }
    }

    @Test func ansi16PaletteHasSixteenColors() {
        let group = PaletteMatchFixtures.all.first { $0.id == "ansi16" }
        #expect(group?.colors.count == 16)
    }

    @Test func monochromePaletteIsSingleColor() {
        let group = PaletteMatchFixtures.all.first { $0.id == "monochrome" }
        #expect(group?.colors.count == 1)
    }

    @Test func syntheticDisplayP3PaletteHasAtLeastOneDisplayP3Color() {
        let group = PaletteMatchFixtures.all.first { $0.id == "synthetic_displayp3" }
        #expect(group?.colors.contains { $0.colorSpace == .displayP3 } == true)
    }

    @Test func atLeastOneSyntheticSourceIsDeclaredAsDisplayP3() {
        let group = PaletteMatchFixtures.all.first { $0.id == "synthetic_displayp3" }
        let p3Sources = group?.sources.filter { $0.color.colorSpace == .displayP3 } ?? []
        #expect(!p3Sources.isEmpty)
    }

    @Test func runWritesCSVAtExpectedPathAndReturnsSuccess() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var stderr = ""
        let status = try PaletteMatchAblationSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { stderr += $0 })

        #expect(status == .success, "stderr: \(stderr)")
        let csv = directory.appending(path: "palette-match-ablation.csv")
        #expect(FileManager.default.fileExists(atPath: csv.path))
    }

    @Test func headerOrderMatchesContract() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try PaletteMatchAblationSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })

        let csv = directory.appending(path: "palette-match-ablation.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let header = contents.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)

        let expected =
            ([
                "schema_version", "command", "aski_git_sha", "run_seed",
                "sample_id", "fixture_id", "policy",
                "input_space", "input_components",
                "output_space", "output_components",
            ] + [
                "palette_id", "palette_color_count", "source_oklab",
                "selected_palette_index", "selected_palette_space", "selected_palette_components",
                "selected_oklab", "distance", "delta_l", "delta_ab",
                "baseline_selected_palette_index", "baseline_distance", "baseline_selection_distance",
                "differs_from_baseline",
                "delta_distance_from_baseline_selection", "distance_ratio_to_baseline_selection",
            ]).joined(separator: ",")

        #expect(header == expected)
    }

    @Test func rowCountIsSourceFixturesTimesFourPlusOne() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try PaletteMatchAblationSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })

        let csv = directory.appending(path: "palette-match-ablation.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let sourceCount = PaletteMatchFixtures.all.reduce(0) { $0 + $1.sources.count }
        // Four policy rows per source: oklabEuclidean, oklabHyAB, helmlabEuclidean,
        // helmlabCompressed (the two Helmlab rows are the Task 6 probe).
        #expect(lines.count == sourceCount * 4 + 1)
    }

    @Test func firstSourceEmitsFourPoliciesWithSharedSampleAndFixtureID() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try PaletteMatchAblationSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })

        let csv = directory.appending(path: "palette-match-ablation.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        // The four policy rows for the first source fixture, in fixed order.
        let sourceRows = (1...4).map { String(lines[$0]).split(separator: ",").map(String.init) }

        #expect(sourceRows.allSatisfy { $0[4] == "0" }, "sample_id is shared across all four policy rows")
        #expect(sourceRows.allSatisfy { $0[5] == sourceRows[0][5] }, "fixture_id is shared across policy rows")
        #expect(sourceRows[0][6] == "oklabEuclidean")
        #expect(sourceRows[1][6] == "oklabHyAB")
        #expect(sourceRows[2][6] == "helmlabEuclidean")
        #expect(sourceRows[3][6] == "helmlabCompressed")

        // The second source fixture starts at line 5 with sample_id 1: sample_id
        // increments per source fixture, not per row.
        let nextSourceRow = String(lines[5]).split(separator: ",").map(String.init)
        #expect(nextSourceRow[4] == "1", "sample_id should increment per source fixture, not per row")
    }

    @Test func euclideanRowsHaveTautologicalBaselineColumns() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try PaletteMatchAblationSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })

        let csv = directory.appending(path: "palette-match-ablation.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let policyColumn = header.firstIndex(of: "policy")!
        let deltaColumn = header.firstIndex(of: "delta_distance_from_baseline_selection")!
        let ratioColumn = header.firstIndex(of: "distance_ratio_to_baseline_selection")!

        for line in lines.dropFirst() {
            let row = String(line).split(separator: ",").map(String.init)
            if row[policyColumn] == "oklabEuclidean" {
                #expect(row[deltaColumn] == "0.000000")
                #expect(row[ratioColumn] == "1.000000")
            }
        }
    }

    @Test func twoIdenticalRunsProduceByteIdenticalCSVs() throws {
        let directoryA = try temporaryDirectory()
        let directoryB = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryA)
            try? FileManager.default.removeItem(at: directoryB)
        }

        for dir in [directoryA, directoryB] {
            let status = try PaletteMatchAblationSubcommand.parse([
                "--output-dir", dir.path,
                "--aski-git-sha", "test-sha",
                "--seed", "7",
            ]).execute(standardError: { _ in })
            #expect(status == .success)
        }

        let csvA = try Data(contentsOf: directoryA.appending(path: "palette-match-ablation.csv"))
        let csvB = try Data(contentsOf: directoryB.appending(path: "palette-match-ablation.csv"))
        #expect(csvA == csvB)
    }

    @Test func monochromeFixturesNeverDivergeFromBaseline() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try PaletteMatchAblationSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })

        let csv = directory.appending(path: "palette-match-ablation.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let paletteColumn = header.firstIndex(of: "palette_id")!
        let differsColumn = header.firstIndex(of: "differs_from_baseline")!

        var monochromeRowCount = 0
        for line in lines.dropFirst() {
            let row = String(line).split(separator: ",").map(String.init)
            if row[paletteColumn] == "monochrome" {
                monochromeRowCount += 1
                #expect(row[differsColumn] == "false")
            }
        }
        #expect(monochromeRowCount > 0, "expected at least one monochrome row")
    }

    @Test func atLeastOneSyntheticNearBisectorDivergesUnderHyAB() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try PaletteMatchAblationSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })

        let csv = directory.appending(path: "palette-match-ablation.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let policyColumn = header.firstIndex(of: "policy")!
        let fixtureColumn = header.firstIndex(of: "fixture_id")!
        let differsColumn = header.firstIndex(of: "differs_from_baseline")!

        let divergedHyABNearBisectors = lines.dropFirst().filter { line in
            let row = String(line).split(separator: ",").map(String.init)
            return row[policyColumn] == "oklabHyAB"
                && row[fixtureColumn].contains("near_bisector")
                && row[differsColumn] == "true"
        }
        #expect(
            !divergedHyABNearBisectors.isEmpty,
            "expected at least one near-bisector fixture to diverge under HyAB — adjust synthetic_srgb palette/source values along the chroma-vs-lightness axis until divergence is achieved"
        )
    }

    @Test func displayP3FixtureRowsCarryDisplayP3SpaceFieldsAndResolvedOKLab() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try PaletteMatchAblationSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })

        let csv = directory.appending(path: "palette-match-ablation.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let inputSpaceColumn = header.firstIndex(of: "input_space")!
        let outputSpaceColumn = header.firstIndex(of: "output_space")!
        let outputComponentsColumn = header.firstIndex(of: "output_components")!
        let selectedSpaceColumn = header.firstIndex(of: "selected_palette_space")!
        let selectedComponentsColumn = header.firstIndex(of: "selected_palette_components")!
        let fixtureColumn = header.firstIndex(of: "fixture_id")!
        let sourceOKLabColumn = header.firstIndex(of: "source_oklab")!

        let displayP3SourceRows = lines.dropFirst().filter { line in
            let row = String(line).split(separator: ",").map(String.init)
            return row[fixtureColumn].hasPrefix("displayp3_") && row[inputSpaceColumn] == "displayP3"
        }
        #expect(!displayP3SourceRows.isEmpty, "expected at least one displayP3-declared source row")

        for row in displayP3SourceRows {
            let cells = String(row).split(separator: ",").map(String.init)
            let semicolons = cells[sourceOKLabColumn].filter { $0 == ";" }.count
            #expect(semicolons == 2, "source_oklab should be a 3-component semicolon-joined float vector")
        }

        // The exact-Display-P3-red source should select the Display P3 saturated-red
        // palette entry, and the selected-side columns must propagate the Display P3
        // declaration. All four policies should agree on this exact-match fixture.
        let exactP3RedRows = lines.dropFirst().filter { line in
            let row = String(line).split(separator: ",").map(String.init)
            return row[fixtureColumn] == "displayp3_exact_saturated_red"
        }
        #expect(exactP3RedRows.count == 4, "expected one row per policy (oklab×2 + helmlab×2) for the exact P3 red fixture")
        for row in exactP3RedRows {
            let cells = String(row).split(separator: ",").map(String.init)
            #expect(
                cells[outputSpaceColumn] == "displayP3",
                "output_space must round-trip the Display P3 declaration on a P3-selected row")
            #expect(
                cells[selectedSpaceColumn] == "displayP3",
                "selected_palette_space must round-trip the Display P3 declaration on a P3-selected row")
            #expect(
                cells[outputComponentsColumn] == cells[selectedComponentsColumn],
                "output_components and selected_palette_components must match on a single-policy row")
            #expect(
                cells[selectedComponentsColumn] == "1.000000;0.000000;0.000000",
                "selected_palette_components must equal the declared P3 saturated-red components")
        }
    }

    @Test func displayP3SaturatedRedResolvesDistinctFromSRGBSaturatedRed() {
        let p3Red = PaletteMatchPolicies.resolveToOKLab(
            PaletteColor(SIMD3<Float>(1, 0, 0), colorSpace: .displayP3)
        )
        let srgbRed = PaletteMatchPolicies.resolveToOKLab(
            PaletteColor(SIMD3<Float>(1, 0, 0), colorSpace: .sRGB)
        )
        let delta = simd_length(p3Red - srgbRed)
        #expect(delta > 1e-3, "Display P3 saturated red must not collapse to sRGB-resolved OKLab")
    }

    fileprivate func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AskiColorLabPaletteMatchAblationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
