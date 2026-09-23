import AskiToolSupport
import Darwin
import Foundation

public enum CuberootAccuracyCommand {
    public static let commandName = "cuberoot-accuracy"
    public static let outputFileName = "cuberoot-accuracy.csv"

    public static let metricColumns: [String] = [
        "fixture_group",
        "reference_float",
        "output_bits_hex",
        "reference_bits_hex",
        "ulp_distance",
        "abs_error",
        "rel_error",
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

        let fixtures = CuberootAccuracyFixtures.all(seed: arguments.seed)
        for (sampleID, fixture) in fixtures.enumerated() {
            // Addendum §"CSV schema": `Float(Darwin.cbrt(Double(x)))` — Float64
            // reference rounded back to Float. Explicitly not an MPFR proof.
            let reference = Float(Darwin.cbrt(Double(fixture.input)))

            for policy in CuberootAccuracyPolicies.canonicalOrder {
                let output = CuberootAccuracyPolicies.apply(
                    policy: policy,
                    input: fixture.input
                )
                let metrics = CuberootAccuracyMetrics.compute(
                    output: output,
                    reference: reference
                )
                let row = makeRow(
                    sampleID: sampleID,
                    fixture: fixture,
                    policy: policy,
                    output: output,
                    reference: reference,
                    metrics: metrics,
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
        fixture: CuberootAccuracyFixture,
        policy: CuberootAccuracyPolicies.Identifier,
        output: Float,
        reference: Float,
        metrics: CuberootAccuracyMetrics.Result,
        gitSHA: String,
        seed: UInt64
    ) -> [String] {
        return [
            CSVSchema.schemaVersion,
            commandName,
            gitSHA,
            String(seed),
            String(sampleID),
            fixture.id,
            policy.csvLabel,
            "LMS_component",
            CSVSchema.formatFloat(fixture.input),
            "LMS_prime_component",
            CSVSchema.formatFloat(output),
            // command-specific columns:
            fixture.group.csvLabel,
            CSVSchema.formatFloat(reference),
            formatBitsHex(output),
            formatBitsHex(reference),
            String(metrics.ulpDistance),
            formatScientific(metrics.absError),
            metrics.relError.map(formatScientific) ?? "n/a",
        ]
    }

    private static func formatBitsHex(_ value: Float) -> String {
        String(format: "0x%08x", value.bitPattern)
    }

    private static func formatScientific(_ value: Float) -> String {
        String(format: "%.9e", value)
    }
}
