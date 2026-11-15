import simd

/// An expert extension point for character sets with precomputed matching data.
///
/// Use ``RasterizedCharacterSet`` to create a set from a font and a glyph list.
/// Conform directly when you supply the matcher data for each glyph.
/// The descriptor is one whole-raster, 60-component log-polar histogram,
/// simplified from the tiled construction in Xu, Zhang and Wong's
/// *Structure-based ASCII Art* (SIGGRAPH 2010). It does not reproduce that
/// paper's positional descriptor; see the ASKI-52/26 convention study under
/// `docs/Research/2026-08-28-aski52-26-candidate-convention.md`.
///
/// Keep `characters` nonempty and all four arrays aligned in glyph order.
/// Both density arrays have one entry per glyph. The shape array has
/// `lanesPerCharacter` consecutive SIMD entries per glyph.
///
/// Keep the arrays coherent while the converter reads them. An
/// ``ASCIIConverter`` traps on an empty set or mismatched array lengths when it
/// takes a snapshot at initialization or on assignment to `characterSet`. If a
/// reference-type conformance changes later, assign it again to take a fresh
/// snapshot.
public protocol ASCIICharacterSet: Sendable {

    /// The characters in this set, in presentation order.
    var characters: [Character] { get }

    /// Normalized ink density per glyph, with finite values in `0...1`.
    /// Used by dot-matrix selection and the log-polar brightness prefilter.
    var brightnessValues: [Float] { get }

    /// The fraction of each glyph cell covered by ink, with finite values in
    /// `0...1`. Retained for research and replay. The default implementation
    /// uses `brightnessValues` as an approximation for sets without measured
    /// coverage. Look up values by glyph index because the array can be unsorted.
    var rawDensityValues: [Float] { get }

    /// The log-polar descriptor for each glyph, packed as 15 consecutive
    /// `SIMD4<Float>` entries with no padding. Entries `i * 15 ..< (i + 1) * 15`
    /// contain the 60 components for glyph `i`. Supply this layout for every
    /// glyph, including when using dot-matrix selection.
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
