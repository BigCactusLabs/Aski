import ArgumentParser
import Aski
import AskiToolSupport
import Foundation
import Testing
import simd
@testable import AskiColorLab

@Suite struct AskiColorLabGamutSweepTests {
    @Test func usageListsGamutSweepCommand() {
        #expect(AskiColorLabCommand.helpMessage().contains("gamut-sweep"))
    }

    @Test func boundaryFixturesIncludeAllTenSpecCases() {
        let ids = GamutSweepFixtures.boundary.map(\.id)
        #expect(
            ids == [
                "mid_gray",
                "p3_only_green",
                "cyan_peak",
                "yellow_peak",
                "blue_corner",
                "deep_magenta",
                "deep_red",
                "lightness_floor",
                "lightness_ceiling",
                "superwhite_csswg6999",
            ])
    }

    @Test func oklchConversionUsesRadians() {
        // OkLCh(0.5, 0.1, 90°) → OKLab: a = 0.1·cos(π/2) ≈ 0; b = 0.1·sin(π/2) = 0.1.
        let fixture = GamutSweepFixture(
            id: "test",
            okLChL: 0.5,
            okLChC: 0.1,
            okLChHueDegrees: 90
        )
        let oklab = fixture.sourceOKLab
        #expect(abs(oklab.x - 0.5) < 1e-6)
        #expect(abs(oklab.y) < 1e-6)
        #expect(abs(oklab.z - 0.1) < 1e-6)
    }

    @Test func gridHasSevenLightnessTimesFourChromaTimesTwentyFourHues() {
        #expect(GamutSweepFixtures.grid.count == 7 * 4 * 24)
    }

    @Test func gridIsOrderedLightnessThenChromaThenHue() {
        let g = GamutSweepFixtures.grid
        #expect(g.first?.id == "grid_L000_C010_H000")
        // Second row: same L, same C, hue advances by 15°.
        #expect(g[1].id == "grid_L000_C010_H015")
        // 24th row: same L, same C, hue wrapped to last value.
        #expect(g[23].id == "grid_L000_C010_H345")
        // 25th row: same L, next C.
        #expect(g[24].id == "grid_L000_C020_H000")
        // 97th row: same L=0, next-after-C=0.8 — but we only have 4 C values,
        // so row 96 starts the next L. 4 × 24 = 96.
        #expect(g[96].id == "grid_L005_C010_H000")
    }

    @Test func gridIDFormatUsesZeroPaddedThreeDigits() {
        // L = 0.75, C = 0.40, h = 195° → L075_C040_H195.
        let target = GamutSweepFixtures.grid.first {
            abs($0.okLChL - 0.75) < 1e-6
                && abs($0.okLChC - 0.4) < 1e-6
                && abs($0.okLChHueDegrees - 195) < 1e-6
        }
        #expect(target?.id == "grid_L075_C040_H195")
    }

    @Test func gridIDFormatsLightnessOneAsL100() {
        let target = GamutSweepFixtures.grid.first {
            abs($0.okLChL - 1) < 1e-6
                && abs($0.okLChC - 0.1) < 1e-6
                && abs($0.okLChHueDegrees) < 1e-6
        }
        #expect(target?.id == "grid_L100_C010_H000")
    }

    @Test func allFixturesUniqueByID() {
        let ids = GamutSweepFixtures.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.count == 682)
    }

    @Test func adaptiveL0RoundTripsMidGray() {
        let oklab = ColorConversion.linearSRGBToOKLAB(SIMD3<Float>(0.5, 0.5, 0.5))
        let mapped = GamutSweepPolicies.adaptiveL0(oklab: oklab, target: .sRGB)
        #expect(abs(mapped.x - 0.5) < 0.01)
        #expect(abs(mapped.y - 0.5) < 0.01)
        #expect(abs(mapped.z - 0.5) < 0.01)
    }

    @Test func clipPolicyClampsSuperWhiteToOne() {
        // OkLab(1.5, 0, 0) → linear sRGB (3.375, 3.375, 3.375) → clip to (1, 1, 1).
        let oklab = SIMD3<Float>(1.5, 0, 0)
        let mapped = GamutSweepPolicies.clip(oklab: oklab, target: .sRGB)
        #expect(abs(mapped.x - 1) < 1e-6)
        #expect(abs(mapped.y - 1) < 1e-6)
        #expect(abs(mapped.z - 1) < 1e-6)
    }

    @Test func clipPolicyClampsNegativeChannelsToZero() {
        // Pick an OKLab with a negative linear RGB channel for sRGB and verify clip → 0.
        let oklab = SIMD3<Float>(0.2, -0.2, -0.2)
        let mapped = GamutSweepPolicies.clip(oklab: oklab, target: .sRGB)
        #expect(mapped.x >= 0 && mapped.x <= 1)
        #expect(mapped.y >= 0 && mapped.y <= 1)
        #expect(mapped.z >= 0 && mapped.z <= 1)
    }

    @Test func localMINDESuperWhiteShortCircuitsToWhite() {
        // superwhite_csswg6999: OkLCh(1.044, 0, 336°). L > 1, so guard returns
        // target-gamut white without entering the binary search.
        let fixture = GamutSweepFixture(
            id: "superwhite_csswg6999",
            okLChL: 1.044,
            okLChC: 0,
            okLChHueDegrees: 336
        )
        let mapped = GamutSweepPolicies.localMINDE(oklab: fixture.sourceOKLab, target: .sRGB)
        #expect(abs(mapped.x - 1) < 0.005)
        #expect(abs(mapped.y - 1) < 0.005)
        #expect(abs(mapped.z - 1) < 0.005)
    }

    @Test func localMINDELightnessFloorShortCircuitsToBlack() {
        // OkLCh(0, 0.1, 0°). L = 0, so guard returns black.
        let fixture = GamutSweepFixture(
            id: "lightness_floor",
            okLChL: 0,
            okLChC: 0.1,
            okLChHueDegrees: 0
        )
        let mapped = GamutSweepPolicies.localMINDE(oklab: fixture.sourceOKLab, target: .displayP3)
        #expect(abs(mapped.x) < 0.005)
        #expect(abs(mapped.y) < 0.005)
        #expect(abs(mapped.z) < 0.005)
    }

    @Test func localMINDEInGamutChromaticPassesThroughUntouched() {
        // OkLCh(0.5, 0.1, 90°) is in sRGB; the in-gamut guard must return the
        // raw linear RGB rather than running the binary search.
        let fixture = GamutSweepFixture(
            id: "in_gamut_chromatic",
            okLChL: 0.5,
            okLChC: 0.1,
            okLChHueDegrees: 90
        )
        let mapped = GamutSweepPolicies.localMINDE(oklab: fixture.sourceOKLab, target: .sRGB)
        let direct = ColorConversion.oklabToLinearSRGB(fixture.sourceOKLab)
        // Guard returns the direct conversion (strict in [0, 1] case), so the
        // delta from a fresh conversion is zero up to float precision.
        #expect(simd_length(mapped - direct) < 1e-5)
    }

    @Test func localMINDEOutOfGamutReducesChromaTowardLow() {
        // cyan_peak at sRGB is out of gamut. Run localMINDE and verify the
        // mapped chroma is strictly less than source chroma (binary search
        // converged toward an in-gamut clipped candidate).
        let fixture = GamutSweepFixture(
            id: "cyan_peak",
            okLChL: 0.75,
            okLChC: 0.4,
            okLChHueDegrees: 195
        )
        let mapped = GamutSweepPolicies.localMINDE(oklab: fixture.sourceOKLab, target: .sRGB)
        let mappedOKLab = ColorConversion.linearSRGBToOKLAB(mapped)
        let mappedC = sqrt(mappedOKLab.y * mappedOKLab.y + mappedOKLab.z * mappedOKLab.z)
        #expect(
            mappedC < fixture.okLChC,
            "localMINDE must reduce chroma when source is out of target gamut")
        #expect(
            mappedC > 0,
            "localMINDE must not collapse to achromatic for an L ∈ (0, 1) chromatic source")
    }

    /// **Red-signal test.** Distinguishes real `localMINDE` from the Task 4
    /// `clip` placeholder. Two algorithm-specific assertions a per-channel
    /// clamp cannot satisfy:
    ///   1. The mapped linear RGB is *materially different* from `clip`'s
    ///      output (Euclidean delta > 0.01).
    ///   2. The round-tripped `mapped_oklab.x` stays within 0.05 of source L.
    ///      `localMINDE` builds candidates as `OkLCh(L=source, mid·cosH, mid·sinH)`
    ///      then channel-clips; the JND threshold (0.02) bounds L drift to a
    ///      few hundredths. `clip` does per-channel clamping in linear RGB
    ///      space, which has no L-preservation property and shifts L
    ///      substantially on out-of-gamut chromatic inputs like cyan_peak.
    @Test func localMINDEOutOfGamutDiffersFromClipPlaceholderAndPreservesL() {
        let fixture = GamutSweepFixture(
            id: "cyan_peak",
            okLChL: 0.75,
            okLChC: 0.4,
            okLChHueDegrees: 195
        )
        let lm = GamutSweepPolicies.localMINDE(oklab: fixture.sourceOKLab, target: .sRGB)
        let clip = GamutSweepPolicies.clip(oklab: fixture.sourceOKLab, target: .sRGB)
        #expect(
            simd_length(lm - clip) > 0.01,
            "localMINDE must produce different output than clip on out-of-gamut chromatic input")
        let lmOKLab = ColorConversion.linearSRGBToOKLAB(lm)
        #expect(
            abs(lmOKLab.x - 0.75) < 0.05,
            "localMINDE must preserve source L within JND envelope; got mapped L \(lmOKLab.x)")
    }

    @Test func rayTraceInGamutChromaticPassesThroughUntouched() {
        // OkLCh(0.5, 0.1, 90°) is in sRGB. The strict [0, 1] in-gamut guard
        // must return the direct conversion; without it the loop would push
        // the iterate to the gamut surface and shrink chroma needlessly.
        let fixture = GamutSweepFixture(
            id: "in_gamut_chromatic",
            okLChL: 0.5,
            okLChC: 0.1,
            okLChHueDegrees: 90
        )
        let mapped = GamutSweepPolicies.rayTrace(oklab: fixture.sourceOKLab, target: .sRGB)
        let direct = ColorConversion.oklabToLinearSRGB(fixture.sourceOKLab)
        #expect(simd_length(mapped - direct) < 1e-5)
    }

    @Test func rayTraceLightnessCeilingShortCircuitsToWhite() {
        let oklab = SIMD3<Float>(1.044, 0, 0)
        let mapped = GamutSweepPolicies.rayTrace(oklab: oklab, target: .sRGB)
        #expect(abs(mapped.x - 1) < 0.005)
        #expect(abs(mapped.y - 1) < 0.005)
        #expect(abs(mapped.z - 1) < 0.005)
    }

    @Test func rayTraceLightnessFloorShortCircuitsToBlack() {
        let oklab = SIMD3<Float>(0, 0.1, 0)
        let mapped = GamutSweepPolicies.rayTrace(oklab: oklab, target: .displayP3)
        #expect(abs(mapped.x) < 0.005)
        #expect(abs(mapped.y) < 0.005)
        #expect(abs(mapped.z) < 0.005)
    }

    @Test func rayTraceOutOfGamutReturnsInGamut() {
        // deep_magenta is wildly out of sRGB.
        let fixture = GamutSweepFixture(
            id: "deep_magenta",
            okLChL: 0.5,
            okLChC: 0.8,
            okLChHueDegrees: 315
        )
        let mapped = GamutSweepPolicies.rayTrace(oklab: fixture.sourceOKLab, target: .sRGB)
        #expect(mapped.x >= 0 && mapped.x <= 1)
        #expect(mapped.y >= 0 && mapped.y <= 1)
        #expect(mapped.z >= 0 && mapped.z <= 1)
    }

    /// **Red-signal test.** Distinguishes real `rayTrace` from the Task 4
    /// `clip` placeholder. Two algorithm-specific assertions a per-channel
    /// clamp cannot satisfy:
    ///   1. Output is materially different from `clip`'s output.
    ///   2. `mapped_oklab.x` ≈ source L. Ray-trace explicitly restores source
    ///      `(L, h)` on each of the three OkLCh-correction iterations, so the
    ///      final mapped color sits on the constant-L plane. `clip`'s
    ///      per-channel clamp has no such property and shifts L noticeably on
    ///      out-of-gamut chromatic inputs.
    @Test func rayTraceOutOfGamutDiffersFromClipPlaceholderAndPreservesL() {
        let fixture = GamutSweepFixture(
            id: "cyan_peak",
            okLChL: 0.75,
            okLChC: 0.4,
            okLChHueDegrees: 195
        )
        let rt = GamutSweepPolicies.rayTrace(oklab: fixture.sourceOKLab, target: .sRGB)
        let clip = GamutSweepPolicies.clip(oklab: fixture.sourceOKLab, target: .sRGB)
        #expect(
            simd_length(rt - clip) > 0.01,
            "rayTrace must produce different output than clip on out-of-gamut chromatic input")
        let rtOKLab = ColorConversion.linearSRGBToOKLAB(rt)
        #expect(
            abs(rtOKLab.x - 0.75) < 0.05,
            "rayTrace must preserve source L via OkLCh correction; got mapped L \(rtOKLab.x)")
    }

    /// Red-signal: ray-trace must land mapped linear RGB *on* the unit cube
    /// boundary (at least one channel at 0 or 1) for an out-of-gamut input.
    ///
    /// Catches the anchor-update-before-intersection ordering bug: when the
    /// OkLCh-corrected iterate is strictly inside the cube, moving `anchor`
    /// to it BEFORE the next `rayBoxIntersection` zeros the ray direction,
    /// degenerating to the interior corrected point. A merely-in-`[0,1]`
    /// assertion (see `rayTraceOutOfGamutReturnsInGamut`) trivially holds
    /// on the buggy interior point and does not detect this regression.
    @Test func rayTraceOutOfGamutLandsOnCubeFace() {
        // grid_L095_C080_H105 sits well out of sRGB. Reference algorithm
        // lands near (1.0, 0.909, 0.106) — one channel saturated.
        let fixture = GamutSweepFixture(
            id: "grid_L095_C080_H105",
            okLChL: 0.95,
            okLChC: 0.8,
            okLChHueDegrees: 105
        )
        let mapped = GamutSweepPolicies.rayTrace(oklab: fixture.sourceOKLab, target: .sRGB)
        let epsilon: Float = 1e-3
        let touchesFace =
            mapped.x <= epsilon || mapped.x >= 1 - epsilon
            || mapped.y <= epsilon || mapped.y >= 1 - epsilon
            || mapped.z <= epsilon || mapped.z >= 1 - epsilon
        #expect(
            touchesFace,
            "rayTrace must land mapped linear RGB on a unit cube face for out-of-gamut input; got interior point \(mapped)")
    }

    @Test func edgeSeekerLightnessCeilingReturnsWhite() {
        // OkLCh(1, 0.1, 0°) → guard returns achromatic at hue (1, 0, 0) → white.
        let fixture = GamutSweepFixture(
            id: "lightness_ceiling",
            okLChL: 1,
            okLChC: 0.1,
            okLChHueDegrees: 0
        )
        let mapped = EdgeSeekerMapping.forSRGB.map(oklab: fixture.sourceOKLab)
        #expect(abs(mapped.x - 1) < 0.005)
        #expect(abs(mapped.y - 1) < 0.005)
        #expect(abs(mapped.z - 1) < 0.005)
    }

    @Test func edgeSeekerLightnessFloorReturnsBlack() {
        let fixture = GamutSweepFixture(
            id: "lightness_floor",
            okLChL: 0,
            okLChC: 0.1,
            okLChHueDegrees: 0
        )
        let mapped = EdgeSeekerMapping.forDisplayP3.map(oklab: fixture.sourceOKLab)
        #expect(abs(mapped.x) < 0.005)
        #expect(abs(mapped.y) < 0.005)
        #expect(abs(mapped.z) < 0.005)
    }

    @Test func edgeSeekerSRGBCuspIsSmallerThanP3Cusp() {
        // p3_only_green: in P3, out of sRGB. EdgeSeeker on sRGB must reduce
        // chroma more than EdgeSeeker on P3 — the sRGB gamut surface is
        // strictly inside the P3 gamut surface at this hue/L.
        let fixture = GamutSweepFixture(
            id: "p3_only_green",
            okLChL: 0.87,
            okLChC: 0.295,
            okLChHueDegrees: 142
        )
        let sRGBMapped = EdgeSeekerMapping.forSRGB.map(oklab: fixture.sourceOKLab)
        let p3Mapped = EdgeSeekerMapping.forDisplayP3.map(oklab: fixture.sourceOKLab)

        let sRGBMappedOKLab = ColorConversion.linearSRGBToOKLAB(sRGBMapped)
        let p3MappedOKLab = ColorConversion.linearP3ToOKLAB(p3Mapped)
        let sRGBMappedC = sqrt(sRGBMappedOKLab.y * sRGBMappedOKLab.y + sRGBMappedOKLab.z * sRGBMappedOKLab.z)
        let p3MappedC = sqrt(p3MappedOKLab.y * p3MappedOKLab.y + p3MappedOKLab.z * p3MappedOKLab.z)

        #expect(
            sRGBMappedC < p3MappedC,
            "sRGB EdgeSeeker must reduce chroma more than P3 EdgeSeeker at a P3-only hue")
        #expect(
            sRGBMappedC < fixture.okLChC,
            "sRGB EdgeSeeker must reduce p3_only_green chroma below source")
    }

    @Test func edgeSeekerInGamutChromaticPreservesChroma() {
        // OkLCh(0.5, 0.1, 90°) is in sRGB. EdgeSeeker's natural
        // min(source_C, edge_C) preserves it: edge_C at this (L, h) > 0.1.
        let fixture = GamutSweepFixture(
            id: "in_gamut_chromatic",
            okLChL: 0.5,
            okLChC: 0.1,
            okLChHueDegrees: 90
        )
        let mapped = EdgeSeekerMapping.forSRGB.map(oklab: fixture.sourceOKLab)
        let mappedOKLab = ColorConversion.linearSRGBToOKLAB(mapped)
        let mappedC = sqrt(mappedOKLab.y * mappedOKLab.y + mappedOKLab.z * mappedOKLab.z)
        // Allow generous tolerance — cusp LUT interpolation introduces small
        // chroma deltas even when the source is comfortably in-gamut.
        #expect(abs(mappedC - fixture.okLChC) < 0.005)
    }

    /// **Red-signal test.** Distinguishes real `edgeSeeker` from the Task 4
    /// `clip` placeholder. Two algorithm-specific assertions:
    ///   1. Output is materially different from `clip`'s output on cyan_peak.
    ///   2. `mapped_oklab.x` ≈ source L. EdgeSeeker operates entirely in OkLCh
    ///      with constant `L`; the only departure from source L comes from
    ///      target-gamut round-trip float error, bounded near `1e-3`. Clip's
    ///      per-channel clamp has no L-preservation property and shifts L
    ///      noticeably on out-of-gamut chromatic inputs.
    @Test func edgeSeekerOutOfGamutDiffersFromClipPlaceholderAndPreservesL() {
        let fixture = GamutSweepFixture(
            id: "cyan_peak",
            okLChL: 0.75,
            okLChC: 0.4,
            okLChHueDegrees: 195
        )
        let es = EdgeSeekerMapping.forSRGB.map(oklab: fixture.sourceOKLab)
        let clip = GamutSweepPolicies.clip(oklab: fixture.sourceOKLab, target: .sRGB)
        #expect(
            simd_length(es - clip) > 0.01,
            "edgeSeeker must produce different output than clip on out-of-gamut chromatic input")
        let esOKLab = ColorConversion.linearSRGBToOKLAB(es)
        #expect(
            abs(esOKLab.x - 0.75) < 0.05,
            "edgeSeeker must preserve source L by construction; got mapped L \(esOKLab.x)")
    }

    @Test func chromaReductionPctAchromaticSourceWritesZero() {
        // source_C < 1e-6, regardless of mapped_C, must yield 0.
        let zero = GamutSweepMetrics.chromaReductionPct(sourceC: 0, mappedC: 0)
        #expect(zero == 0)
        let zeroEvenIfMappedIsZero = GamutSweepMetrics.chromaReductionPct(sourceC: 1e-9, mappedC: 0.5)
        #expect(zeroEvenIfMappedIsZero == 0)
    }

    @Test func chromaReductionPctChromaticToAchromaticWritesOneHundred() {
        let value = GamutSweepMetrics.chromaReductionPct(sourceC: 0.3, mappedC: 0)
        #expect(value == 100)
    }

    @Test func chromaReductionPctHalvingChromaWritesFifty() {
        let value = GamutSweepMetrics.chromaReductionPct(sourceC: 0.4, mappedC: 0.2)
        #expect(abs(value - 50) < 1e-4)
    }

    @Test func hueDeltaAchromaticReturnsZero() {
        let source = SIMD3<Float>(0.5, 0, 0)
        let mapped = SIMD3<Float>(0.5, 0.1, 0.1)
        #expect(GamutSweepMetrics.hueDeltaDegrees(source: source, mapped: mapped) == 0)
        #expect(GamutSweepMetrics.hueDeltaDegrees(source: mapped, mapped: source) == 0)
    }

    @Test func hueDeltaWrapsToMinus180And180Range() {
        // Source at 170°, mapped at -170° (≡ 190°). Signed delta = 20° (CCW).
        let source = SIMD3<Float>(0.5, 0.1 * cos(170 * .pi / 180), 0.1 * sin(170 * .pi / 180))
        let mapped = SIMD3<Float>(0.5, 0.1 * cos(-170 * .pi / 180), 0.1 * sin(-170 * .pi / 180))
        let delta = GamutSweepMetrics.hueDeltaDegrees(source: source, mapped: mapped)
        #expect(abs(delta - 20) < 0.1)
    }

    @Test func encodedRGBAppliesSRGBTransferAndClamps() {
        let linear = SIMD3<Float>(0.5, 0, 1)
        let encoded = GamutSweepMetrics.encodedRGB(linear)
        // sRGB encode of 0.5 ≈ 0.735355, of 0 = 0, of 1 = 1.
        #expect(abs(encoded.x - 0.735355) < 1e-3)
        #expect(abs(encoded.y) < 1e-6)
        #expect(abs(encoded.z - 1) < 1e-6)
    }

    @Test func sourceInTargetGamutUsesAskiSlack() {
        // OKLab(0.5, 0, 0) → linear RGB sits inside [0, 1] → true for sRGB.
        let oklab = ColorConversion.linearSRGBToOKLAB(SIMD3<Float>(0.5, 0.5, 0.5))
        #expect(GamutSweepMetrics.isSourceInTargetGamut(oklab: oklab, target: .sRGB))
        // p3_only_green is out of sRGB, in P3.
        let p3OnlyGreen = GamutSweepFixture(
            id: "p3_only_green",
            okLChL: 0.87,
            okLChC: 0.295,
            okLChHueDegrees: 142
        ).sourceOKLab
        #expect(!GamutSweepMetrics.isSourceInTargetGamut(oklab: p3OnlyGreen, target: .sRGB))
        #expect(GamutSweepMetrics.isSourceInTargetGamut(oklab: p3OnlyGreen, target: .displayP3))
    }

    @Test func runWritesCSVAtExpectedPath() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var stderr = ""
        let status = try GamutSweepSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { stderr += $0 })
        #expect(status == .success, "stderr: \(stderr)")
        let csv = directory.appending(path: "gamut-sweep.csv")
        #expect(FileManager.default.fileExists(atPath: csv.path))
    }

    @Test func rowCountEqualsFixturesTimesPoliciesTimesGamutsPlusOne() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try GamutSweepSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "gamut-sweep.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 682 * 5 * 2 + 1)
        #expect(lines.count == 6821)
    }

    @Test func headerOrderMatchesContract() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try GamutSweepSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "gamut-sweep.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let header = contents.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
        let expected =
            ([
                "schema_version", "command", "aski_git_sha", "run_seed",
                "sample_id", "fixture_id", "policy",
                "input_space", "input_components",
                "output_space", "output_components",
            ] + GamutSweepCommand.metricColumns).joined(separator: ",")
        #expect(header == expected)
    }

    @Test func firstFixtureTenRowsShareSampleIDAndFixtureID() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try GamutSweepSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "gamut-sweep.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        // Rows 1...10 are the first fixture (line 0 is the header).
        let firstFixtureRows = lines[1...10].map { String($0).split(separator: ",").map(String.init) }
        let expectedSequence: [(String, String)] = [
            ("adaptiveL0", "sRGB"),
            ("adaptiveL0", "displayP3"),
            ("clip", "sRGB"),
            ("clip", "displayP3"),
            ("localMINDE", "sRGB"),
            ("localMINDE", "displayP3"),
            ("rayTrace", "sRGB"),
            ("rayTrace", "displayP3"),
            ("edgeSeeker", "sRGB"),
            ("edgeSeeker", "displayP3"),
        ]
        for (i, expected) in expectedSequence.enumerated() {
            let row = firstFixtureRows[i]
            #expect(row[4] == "0", "sample_id should be 0 for the first fixture's rows")
            #expect(row[5] == firstFixtureRows[0][5], "fixture_id should be shared")
            #expect(row[6] == expected.0, "policy mismatch at row \(i)")
            // target_gamut is the 12th metric column; shared prefix has 11 columns.
            let targetGamutColumnIndex = 11 + 0
            #expect(row[targetGamutColumnIndex] == expected.1, "target_gamut mismatch at row \(i)")
        }
        // The eleventh row (lines[11]) starts the second fixture with sample_id 1.
        let secondFixtureFirstRow = String(lines[11]).split(separator: ",").map(String.init)
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
            let status = try GamutSweepSubcommand.parse([
                "--output-dir", dir.path,
                "--aski-git-sha", "test-sha",
                "--seed", "7",
            ]).execute(standardError: { _ in })
            #expect(status == .success)
        }
        let csvA = try Data(contentsOf: directoryA.appending(path: "gamut-sweep.csv"))
        let csvB = try Data(contentsOf: directoryB.appending(path: "gamut-sweep.csv"))
        #expect(csvA == csvB)
    }

    @Test func adaptiveL0RowsReportZeroEncodedDistanceFromBaseline() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try GamutSweepSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "gamut-sweep.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let policyColumn = header.firstIndex(of: "policy")!
        let distanceColumn = header.firstIndex(of: "encoded_rgb_distance_from_baseline")!
        var adaptiveL0RowCount = 0
        for line in lines.dropFirst() {
            let row = String(line).split(separator: ",").map(String.init)
            if row[policyColumn] == "adaptiveL0" {
                adaptiveL0RowCount += 1
                #expect(
                    row[distanceColumn] == "0.000000",
                    "adaptiveL0 rows must report exact zero distance from baseline by construction")
            }
        }
        #expect(adaptiveL0RowCount == 682 * 2, "expected one adaptiveL0 row per fixture per target")
    }

    @Test func everyMappedEncodedRGBComponentIsInZeroOneRange() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try GamutSweepSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "gamut-sweep.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let mappedColumn = header.firstIndex(of: "mapped_encoded_rgb")!
        for line in lines.dropFirst() {
            let row = String(line).split(separator: ",").map(String.init)
            let components = row[mappedColumn].split(separator: ";").compactMap { Float($0) }
            #expect(components.count == 3)
            for component in components {
                #expect(
                    component >= 0 && component <= 1,
                    "mapped_encoded_rgb out of [0, 1]: \(row[mappedColumn])")
            }
        }
    }

    @Test func superwhiteCsswg6999CompletesUnderEveryPolicy() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try GamutSweepSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "gamut-sweep.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let fixtureColumn = header.firstIndex(of: "fixture_id")!
        let policyColumn = header.firstIndex(of: "policy")!
        let deltaColumn = header.firstIndex(of: "delta_e_ok")!

        let rows = lines.dropFirst().filter { line in
            String(line).split(separator: ",").map(String.init)[fixtureColumn] == "superwhite_csswg6999"
        }
        #expect(
            rows.count == 10,
            "every policy × gamut must complete on superwhite_csswg6999 (the CSSWG #6999 infinite-loop case)")
        for line in rows {
            let row = String(line).split(separator: ",").map(String.init)
            let value = Float(row[deltaColumn])
            #expect(value != nil, "delta_e_ok must parse")
            if let value {
                #expect(value.isFinite, "delta_e_ok must be finite on \(row[policyColumn])")
            }
        }
    }

    @Test func midGrayIsInGamutForBothTargetsOnEveryPolicy() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try GamutSweepSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "gamut-sweep.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let fixtureColumn = header.firstIndex(of: "fixture_id")!
        let inGamutColumn = header.firstIndex(of: "source_in_target_gamut")!
        let deltaColumn = header.firstIndex(of: "delta_e_ok")!

        let rows = lines.dropFirst().filter { line in
            String(line).split(separator: ",").map(String.init)[fixtureColumn] == "mid_gray"
        }
        #expect(rows.count == 10)
        for line in rows {
            let row = String(line).split(separator: ",").map(String.init)
            #expect(
                row[inGamutColumn] == "true",
                "mid_gray must report source_in_target_gamut=true on every policy and gamut")
            if let value = Float(row[deltaColumn]) {
                #expect(
                    value < 0.005,
                    "mid_gray delta_e_ok must be below 0.005 on every policy (achromatic in-gamut fast path)")
            }
        }
    }

    @Test func lightnessCeilingMapsNearWhiteUnderGuardedPolicies() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try GamutSweepSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "gamut-sweep.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let fixtureColumn = header.firstIndex(of: "fixture_id")!
        let policyColumn = header.firstIndex(of: "policy")!
        let mappedOKLabColumn = header.firstIndex(of: "mapped_oklab")!

        for fixtureID in ["lightness_ceiling", "lightness_floor"] {
            let rows = lines.dropFirst().filter { line in
                String(line).split(separator: ",").map(String.init)[fixtureColumn] == fixtureID
            }
            #expect(rows.count == 10)
            for line in rows {
                let row = String(line).split(separator: ",").map(String.init)
                let policy = row[policyColumn]
                guard ["localMINDE", "rayTrace", "edgeSeeker"].contains(policy) else { continue }
                let components = row[mappedOKLabColumn].split(separator: ";").compactMap { Float($0) }
                #expect(components.count == 3)
                let mappedL = components.first ?? Float.nan
                if fixtureID == "lightness_ceiling" {
                    #expect(
                        mappedL >= 0.995 && mappedL <= 1.005,
                        "lightness_ceiling under \(policy) must short-circuit to L≈1, got \(mappedL)")
                } else {
                    #expect(
                        mappedL >= -0.005 && mappedL <= 0.005,
                        "lightness_floor under \(policy) must short-circuit to L≈0, got \(mappedL)")
                }
            }
        }
    }

    @Test func p3OnlyGreenFlipsInTargetGamutAcrossGamuts() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try GamutSweepSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "gamut-sweep.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let fixtureColumn = header.firstIndex(of: "fixture_id")!
        let targetColumn = header.firstIndex(of: "target_gamut")!
        let inGamutColumn = header.firstIndex(of: "source_in_target_gamut")!

        let rows = lines.dropFirst().filter { line in
            String(line).split(separator: ",").map(String.init)[fixtureColumn] == "p3_only_green"
        }
        #expect(rows.count == 10)
        for line in rows {
            let row = String(line).split(separator: ",").map(String.init)
            let target = row[targetColumn]
            let inGamut = row[inGamutColumn]
            if target == "sRGB" {
                #expect(
                    inGamut == "false",
                    "p3_only_green must be out of sRGB on every policy row")
            } else if target == "displayP3" {
                #expect(
                    inGamut == "true",
                    "p3_only_green must be in Display P3 on every policy row")
            }
        }
    }

    /// Spec §Tests: "cyan_peak under displayP3 shows nonzero chroma_reduction_pct
    /// divergence between at least two candidate policies. Sanity check that the
    /// five algorithms are not collapsed to identical behavior."
    ///
    /// Includes ALL FIVE policies — clip's per-channel clamp is structurally
    /// different from the gamut-aware candidates (localMINDE / rayTrace /
    /// edgeSeeker), and adaptiveL0's adaptive-anchor projection differs from
    /// constant-L mapping. Excluding clip and adaptiveL0 makes the test too
    /// strict: on cyan_peak under displayP3, the three CSS Color 4 candidates
    /// converge to within ~1pp of each other near the P3 cyan boundary, so a
    /// candidates-only spread of `> 1pp` is not robustly satisfiable. The spec
    /// language ("at least two candidate policies") does not exclude clip; the
    /// invariant is "not all five collapsed."
    @Test func cyanPeakDisplayP3ShowsDivergenceAcrossThePolicies() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try GamutSweepSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "gamut-sweep.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let fixtureColumn = header.firstIndex(of: "fixture_id")!
        let policyColumn = header.firstIndex(of: "policy")!
        let targetColumn = header.firstIndex(of: "target_gamut")!
        let chromaReductionColumn = header.firstIndex(of: "chroma_reduction_pct")!

        let cyanP3Rows = lines.dropFirst().filter { line in
            let row = String(line).split(separator: ",").map(String.init)
            return row[fixtureColumn] == "cyan_peak" && row[targetColumn] == "displayP3"
        }
        #expect(cyanP3Rows.count == 5)
        let reductions = cyanP3Rows.compactMap { line -> (String, Float)? in
            let row = String(line).split(separator: ",").map(String.init)
            guard let value = Float(row[chromaReductionColumn]) else { return nil }
            return (row[policyColumn], value)
        }
        let minR = reductions.map(\.1).min() ?? 0
        let maxR = reductions.map(\.1).max() ?? 0
        #expect(
            maxR - minR > 1,
            "cyan_peak displayP3 chroma_reduction_pct spread across all five policies must exceed 1pp — got spread \(maxR - minR) over \(reductions.map { "\($0.0)=\($0.1)" }.joined(separator: ", "))"
        )
    }

    @Test func cyanPeakSRGBLocalMINDEAndEdgeSeekerAgreeWithinTwentyPercent() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try GamutSweepSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "gamut-sweep.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let fixtureColumn = header.firstIndex(of: "fixture_id")!
        let policyColumn = header.firstIndex(of: "policy")!
        let targetColumn = header.firstIndex(of: "target_gamut")!
        let chromaReductionColumn = header.firstIndex(of: "chroma_reduction_pct")!

        var localMINDE: Float?
        var edgeSeeker: Float?
        for line in lines.dropFirst() {
            let row = String(line).split(separator: ",").map(String.init)
            guard row[fixtureColumn] == "cyan_peak" && row[targetColumn] == "sRGB" else { continue }
            if row[policyColumn] == "localMINDE" { localMINDE = Float(row[chromaReductionColumn]) }
            if row[policyColumn] == "edgeSeeker" { edgeSeeker = Float(row[chromaReductionColumn]) }
        }
        guard let localMINDE, let edgeSeeker else {
            Issue.record("missing cyan_peak sRGB rows for localMINDE or edgeSeeker")
            return
        }
        #expect(
            abs(localMINDE - edgeSeeker) <= 20,
            "localMINDE (\(localMINDE)) and edgeSeeker (\(edgeSeeker)) must agree within 20pp on cyan_peak sRGB — a buggy localMINDE returning the mid candidate would desaturate ~half-chroma further than edgeSeeker"
        )
    }

    @Test func inGamutChromaticGridFixturePreservesChromaUnderEveryCandidate() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try GamutSweepSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        let csv = directory.appending(path: "gamut-sweep.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let fixtureColumn = header.firstIndex(of: "fixture_id")!
        let policyColumn = header.firstIndex(of: "policy")!
        let chromaReductionColumn = header.firstIndex(of: "chroma_reduction_pct")!

        let rows = lines.dropFirst().filter { line in
            String(line).split(separator: ",").map(String.init)[fixtureColumn] == "grid_L050_C010_H090"
        }
        #expect(rows.count == 10)
        for line in rows {
            let row = String(line).split(separator: ",").map(String.init)
            let policy = row[policyColumn]
            guard ["localMINDE", "rayTrace", "edgeSeeker"].contains(policy) else { continue }
            if let value = Float(row[chromaReductionColumn]) {
                #expect(
                    value < 0.5,
                    "in-gamut chromatic fixture grid_L050_C010_H090 must preserve chroma under \(policy), got \(value)%")
            }
        }
    }

    @Test func gamutSweepRayTraceRowsUseProductionRayTrace() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let status = try GamutSweepSubcommand.parse([
            "--output-dir", directory.path,
            "--aski-git-sha", "test-sha",
        ]).execute(standardError: { _ in })
        #expect(status == .success)

        let csv = directory.appending(path: "gamut-sweep.csv")
        let contents = try String(contentsOf: csv, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0]).split(separator: ",").map(String.init)
        let formattedVector = CSVSchema.formatSIMD3(SIMD3<Float>(1, 0.5, 0))
        #expect(formattedVector == "1.000000;0.500000;0.000000")
        #expect(!formattedVector.contains(","))
        let fixtureColumn = header.firstIndex(of: "fixture_id")!
        let policyColumn = header.firstIndex(of: "policy")!
        let targetColumn = header.firstIndex(of: "target_gamut")!
        let mappedEncodedColumn = header.firstIndex(of: "mapped_encoded_rgb")!

        let row = lines.dropFirst()
            .map { String($0).split(separator: ",").map(String.init) }
            .first { columns in
                columns[fixtureColumn] == "cyan_peak"
                    && columns[policyColumn] == "rayTrace"
                    && columns[targetColumn] == "sRGB"
            }

        guard let row else {
            Issue.record("missing cyan_peak rayTrace sRGB row")
            return
        }

        let fixture = GamutSweepFixtures.boundary.first { $0.id == "cyan_peak" }!
        let expected = GamutSweepMetrics.encodedRGB(GamutMapping.rayTraceToSRGB(fixture.sourceOKLab))
        #expect(row[mappedEncodedColumn] == CSVSchema.formatSIMD3(expected))
    }

    @Test func gamutSweepBaselinePolicyLabelRemainsAdaptiveL0() {
        #expect(GamutSweepCommand.baselinePolicyLabel == "adaptiveL0")
    }

    fileprivate func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AskiColorLabGamutSweepTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
