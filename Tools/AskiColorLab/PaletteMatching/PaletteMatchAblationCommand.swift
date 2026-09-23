import Aski
import AskiToolSupport
import Foundation
import simd

public enum PaletteMatchAblationCommand {
    public static let commandName = "palette-match-ablation"
    public static let outputFileName = "palette-match-ablation.csv"

    public static let metricColumns: [String] = [
        "palette_id", "palette_color_count", "source_oklab",
        "selected_palette_index", "selected_palette_space", "selected_palette_components",
        "selected_oklab", "distance", "delta_l", "delta_ab",
        "baseline_selected_palette_index", "baseline_distance", "baseline_selection_distance",
        "differs_from_baseline",
        "delta_distance_from_baseline_selection", "distance_ratio_to_baseline_selection",
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

        var sampleID = 0
        for group in PaletteMatchFixtures.all {
            let resolvedPalette = group.colors.map(PaletteMatchPolicies.resolveToOKLab)

            for source in group.sources {
                let sourceOKLab = PaletteMatchPolicies.resolveToOKLab(source.color)

                let baselineSelection = PaletteMatchPolicies.nearest(
                    in: resolvedPalette,
                    to: sourceOKLab,
                    using: PaletteMatchPolicies.oklabEuclidean
                )
                let baselineSelectedOKLab = resolvedPalette[baselineSelection.index]

                let euclideanRow = makeRow(
                    schemaVersion: CSVSchema.schemaVersion,
                    gitSHA: gitSHA,
                    seed: arguments.seed,
                    sampleID: sampleID,
                    fixtureID: source.id,
                    policy: "oklabEuclidean",
                    source: source,
                    sourceOKLab: sourceOKLab,
                    paletteGroup: group,
                    resolvedPalette: resolvedPalette,
                    selection: baselineSelection,
                    baseline: baselineSelection,
                    baselineSelectedOKLab: baselineSelectedOKLab,
                    currentMetric: PaletteMatchPolicies.oklabEuclidean
                )
                do { try writer.writeRow(euclideanRow) } catch {
                    standardError("error: \(error)\n")
                    return .ioError
                }

                let hyabSelection = PaletteMatchPolicies.nearest(
                    in: resolvedPalette,
                    to: sourceOKLab,
                    using: PaletteMatchPolicies.oklabHyAB
                )
                let hyabRow = makeRow(
                    schemaVersion: CSVSchema.schemaVersion,
                    gitSHA: gitSHA,
                    seed: arguments.seed,
                    sampleID: sampleID,
                    fixtureID: source.id,
                    policy: "oklabHyAB",
                    source: source,
                    sourceOKLab: sourceOKLab,
                    paletteGroup: group,
                    resolvedPalette: resolvedPalette,
                    selection: hyabSelection,
                    baseline: baselineSelection,
                    baselineSelectedOKLab: baselineSelectedOKLab,
                    currentMetric: PaletteMatchPolicies.oklabHyAB
                )
                do { try writer.writeRow(hyabRow) } catch {
                    standardError("error: \(error)\n")
                    return .ioError
                }

                // Helmlab MetricSpace probe rows. Every numeric column is real
                // and computed WITHIN Helmlab units (same shape as the HyAB row:
                // current-metric to current-metric). This is a divergence /
                // saturation probe, not a cross-metric quality oracle — absolute
                // Helmlab distances are not comparable to absolute OKLab
                // distances across rows (spec § ColorLab harness).
                let paletteHelmlab = group.colors.map(PaletteMatchPolicies.resolveToHelmlab)
                let sourceHelmlab = PaletteMatchPolicies.resolveToHelmlab(source.color)

                let helmlabMetrics: [(String, (SIMD3<Double>, SIMD3<Double>) -> Double)] = [
                    ("helmlabEuclidean", PaletteMatchPolicies.helmlabEuclidean),
                    ("helmlabCompressed", PaletteMatchPolicies.helmlabCompressed),
                ]
                for (policyName, metric) in helmlabMetrics {
                    let selection = PaletteMatchPolicies.nearestHelmlab(
                        in: paletteHelmlab, to: sourceHelmlab, using: metric
                    )
                    let helmlabRow = makeHelmlabRow(
                        schemaVersion: CSVSchema.schemaVersion,
                        gitSHA: gitSHA,
                        seed: arguments.seed,
                        sampleID: sampleID,
                        fixtureID: source.id,
                        policy: policyName,
                        source: source,
                        sourceOKLab: sourceOKLab,
                        paletteGroup: group,
                        resolvedPalette: resolvedPalette,
                        sourceHelmlab: sourceHelmlab,
                        paletteHelmlab: paletteHelmlab,
                        metric: metric,
                        selection: selection,
                        baseline: baselineSelection
                    )
                    do { try writer.writeRow(helmlabRow) } catch {
                        standardError("error: \(error)\n")
                        return .ioError
                    }
                }

                sampleID += 1
            }
        }

        return .success
    }

