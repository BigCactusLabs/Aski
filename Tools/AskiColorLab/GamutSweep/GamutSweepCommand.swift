import Aski
import AskiToolSupport
import Foundation
import simd

public enum GamutSweepCommand {
    public static let commandName = "gamut-sweep"
    public static let outputFileName = "gamut-sweep.csv"

    /// Always the literal string written to the `baseline_policy` column.
    public static let baselinePolicyLabel = GamutSweepPolicies.Identifier.adaptiveL0.csvLabel

    public static let metricColumns: [String] = [
        "target_gamut",
        "source_oklch_l",
        "source_oklch_c",
        "source_oklch_h_degrees",
        "source_oklab",
        "mapped_linear_rgb",
        "mapped_encoded_rgb",
        "mapped_oklab",
        "delta_e_ok",
        "hue_delta_degrees",
        "lightness_delta",
        "chroma_reduction_pct",
        "baseline_policy",
        "baseline_mapped_encoded_rgb",
        "encoded_rgb_distance_from_baseline",
        "source_in_target_gamut",
    ]

    public static func run(
        arguments: LabArguments,
        standardError: (String) -> Void
    ) -> LabExitCode {
        let outputURL = URL(fileURLWithPath: arguments.outputDirectory)
            .appendingPathComponent(outputFileName)
        let gitSHA = GitSHA.resolve(override: arguments.gitShaOverride)
        let columns = CSVSchema.sharedPrefixColumns + metricColumns

        let writer: CSVWriter
        do {
            writer = try CSVWriter(url: outputURL, columns: columns)
        } catch {
            standardError("error: \(error)\n")
            return .ioError
        }
        defer { try? writer.close() }

        let fixtures = GamutSweepFixtures.all

        for (sampleID, fixture) in fixtures.enumerated() {
            // Pre-compute baseline encoded RGB per target so candidate rows
            // can reference it without re-running adaptiveL0.
            var baselineEncoded: [GamutSweepTarget: SIMD3<Float>] = [:]
            for target in GamutSweepTarget.allCases {
                let baselineLinear = GamutSweepPolicies.adaptiveL0(
                    oklab: fixture.sourceOKLab,
                    target: target
                )
                baselineEncoded[target] = GamutSweepMetrics.encodedRGB(baselineLinear)
            }

            for policy in GamutSweepPolicies.canonicalOrder {
                for target in GamutSweepTarget.allCases {
                    let row = makeRow(
                        sampleID: sampleID,
                        fixture: fixture,
                        policy: policy,
                        target: target,
                        gitSHA: gitSHA,
                        seed: arguments.seed,
                        baselineEncoded: baselineEncoded[target] ?? .zero
                    )
                    do {
                        try writer.writeRow(row)
                    } catch {
                        standardError("error: \(error)\n")
                        return .ioError
                    }
                }
            }
        }

        return .success
    }

    private static func makeRow(
        sampleID: Int,
        fixture: GamutSweepFixture,
        policy: GamutSweepPolicies.Identifier,
        target: GamutSweepTarget,
        gitSHA: String,
        seed: UInt64,
        baselineEncoded: SIMD3<Float>
    ) -> [String] {
        let sourceOKLab = fixture.sourceOKLab
        let mappedLinearRGB = GamutSweepPolicies.map(
            oklab: sourceOKLab,
            target: target,
            policy: policy
        )
        let mappedEncodedRGB = GamutSweepMetrics.encodedRGB(mappedLinearRGB)
        let mappedOKLab = target.linearRGBToOKLab(mappedLinearRGB)

        let deltaEOK = GamutSweepMetrics.deltaEOK(source: sourceOKLab, mapped: mappedOKLab)
        let hueDelta = GamutSweepMetrics.hueDeltaDegrees(source: sourceOKLab, mapped: mappedOKLab)
        let lightnessDelta = GamutSweepMetrics.lightnessDelta(source: sourceOKLab, mapped: mappedOKLab)

        let sourceC = GamutSweepMetrics.chroma(of: sourceOKLab)
        let mappedC = GamutSweepMetrics.chroma(of: mappedOKLab)
        let chromaReductionPct = GamutSweepMetrics.chromaReductionPct(
            sourceC: sourceC,
            mappedC: mappedC
        )

        let baselineDistance = simd_length(mappedEncodedRGB - baselineEncoded)
        let inTargetGamut = GamutSweepMetrics.isSourceInTargetGamut(
            oklab: sourceOKLab,
            target: target
        )

        return [
            CSVSchema.schemaVersion,
            commandName,
            gitSHA,
            String(seed),
            String(sampleID),
            fixture.id,
            policy.csvLabel,
            "oklab",
            CSVSchema.formatSIMD3(sourceOKLab),
            target.csvLabel,
            CSVSchema.formatSIMD3(mappedEncodedRGB),
            target.csvLabel,
            CSVSchema.formatFloat(fixture.okLChL),
            CSVSchema.formatFloat(fixture.okLChC),
            CSVSchema.formatFloat(fixture.okLChHueDegrees),
            CSVSchema.formatSIMD3(sourceOKLab),
            CSVSchema.formatSIMD3(mappedLinearRGB),
            CSVSchema.formatSIMD3(mappedEncodedRGB),
            CSVSchema.formatSIMD3(mappedOKLab),
            CSVSchema.formatFloat(deltaEOK),
            CSVSchema.formatFloat(hueDelta),
            CSVSchema.formatFloat(lightnessDelta),
            CSVSchema.formatFloat(chromaReductionPct),
            baselinePolicyLabel,
            CSVSchema.formatSIMD3(baselineEncoded),
            CSVSchema.formatFloat(baselineDistance),
            inTargetGamut ? "true" : "false",
        ]
    }
}
