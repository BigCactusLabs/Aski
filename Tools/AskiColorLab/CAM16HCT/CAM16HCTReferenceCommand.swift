import Aski
import AskiToolSupport
import Foundation
import simd

public enum CAM16HCTReferenceCommand {
    public static let commandName = "cam16-hct-reference"
    public static let referenceOutputFileName = "cam16-hct-reference.csv"
    public static let paletteOutputFileName = "palette-match-cam16-ucs.csv"

    public static let referenceMetricColumns: [String] = [
        "reference_kind", "argb_hex",
        "cam16_hue", "cam16_chroma", "cam16_j", "cam16_q", "cam16_m", "cam16_s",
        "cam16_jstar", "cam16_astar", "cam16_bstar",
        "hct_hue", "hct_chroma", "hct_tone",
        "roundtrip_argb_hex", "roundtrip_matches",
        "material_color_utilities_sha",
    ]

    public static let paletteMetricColumns: [String] = [
        "palette_id", "palette_color_count",
        "source_oklab", "source_cam16ucs",
        "selected_palette_index", "selected_palette_space", "selected_palette_components",
        "selected_cam16ucs", "cam16ucs_distance",
        "baseline_selected_palette_index", "baseline_oklab_distance",
        "baseline_selection_cam16ucs_distance", "differs_from_oklab_baseline",
    ]

    public static func run(
        arguments: LabArguments,
        standardError: (String) -> Void
    ) -> LabExitCode {
        let directory = URL(fileURLWithPath: arguments.outputDirectory)
        let gitSHA = GitSHA.resolve(override: arguments.gitShaOverride)

        switch writeReferenceCSV(directory: directory, gitSHA: gitSHA, seed: arguments.seed) {
        case .success:
            break
        case .failure(let error):
            standardError("error: \(error)\n")
            return .ioError
        }

        switch writePaletteCSV(directory: directory, gitSHA: gitSHA, seed: arguments.seed) {
        case .success:
            return .success
        case .failure(let error):
            standardError("error: \(error)\n")
            return .ioError
        }
    }

    private static func writeReferenceCSV(
        directory: URL,
        gitSHA: String,
        seed: UInt64
    ) -> Result<Void, Error> {
        Result {
            let writer = try CSVWriter(
                url: directory.appendingPathComponent(referenceOutputFileName),
                columns: CSVSchema.sharedPrefixColumns + referenceMetricColumns
            )
            defer { try? writer.close() }

            var sampleID = 0
            for reference in materialReferences {
                try writer.writeRow(
                    referenceRow(
                        referenceKind: "material_primary",
                        sampleID: sampleID,
                        fixtureID: reference.id,
                        argb: reference.argb,
                        roundtripARGB: reference.argb,
                        gitSHA: gitSHA,
                        seed: seed
                    ))
                sampleID += 1
            }

            for argb in hctRoundTripARGBGrid() {
                let hct = HCTColor.fromInt(argb)
                let roundtrip = HCTColor.from(hue: hct.hue, chroma: hct.chroma, tone: hct.tone).argb
                try writer.writeRow(
                    referenceRow(
                        referenceKind: "hct_roundtrip",
                        sampleID: sampleID,
                        fixtureID: "roundtrip_\(formatSixDigit(sampleID - materialReferences.count))",
                        argb: argb,
                        roundtripARGB: roundtrip,
                        gitSHA: gitSHA,
                        seed: seed
                    ))
                sampleID += 1
            }
        }
    }

    private static func writePaletteCSV(
        directory: URL,
        gitSHA: String,
        seed: UInt64
    ) -> Result<Void, Error> {
        Result {
            let writer = try CSVWriter(
                url: directory.appendingPathComponent(paletteOutputFileName),
                columns: CSVSchema.sharedPrefixColumns + paletteMetricColumns
            )
            defer { try? writer.close() }

            var sampleID = 0
            for group in PaletteMatchFixtures.all {
                let paletteOKLab = group.colors.map(PaletteMatchPolicies.resolveToOKLab)
                let paletteCAM16 = group.colors.map(cam16UCS)

                for source in group.sources {
                    let sourceOKLab = PaletteMatchPolicies.resolveToOKLab(source.color)
                    let sourceCAM16 = cam16UCS(source.color)

                    let baseline = PaletteMatchPolicies.nearest(
                        in: paletteOKLab,
                        to: sourceOKLab,
                        using: PaletteMatchPolicies.oklabEuclidean
                    )
                    let cam16Selection = nearestCAM16UCS(in: paletteCAM16, to: sourceCAM16)
                    let selectedColor = group.colors[cam16Selection.index]

                    try writer.writeRow([
                        CSVSchema.schemaVersion,
                        commandName,
                        gitSHA,
                        String(seed),
                        String(sampleID),
                        source.id,
                        "cam16UCS",
                        spaceName(source.color.colorSpace),
                        CSVSchema.formatSIMD3(source.color.components),
                        spaceName(selectedColor.colorSpace),
                        CSVSchema.formatSIMD3(selectedColor.components),
                        group.id,
                        String(group.colors.count),
                        CSVSchema.formatSIMD3(sourceOKLab),
                        formatCAM16UCS(sourceCAM16),
                        String(cam16Selection.index),
                        spaceName(selectedColor.colorSpace),
                        CSVSchema.formatSIMD3(selectedColor.components),
                        formatCAM16UCS(paletteCAM16[cam16Selection.index]),
                        formatDouble(cam16Selection.distance),
                        String(baseline.index),
                        CSVSchema.formatFloat(baseline.distance),
                        formatDouble(sourceCAM16.distance(paletteCAM16[baseline.index])),
                        cam16Selection.index == baseline.index ? "false" : "true",
                    ])
                    sampleID += 1
                }
            }
        }
    }

