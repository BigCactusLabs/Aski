import Foundation

public extension ASCIIGrid {
    /// Returns a copy of the grid with each cell's alpha multiplied by the
    /// ongoing pattern's value at `time`, leaving glyphs, colors, brightness,
    /// and coverage untouched.
    ///
    /// This is a pure function of `(pattern, time)`. Feeding each video frame
    /// its own presentation timestamp therefore yields a phase that advances
    /// coherently across frames *by construction* — the global-phase model
    /// behind AC#2 (see the ASTSK-39 pattern-overlay design). It mirrors the
    /// ongoing-alpha modulation in `AnimatedASCIIGrid.grid(at:)`, generalized
    /// to an arbitrary per-frame base grid rather than a single static one.
    ///
    /// A pattern that evaluates to a unit multiplier (e.g. `pulse(depth: 0)` or
    /// `wave(amplitude: 0)`) returns the grid unchanged.
    func applyingOngoingPattern(_ pattern: OngoingPattern, at time: TimeInterval) -> ASCIIGrid {
        // Checked ahead of the empty-grid shortcut so the contract does not
        // depend on how many cells the grid happens to have (ASKI-18).
        pattern.validate()
        guard rows > 0, columns > 0 else { return self }
        let resolvedTime = time.isFinite ? max(0, time) : 0

        let modulated = cells.enumerated().map { row, line in
            line.enumerated().map { column, cell -> ASCIICell in
                let coord = AnimationCellCoordinate(
                    column: column,
                    row: row,
                    columns: columns,
                    rows: rows
                )
                let multiplier = PatternEvaluator.ongoingAlpha(pattern, coord: coord, time: resolvedTime)
                let alpha = cell.alpha * Float(PatternEvaluator.clampUnit(multiplier, fallback: 1))
                return ASCIICell(
                    character: cell.character,
                    displayColor: cell.displayColor,
                    alpha: alpha,
                    brightness: cell.brightness,
                    coverage: cell.coverage
                )
            }
        }

        return ASCIIGrid(
            cells: modulated,
            colorSpace: colorSpace,
            composition: composition,
            maskFallback: maskFallback,
            maskGroundColor: maskGroundColor,
            maskUsesHardEdges: maskUsesHardEdges
        )
    }
}
