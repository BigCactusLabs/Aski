import Foundation

/// Texture readouts over a grid of glyph picks (ASKI-80 AC#1).
///
/// The oracle panel scores each cell on its own, so it cannot see the failure
/// ASKI-80 reports: a selector that maps every cell in a tone band to the same
/// glyph can hold a reasonable per-cell MAE while the output reads as rows of
/// `zzzz`, `====`, `||||`. These readouts measure that directly, from the picks
/// alone, and travel next to the oracle means.
///
/// Definitions, fixed so two runs are comparable:
///
/// - A **blank** is a glyph the caller marks blank. The census passes the
///   zero-norm glyphs (`|g|² == 0`), the only candidates the log-polar distance
///   cannot tell apart from an empty cell.
/// - A **run** is a maximal horizontal sequence of cells in one row holding the
///   same non-blank glyph. A blank, an unscored cell (`nil`) or the row end
///   closes a run. A lone non-blank cell is a run of length 1.
/// - `glyphsUsed` counts distinct picked glyphs, blank included, so an all-blank
///   grid reads `1` next to `blankShare == 1`.
/// - `runMean` is the unweighted mean over runs (non-blank cells / runs).
///   `runP95` is the nearest-rank 95th percentile of the same run-length
///   distribution.
/// - `run5Share` is the share of **non-blank** cells that sit in runs of
///   length 5 or more; `blankShare` is the share of scored cells that are blank.
///
/// Every ratio is `nan` when its denominator is empty, never `0`: an all-blank
/// grid has no runs, and reporting a mean run of 0 would read as "no runs of
/// repeated glyphs", which is the opposite of what happened.
enum PickTexture {

    /// The run length at and above which a run counts toward `run5Share`.
    static let longRunThreshold = 5

    struct Readout: Sendable, Equatable {
        let cells: Int
        let blankCells: Int
        let glyphsUsed: Int
        let runs: Int
        let runMean: Double
        let runP95: Double
        let runMax: Int
        let run5Share: Double
        let blankShare: Double
    }

    /// Streams any number of pick grids into one pooled readout, so a census row
    /// can describe a whole corpus rather than averaging per-fixture ratios.
    struct Accumulator: Sendable {
        private var cells = 0
        private var blankCells = 0
        private var nonBlankCells = 0
        private var cellsInLongRuns = 0
        private var glyphs = Set<Int>()
        /// `runLengths[n]` = number of runs of length `n`.
        private var runLengths: [Int: Int] = [:]

        init() {}

        /// Adds one grid. `picks[row][column]` is a glyph index, or `nil` for a
        /// cell that was not scored; `isBlank` decides blank-ness per index.
        mutating func add(_ picks: [[Int?]], isBlank: (Int) -> Bool) {
            for row in picks {
                var current: Int?
                var length = 0
                func close() {
                    if current != nil, length > 0 {
                        runLengths[length, default: 0] += 1
                        if length >= PickTexture.longRunThreshold { cellsInLongRuns += length }
                    }
                    current = nil
                    length = 0
                }
                for pick in row {
                    guard let pick else {
                        close()
                        continue
                    }
                    cells += 1
                    glyphs.insert(pick)
                    if isBlank(pick) {
                        blankCells += 1
                        close()
                        continue
                    }
                    nonBlankCells += 1
                    if pick == current {
                        length += 1
                    } else {
                        close()
                        current = pick
                        length = 1
                    }
                }
                close()
            }
        }

        func resolved() -> Readout {
            let runs = runLengths.values.reduce(0, +)
            return Readout(
                cells: cells,
                blankCells: blankCells,
                glyphsUsed: glyphs.count,
                runs: runs,
                runMean: runs > 0 ? Double(nonBlankCells) / Double(runs) : .nan,
                runP95: PickTexture.nearestRankPercentile(runLengths, percentile: 0.95),
                runMax: runLengths.keys.max() ?? 0,
                run5Share: nonBlankCells > 0
                    ? Double(cellsInLongRuns) / Double(nonBlankCells) : .nan,
                blankShare: cells > 0 ? Double(blankCells) / Double(cells) : .nan)
        }
    }

    /// One grid's readout.
    static func readout(_ picks: [[Int?]], isBlank: (Int) -> Bool) -> Readout {
        var accumulator = Accumulator()
        accumulator.add(picks, isBlank: isBlank)
        return accumulator.resolved()
    }

    /// Nearest-rank percentile of a histogram `{value: count}`: the smallest
    /// value whose cumulative count reaches `ceil(p * n)`. `nan` when empty.
    static func nearestRankPercentile(_ histogram: [Int: Int], percentile: Double) -> Double {
        let total = histogram.values.reduce(0, +)
        guard total > 0 else { return .nan }
        let rank = max(1, Int((percentile * Double(total)).rounded(.up)))
        var cumulative = 0
        for value in histogram.keys.sorted() {
            cumulative += histogram[value] ?? 0
            if cumulative >= rank { return Double(value) }
        }
        return Double(histogram.keys.max() ?? 0)
    }

    /// Indices of the zero-norm glyphs in a flattened lane array — the glyphs
    /// the log-polar distance scores as `|q|²` whatever the query.
    static func zeroNormGlyphs(candidateLanes: [SIMD4<Float>], lanesPerCharacter: Int) -> Set<Int> {
        guard lanesPerCharacter > 0 else { return [] }
        let count = candidateLanes.count / lanesPerCharacter
        var out = Set<Int>()
        for index in 0..<count {
            var norm: Float = 0
            for lane in 0..<lanesPerCharacter {
                let value = candidateLanes[index * lanesPerCharacter + lane]
                norm += (value * value).sum()
            }
            if norm == 0 { out.insert(index) }
        }
        return out
    }
}
