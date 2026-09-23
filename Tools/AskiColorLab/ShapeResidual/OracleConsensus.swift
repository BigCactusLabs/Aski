// MARK: - Training-free oracle consensus (ASTSK-31 AC#2)

/// A training-free consensus across the three structure oracles (`gmsd`,
/// `1 − ssim_structure`, `1 − haarpsi`), used as the pre-registered verdict
/// statistic for the general-signal axis.
///
/// **Why median-of-ranks, and why training-free.** The IQA fusion literature is
/// dominated by *trained* fusion (SVR / annealing weight fitting), which is
/// unusable here: there is no MOS data, and a fitted rule cannot be pre-registered
/// honestly. The training-free branch is rank aggregation (RRF-style); a per-cell
/// **median of the three oracle ranks** is its simplest defensible member — it
/// needs no weights, is robust to one oracle disagreeing (the median ignores the
/// outlier), and is invariant to each oracle's monotone scaling.
///
/// **Population-relative (load-bearing).** Ranks are computed *within the
/// population being correlated*: per-fixture ranks for the per-fixture ρ, pooled
/// ranks for the pooled ρ. The same cell therefore gets a different consensus
/// value in a per-fixture vs a pooled correlation — so the consensus is NOT a
/// per-cell CSV column (it has no population-independent value); it lives only in
/// the Spearman table and `spearman_summary.csv`.
///
/// All three inputs are already oriented "higher = worse" (the residual's axis):
/// `gmsd` directly, and the two SSIM/HaarPSI similarities via `1 − ·`. So a valid
/// residual yields a POSITIVE ρ(residual, consensus).
enum OracleConsensus {
    /// Per-cell consensus = median of the average-ranks of the three oracle vectors
    /// within this population. All three inputs must be the same length and aligned
    /// cell-for-cell with the residual; returns one consensus value per cell (a
    /// rank, generally fractional under ties).
    static func medianRank(
        gmsd: [Double], oneMinusStructure: [Double], oneMinusHaar: [Double]
    ) -> [Double] {
        let n = gmsd.count
        precondition(
            oneMinusStructure.count == n && oneMinusHaar.count == n,
            "OracleConsensus.medianRank requires equal-length oracle vectors"
        )
        guard n > 0 else { return [] }
        let rankG = Spearman.averageRanks(gmsd)
        let rankS = Spearman.averageRanks(oneMinusStructure)
        let rankH = Spearman.averageRanks(oneMinusHaar)
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            out[i] = median3(rankG[i], rankS[i], rankH[i])
        }
        return out
    }

    /// Spearman ρ(residual, consensus) where the consensus is the median-of-ranks
    /// over the SAME population as `residual`. A convenience that pairs the
    /// population-relative consensus with the residual it is correlated against.
    static func rho(
        residual: [Double], gmsd: [Double], oneMinusStructure: [Double], oneMinusHaar: [Double]
    ) -> Double {
        let consensus = medianRank(
            gmsd: gmsd, oneMinusStructure: oneMinusStructure, oneMinusHaar: oneMinusHaar)
        return Spearman.rho(residual, consensus)
    }

    /// Middle of three values (median), tie-safe.
    private static func median3(_ a: Double, _ b: Double, _ c: Double) -> Double {
        max(min(a, b), min(max(a, b), c))
    }
}
