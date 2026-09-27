import Testing

@testable import AskiColorLab

/// Guards the ASKI-80 texture readouts (`PickTexture`) the selection-ceiling
/// census and `query-orthogonality` report next to the oracle means.
///
/// Every expectation below is derived by hand from the grid in the test, not
/// read back from the implementation: a run-length counter that is off by one at
/// a row end, or that lets a blank or an unscored cell extend a run, would
/// report exactly the long same-glyph runs ASKI-80 is trying to measure.
@Suite struct AskiColorLabPickTextureTests {

    /// Glyph 0 is the blank; 1 and 2 are inked.
    private static let isBlank: @Sendable (Int) -> Bool = { $0 == 0 }

    /// Two rows. Row 0: `a a a a a b _ b b · b` (`_` blank, `·` unscored).
    /// Row 1: `b b b b b b a _ _ a`.
    ///
    /// Runs: row 0 → 5 (a), 1 (b), 2 (b b), 1 (b, the unscored cell closed the
    /// previous run); row 1 → 6 (b), 1 (a), 1 (a). Seven runs of lengths
    /// {1,1,1,1,2,5,6} over 17 inked cells; 20 scored cells, 3 blank.
    @Test func handBuiltGridMatchesHandCountedRuns() {
        let grid: [[Int?]] = [
            [1, 1, 1, 1, 1, 2, 0, 2, 2, nil, 2],
            [2, 2, 2, 2, 2, 2, 1, 0, 0, 1],
        ]
        let readout = PickTexture.readout(grid, isBlank: Self.isBlank)

        #expect(readout.cells == 20)
        #expect(readout.blankCells == 3)
        #expect(readout.glyphsUsed == 3, "blank counts as a used glyph")
        #expect(readout.runs == 7)
        #expect(readout.runMean == 17.0 / 7.0)
        // Nearest rank: ceil(0.95 * 7) = 7th of {1,1,1,1,2,5,6} → 6.
        #expect(readout.runP95 == 6)
        #expect(readout.runMax == 6)
        // Runs of 5 and 6 are long: 11 of 17 inked cells.
        #expect(readout.run5Share == 11.0 / 17.0)
        #expect(readout.blankShare == 3.0 / 20.0)
    }

    /// A run never continues across a row boundary: `a a a` then `a a` on the
    /// next row are two runs of 3 and 2, so nothing reaches the long threshold.
    @Test func rowEndClosesARun() {
        let readout = PickTexture.readout([[1, 1, 1], [1, 1]], isBlank: Self.isBlank)
        #expect(readout.runs == 2)
        #expect(readout.runMax == 3)
        #expect(readout.run5Share == 0)
    }

    /// A blank between two identical inked cells splits them; the blank is not
    /// part of either run.
    @Test func blankClosesARunAndIsNotPartOfIt() {
        let readout = PickTexture.readout([[1, 1, 1, 0, 1, 1, 1]], isBlank: Self.isBlank)
        #expect(readout.runs == 2)
        #expect(readout.runMax == 3)
        #expect(readout.blankShare == 1.0 / 7.0)
    }

    /// Exactly at the threshold counts; one below does not.
    @Test func longRunThresholdIsInclusive() {
        let atThreshold = PickTexture.readout([[1, 1, 1, 1, 1, 2]], isBlank: Self.isBlank)
        #expect(atThreshold.run5Share == 5.0 / 6.0)
        let below = PickTexture.readout([[1, 1, 1, 1, 2]], isBlank: Self.isBlank)
        #expect(below.run5Share == 0)
    }

    /// ASKI-79's all-blank grid has no runs. The run statistics are undefined,
    /// not zero: a mean run of 0 would read as "no repeated glyphs".
    @Test func allBlankGridReportsUndefinedRunsAndFullBlankShare() {
        let readout = PickTexture.readout([[0, 0, 0], [0, 0]], isBlank: Self.isBlank)
        #expect(readout.glyphsUsed == 1)
        #expect(readout.blankShare == 1)
        #expect(readout.runs == 0)
        #expect(readout.runMean.isNaN)
        #expect(readout.runP95.isNaN)
        #expect(readout.run5Share.isNaN)
    }

    /// Pooling two grids is the same as one grid holding both sets of rows —
    /// the census pools fixtures this way.
    @Test func accumulatorPoolsGridsAsIfTheirRowsWereStacked() {
        let first: [[Int?]] = [[1, 1, 1, 1, 1, 1], [2, 0, 2]]
        let second: [[Int?]] = [[2, 2, 1], [nil, 1, 1, 1, 1, 1]]
        var accumulator = PickTexture.Accumulator()
        accumulator.add(first, isBlank: Self.isBlank)
        accumulator.add(second, isBlank: Self.isBlank)
        #expect(
            accumulator.resolved()
                == PickTexture.readout(first + second, isBlank: Self.isBlank))
    }

    @Test func nearestRankPercentileUsesTheCeilingRank() {
        // n = 20, rank = ceil(0.95 * 20) = 19.
        #expect(PickTexture.nearestRankPercentile([1: 19, 10: 1], percentile: 0.95) == 1)
        #expect(PickTexture.nearestRankPercentile([1: 18, 10: 2], percentile: 0.95) == 10)
        #expect(PickTexture.nearestRankPercentile([3: 1], percentile: 0.5) == 3)
        #expect(PickTexture.nearestRankPercentile([:], percentile: 0.95).isNaN)
    }

    /// The census's blank predicate: a glyph whose every lane is zero.
    @Test func zeroNormGlyphsFindsOnlyAllZeroVectors() {
        let lanesPerCharacter = 2
        let lanes: [SIMD4<Float>] = [
            .zero, .zero,  // 0: blank
            SIMD4(0, 0, 0, 0.5), .zero,  // 1: inked
            .zero, SIMD4(1e-7, 0, 0, 0),  // 2: tiny but non-zero
        ]
        #expect(
            PickTexture.zeroNormGlyphs(candidateLanes: lanes, lanesPerCharacter: lanesPerCharacter)
                == [0])
    }
}
