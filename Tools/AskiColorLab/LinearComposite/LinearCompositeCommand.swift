import Aski
import AskiToolSupport
import Foundation
import simd

public enum LinearCompositeCommand {
    public static let commandName = "linear-composite-ab"
    public static let outputFileName = "linear-composite-ab.csv"

    public static let metricColumns: [String] = [
        "target_gamut",
        "fg_byte",
        "fg_alpha_byte",
        "bg_byte",
        "bg_alpha_byte",
        "fg_color_space",
        "policy_working_space",
        "mapped_linear_rgb",
        "mapped_encoded_rgb",
        "mapped_alpha_byte",
        "ground_truth_linear_rgb",
        "ground_truth_encoded_rgb",
        "ground_truth_alpha_byte",
        "delta_e_ok_to_ground_truth",
        "encoded_rgb_distance_to_ground_truth",
        "max_channel_abs_diff_to_ground_truth",
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

        // Spec §Architecture: pre-compute linearFloat ground truth per fixture
        // so candidate rows can reference it without recomputation.
        for (sampleID, fixture) in LinearCompositeFixtures.all.enumerated() {
            let groundTruth = LinearCompositePolicies.linearFloat(
                fgByte: fixture.fgByte,
                fgAlphaByte: fixture.fgAlphaByte,
                bgByte: fixture.bgByte,
                bgAlphaByte: fixture.bgAlphaByte,
                target: fixture.targetGamut
            )

            for policy in LinearCompositePolicies.canonicalOrder {
                let output = LinearCompositePolicies.apply(
                    policy: policy,
                    fgByte: fixture.fgByte,
                    fgAlphaByte: fixture.fgAlphaByte,
                    bgByte: fixture.bgByte,
                    bgAlphaByte: fixture.bgAlphaByte,
                    target: fixture.targetGamut
                )
                let row = makeRow(
                    sampleID: sampleID,
                    fixture: fixture,
                    policy: policy,
                    output: output,
                    groundTruth: groundTruth,
                    gitSHA: gitSHA,
                    seed: arguments.seed
                )
                do {
                    try writer.writeRow(row)
                } catch {
                    standardError("error: \(error)\n")
                    return .ioError
                }
            }
        }

        return .success
    }

    private static func makeRow(
        sampleID: Int,
        fixture: LinearCompositeFixture,
        policy: LinearCompositePolicies.Identifier,
        output: LinearCompositePolicies.PolicyOutput,
        groundTruth: LinearCompositePolicies.PolicyOutput,
        gitSHA: String,
        seed: UInt64
    ) -> [String] {
        let target = fixture.targetGamut
        let workingSpace: String
        switch policy {
        case .encoded8bit:
            workingSpace = target.encodedWorkingSpaceLabel
        case .linear8bit, .linearFloat:
            workingSpace = target.linearWorkingSpaceLabel
        }

        let metrics = LinearCompositeMetrics.compute(
            mappedLinearRGB: output.mappedLinearRGB,
            mappedEncodedRGB: output.mappedEncodedRGB,
            mappedAlphaByte: output.mappedAlphaByte,
            groundTruthLinearRGB: groundTruth.mappedLinearRGB,
            groundTruthEncodedRGB: groundTruth.mappedEncodedRGB,
            groundTruthAlphaByte: groundTruth.mappedAlphaByte,
            target: target
        )

        // Spec §CSV Contract: input_components = (fg_r, fg_g, fg_b, fg_alpha) / 255.
        let inputComponents = [
            fixture.fgByte.x / 255.0,
            fixture.fgByte.y / 255.0,
            fixture.fgByte.z / 255.0,
            Float(fixture.fgAlphaByte) / 255.0,
        ]
        // Spec §CSV Contract: output_components = (mapped_encoded_rgb, mapped_alpha / 255).
        let outputComponents = [
            output.mappedEncodedRGB.x,
            output.mappedEncodedRGB.y,
            output.mappedEncodedRGB.z,
            Float(output.mappedAlphaByte) / 255.0,
        ]

        return [
            CSVSchema.schemaVersion,
            commandName,
            gitSHA,
            String(seed),
            String(sampleID),
            fixture.id,
            policy.csvLabel,
            target.inputSpaceLabel,
            CSVSchema.formatComponents(inputComponents),
            target.outputSpaceLabel,
            CSVSchema.formatComponents(outputComponents),
            // command-specific columns:
            target.csvLabel,
            formatByteTriple(fixture.fgByte),
            String(fixture.fgAlphaByte),
            formatByteTriple(fixture.bgByte),
            String(fixture.bgAlphaByte),
            fixture.fgColorSpace.csvLabel,
            workingSpace,
            CSVSchema.formatSIMD3(output.mappedLinearRGB),
            CSVSchema.formatSIMD3(output.mappedEncodedRGB),
            String(output.mappedAlphaByte),
            CSVSchema.formatSIMD3(groundTruth.mappedLinearRGB),
            CSVSchema.formatSIMD3(groundTruth.mappedEncodedRGB),
            String(groundTruth.mappedAlphaByte),
            CSVSchema.formatFloat(metrics.deltaEOK),
            CSVSchema.formatFloat(metrics.encodedRGBDistance),
            CSVSchema.formatFloat(metrics.maxChannelAbsDiff),
        ]
    }

    /// Spec §CSV Contract: byte triples are semicolon-delimited integers in
    /// `[0, 255]`. No fractional part.
    private static func formatByteTriple(_ rgb: SIMD3<Float>) -> String {
        "\(Int(rgb.x));\(Int(rgb.y));\(Int(rgb.z))"
    }
}
