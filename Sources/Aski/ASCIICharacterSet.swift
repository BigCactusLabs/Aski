import simd

/// A character set with precomputed matching data.
///
/// **Dimensionality:** 60D log-polar shape context per character, stored as
/// 15 × SIMD4<Float> (60 lanes, zero padding, clean NEON register tiling).
///
/// The log-polar idea comes from Xu, Zhang & Wong, *Structure-based ASCII Art*,
/// ACM Transactions on Graphics 29(4), SIGGRAPH 2010 — **not** SIGGRAPH Asia,
/// as this comment previously said. The construction here is a deliberate
/// simplification of that paper's, and calling it a match would overstate the
/// lineage: the paper samples a *tiled* lattice of overlapping log-polar
/// windows (stride 2) across the whole cell and concatenates them, so a cell
/// carries dozens of windows and thousands of dimensions, and it applies the
/// same pattern to the source cell and the glyph alike. This descriptor is one
/// window over the whole raster — N = 1, 60 dimensions total — which keeps the
/// matcher cheap but discards the positional structure the tiling exists to
/// preserve. Measured in ASKI-52 / ASKI-26; see
/// `docs/Research/2026-08-28-aski52-26-candidate-convention.md`.
///
/// **Parallel-array invariant (a precondition, not a hint).** Every per-glyph
/// array is indexed in lockstep with `characters`: `brightnessValues.count` and
/// `rawDensityValues.count` equal `characters.count`, `shapeVectorLanes.count`
/// equals `characters.count * lanesPerCharacter`.
/// Conformances should enforce this at construction; `StandardCharacterSet.parse`
/// throws `LoadError.invalidScalar` rather than return a short `characters`
/// array. `ASCIIConverter.init(characterSet:palette:...)` takes one validated
/// internal snapshot before a matcher can use the arrays unchecked.
public protocol ASCIICharacterSet: Sendable {

    /// The characters in this set, in presentation order.
    var characters: [Character] { get }

    /// Mean ink density per character (1D), used for the first-pass brightness filter.
    /// Same count as `characters`, values in 0...1.
    var brightnessValues: [Float] { get }

    /// Absolute ink-area density per character: the fraction of the character
    /// cell covered by ink, in 0...1. Unlike `brightnessValues`, this is NOT
    /// normalized to the densest glyph — `rawDensityValues[i]` is the physical
    /// coverage `k` retained for tone/oracle research and historical replay.
    /// The current production matcher does not read this channel.
    /// Same count as `characters`.
    ///
    /// Ordering follows the `brightnessValues` density ramp only up to
    /// brightness-quantization ties (distinct raw values can normalize to the
    /// same brightness float, leaving one-ulp inversions — e.g. braille).
    /// Index into it; do not binary-search it.
    var rawDensityValues: [Float] { get }

    /// Flat array of SIMD4 lanes representing the 60D shape vector per character.
    /// Layout: `characters.count * 15` entries, where lanes `[i*15 ..< (i+1)*15]`
    /// contain the 60 float values for character `i`.
    var shapeVectorLanes: [SIMD4<Float>] { get }

}

public extension ASCIICharacterSet {
    /// Number of SIMD4 lanes per character. Constant: 15 (= 60 / 4).
    static var lanesPerCharacter: Int { GlyphBank.lanesPerCharacter }

    /// Shape vector dimensionality. Constant: 60.
    static var shapeVectorDimension: Int { GlyphBank.shapeVectorDimension }

    /// Fallback for sets that don't carry absolute density: approximates raw
    /// density with the normalized brightness (identical to the v1 `.bin`
    /// back-compat behavior).
    var rawDensityValues: [Float] { brightnessValues }

}
