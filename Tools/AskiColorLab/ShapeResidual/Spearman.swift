// MARK: - Spearman rank correlation (B5 KILL statistic)

/// Spearman's rank correlation coefficient ρ between two equal-length samples.
///
/// **Definition.** Each input is converted to *fractional* ranks with
/// **average-rank tie handling**: a run of tied values is assigned the mean of
/// the rank positions it occupies (e.g. two values sharing positions 1 and 2 each
/// get rank 1.5). ρ is then the **Pearson correlation of the two rank vectors**.
///
/// This is the correct, tie-robust definition. We deliberately do *not* use the
/// `1 − 6Σd²/(n(n²−1))` shortcut: that closed form is only valid when there are
/// no ties, and silently biases ρ when ties are present. The shape-residual gate
/// (B5) rank-correlates `residual` against `1 − SSIM`, and both fields tie often
/// (flat cells, identical glyphs), so the Pearson-on-average-ranks path is the
/// only safe one — getting it wrong would corrupt the KILL.
///
/// **Degenerate cases return `0`** (documented as "no signal"; the caller treats a
/// `0` ρ as the absence of a usable structure signal):
///   - `n < 2` (fewer than two paired observations), or
///   - either rank vector has zero variance (every value tied → no ordering).
enum Spearman {
    /// Spearman's ρ between `x` and `y`. Precondition: `x.count == y.count`.
    /// Returns `0` for degenerate inputs (see type doc).
    static func rho(_ x: [Double], _ y: [Double]) -> Double {
        precondition(x.count == y.count, "Spearman.rho requires equal-length inputs")
        let n = x.count
        guard n >= 2 else { return 0 }

        let rankX = averageRanks(x)
        let rankY = averageRanks(y)
        return pearson(rankX, rankY)
    }

    /// `Float` convenience overload — promotes to `Double` and defers to the
    /// canonical implementation so the math is computed once, in one precision.
    static func rho(_ x: [Float], _ y: [Float]) -> Double {
        rho(x.map(Double.init), y.map(Double.init))
    }

    // MARK: - Internals

    /// Fractional ranks with average-rank tie handling. The smallest value gets
    /// rank 1; tied values share the mean of the positions they would occupy.
    static func averageRanks(_ values: [Double]) -> [Double] {
        let n = values.count
        guard n > 0 else { return [] }

        // Indices sorted by value (ascending). Ties are grouped by scanning runs
        // of equal value in this order, so the assignment is deterministic.
        let order = Array(0..<n).sorted { values[$0] < values[$1] }
        var ranks = [Double](repeating: 0, count: n)

        var i = 0
        while i < n {
            var j = i + 1
            // Extend the tie run while the next value equals the current one.
            while j < n && values[order[j]] == values[order[i]] {
                j += 1
            }
            // Positions i..<j (0-based) occupy 1-based ranks (i+1)...(j). Their
            // average is the mean of the first and last 1-based rank.
            let averageRank = Double((i + 1) + j) / 2.0
            for k in i..<j {
                ranks[order[k]] = averageRank
            }
            i = j
        }
        return ranks
    }

    /// Pearson correlation. Returns `0` if either input has zero variance.
    private static func pearson(_ a: [Double], _ b: [Double]) -> Double {
        let n = a.count
        guard n >= 2 else { return 0 }
        let count = Double(n)

        var sumA = 0.0, sumB = 0.0
        for i in 0..<n { sumA += a[i]; sumB += b[i] }
        let meanA = sumA / count
        let meanB = sumB / count

        var cov = 0.0, varA = 0.0, varB = 0.0
        for i in 0..<n {
            let da = a[i] - meanA
            let db = b[i] - meanB
            cov += da * db
            varA += da * da
            varB += db * db
        }
        guard varA > 0, varB > 0 else { return 0 }
        return cov / (varA * varB).squareRoot()
    }
}
