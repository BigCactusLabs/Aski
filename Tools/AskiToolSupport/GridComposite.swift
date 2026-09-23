import Foundation

// MARK: - Rendered-grid compositor (ASTSK-43 Unit 3)

/// Tiles a grid of chosen glyphs into a single native-resolution pixel image, so
/// the seam-continuity (M1) and GMSD/HaarPSI (M2) oracles have a *rendered grid
/// with real cell seams* to score — the thing the per-cell oracle path in
/// `ShapeResidualCommand` does not produce.
public enum GridComposite {
    /// Tile per-cell glyph rasters into one row-major `[Float]` image of size
    /// `(cols·cellPx) × (rows·cellPx)`. `raster(character)` returns a row-major
    /// `cellPx·cellPx` luma block (e.g. `GlyphRaster.luma`). Cells whose raster is
    /// the wrong size are left as background (0). Returns `([], 0, 0)` for a
    /// degenerate / ragged grid.
    public static func compose(
        characters: [[Character]], cellPx: Int, raster: (Character) -> [Float]
    ) -> (pixels: [Float], width: Int, height: Int) {
        let rows = characters.count
        guard rows > 0, cellPx > 0 else { return ([], 0, 0) }
        let cols = characters[0].count
        guard cols > 0, characters.allSatisfy({ $0.count == cols }) else { return ([], 0, 0) }

        let width = cols * cellPx, height = rows * cellPx
        var out = [Float](repeating: 0, count: width * height)
        for r in 0..<rows {
            for c in 0..<cols {
                let block = raster(characters[r][c])
                guard block.count == cellPx * cellPx else { continue }
                for py in 0..<cellPx {
                    let dstRow = (r * cellPx + py) * width + c * cellPx
                    let srcRow = py * cellPx
                    for px in 0..<cellPx {
                        out[dstRow + px] = block[srcRow + px]
                    }
                }
            }
        }
        return (out, width, height)
    }
}