    private static func makeRow(
        schemaVersion: String,
        gitSHA: String,
        seed: UInt64,
        sampleID: Int,
        fixtureID: String,
        policy: String,
        source: PaletteMatchSource,
        sourceOKLab: SIMD3<Float>,
        paletteGroup: PaletteMatchPaletteGroup,
        resolvedPalette: [SIMD3<Float>],
        selection: PaletteMatchPolicies.Selection,
        baseline: PaletteMatchPolicies.Selection,
        baselineSelectedOKLab: SIMD3<Float>,
        currentMetric: (SIMD3<Float>, SIMD3<Float>) -> Float
    ) -> [String] {
        let selectedColor = paletteGroup.colors[selection.index]
        let selectedOKLab = resolvedPalette[selection.index]

        let signedDeltaL = selectedOKLab.x - sourceOKLab.x
        let deltaAB = simd_length(
            SIMD2<Float>(
                selectedOKLab.y - sourceOKLab.y,
                selectedOKLab.z - sourceOKLab.z
            ))

        let baselineSelectionDistance = currentMetric(sourceOKLab, baselineSelectedOKLab)
        let differsFromBaseline = selection.index != baseline.index
        let deltaFromBaseline = selection.distance - baselineSelectionDistance
        let ratioToBaseline: Float
        if baselineSelectionDistance == 0 && selection.distance == 0 {
            ratioToBaseline = 1
        } else {
            ratioToBaseline = selection.distance / baselineSelectionDistance
        }

        return [
            schemaVersion,
            commandName,
            gitSHA,
            String(seed),
            String(sampleID),
            fixtureID,
            policy,
            spaceName(source.color.colorSpace),
            CSVSchema.formatSIMD3(source.color.components),
            spaceName(selectedColor.colorSpace),
            CSVSchema.formatSIMD3(selectedColor.components),
            paletteGroup.id,
            String(paletteGroup.colors.count),
            CSVSchema.formatSIMD3(sourceOKLab),
            String(selection.index),
            spaceName(selectedColor.colorSpace),
            CSVSchema.formatSIMD3(selectedColor.components),
            CSVSchema.formatSIMD3(selectedOKLab),
            CSVSchema.formatFloat(selection.distance),
            CSVSchema.formatFloat(signedDeltaL),
            CSVSchema.formatFloat(deltaAB),
            String(baseline.index),
            CSVSchema.formatFloat(baseline.distance),
            CSVSchema.formatFloat(baselineSelectionDistance),
            differsFromBaseline ? "true" : "false",
            CSVSchema.formatFloat(deltaFromBaseline),
            CSVSchema.formatFloat(ratioToBaseline),
        ]
    }

    private static func makeHelmlabRow(
        schemaVersion: String,
        gitSHA: String,
        seed: UInt64,
        sampleID: Int,
        fixtureID: String,
        policy: String,
        source: PaletteMatchSource,
        sourceOKLab: SIMD3<Float>,
        paletteGroup: PaletteMatchPaletteGroup,
        resolvedPalette: [SIMD3<Float>],
        sourceHelmlab: SIMD3<Double>,
        paletteHelmlab: [SIMD3<Double>],
        metric: (SIMD3<Double>, SIMD3<Double>) -> Double,
        selection: PaletteMatchPolicies.DoubleSelection,
        baseline: PaletteMatchPolicies.Selection
    ) -> [String] {
        let selectedColor = paletteGroup.colors[selection.index]
        let selectedOKLab = resolvedPalette[selection.index]
        let signedDeltaL = selectedOKLab.x - sourceOKLab.x
        let deltaAB = simd_length(
            SIMD2<Float>(
                selectedOKLab.y - sourceOKLab.y,
                selectedOKLab.z - sourceOKLab.z
            ))
        // All within Helmlab units: the Helmlab distance from the source to the
        // entry the OKLab baseline picked, vs the Helmlab-selected distance.
        let baselineSelectionDistance = metric(sourceHelmlab, paletteHelmlab[baseline.index])
        let differsFromBaseline = selection.index != baseline.index
        let deltaFromBaseline = selection.distance - baselineSelectionDistance
        let ratioToBaseline: Double
        if baselineSelectionDistance == 0 && selection.distance == 0 {
            ratioToBaseline = 1
        } else if baselineSelectionDistance == 0 {
            ratioToBaseline = Double.infinity
        } else {
            ratioToBaseline = selection.distance / baselineSelectionDistance
        }
        return [
            schemaVersion, commandName, gitSHA, String(seed), String(sampleID), fixtureID, policy,
            spaceName(source.color.colorSpace),
            CSVSchema.formatSIMD3(source.color.components),
            spaceName(selectedColor.colorSpace),
            CSVSchema.formatSIMD3(selectedColor.components),
            paletteGroup.id, String(paletteGroup.colors.count),
            CSVSchema.formatSIMD3(sourceOKLab),
            String(selection.index),
            spaceName(selectedColor.colorSpace),
            CSVSchema.formatSIMD3(selectedColor.components),
            CSVSchema.formatSIMD3(selectedOKLab),
            String(format: "%.6f", selection.distance),  // distance (Helmlab units)
            CSVSchema.formatFloat(signedDeltaL),  // descriptive OKLab geometry
            CSVSchema.formatFloat(deltaAB),  // descriptive OKLab geometry
            String(baseline.index),
            CSVSchema.formatFloat(baseline.distance),  // OKLab baseline's own distance (carried, as in HyAB rows)
            String(format: "%.6f", baselineSelectionDistance),  // baseline pick distance, Helmlab units
            differsFromBaseline ? "true" : "false",
            String(format: "%.6f", deltaFromBaseline),  // within-Helmlab delta
            String(format: "%.6f", ratioToBaseline),  // within-Helmlab ratio
        ]
    }

    private static func spaceName(_ space: PaletteColorSpace) -> String {
        if space == .sRGB { return "sRGB" }
        if space == .displayP3 { return "displayP3" }
        preconditionFailure("Unsupported PaletteColorSpace in AskiColorLab: update PaletteMatchAblationCommand.spaceName")
    }
}
