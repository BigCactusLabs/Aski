// Sources/Aski/ASCIIAlgorithm.swift

/// Selects which character-matching kernel runs inside `ASCIIConverter.convert(_:columns:)`.
///
/// - Note: `algorithm` and `characterSet` are independent fields. Aski documents
///   recommended pairings (see `Aski.docc/Algorithms.md`); mismatched combinations
///   run without error but may produce poor visual output.
public enum ASCIIAlgorithm: Sendable {
    /// 60D log-polar shape-context matching. Default; pairs well with the
    /// general-purpose ramp charsets (`standard`, `minimal`, `mixed`, `dots`, `braille`).
    case logPolar

    /// Brightness-based matching with Floyd–Steinberg error diffusion.
    /// Pairs well with density-ramp charsets (`minimal`, `blocks`, `dots`, `braille`).
    case dotMatrix
}
