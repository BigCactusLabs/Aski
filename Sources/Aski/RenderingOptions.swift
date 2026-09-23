// Sources/Aski/RenderingOptions.swift
import simd

/// Which end of a source cell the `logPolar` shape query treats as ink
/// (ASKI-60). A factor rather than a constant because production's two halves
/// disagree: the candidate rasters are ink-high (`RasterizedCharacterSet`
/// fills at gray 0 and draws at gray 1) and the tone pre-filter matches a
/// BRIGHT cell to a dense glyph, while the shape query has inverted the source
/// since the first log-polar commit. Measuring the disagreement needs both
/// arms reachable from one binary.
public enum ShapeQueryPolarity: Sendable {
    /// `1 - Rec.601 luma`: DARK source regions carry the descriptor mass. The
    /// shipped default; reproduces every archived pick byte for byte.
    case inverted
    /// Raw Rec.601 luma: BRIGHT source regions carry the descriptor mass,
    /// putting the query on the same ink axis as the candidates, the tone
    /// pre-filter and the renderer.
    case direct
}

/// Universal rendering knobs. Each algorithm uses what's relevant to it. Out-of-range
/// values clamp silently — see `ResolvedRenderingOptions`.
public struct RenderingOptions: Sendable {
    /// 0...1. Floyd–Steinberg dither strength. `0` = no dither.
    /// Used by `dotMatrix`. Other algorithms ignore.
    public var coverage: Float

    /// 0...1. Algorithm-specific slack:
    /// - `logPolar`: widens brightness-prefilter top-K from 12 → 36.
    /// - `dotMatrix`: ignored.
    /// Finite values outside `0...1` clamp to the nearest endpoint during
    /// conversion. Non-finite values resolve to the default `0`.
    public var density: Float

    /// 0...1. Edge-emphasis weighting in shape match (`logPolar` only).
    public var edgeEmphasis: Float

    /// -1...1. Additive offset on OKLAB L. Affects display color AND
    /// brightness-based matching.
    public var brightness: Float

    /// -1...1. Scale-around-0.5 on OKLAB L. Affects display color AND
    /// brightness-based matching.
    public var contrast: Float

    /// Research-only (ASKI-60): which end of the source cell the `logPolar`
    /// shape query treats as ink. `.inverted` — the shipped default — is
    /// byte-identical to every release before the knob existed. Set
    /// post-construction by the labs; the public `init` does not expose it.
    @_spi(AskiResearch) public var shapeQueryPolarity: ShapeQueryPolarity = .inverted

    public init(
        coverage: Float = 0,
        density: Float = 0,
        edgeEmphasis: Float = 0,
        brightness: Float = 0,
        contrast: Float = 0
    ) {
        self.coverage = coverage
        self.density = density
        self.edgeEmphasis = edgeEmphasis
        self.brightness = brightness
        self.contrast = contrast
    }

    /// The bit-identical default: every effect knob is zero.
    public static let `default` = RenderingOptions()
}

/// Internal snapshot of `RenderingOptions` taken at the top of `convert(_:columns:)`.
/// All fields clamped to their valid ranges so kernels never see invalid inputs.
internal struct ResolvedRenderingOptions: Sendable {
    let coverage: Float  // clamped to 0...1
    let density: Float  // sanitized to 0...1; non-finite resolves to 0
    let edgeEmphasis: Float  // clamped to 0...1
    let brightness: Float  // clamped to -1...1
    let contrast: Float  // clamped to -1...1
    let shapeQueryPolarity: ShapeQueryPolarity  // no range to clamp; research-only

    init(_ raw: RenderingOptions) {
        self.coverage = simd_clamp(raw.coverage, 0, 1)
        self.density = Self.sanitizedClamped(raw.density, min: 0, max: 1, defaultValue: 0)
        self.edgeEmphasis = simd_clamp(raw.edgeEmphasis, 0, 1)
        self.brightness = simd_clamp(raw.brightness, -1, 1)
        self.contrast = simd_clamp(raw.contrast, -1, 1)
        self.shapeQueryPolarity = raw.shapeQueryPolarity
    }

    /// Matches the Batch A aesthetic-knob rule: non-finite inputs choose the
    /// documented default; finite inputs clamp to their documented range.
    private static func sanitizedClamped(
        _ value: Float,
        min minimum: Float,
        max maximum: Float,
        defaultValue: Float
    ) -> Float {
        guard value.isFinite else { return defaultValue }
        return Swift.min(maximum, Swift.max(minimum, value))
    }
}
