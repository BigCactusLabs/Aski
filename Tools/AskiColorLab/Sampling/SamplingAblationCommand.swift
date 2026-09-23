import Aski
import AskiToolSupport
import Foundation
import simd

public enum SamplingAblationCommand {
    public static let commandName = "sampling-ablation"
    public static let outputFileName = "sampling-ablation.csv"

    public static let metricColumns: [String] = [
        "fixture_width",
        "fixture_height",
        "input_alpha_mean",
        "output_alpha",
        "oklab_l",
        "oklab_a",
        "oklab_b",
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

        for (sampleID, fixture) in SamplingFixtures.all.enumerated() {
            let inputMeanEncoded = encodedMeanRGB(of: fixture)
            let inputAlphaMean = alphaMean(of: fixture)

            for policy in samplingPolicies {
                let sampled = sample(fixture: fixture, policy: policy.kind)
                let oklab = oklabFromLinearRGB(sampled.linearRGB, colorSpace: fixture.colorSpace)

                let row: [String] = [
                    CSVSchema.schemaVersion,
                    commandName,
                    gitSHA,
                    String(arguments.seed),
                    String(sampleID),
                    fixture.id,
                    policy.identifier,
                    inputSpaceName(fixture.colorSpace),
                    CSVSchema.formatSIMD3(inputMeanEncoded),
                    outputSpaceName(fixture.colorSpace),
                    CSVSchema.formatSIMD3(sampled.linearRGB),
                    String(fixture.width),
                    String(fixture.height),
                    CSVSchema.formatFloat(inputAlphaMean),
                    CSVSchema.formatFloat(sampled.alpha),
                    CSVSchema.formatFloat(oklab.x),
                    CSVSchema.formatFloat(oklab.y),
                    CSVSchema.formatFloat(oklab.z),
                ]

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

    private struct PolicyEntry {
        let kind: Kind
        let identifier: String
        enum Kind { case encodedAverageLegacy, linearLightAverage }
    }

    private static let samplingPolicies: [PolicyEntry] = [
        PolicyEntry(kind: .encodedAverageLegacy, identifier: "encodedAverageLegacy"),
        PolicyEntry(kind: .linearLightAverage, identifier: "linearLightAverage"),
    ]

    private static func sample(
        fixture: SamplingFixture,
        policy: PolicyEntry.Kind
    ) -> SampledLinearRGB {
        switch policy {
        case .encodedAverageLegacy:
            return SamplingPolicies.encodedAverageLegacy(
                pixels: fixture.pixels,
                width: fixture.width,
                height: fixture.height
            )
        case .linearLightAverage:
            return SamplingPolicies.linearLightAverage(
                pixels: fixture.pixels,
                width: fixture.width,
                height: fixture.height
            )
        }
    }

    private static func oklabFromLinearRGB(
        _ linearRGB: SIMD3<Float>,
        colorSpace: RenderColorSpace
    ) -> SIMD3<Float> {
        switch colorSpace {
        case .sRGB: return ColorConversion.linearSRGBToOKLAB(linearRGB)
        case .displayP3: return ColorConversion.linearP3ToOKLAB(linearRGB)
        }
    }

    private static func encodedMeanRGB(of fixture: SamplingFixture) -> SIMD3<Float> {
        var rSum: Float = 0
        var gSum: Float = 0
        var bSum: Float = 0
        let pixelCount = fixture.width * fixture.height
        for index in 0..<pixelCount {
            let offset = index * 4
            rSum += Float(fixture.pixels[offset]) / 255
            gSum += Float(fixture.pixels[offset + 1]) / 255
            bSum += Float(fixture.pixels[offset + 2]) / 255
        }
        let count = Float(pixelCount)
        return SIMD3<Float>(rSum / count, gSum / count, bSum / count)
    }

    private static func alphaMean(of fixture: SamplingFixture) -> Float {
        let pixelCount = fixture.width * fixture.height
        var sum: Float = 0
        for index in 0..<pixelCount {
            sum += Float(fixture.pixels[index * 4 + 3]) / 255
        }
        return sum / Float(pixelCount)
    }

    private static func inputSpaceName(_ space: RenderColorSpace) -> String {
        switch space {
        case .sRGB: return "sRGB"
        case .displayP3: return "displayP3"
        }
    }

    private static func outputSpaceName(_ space: RenderColorSpace) -> String {
        switch space {
        case .sRGB: return "linearSRGB"
        case .displayP3: return "linearDisplayP3"
        }
    }
}
