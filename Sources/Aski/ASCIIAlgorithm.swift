// Sources/Aski/ASCIIAlgorithm.swift

/// Selects which character-matching kernel runs inside `ASCIIConverter.convert(_:columns:)`.
///
/// - Note: `algorithm` and `characterSet` are independent fields. Aski documents
///   recommended pairings (see `Aski.docc/Algorithms.md`); mismatched combinations
///   run without error but may produce poor visual output.
public enum ASCIIAlgorithm: Sendable {
    /// 60D log-polar shape-context matching. Default; pairs well with `standard`
    /// and `braille`.
    ///
    /// At the default `oversample`, `minimal`, `dots`, `diagonal`, `cross` and
    /// `diamond` render every cell as a space under this algorithm, and `blocks`,
    /// `lines` and `mixed` settle on a few glyphs per image. A custom set
    /// whose glyphs have no ink in the few descriptor bins a cell query reaches
    /// behaves the same way. Use ``ASCIIAlgorithm/dotMatrix`` for those sets; see
    /// `Aski.docc/Algorithms.md`.
    case logPolar

    /// Brightness-based matching with Floyd–Steinberg error diffusion.
    /// Pairs well with density-ramp charsets (`minimal`, `blocks`, `dots`, `braille`).
    case dotMatrix
}
