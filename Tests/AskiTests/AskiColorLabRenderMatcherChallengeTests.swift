import Foundation
import Testing
@testable import AskiColorLab

@Suite struct AskiColorLabRenderMatcherChallengeTests {
    @Test func frozenDesignMatchesTheCommittedRule() {
        #expect(RenderMatcherChallenge.columns == 80)
        #expect(RenderMatcherChallenge.oversample == 2)
        #expect(RenderMatcherChallenge.footprint == 24)
        #expect(RenderMatcherChallenge.candidateSupersample == 4)
        #expect(RenderMatcherChallenge.memoryBudgetBytes == 1_048_576)
        #expect(
            RenderMatcherChallenge.corpora.map(\.name) == [
                "nasa-structure-v1", "nasa-steerable-v1",
            ])
        #expect(RenderMatcherChallenge.charsetNames == ["blocks", "standard"])
        #expect(RenderMatcherChallenge.Arm.allCases.map(\.rawValue) == ["P", "A", "S1", "TF"])
    }

    @Test func alignedArmRecoversAnExactCandidateAndUsesLowerIndexForTies() {
        let rasters: [[Float]] = [
            [0, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 1, 0, 0],
        ]
        #expect(
            RenderMatcherChallenge.fixedFootprintPick(
                arm: .aligned,
                source: rasters[1],
                rasters: rasters,
                width: 2,
                height: 2
            ) == 1)
    }

    @Test func boundedAlignmentRecoversTheLowerIndexAfterOnePixelShift() {
        let centered: [Float] = [
            0, 0, 0,
            0, 1, 0,
            0, 0, 0,
        ]
        let shifted: [Float] = [
            0, 0, 0,
            0, 0, 1,
            0, 0, 0,
        ]
        let rasters = [centered, shifted]

        #expect(
            RenderMatcherChallenge.fixedFootprintPick(
                arm: .aligned, source: shifted, rasters: rasters, width: 3, height: 3) == 1)
        #expect(
            RenderMatcherChallenge.fixedFootprintPick(
                arm: .shifted, source: shifted, rasters: rasters, width: 3, height: 3) == 0)
        #expect(
            RenderMatcherChallenge.shiftedMAE(
                centered, shifted, width: 3, height: 3) == 0)
    }

    @Test func toneAndMeanCenteredFillAreIndependentLiveTerms() {
        let source: [Float] = [0.2, 0.8]
        let toneOnly = RenderMatcherChallenge.toneFillComponents([0.3, 0.9], source)
        #expect(abs(toneOnly.tone - 0.1) < 1e-6)
        #expect(toneOnly.fill < 1e-6)

        let fillOnly = RenderMatcherChallenge.toneFillComponents([0.4, 0.6], source)
        #expect(fillOnly.tone < 1e-6)
        #expect(abs(fillOnly.fill - 0.2) < 1e-6)
        #expect(toneOnly.total.isFinite && fillOnly.total.isFinite)
    }

    @Test func decisionRuleHoldsAQualifiedArmForNewPerceptualEvidence() {
        let rows = Self.rows(blocksMAE: 0.90, standardMAE: 1.005)
        let assessment = RenderMatcherChallenge.assess(rows)

        #expect(assessment.verdict == "HOLD - PERCEPTUAL DISPOSITION OPEN")
        #expect(assessment.objectiveCandidates == [.aligned])
        #expect(assessment.selectedTreatment == .aligned)
        #expect(assessment.selectedMeetsCostBudget)
    }

    @Test func decisionRuleKillsAnArmBelowTheBlocksBar() {
        let assessment = RenderMatcherChallenge.assess(
            Self.rows(blocksMAE: 0.96, standardMAE: 1.0))

        #expect(assessment.verdict == "KILL")
        #expect(assessment.objectiveCandidates.isEmpty)
        #expect(assessment.selectedTreatment == nil)
    }

    @Test func memoryFailureKillsEvenAQualityQualifiedArm() {
        let assessment = RenderMatcherChallenge.assess(
            Self.rows(
                blocksMAE: 0.90,
                standardMAE: 1.0,
                memoryBytes: RenderMatcherChallenge.memoryBudgetBytes + 1))

        #expect(assessment.verdict == "KILL")
        #expect(assessment.objectiveCandidates == [.aligned])
        #expect(assessment.selectedTreatment == nil)
    }

    @Test func csvFieldOrderAndReproductionCommandAreStable() {
        let rows = Self.rows(blocksMAE: 0.90, standardMAE: 1.0)
        let first = RenderMatcherChallenge.csv(rows)
        let second = RenderMatcherChallenge.csv(rows)
        #expect(first == second)
        #expect(
            first.split(separator: "\n").first
                == "corpus,charset,arm,cells,glyphs,distinct_glyphs,largest_glyph_share,candidate_churn,mean_mae,mean_gmsd,selection_wall_seconds,time_ratio_to_p,estimated_peak_selector_bytes,git_sha"
        )
        #expect(
            RenderMatcherChallenge.reproductionCommand(
                outputDirectory: "/tmp/aski69", gitSHAOverride: "abc123")
                == "xcrun swift run -c release AskiColorLab render-matcher-challenge --output-dir /tmp/aski69 --aski-git-sha abc123"
        )
    }

    private static func rows(
        blocksMAE: Double,
        standardMAE: Double,
        memoryBytes: Int = 100
    ) -> [RenderMatcherChallenge.Row] {
        var rows: [RenderMatcherChallenge.Row] = []
        for corpus in RenderMatcherChallenge.corpora.map(\.name) {
            for charset in RenderMatcherChallenge.charsetNames {
                rows.append(
                    row(
                        corpus: corpus,
                        charset: charset,
                        arm: .production,
                        mae: 1,
                        gmsd: 1,
                        churn: 0,
                        timeRatio: 1,
                        memoryBytes: memoryBytes
                    ))
                rows.append(
                    row(
                        corpus: corpus,
                        charset: charset,
                        arm: .aligned,
                        mae: charset == "blocks" ? blocksMAE : standardMAE,
                        gmsd: 1,
                        churn: 0.2,
                        timeRatio: charset == "blocks" ? 2 : 5,
                        memoryBytes: memoryBytes
                    ))
            }
        }
        return rows
    }

    private static func row(
        corpus: String,
        charset: String,
        arm: RenderMatcherChallenge.Arm,
        mae: Double,
        gmsd: Double,
        churn: Double,
        timeRatio: Double,
        memoryBytes: Int
    ) -> RenderMatcherChallenge.Row {
        RenderMatcherChallenge.Row(
            corpus: corpus,
            charset: charset,
            arm: arm,
            cells: 10,
            glyphs: 8,
            distinctGlyphs: 3,
            largestGlyphShare: 0.5,
            candidateChurnFraction: churn,
            meanMAE: mae,
            meanGMSD: gmsd,
            selectionWallSeconds: timeRatio,
            timeRatioToProduction: timeRatio,
            estimatedPeakSelectorBytes: memoryBytes,
            gitSHA: "abc123"
        )
    }
}
