import Aski

/// Descriptive (NOT evaluative) per-candidate stats. Deliberately carries no
/// quality score: the frontier sweep flagged reconstruction metrics (GMSD
/// tunnel vision) as the trap here — the human ranks the renders by eye; these
/// numbers only orient (denser vs sparser, glyph vocabulary actually used).
public struct CandidateStats: Equatable, Sendable {
    public let columns: Int
    public let rows: Int
    public let cellCount: Int
    public let distinctGlyphs: Int

    public init(columns: Int, rows: Int, cellCount: Int, distinctGlyphs: Int) {
        self.columns = columns
        self.rows = rows
        self.cellCount = cellCount
        self.distinctGlyphs = distinctGlyphs
    }

    public static func from(grid: ASCIIGrid) -> CandidateStats {
        var glyphs = Set<Character>()
        var cellCount = 0
        for row in grid.cells {
            for cell in row {
                glyphs.insert(cell.character)
                cellCount += 1
            }
        }
        return CandidateStats(
            columns: grid.columns,
            rows: grid.rows,
            cellCount: cellCount,
            distinctGlyphs: glyphs.count
        )
    }
}
