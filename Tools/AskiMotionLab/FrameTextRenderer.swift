import Aski

/// Alpha-aware text renderer for canonical MotionLab frames. Unlike the
/// library's `ASCIIGrid.renderPlainText()` (which gates only on `coverage` and
/// ignores `alpha`), a cell shows its `character` only when both
/// `coverage >= 0.5` and `alpha >= 0.5`; otherwise a space. This captures the
/// `reveal` preset's visibility motion and the `cycle` preset's glyph motion,
/// so the canonical sequence is non-degenerate for both presets.
public enum FrameTextRenderer {
    /// Visibility threshold, matching `PlainTextRenderer`'s coverage gate.
    public static let visibilityThreshold: Float = 0.5

    public static func render(_ grid: ASCIIGrid) -> String {
        if grid.cells.isEmpty { return "" }
        var result = ""
        result.reserveCapacity(grid.rows * (grid.columns + 1))
        for (index, row) in grid.cells.enumerated() {
            for cell in row {
                if cell.coverage >= visibilityThreshold && cell.alpha >= visibilityThreshold {
                    result.append(cell.character)
                } else {
                    result.append(" ")
                }
            }
            if index < grid.cells.count - 1 {
                result.append("\n")
            }
        }
        return result
    }
}
