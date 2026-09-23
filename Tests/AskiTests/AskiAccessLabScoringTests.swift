import Testing
import simd
@testable import AskiAccessLab

@Suite struct AskiAccessLabScoringTests {
    @Test func hexSerializationIsDelimiterSafeAndUppercase() {
        #expect(AccessScoring.hex(SIMD3<Float>(1, 0.5, 0)) == "#FF8000")
        #expect(!AccessScoring.hex(SIMD3<Float>(1, 0.5, 0)).contains(","))
    }

    @Test func wcagContrastUsesLinearizedSRGB() {
        let black = SIMD3<Float>(0, 0, 0)
        let white = SIMD3<Float>(1, 1, 1)
        #expect(abs(AccessScoring.wcagContrast(encodedA: black, encodedB: white) - 21.0) < 0.0001)
    }

    @Test func oklabDeltaUsesLinearSRGBConversion() {
        let delta = AccessScoring.oklabDelta(
            encodedA: SIMD3<Float>(1, 0, 0),
            encodedB: SIMD3<Float>(0, 1, 0)
        )
        #expect(delta > 0.5)
    }

    @Test func scoreUsesSimulatedColorsForMetrics() {
        let sample = AccessSample(
            sampleID: "palette-ansi16-red-black",
            comparisonRole: .colorOnBlack,
            surface: .palette,
            paletteID: "ansi16",
            candidateID: "default",
            fixtureID: "palette",
            sampleA: "red",
            sampleB: "black",
            encodedA: SIMD3<Float>(1, 0, 0),
            encodedB: .zero,
            brightnessDelta: 1
        )
        let row = AccessScoring.score(sample: sample, deficiency: .deuteranopia)
        #expect(row.modelID == CVDModel.modelID)
        #expect(row.severity == "1.0")
        #expect(row.sourceAHex == "#FF0000")
        #expect(row.simulatedAHex != "#FF0000")
        #expect(row.wcagContrast > 1)
    }

    @Test func csvHeaderMatchesSpecAndOmitsRunSeed() {
        #expect(
            AccessLabResults.csvHeader == [
                "schema_version", "command", "aski_git_sha", "sample_id",
                "comparison_role", "surface", "palette_id", "candidate_id",
                "fixture_id", "deficiency", "severity", "model_id",
                "sample_a", "sample_b", "source_a_hex", "source_b_hex",
                "simulated_a_hex", "simulated_b_hex", "wcag_contrast",
                "oklab_delta", "brightness_delta", "confusion_flag",
                "luminance_threshold_met",
            ])
        #expect(!AccessLabResults.csvHeader.contains("run_seed"))
        #expect(!AccessLabResults.csvHeader.contains("contrast_pass"))
    }

    @Test func csvQuotingHandlesUserControlledCommand() {
        var row = AccessScoreRow.example
        row.command = "swift run AskiAccessLab audit --output-dir /tmp/a,b"
        let line = AccessLabResults.csvLine(row)
        #expect(line.contains("\"swift run AskiAccessLab audit --output-dir /tmp/a,b\""))
    }
}
