// Sources/Aski/ASCIITileShape.swift

/// Source-pixel sampling aspect ratio. Adjusts how many source pixels go into
/// each cell; renderers keep the font's natural cell aspect (sampling-only).
///
/// Higher values produce taller source cells, fewer rows, and characters
/// chosen for stocky shapes. `.wide` (= 2.2) reproduces today's default
/// `widthRatio: 2.2` behavior bit-identically.
public enum ASCIITileShape: Sendable {
    case square  // 1.0
    case wide  // 2.2 — the historical Aski default
    case tall  // 0.5

    /// Source cell height divided by source cell width, in pixels.
    /// Renderers do NOT consult this — only the converter's grid-dimension
    /// computation does.
    public var sourceCellHeightOverWidth: Float {
        switch self {
        case .square: return 1.0
        case .wide: return 2.2
        case .tall: return 0.5
        }
    }
}
