import Aski
import simd

/// One declared source-color fixture evaluated against one palette group.
/// `id` is the `fixture_id` written to CSV.
public struct PaletteMatchSource: Sendable, Hashable {
    public let id: String
    public let color: PaletteColor
}

/// A palette group is one palette and the set of source fixtures evaluated
/// against it. Order within each group is significant for CSV determinism.
public struct PaletteMatchPaletteGroup: Sendable {
    public let id: String
    public let colors: [PaletteColor]
    public let sources: [PaletteMatchSource]
}

/// Deterministic fixture set for `palette-match-ablation`.
///
/// Palette-group order is fixed by the spec: `ansi16`, `monochrome`,
/// `synthetic_srgb`, `synthetic_displayp3`. Source-fixture order within each
/// group is also fixed. Any future randomized fixture must be funnelled through
/// the lab's `--seed` argument explicitly; this enum is intentionally pure-data
/// so `--seed` cannot silently change provenance semantics.
public enum PaletteMatchFixtures {
    public static let all: [PaletteMatchPaletteGroup] = [
        ansi16Group(),
        monochromeGroup(),
        syntheticSRGBGroup(),
        syntheticDisplayP3Group(),
    ]

    // MARK: - ansi16

    private static func ansi16Group() -> PaletteMatchPaletteGroup {
        guard let colors = BuiltInPalette.ansi16.content.colors else {
            preconditionFailure("BuiltInPalette.ansi16 must be a fixed palette")
        }
        let sources: [PaletteMatchSource] = [
            .init(
                id: "ansi16_exact_black",
                color: PaletteColor(SIMD3<Float>(0, 0, 0), colorSpace: .sRGB)),
            .init(
                id: "ansi16_exact_bright_white",
                color: PaletteColor(SIMD3<Float>(1, 1, 1), colorSpace: .sRGB)),
            .init(
                id: "ansi16_neutral_midgray",
                color: PaletteColor(SIMD3<Float>(0.5, 0.5, 0.5), colorSpace: .sRGB)),
            .init(
                id: "ansi16_bright_red_perturbed",
                color: PaletteColor(SIMD3<Float>(0.95, 0.05, 0.05), colorSpace: .sRGB)),
        ]
        return PaletteMatchPaletteGroup(id: "ansi16", colors: colors, sources: sources)
    }

    // MARK: - monochrome

    private static func monochromeGroup() -> PaletteMatchPaletteGroup {
        guard let colors = BuiltInPalette.monochrome.content.colors else {
            preconditionFailure("BuiltInPalette.monochrome must be a fixed palette")
        }
        let sources: [PaletteMatchSource] = [
            .init(
                id: "monochrome_neutral_black",
                color: PaletteColor(SIMD3<Float>(0, 0, 0), colorSpace: .sRGB)),
            .init(
                id: "monochrome_neutral_midgray",
                color: PaletteColor(SIMD3<Float>(0.5, 0.5, 0.5), colorSpace: .sRGB)),
            .init(
                id: "monochrome_saturated_red",
                color: PaletteColor(SIMD3<Float>(1, 0, 0), colorSpace: .sRGB)),
        ]
        return PaletteMatchPaletteGroup(id: "monochrome", colors: colors, sources: sources)
    }

    // MARK: - synthetic sRGB

    private static func syntheticSRGBGroup() -> PaletteMatchPaletteGroup {
        // Constructed for chroma-vs-lightness trade-off so HyAB and Euclidean
        // can disagree. `near_bisector_chroma_vs_lightness` is the divergence
        // fixture: source sits between a chroma-neighbor and a lightness-
        // neighbor in OKLab, and Euclidean / HyAB rank them differently.
        let colors: [PaletteColor] = [
            PaletteColor(SIMD3<Float>(0.20, 0.20, 0.20), colorSpace: .sRGB),  // dark neutral
            PaletteColor(SIMD3<Float>(0.85, 0.85, 0.85), colorSpace: .sRGB),  // light neutral
            PaletteColor(SIMD3<Float>(0.95, 0.05, 0.05), colorSpace: .sRGB),  // saturated red
            PaletteColor(SIMD3<Float>(0.40, 0.65, 0.40), colorSpace: .sRGB),  // muted green
            PaletteColor(SIMD3<Float>(0.55, 0.55, 0.20), colorSpace: .sRGB),  // chroma neighbor: similar L to source, distinct ab
            PaletteColor(SIMD3<Float>(0.85, 0.55, 0.55), colorSpace: .sRGB),  // lightness neighbor: lighter L, ab close to source
        ]
        let sources: [PaletteMatchSource] = [
            .init(
                id: "synthetic_srgb_exact_dark_neutral",
                color: PaletteColor(SIMD3<Float>(0.20, 0.20, 0.20), colorSpace: .sRGB)),
            .init(
                id: "synthetic_srgb_midpoint_neutral",
                color: PaletteColor(SIMD3<Float>(0.50, 0.50, 0.50), colorSpace: .sRGB)),
            .init(
                id: "synthetic_srgb_low_light_high_chroma",
                color: PaletteColor(SIMD3<Float>(0.30, 0.05, 0.05), colorSpace: .sRGB)),
            .init(
                id: "synthetic_srgb_neutral_lightness_ramp_step",
                color: PaletteColor(SIMD3<Float>(0.65, 0.65, 0.65), colorSpace: .sRGB)),
            // Verified divergent under the palette above: Euclidean selects
            // index 5 (lightness neighbor, light red-pink); HyAB selects
            // index 4 (chroma neighbor, yellow-olive). Independently confirmed
            // before the plan was finalized; if a future palette edit breaks
            // divergence, retune per Task 6 guidance.
            .init(
                id: "near_bisector_chroma_vs_lightness",
                color: PaletteColor(SIMD3<Float>(0.46, 0.50, 0.80), colorSpace: .sRGB)),
        ]
        return PaletteMatchPaletteGroup(id: "synthetic_srgb", colors: colors, sources: sources)
    }

    // MARK: - synthetic Display P3

    private static func syntheticDisplayP3Group() -> PaletteMatchPaletteGroup {
        // One Display P3 entry plus an sRGB neutral, so we exercise mixed-space
        // resolution in the same group. Saturated red is the canonical case
        // where sRGB and Display P3 declarations resolve to different OKLab
        // chroma values; the synthetic_displayp3 group must contain at least
        // one Display P3 palette color and at least one Display P3 source.
        let colors: [PaletteColor] = [
            PaletteColor(SIMD3<Float>(1, 0, 0), colorSpace: .displayP3),  // saturated P3 red
            PaletteColor(SIMD3<Float>(0, 0, 0), colorSpace: .sRGB),
            PaletteColor(SIMD3<Float>(1, 1, 1), colorSpace: .sRGB),
        ]
        let sources: [PaletteMatchSource] = [
            .init(
                id: "displayp3_exact_saturated_red",
                color: PaletteColor(SIMD3<Float>(1, 0, 0), colorSpace: .displayP3)),
            .init(
                id: "displayp3_near_saturated_red",
                color: PaletteColor(SIMD3<Float>(0.95, 0.05, 0.05), colorSpace: .displayP3)),
            .init(
                id: "displayp3_neutral_midgray_srgb_declared",
                color: PaletteColor(SIMD3<Float>(0.5, 0.5, 0.5), colorSpace: .sRGB)),
        ]
        return PaletteMatchPaletteGroup(id: "synthetic_displayp3", colors: colors, sources: sources)
    }
}
