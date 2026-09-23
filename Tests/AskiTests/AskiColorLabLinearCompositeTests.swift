import ArgumentParser
import Aski
import AskiToolSupport
import Foundation
import Testing
import simd
@testable import AskiColorLab

@Suite struct AskiColorLabLinearCompositeTests {
    fileprivate func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AskiColorLabLinearCompositeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func transferEncodeDecodeRoundTripsWithinFloatPrecision() {
        for sample: Float in [0, 0.04, 0.18, 0.5, 0.735, 1.0] {
            let linear = LinearCompositeSpaces.transferDecode(sample)
            let encoded = LinearCompositeSpaces.transferEncode(linear)
            #expect(
                abs(encoded - sample) < 1e-6,
                "round-trip sample=\(sample) drifted to encoded=\(encoded)")
        }
    }

    @Test func targetGamutLabelsMatchCSVConvention() {
        #expect(LinearCompositeSpaces.TargetGamut.sRGB.csvLabel == "sRGB")
        #expect(LinearCompositeSpaces.TargetGamut.displayP3.csvLabel == "displayP3")
    }

    @Test func policyWorkingSpaceLabelMatchesContract() {
        // Spec §CSV Contract: encoded8bit → "encoded_sRGB" / "encoded_displayP3";
        // linear8bit / linearFloat → "linear_sRGB" / "linear_displayP3".
        #expect(LinearCompositeSpaces.TargetGamut.sRGB.encodedWorkingSpaceLabel == "encoded_sRGB")
        #expect(LinearCompositeSpaces.TargetGamut.sRGB.linearWorkingSpaceLabel == "linear_sRGB")
        #expect(LinearCompositeSpaces.TargetGamut.displayP3.encodedWorkingSpaceLabel == "encoded_displayP3")
        #expect(LinearCompositeSpaces.TargetGamut.displayP3.linearWorkingSpaceLabel == "linear_displayP3")
    }

    @Test func policyIdentifierCanonicalOrderMatchesCSVContract() {
        // Spec §Policies "Policy identifiers written to CSV are exactly":
        //   encoded8bit, linear8bit, linearFloat — in this order.
        #expect(
            LinearCompositePolicies.canonicalOrder.map(\.csvLabel)
                == ["encoded8bit", "linear8bit", "linearFloat"])
    }

    @Test func encoded8bitFullyOpaqueSourceCoversBackgroundBytewise() {
        // α_src = 255, fg = (200, 100, 50), bg = (0, 0, 0, 255).
        // Premultiply fg → (200, 100, 50); bg contribution gated by (255-255)=0.
        // Composite → (200, 100, 50, 255). Unpremultiplied → (200/255, 100/255, 50/255).
        let output = LinearCompositePolicies.encoded8bit(
            fgByte: SIMD3<Float>(200, 100, 50),
            fgAlphaByte: 255,
            bgByte: SIMD3<Float>(0, 0, 0),
            bgAlphaByte: 255,
            target: .sRGB
        )
        #expect(output.mappedAlphaByte == 255)
        #expect(abs(output.mappedEncodedRGB.x - 200.0 / 255.0) < 1e-6)
        #expect(abs(output.mappedEncodedRGB.y - 100.0 / 255.0) < 1e-6)
        #expect(abs(output.mappedEncodedRGB.z - 50.0 / 255.0) < 1e-6)
    }

    @Test func encoded8bitZeroAlphaSourceLeavesOpaqueBackgroundUntouched() {
        // α_src = 0 over (255, 255, 255, 255). Output bytes must equal bg.
        let output = LinearCompositePolicies.encoded8bit(
            fgByte: SIMD3<Float>(255, 0, 0),
            fgAlphaByte: 0,
            bgByte: SIMD3<Float>(255, 255, 255),
            bgAlphaByte: 255,
            target: .sRGB
        )
        #expect(output.mappedAlphaByte == 255)
        #expect(abs(output.mappedEncodedRGB.x - 1.0) < 1e-6)
        #expect(abs(output.mappedEncodedRGB.y - 1.0) < 1e-6)
        #expect(abs(output.mappedEncodedRGB.z - 1.0) < 1e-6)
    }

    @Test func encoded8bitZeroAlphaSourceOverTransparentBackgroundProducesZeroAlpha() {
        // α_src = 0, α_bg = 0 → α_out = 0; unpremultiply returns (0, 0, 0).
        let output = LinearCompositePolicies.encoded8bit(
            fgByte: SIMD3<Float>(255, 0, 0),
            fgAlphaByte: 0,
            bgByte: SIMD3<Float>(0, 0, 0),
            bgAlphaByte: 0,
            target: .sRGB
        )
        #expect(output.mappedAlphaByte == 0)
        #expect(output.mappedEncodedRGB == SIMD3<Float>(0, 0, 0))
    }

    @Test func linear8bitFullyOpaqueSourceCoversBackgroundBytewise() {
        // α_src = 255 over opaque bg. Round-trip through linear and re-encode
        // must preserve the source bytes within ±1/255.
        let output = LinearCompositePolicies.linear8bit(
            fgByte: SIMD3<Float>(200, 100, 50),
            fgAlphaByte: 255,
            bgByte: SIMD3<Float>(0, 0, 0),
            bgAlphaByte: 255,
            target: .sRGB
        )
        #expect(output.mappedAlphaByte == 255)
        #expect(abs(output.mappedEncodedRGB.x - 200.0 / 255.0) <= 1.0 / 255.0)
        #expect(abs(output.mappedEncodedRGB.y - 100.0 / 255.0) <= 1.0 / 255.0)
        #expect(abs(output.mappedEncodedRGB.z - 50.0 / 255.0) <= 1.0 / 255.0)
    }

    @Test func linear8bitZeroAlphaSourceLeavesOpaqueBackgroundUntouched() {
        let output = LinearCompositePolicies.linear8bit(
            fgByte: SIMD3<Float>(255, 0, 0),
            fgAlphaByte: 0,
            bgByte: SIMD3<Float>(255, 255, 255),
            bgAlphaByte: 255,
            target: .sRGB
        )
        #expect(output.mappedAlphaByte == 255)
        #expect(abs(output.mappedEncodedRGB.x - 1.0) <= 1.0 / 255.0)
        #expect(abs(output.mappedEncodedRGB.y - 1.0) <= 1.0 / 255.0)
        #expect(abs(output.mappedEncodedRGB.z - 1.0) <= 1.0 / 255.0)
    }

    @Test func linear8bitGray50OverWhiteDivergesFromEncoded8bit() {
        // Spec §Fixtures: edge_gray50_over_white_alpha050.
        // encoded8bit composites to byte ≈ 191; linear8bit composites to byte
        // ≈ 204 because linear-light averaging of dark-over-light preserves
        // more brightness than encoded averaging. The two policies must differ
        // materially on this discriminator.
        let fg = SIMD3<Float>(128, 128, 128)
        let bg = SIMD3<Float>(255, 255, 255)
        let encoded = LinearCompositePolicies.encoded8bit(
            fgByte: fg, fgAlphaByte: 128,
            bgByte: bg, bgAlphaByte: 255,
            target: .sRGB
        )
        let linear = LinearCompositePolicies.linear8bit(
            fgByte: fg, fgAlphaByte: 128,
            bgByte: bg, bgAlphaByte: 255,
            target: .sRGB
        )
        let encodedByteR = Int((encoded.mappedEncodedRGB.x * 255.0).rounded())
        let linearByteR = Int((linear.mappedEncodedRGB.x * 255.0).rounded())
        // linear path must produce a brighter result than the encoded path on
        // dark-over-light; per spec ≈ 204 vs ≈ 191.
        #expect(
            linearByteR > encodedByteR + 5,
            "linear8bit (\(linearByteR)) must exceed encoded8bit (\(encodedByteR)) by >5 bytes on gray50-over-white")
    }

    @Test func linearFloatPreservesShadowQuantizationDetailBelowOneOver255() {
        // Spec §Fixtures edge_shadow_quantization: fg (3, 0, 0) over (0, 0, 0)
        // opaque @ α=13. Linear contribution ≈ 0.000912 · 0.051 ≈ 4.65e-5,
        // well below the 8-bit threshold (1/255 ≈ 3.9e-3). linearFloat must
        // preserve the float value strictly above 3e-5.
        let output = LinearCompositePolicies.linearFloat(
            fgByte: SIMD3<Float>(3, 0, 0),
            fgAlphaByte: 13,
            bgByte: SIMD3<Float>(0, 0, 0),
            bgAlphaByte: 255,
            target: .sRGB
        )
        #expect(
            output.mappedLinearRGB.x > 3e-5,
            "linearFloat must preserve the unquantized shadow contribution, got \(output.mappedLinearRGB.x)")
    }

    @Test func linearFloatFullyOpaqueSourceMatchesItsLinearDecode() {
        // α = 255 over opaque bg: the composite reduces to linear-decode of
        // the source bytes exactly.
        let fg = SIMD3<Float>(128, 64, 200)
        let output = LinearCompositePolicies.linearFloat(
            fgByte: fg,
            fgAlphaByte: 255,
            bgByte: SIMD3<Float>(0, 0, 0),
            bgAlphaByte: 255,
            target: .sRGB
        )
        let expected = LinearCompositeSpaces.transferDecode(fg / 255.0)
        #expect(abs(output.mappedLinearRGB.x - expected.x) < 1e-6)
        #expect(abs(output.mappedLinearRGB.y - expected.y) < 1e-6)
        #expect(abs(output.mappedLinearRGB.z - expected.z) < 1e-6)
        #expect(output.mappedAlphaByte == 255)
    }

    @Test func applyDispatchesToEachPolicy() {
        let fg = SIMD3<Float>(200, 100, 50)
        let bg = SIMD3<Float>(0, 0, 0)
        let fgAlpha = 128
        let bgAlpha = 255
        let e = LinearCompositePolicies.apply(
            policy: .encoded8bit,
            fgByte: fg, fgAlphaByte: fgAlpha,
            bgByte: bg, bgAlphaByte: bgAlpha,
            target: .sRGB
        )
        let l = LinearCompositePolicies.apply(
            policy: .linear8bit,
            fgByte: fg, fgAlphaByte: fgAlpha,
            bgByte: bg, bgAlphaByte: bgAlpha,
            target: .sRGB
        )
        let f = LinearCompositePolicies.apply(
            policy: .linearFloat,
            fgByte: fg, fgAlphaByte: fgAlpha,
            bgByte: bg, bgAlphaByte: bgAlpha,
            target: .sRGB
        )
        // All three must produce equal alpha (Porter-Duff source-over alpha is
        // identical in every working space).
        #expect(e.mappedAlphaByte == l.mappedAlphaByte)
        #expect(l.mappedAlphaByte == f.mappedAlphaByte)
        // encoded8bit and linear8bit must differ on a dark-over-light blend.
        #expect(simd_length(e.mappedEncodedRGB - l.mappedEncodedRGB) > 1e-3)
    }

    @Test func deltaEOKZeroWhenInputsAreEqual() {
        let v = SIMD3<Float>(0.5, 0.1, -0.05)
        #expect(LinearCompositeMetrics.deltaEOK(mappedOKLab: v, groundTruthOKLab: v) == 0)
    }

    @Test func encodedRGBDistanceZeroWhenInputsAreEqual() {
        let v = SIMD3<Float>(0.5, 0.5, 0.5)
        #expect(LinearCompositeMetrics.encodedRGBDistance(mapped: v, groundTruth: v) == 0)
    }

    @Test func encodedRGBDistanceUsesEuclideanLength() {
        let mapped = SIMD3<Float>(0, 0, 0)
        let truth = SIMD3<Float>(1, 0, 0)
        let d = LinearCompositeMetrics.encodedRGBDistance(mapped: mapped, groundTruth: truth)
        #expect(abs(d - 1.0) < 1e-6)
    }

    @Test func maxChannelAbsDiffPicksWorstChannel() {
        let mapped = SIMD3<Float>(0.1, 0.5, 0.0)
        let truth = SIMD3<Float>(0.1, 0.6, 0.4)
        let d = LinearCompositeMetrics.maxChannelAbsDiff(mapped: mapped, groundTruth: truth)
        #expect(abs(d - 0.4) < 1e-6)
    }

    @Test func zeroAlphaConventionReturnsZeroForAllMetrics() {
        // Spec §CSV Contract: when mapped_alpha_byte == 0 or
        // ground_truth_alpha_byte == 0, all three metrics write 0.000000.
        let metrics = LinearCompositeMetrics.compute(
            mappedLinearRGB: SIMD3<Float>(1, 0, 0),
            mappedEncodedRGB: SIMD3<Float>(1, 0, 0),
            mappedAlphaByte: 0,
            groundTruthLinearRGB: SIMD3<Float>(0, 1, 0),
            groundTruthEncodedRGB: SIMD3<Float>(0, 1, 0),
            groundTruthAlphaByte: 255,
            target: .sRGB
        )
        #expect(metrics.deltaEOK == 0)
        #expect(metrics.encodedRGBDistance == 0)
        #expect(metrics.maxChannelAbsDiff == 0)
    }

    /// Red-signal test: catches a regression that routes Display P3 fixtures
    /// through `linearSRGBToOKLAB` (or vice versa). Such a bug would silently
    /// produce wrong `delta_e_ok_to_ground_truth` values on P3 rows but would
    /// not be caught by any encoded-distance-only assertion downstream.
    @Test func metricsComputeUsesTargetGamutSpecificOKLabConversion() {
        // A non-trivial linear triple whose OKLab via the sRGB matrix differs
        // materially from its OKLab via the P3 matrix.
        let mappedLinear = SIMD3<Float>(0.1, 0.7, 0.3)
        let truthLinear = SIMD3<Float>(0.4, 0.5, 0.2)
        let sRGBExpected = simd_length(
            ColorConversion.linearSRGBToOKLAB(mappedLinear)
                - ColorConversion.linearSRGBToOKLAB(truthLinear)
        )
        let p3Expected = simd_length(
            ColorConversion.linearP3ToOKLAB(mappedLinear)
                - ColorConversion.linearP3ToOKLAB(truthLinear)
        )
        // Sanity-guard: if the fixture is degenerate (sRGB and P3 OKLab agree
        // for this triple) the dispatch test below is vacuous. Pick a different
        // pair if this fires.
        #expect(
            abs(sRGBExpected - p3Expected) > 1e-4,
            "fixture is degenerate; pick a triple where sRGB and P3 OKLab transforms diverge")

        let sRGBActual = LinearCompositeMetrics.compute(
            mappedLinearRGB: mappedLinear,
            mappedEncodedRGB: SIMD3<Float>(0.5, 0.5, 0.5),
            mappedAlphaByte: 255,
            groundTruthLinearRGB: truthLinear,
            groundTruthEncodedRGB: SIMD3<Float>(0.5, 0.5, 0.5),
            groundTruthAlphaByte: 255,
            target: .sRGB
        ).deltaEOK
        let p3Actual = LinearCompositeMetrics.compute(
            mappedLinearRGB: mappedLinear,
            mappedEncodedRGB: SIMD3<Float>(0.5, 0.5, 0.5),
            mappedAlphaByte: 255,
            groundTruthLinearRGB: truthLinear,
            groundTruthEncodedRGB: SIMD3<Float>(0.5, 0.5, 0.5),
            groundTruthAlphaByte: 255,
            target: .displayP3
        ).deltaEOK
        #expect(
            abs(sRGBActual - sRGBExpected) < 1e-6,
            "compute(target: .sRGB) must dispatch through linearSRGBToOKLAB; got \(sRGBActual), expected \(sRGBExpected)")
        #expect(
            abs(p3Actual - p3Expected) < 1e-6,
            "compute(target: .displayP3) must dispatch through linearP3ToOKLAB; got \(p3Actual), expected \(p3Expected)")
    }

    @Test func sRGBGridIsSixColorsTimesFourBackgroundsTimesEightAlphas() {
        #expect(LinearCompositeFixtures.sRGBGrid.count == 6 * 4 * 8)
        #expect(LinearCompositeFixtures.sRGBGrid.count == 192)
    }

    @Test func p3GridIsSixColorsTimesFourBackgroundsTimesEightAlphas() {
        #expect(LinearCompositeFixtures.p3Grid.count == 6 * 4 * 8)
        #expect(LinearCompositeFixtures.p3Grid.count == 192)
    }

    @Test func sRGBGridEnumerationOrderIsColorBackgroundAlpha() {
        // Spec §Fixtures §Enumeration order: outer index COLOR (R, G, B, C, M, Y),
        // then BG (K, W, G50, T), then ALPHA_BYTE (000, 001, 013, 064, 128, 191, 242, 255).
        let g = LinearCompositeFixtures.sRGBGrid
        #expect(g.first?.id == "grid_sRGB_R_K_000")
        // Second row: same color, same bg, next alpha.
        #expect(g[1].id == "grid_sRGB_R_K_001")
        // 8th row: same color, same bg, last alpha.
        #expect(g[7].id == "grid_sRGB_R_K_255")
        // 9th row: same color, next bg.
        #expect(g[8].id == "grid_sRGB_R_W_000")
        // 33rd row: same color, next-after-last bg means next color: 4 × 8 = 32.
        #expect(g[32].id == "grid_sRGB_G_K_000")
    }

    @Test func p3GridUsesP3PrefixInID() {
        #expect(LinearCompositeFixtures.p3Grid.first?.id == "grid_P3_R_K_000")
    }

    @Test func sRGBGridFixturesDeclareSRGBTargetGamut() {
        for fixture in LinearCompositeFixtures.sRGBGrid {
            #expect(fixture.targetGamut == .sRGB)
        }
    }

    @Test func p3GridFixturesDeclareDisplayP3TargetGamut() {
        for fixture in LinearCompositeFixtures.p3Grid {
            #expect(fixture.targetGamut == .displayP3)
        }
    }

    @Test func sRGBGridSaturatedRedOverWhiteAtAlpha128IsPresent() {
        let target = LinearCompositeFixtures.sRGBGrid.first {
            $0.id == "grid_sRGB_R_W_128"
        }
        #expect(target != nil)
        #expect(target?.fgByte == SIMD3<Float>(255, 0, 0))
        #expect(target?.bgByte == SIMD3<Float>(255, 255, 255))
        #expect(target?.fgAlphaByte == 128)
        #expect(target?.bgAlphaByte == 255)
    }

    @Test func sRGBGridTransparentBackgroundUsesZeroAlphaByte() {
        let target = LinearCompositeFixtures.sRGBGrid.first {
            $0.id == "grid_sRGB_R_T_128"
        }
        #expect(target?.bgAlphaByte == 0)
        #expect(target?.bgByte == SIMD3<Float>(0, 0, 0))
    }

    @Test func edgesContainFiveSpecCases() {
        // Spec §Fixtures Group C, exact IDs in spec order.
        let ids = LinearCompositeFixtures.edges.map(\.id)
        #expect(
            ids == [
                "edge_gray50_over_white_alpha050",
                "edge_p3_green_over_white_alpha050",
                "edge_shadow_quantization",
                "edge_zero_alpha_bleed_red_over_white",
                "edge_gray50_over_gray50_alpha050",
            ])
    }

    @Test func edgeGray50OverWhiteHasSpecBytes() {
        let edge = LinearCompositeFixtures.edges.first { $0.id == "edge_gray50_over_white_alpha050" }
        #expect(edge?.fgByte == SIMD3<Float>(128, 128, 128))
        #expect(edge?.fgAlphaByte == 128)
        #expect(edge?.bgByte == SIMD3<Float>(255, 255, 255))
        #expect(edge?.bgAlphaByte == 255)
        #expect(edge?.targetGamut == .sRGB)
    }

    @Test func edgeP3GreenOverWhiteUsesDisplayP3TargetGamut() {
        let edge = LinearCompositeFixtures.edges.first { $0.id == "edge_p3_green_over_white_alpha050" }
        #expect(edge?.targetGamut == .displayP3)
        #expect(edge?.fgByte == SIMD3<Float>(0, 255, 0))
        #expect(edge?.bgByte == SIMD3<Float>(255, 255, 255))
        #expect(edge?.fgAlphaByte == 128)
    }

    @Test func edgeShadowQuantizationHasDeepShadowSourceAndLowAlpha() {
        let edge = LinearCompositeFixtures.edges.first { $0.id == "edge_shadow_quantization" }
        #expect(edge?.fgByte == SIMD3<Float>(3, 0, 0))
        #expect(edge?.fgAlphaByte == 13)
        #expect(edge?.bgByte == SIMD3<Float>(0, 0, 0))
        #expect(edge?.bgAlphaByte == 255)
    }

    @Test func edgeZeroAlphaBleedRedOverWhiteUsesZeroSourceAlpha() {
        let edge = LinearCompositeFixtures.edges.first { $0.id == "edge_zero_alpha_bleed_red_over_white" }
        #expect(edge?.fgByte == SIMD3<Float>(255, 0, 0))
        #expect(edge?.fgAlphaByte == 0)
        #expect(edge?.bgByte == SIMD3<Float>(255, 255, 255))
        #expect(edge?.bgAlphaByte == 255)
    }

    @Test func edgeGray50OverGray50HasSameColorForFGAndBG() {
        let edge = LinearCompositeFixtures.edges.first { $0.id == "edge_gray50_over_gray50_alpha050" }
        #expect(edge?.fgByte == SIMD3<Float>(128, 128, 128))
        #expect(edge?.bgByte == SIMD3<Float>(128, 128, 128))
        #expect(edge?.fgAlphaByte == 128)
        #expect(edge?.bgAlphaByte == 255)
    }

    @Test func allFixturesUniqueAndTotalThreeEightyNine() {
        let all = LinearCompositeFixtures.all
        #expect(all.count == 389)
        let ids = all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func usageListsLinearCompositeABCommand() {
        #expect(AskiColorLabCommand.helpMessage().contains("linear-composite-ab"))
    }

    @Test func runWritesCSVAtExpectedPath() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var stderr = ""
        let status = try LinearCompositeSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { stderr += $0 })
        #expect(status == .success, "stderr: \(stderr)")
        let csv = directory.appending(path: "linear-composite-ab.csv")
        #expect(FileManager.default.fileExists(atPath: csv.path))
    }

    @Test func rowCountEqualsFixturesTimesThreePoliciesPlusOne() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try LinearCompositeSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "linear-composite-ab.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 389 * 3 + 1)
        #expect(lines.count == 1168)
    }

    @Test func headerOrderMatchesContract() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try LinearCompositeSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "linear-composite-ab.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let header = contents.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
        let expected =
            ([
                "schema_version", "command", "aski_git_sha", "run_seed",
                "sample_id", "fixture_id", "policy",
                "input_space", "input_components",
                "output_space", "output_components",
            ] + LinearCompositeCommand.metricColumns).joined(separator: ",")
        #expect(header == expected)
    }

    @Test func firstFixtureThreeRowsShareSampleIDAndFixtureID() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try LinearCompositeSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "linear-composite-ab.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let firstFixtureRows = lines[1...3].map { String($0).split(separator: ",").map(String.init) }
        let expectedPolicies = ["encoded8bit", "linear8bit", "linearFloat"]
        for (i, expected) in expectedPolicies.enumerated() {
            let row = firstFixtureRows[i]
            #expect(row[4] == "0", "sample_id should be 0 for the first fixture's rows")
            #expect(row[5] == firstFixtureRows[0][5], "fixture_id should be shared")
            #expect(row[6] == expected, "policy mismatch at row \(i)")
        }
        // The fourth row (lines[4]) starts the second fixture with sample_id 1.
        let secondFixtureFirstRow = String(lines[4]).split(separator: ",").map(String.init)
        #expect(secondFixtureFirstRow[4] == "1")
    }

    @Test func twoIdenticalRunsProduceByteIdenticalCSVs() throws {
        let directoryA = try temporaryDirectory()
        let directoryB = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryA)
            try? FileManager.default.removeItem(at: directoryB)
        }
        for dir in [directoryA, directoryB] {
            let status = try LinearCompositeSubcommand.parse([
                "--output-dir", dir.path,
                "--aski-git-sha", "test-sha",
                "--seed", "7",
            ]).execute(standardError: { _ in })
            #expect(status == .success)
        }
        let csvA = try Data(contentsOf: directoryA.appending(path: "linear-composite-ab.csv"))
        let csvB = try Data(contentsOf: directoryB.appending(path: "linear-composite-ab.csv"))
        #expect(csvA == csvB)
    }

    @Test func everyMappedEncodedRGBComponentIsInZeroOneRange() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try LinearCompositeSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "linear-composite-ab.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let mappedColumn = header.firstIndex(of: "mapped_encoded_rgb")!
        let alphaColumn = header.firstIndex(of: "mapped_alpha_byte")!
        for line in lines.dropFirst() {
            let row = String(line).split(separator: ",").map(String.init)
            let components = row[mappedColumn].split(separator: ";").compactMap { Float($0) }
            #expect(components.count == 3)
            for component in components {
                #expect(
                    component >= 0 && component <= 1,
                    "mapped_encoded_rgb out of [0, 1]: \(row[mappedColumn])")
            }
            let alpha = Int(row[alphaColumn]) ?? -1
            #expect(
                alpha >= 0 && alpha <= 255,
                "mapped_alpha_byte out of [0, 255]: \(row[alphaColumn])")
        }
    }

    @Test func linearFloatRowsReportZeroForAllThreeGroundTruthMetrics() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try LinearCompositeSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "linear-composite-ab.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let policyColumn = header.firstIndex(of: "policy")!
        let deltaEColumn = header.firstIndex(of: "delta_e_ok_to_ground_truth")!
        let encodedDistColumn = header.firstIndex(of: "encoded_rgb_distance_to_ground_truth")!
        let maxChannelColumn = header.firstIndex(of: "max_channel_abs_diff_to_ground_truth")!
        var linearFloatRowCount = 0
        for line in lines.dropFirst() {
            let row = String(line).split(separator: ",").map(String.init)
            if row[policyColumn] == "linearFloat" {
                linearFloatRowCount += 1
                // Spec §Policies "On linearFloat rows": all three
                // `*_to_ground_truth` metrics are 0.000000 by construction.
                #expect(
                    row[deltaEColumn] == "0.000000",
                    "linearFloat rows must report exact zero ΔEOK to ground truth by construction")
                #expect(
                    row[encodedDistColumn] == "0.000000",
                    "linearFloat rows must report exact zero encoded distance by construction")
                #expect(
                    row[maxChannelColumn] == "0.000000",
                    "linearFloat rows must report exact zero max-channel diff by construction")
            }
        }
        #expect(linearFloatRowCount == 389, "expected one linearFloat row per fixture")
    }

    @Test func transparentBackgroundWithZeroSourceAlphaYieldsZeroAlphaForAllPolicies() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try LinearCompositeSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "linear-composite-ab.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let fixtureColumn = header.firstIndex(of: "fixture_id")!
        let fgAlphaColumn = header.firstIndex(of: "fg_alpha_byte")!
        let bgAlphaColumn = header.firstIndex(of: "bg_alpha_byte")!
        let mappedAlphaColumn = header.firstIndex(of: "mapped_alpha_byte")!
        let mappedEncodedColumn = header.firstIndex(of: "mapped_encoded_rgb")!

        var asserted = 0
        for line in lines.dropFirst() {
            let row = String(line).split(separator: ",").map(String.init)
            guard row[fgAlphaColumn] == "0", row[bgAlphaColumn] == "0" else { continue }
            asserted += 1
            #expect(row[mappedAlphaColumn] == "0", "fixture \(row[fixtureColumn]) must report mapped_alpha_byte=0")
            let components = row[mappedEncodedColumn].split(separator: ";").compactMap { Float($0) }
            #expect(
                components == [0.0, 0.0, 0.0],
                "fixture \(row[fixtureColumn]) mapped_encoded_rgb must be (0, 0, 0), got \(row[mappedEncodedColumn])")
        }
        // 6 colors × 1 transparent bg × 1 α=0 = 6 rows per group, ×2 groups (sRGB + P3) ×3 policies = 36 rows.
        #expect(asserted == 36, "expected 36 fully-transparent fixture rows in the grid, got \(asserted)")
    }

    @Test func opaqueSourceOverOpaqueBackgroundProducesSourceColorWithinByteRounding() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try LinearCompositeSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "linear-composite-ab.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let fgAlphaColumn = header.firstIndex(of: "fg_alpha_byte")!
        let bgAlphaColumn = header.firstIndex(of: "bg_alpha_byte")!
        let fgByteColumn = header.firstIndex(of: "fg_byte")!
        let mappedAlphaColumn = header.firstIndex(of: "mapped_alpha_byte")!
        let mappedEncodedColumn = header.firstIndex(of: "mapped_encoded_rgb")!

        var asserted = 0
        for line in lines.dropFirst() {
            let row = String(line).split(separator: ",").map(String.init)
            guard row[fgAlphaColumn] == "255", row[bgAlphaColumn] == "255" else { continue }
            asserted += 1
            #expect(row[mappedAlphaColumn] == "255")
            let fgBytes = row[fgByteColumn].split(separator: ";").compactMap { Int($0) }
            let mapped = row[mappedEncodedColumn].split(separator: ";").compactMap { Float($0) }
            #expect(fgBytes.count == 3 && mapped.count == 3)
            for i in 0..<3 {
                let expected = Float(fgBytes[i]) / 255.0
                #expect(
                    abs(mapped[i] - expected) <= 1.0 / 255.0,
                    "opaque-over-opaque mapped[\(i)]=\(mapped[i]) must equal fg[\(i)]/255=\(expected) within 1/255")
            }
        }
        // 6 colors × 3 opaque bgs × 1 α=255 × 2 groups × 3 policies = 108 rows.
        #expect(asserted == 108)
    }

    @Test func zeroSourceAlphaOverOpaqueBackgroundProducesBackgroundColor() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try LinearCompositeSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "linear-composite-ab.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let fgAlphaColumn = header.firstIndex(of: "fg_alpha_byte")!
        let bgAlphaColumn = header.firstIndex(of: "bg_alpha_byte")!
        let bgByteColumn = header.firstIndex(of: "bg_byte")!
        let mappedEncodedColumn = header.firstIndex(of: "mapped_encoded_rgb")!

        var asserted = 0
        for line in lines.dropFirst() {
            let row = String(line).split(separator: ",").map(String.init)
            guard row[fgAlphaColumn] == "0", row[bgAlphaColumn] == "255" else { continue }
            asserted += 1
            let bgBytes = row[bgByteColumn].split(separator: ";").compactMap { Int($0) }
            let mapped = row[mappedEncodedColumn].split(separator: ";").compactMap { Float($0) }
            for i in 0..<3 {
                let expected = Float(bgBytes[i]) / 255.0
                #expect(
                    abs(mapped[i] - expected) <= 1.0 / 255.0,
                    "α=0 src over opaque bg: mapped[\(i)]=\(mapped[i]) must equal bg[\(i)]/255=\(expected)")
            }
        }
        // 6 colors × 3 opaque bgs × 1 α=0 × 2 groups × 3 policies = 108 rows
        // PLUS the `edge_zero_alpha_bleed_red_over_white` edge × 3 policies = 3 rows → 111 rows.
        #expect(asserted == 111)
    }

    @Test func sameFGAndBGByteFixtureProducesIdenticalEncoded8bitAndLinear8bitOutput() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try LinearCompositeSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "linear-composite-ab.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let fixtureColumn = header.firstIndex(of: "fixture_id")!
        let policyColumn = header.firstIndex(of: "policy")!
        let mappedEncodedColumn = header.firstIndex(of: "mapped_encoded_rgb")!
        let fgByteColumn = header.firstIndex(of: "fg_byte")!
        let bgByteColumn = header.firstIndex(of: "bg_byte")!

        var sameColorFixtureCount = 0
        for line in lines.dropFirst() {
            let row = String(line).split(separator: ",").map(String.init)
            guard row[policyColumn] == "encoded8bit" else { continue }
            guard row[fgByteColumn] == row[bgByteColumn] else { continue }
            sameColorFixtureCount += 1
            // Find matching linear8bit row.
            let fixtureID = row[fixtureColumn]
            let linearRow = lines.dropFirst().first { otherLine in
                let otherRow = String(otherLine).split(separator: ",").map(String.init)
                return otherRow[fixtureColumn] == fixtureID && otherRow[policyColumn] == "linear8bit"
            }
            #expect(linearRow != nil, "linear8bit row missing for fixture \(fixtureID)")
            let linearComponents = String(linearRow!).split(separator: ",").map(String.init)[mappedEncodedColumn]
                .split(separator: ";").compactMap { Float($0) }
            let encodedComponents = row[mappedEncodedColumn].split(separator: ";").compactMap { Float($0) }
            for i in 0..<3 {
                #expect(
                    abs(linearComponents[i] - encodedComponents[i]) <= 1.0 / 255.0,
                    "fixture \(fixtureID): encoded8bit (\(encodedComponents[i])) must equal linear8bit (\(linearComponents[i])) within 1/255 when fg_byte == bg_byte")
            }
        }
        // Spec §Tests Cross-fixture consistency: at least one fixture must
        // match the fg_byte == bg_byte predicate or the test trivially passes.
        // For the spec's fixture set, edge_gray50_over_gray50_alpha050 is the
        // only matching fixture.
        #expect(
            sameColorFixtureCount >= 1,
            "test must observe at least one fg_byte == bg_byte fixture; got 0 — has the edge fixture set drifted?")
    }

    @Test func edgeGray50OverWhiteEncoded8bitDistanceExceedsThresholdAndLinear8bitIsCloser() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try LinearCompositeSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "linear-composite-ab.csv")
        let (encodedDistance, linearDistance) = try edgeDistances(
            csv: csv,
            fixtureID: "edge_gray50_over_white_alpha050"
        )
        // Spec §Tests: encoded8bit row > 0.03; linear8bit row strictly smaller.
        #expect(
            encodedDistance > 0.03,
            "encoded8bit Euclidean distance \(encodedDistance) must exceed 0.03 on the discriminator fixture")
        #expect(
            linearDistance < encodedDistance,
            "linear8bit (\(linearDistance)) must be strictly closer to ground truth than encoded8bit (\(encodedDistance))")
    }

    @Test func edgeP3GreenOverWhiteShowsSameDiscriminatorPatternOnP3() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try LinearCompositeSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "linear-composite-ab.csv")
        let (encodedDistance, linearDistance) = try edgeDistances(
            csv: csv,
            fixtureID: "edge_p3_green_over_white_alpha050"
        )
        #expect(encodedDistance > 0.03)
        #expect(linearDistance < encodedDistance)
    }

    @Test func edgeZeroAlphaBleedRedOverWhiteAllPoliciesExactlyWhite() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try LinearCompositeSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "linear-composite-ab.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let fixtureColumn = header.firstIndex(of: "fixture_id")!
        let mappedEncodedColumn = header.firstIndex(of: "mapped_encoded_rgb")!
        let mappedAlphaColumn = header.firstIndex(of: "mapped_alpha_byte")!

        let rows = lines.dropFirst().filter { line in
            String(line).split(separator: ",").map(String.init)[fixtureColumn] == "edge_zero_alpha_bleed_red_over_white"
        }
        #expect(rows.count == 3, "expected three policy rows for edge_zero_alpha_bleed_red_over_white")
        for line in rows {
            let row = String(line).split(separator: ",").map(String.init)
            // Pinned exact bytewise equality per spec §Tests.
            #expect(
                row[mappedEncodedColumn] == "1.000000;1.000000;1.000000",
                "α=0 red over opaque white: encoded must be exactly (255, 255, 255) → 1.000000 per channel, got \(row[mappedEncodedColumn])")
            #expect(row[mappedAlphaColumn] == "255")
        }
    }

    @Test func edgeShadowQuantizationLinearFloatPreservesLowAmplitude() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try LinearCompositeSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "linear-composite-ab.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let fixtureColumn = header.firstIndex(of: "fixture_id")!
        let policyColumn = header.firstIndex(of: "policy")!
        let mappedLinearColumn = header.firstIndex(of: "mapped_linear_rgb")!

        let linearFloatRow = lines.dropFirst().first { line in
            let row = String(line).split(separator: ",").map(String.init)
            return row[fixtureColumn] == "edge_shadow_quantization" && row[policyColumn] == "linearFloat"
        }
        #expect(linearFloatRow != nil)
        let components = String(linearFloatRow!).split(separator: ",").map(String.init)[mappedLinearColumn]
            .split(separator: ";").compactMap { Float($0) }
        #expect(components.count == 3)
        // Spec §Tests: linearFloat reports mapped_linear_rgb.x > 3e-5.
        #expect(
            components[0] > 0.00003,
            "linearFloat must preserve the shadow-quantization R channel above 3e-5, got \(components[0])")
    }

    /// Helper: returns `(encoded8bitDistance, linear8bitDistance)` for an edge
    /// fixture's `encoded_rgb_distance_to_ground_truth` column.
    fileprivate func edgeDistances(csv: URL, fixtureID: String) throws -> (Float, Float) {
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let fixtureColumn = header.firstIndex(of: "fixture_id")!
        let policyColumn = header.firstIndex(of: "policy")!
        let distColumn = header.firstIndex(of: "encoded_rgb_distance_to_ground_truth")!

        var encoded: Float = -1
        var linear: Float = -1
        for line in lines.dropFirst() {
            let row = String(line).split(separator: ",").map(String.init)
            guard row[fixtureColumn] == fixtureID else { continue }
            if row[policyColumn] == "encoded8bit", let v = Float(row[distColumn]) {
                encoded = v
            }
            if row[policyColumn] == "linear8bit", let v = Float(row[distColumn]) {
                linear = v
            }
        }
        return (encoded, linear)
    }
}