    private static func referenceRow(
        referenceKind: String,
        sampleID: Int,
        fixtureID: String,
        argb: UInt32,
        roundtripARGB: UInt32,
        gitSHA: String,
        seed: UInt64
    ) -> [String] {
        let cam16 = CAM16Color.fromInt(argb)
        let hct = HCTColor.fromInt(argb)
        return [
            CSVSchema.schemaVersion,
            commandName,
            gitSHA,
            String(seed),
            String(sampleID),
            fixtureID,
            referenceKind,
            "sRGB",
            encodedComponents(argb),
            "cam16-hct",
            CSVSchema.formatComponents([Float(hct.hue), Float(hct.chroma), Float(hct.tone)]),
            referenceKind,
            hexARGB(argb),
            formatDouble(cam16.hue),
            formatDouble(cam16.chroma),
            formatDouble(cam16.j),
            formatDouble(cam16.q),
            formatDouble(cam16.m),
            formatDouble(cam16.s),
            formatDouble(cam16.jstar),
            formatDouble(cam16.astar),
            formatDouble(cam16.bstar),
            formatDouble(hct.hue),
            formatDouble(hct.chroma),
            formatDouble(hct.tone),
            hexARGB(roundtripARGB),
            roundtripARGB == argb ? "true" : "false",
            CAM16HCTProvenance.materialColorUtilitiesSHA,
        ]
    }

    private static let materialReferences: [(id: String, argb: UInt32)] = [
        ("material_red", 0xffff0000),
        ("material_green", 0xff00ff00),
        ("material_blue", 0xff0000ff),
        ("material_white", 0xffffffff),
        ("material_black", 0xff000000),
    ]

    private static func hctRoundTripARGBGrid() -> [UInt32] {
        var values: [UInt32] = []
        values.reserveCapacity(512)
        for red in stride(from: 0, to: 296, by: 37) {
            for green in stride(from: 0, to: 296, by: 37) {
                for blue in stride(from: 0, to: 296, by: 37) {
                    values.append(argb(red: min(255, red), green: min(255, green), blue: min(255, blue)))
                }
            }
        }
        return values
    }

    private static func argb(red: Int, green: Int, blue: Int) -> UInt32 {
        (UInt32(0xff) << 24) | (UInt32(red) << 16) | (UInt32(green) << 8) | UInt32(blue)
    }

    private struct CAM16Selection {
        let index: Int
        let distance: Double
    }

    private static func nearestCAM16UCS(in candidates: [CAM16Color], to source: CAM16Color) -> CAM16Selection {
        precondition(!candidates.isEmpty, "nearestCAM16UCS(in:) requires at least one candidate")
        var bestIndex = 0
        var bestDistance = source.distance(candidates[0])
        for index in 1..<candidates.count {
            let distance = source.distance(candidates[index])
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return CAM16Selection(index: bestIndex, distance: bestDistance)
    }

    private static func cam16UCS(_ color: PaletteColor) -> CAM16Color {
        let xyz = xyzD65(from: color)
        return CAM16Color.fromXyzInViewingConditions(xyz.x, xyz.y, xyz.z, .sRgb())
    }

    private static func xyzD65(from color: PaletteColor) -> SIMD3<Double> {
        let linear = SIMD3<Double>(
            Double(ColorConversion.sRGBDecode(color.components.x)) * 100,
            Double(ColorConversion.sRGBDecode(color.components.y)) * 100,
            Double(ColorConversion.sRGBDecode(color.components.z)) * 100
        )
        if color.colorSpace == .sRGB {
            return multiply(linear, by: ColorUtils.srgbToXyz)
        }
        if color.colorSpace == .displayP3 {
            return multiply(linear, by: displayP3ToXYZD65)
        }
        preconditionFailure("Unsupported PaletteColorSpace in AskiColorLab: update CAM16HCTReferenceCommand.xyzD65")
    }

    private static let displayP3ToXYZD65: [[Double]] = [
        [0.4865709486482162, 0.26566769316909306, 0.1982172852343625],
        [0.2289745640697488, 0.6917385218365064, 0.079286914093745],
        [0.0, 0.04511338185890264, 1.043944368900976],
    ]

    private static func multiply(_ row: SIMD3<Double>, by matrix: [[Double]]) -> SIMD3<Double> {
        SIMD3<Double>(
            row.x * matrix[0][0] + row.y * matrix[0][1] + row.z * matrix[0][2],
            row.x * matrix[1][0] + row.y * matrix[1][1] + row.z * matrix[1][2],
            row.x * matrix[2][0] + row.y * matrix[2][1] + row.z * matrix[2][2]
        )
    }

    private static func encodedComponents(_ argb: UInt32) -> String {
        let red = Float((argb >> 16) & 0xff) / 255
        let green = Float((argb >> 8) & 0xff) / 255
        let blue = Float(argb & 0xff) / 255
        return CSVSchema.formatComponents([red, green, blue])
    }

    private static func formatCAM16UCS(_ cam16: CAM16Color) -> String {
        [cam16.jstar, cam16.astar, cam16.bstar].map(formatDouble).joined(separator: ";")
    }

    private static func formatDouble(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private static func formatSixDigit(_ value: Int) -> String {
        String(format: "%06d", value)
    }

    private static func hexARGB(_ argb: UInt32) -> String {
        String(format: "%08x", argb)
    }

    private static func spaceName(_ space: PaletteColorSpace) -> String {
        if space == .sRGB { return "sRGB" }
        if space == .displayP3 { return "displayP3" }
        preconditionFailure("Unsupported PaletteColorSpace in AskiColorLab: update CAM16HCTReferenceCommand.spaceName")
    }
}
