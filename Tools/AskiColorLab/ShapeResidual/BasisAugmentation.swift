import Foundation

// MARK: - Log-polar basis-augmentation prototype (ASTSK-31 Phase 6 — AC#4)

/// Lab-only prototype of two structure channels the 60D log-polar shape descriptor
/// under-weights, computed per cell on BOTH the source block and the chosen glyph
/// raster at the fixed oracle footprint (`oracleCellSize`):
///
/// - **orientation-energy** — an 8-bin, energy-weighted gradient-orientation
///   histogram, folded to `[0, π)` (an edge and its reverse share an orientation).
///   Its *dispersion* (normalised Shannon entropy) separates single-orientation
///   content (energy in one bin → ~0) from isotropic content (energy spread across
///   bins → ~1). `d_orient` is the L1 distance between the glyph's and the source's
///   normalised histograms.
/// - **radial-frequency** — the radial luma profile about the block centre,
///   summarised by its strongest autocorrelation peak. Concentric content oscillates
///   (strong peak); flat / single-edge content is near-constant (degenerate → 0).
///   `d_radial` is the absolute difference of the glyph's and source's peaks.
///
/// The augmented residual rank-mixes the residual with these two channels at three
/// FIXED, pre-registered weights (`mixes`). **The weights are never fitted** — a `w`
/// tuned against the oracle would be circular. This module only surfaces `d_orient`
/// / `d_radial` and ρ(augmented, consensus); it does NOT change production matching
/// (`Sources/Aski` is untouched). If a mix shows lift, the production basis change
/// is split off as its own task (AC#4 sanctions that disposition).
///
/// Prior art: SYM-FISH (ICCV 2013) augments log-polar shape-context with a
/// symmetry channel; Fourier-Mellin / log-polar-magnitude descriptors capture the
/// radial-frequency structure an orientation-binned basis misses.
enum BasisAugmentation {
    /// Pre-registered augmentation weights. Fixed constants; never fitted.
    static let mixes: [Double] = [0.25, 0.5, 0.75]

    /// Number of orientation bins over `[0, π)`.
    static let orientationBins = 8

    // MARK: - Orientation-energy channel

    /// Energy-weighted gradient-orientation histogram, `orientationBins` bins over
    /// `[0, π)` (gradient orientation folded — an edge and its reverse share an
    /// orientation). Each pixel contributes its Prewitt gradient ENERGY (`gx² + gy²`)
    /// to the bin of its orientation. Returned normalised to sum 1 (or all-zero for
    /// a flat block with no gradient energy). Replicated (clamped) borders, matching
    /// `GMSD.gradientMagnitude`.
    static func orientationHistogram(_ src: [Float], width: Int, height: Int) -> [Double] {
        var hist = [Double](repeating: 0, count: orientationBins)
        guard width > 0, height > 0, src.count == width * height else { return hist }
        @inline(__always) func at(_ xx: Int, _ yy: Int) -> Double {
            let cx = min(max(xx, 0), width - 1)
            let cy = min(max(yy, 0), height - 1)
            return Double(src[cy * width + cx])
        }
        let binWidth = Double.pi / Double(orientationBins)
        for y in 0..<height {
            for x in 0..<width {
                let tl = at(x - 1, y - 1), tc = at(x, y - 1), tr = at(x + 1, y - 1)
                let ml = at(x - 1, y), mr = at(x + 1, y)
                let bl = at(x - 1, y + 1), bc = at(x, y + 1), br = at(x + 1, y + 1)
                let gx = (tr + mr + br) - (tl + ml + bl)
                let gy = (bl + bc + br) - (tl + tc + tr)
                let energy = gx * gx + gy * gy
                guard energy > 0 else { continue }
                var theta = atan2(gy, gx)  // (−π, π]
                if theta < 0 { theta += Double.pi }  // fold to [0, π)
                if theta >= Double.pi { theta -= Double.pi }
                var bin = Int(theta / binWidth)
                if bin < 0 { bin = 0 }
                if bin >= orientationBins { bin = orientationBins - 1 }
                hist[bin] += energy
            }
        }
        let total = hist.reduce(0, +)
        guard total > 0 else { return hist }
        return hist.map { $0 / total }
    }

    /// Normalised Shannon entropy (in `[0, 1]`) of a histogram — its dispersion. 0
    /// for a degenerate (all-zero) or single-bin histogram; 1 for a uniform one.
    static func orientationDispersion(_ histogram: [Double]) -> Double {
        let total = histogram.reduce(0, +)
        guard total > 0, histogram.count > 1 else { return 0 }
        var h = 0.0
        for v in histogram where v > 0 {
            let p = v / total
            h -= p * Foundation.log(p)
        }
        return h / Foundation.log(Double(histogram.count))
    }

    /// `d_orient`: L1 distance between the chosen glyph's and the source block's
    /// normalised orientation histograms (higher = orientation structure differs
    /// more = worse match), in `[0, 2]`. Shares the residual's "higher = worse" axis.
    static func dOrient(glyph: [Float], source: [Float], width: Int, height: Int) -> Double {
        let hg = orientationHistogram(glyph, width: width, height: height)
        let hs = orientationHistogram(source, width: width, height: height)
        var d = 0.0
        for i in 0..<min(hg.count, hs.count) { d += abs(hg[i] - hs[i]) }
        return d
    }

    // MARK: - Radial-frequency channel

    /// Radial luma profile about the block centre: the mean luma of each integer
    /// radius shell, for radii `0 ... floor(min(w, h) / 2)`. Concentric content
    /// makes this oscillate; flat / single-edge content makes it near-constant
    /// (each shell straddling a single edge is balanced about the centre).
    static func radialProfile(_ src: [Float], width: Int, height: Int) -> [Double] {
        guard width > 0, height > 0, src.count == width * height else { return [] }
        let cx = Double(width - 1) / 2.0
        let cy = Double(height - 1) / 2.0
        let maxR = Int((min(Double(width), Double(height)) / 2.0).rounded(.down))
        guard maxR >= 1 else { return [] }
        var sums = [Double](repeating: 0, count: maxR + 1)
        var counts = [Int](repeating: 0, count: maxR + 1)
        for y in 0..<height {
            for x in 0..<width {
                let dx = Double(x) - cx, dy = Double(y) - cy
                let r = Int((dx * dx + dy * dy).squareRoot().rounded())
                guard r <= maxR else { continue }
                sums[r] += Double(src[y * width + x])
                counts[r] += 1
            }
        }
        var profile = [Double]()
        profile.reserveCapacity(maxR + 1)
        for r in 0...maxR where counts[r] > 0 {
            profile.append(sums[r] / Double(counts[r]))
        }
        return profile
    }

    /// Strongest autocorrelation peak of a profile at lag ≥ 2 (the central lobe at
    /// lag 0/1 is skipped so the summary measures *oscillation*, not adjacency).
    /// Normalised autocovariance (`ac[0] = 1`); degenerate (near-zero variance, or
    /// too short) → 0. High for concentric, ~0 for flat/edge.
    static func radialAutocorrelationPeak(_ profile: [Double]) -> Double {
        let n = profile.count
        guard n >= 4 else { return 0 }
        let mean = profile.reduce(0, +) / Double(n)
        var variance = 0.0
        for v in profile {
            let d = v - mean
            variance += d * d
        }
        guard variance > 1e-12 else { return 0 }
        let maxLag = n / 2
        guard maxLag >= 2 else { return 0 }
        var peak = 0.0
        for lag in 2...maxLag {
            var cov = 0.0
            for i in 0..<(n - lag) {
                cov += (profile[i] - mean) * (profile[i + lag] - mean)
            }
            let ac = cov / variance
            if ac > peak { peak = ac }
        }
        return peak
    }

    /// `d_radial`: absolute difference of the chosen glyph's and source block's
    /// radial autocorrelation peaks (higher = radial structure differs more = worse).
    static func dRadial(glyph: [Float], source: [Float], width: Int, height: Int) -> Double {
        let pg = radialAutocorrelationPeak(radialProfile(glyph, width: width, height: height))
        let ps = radialAutocorrelationPeak(radialProfile(source, width: width, height: height))
        return abs(pg - ps)
    }

    // MARK: - Augmented rank-mix

    /// Augmented score per cell: `w·rank(residual) + (1−w)·mean(rank(d_orient),
    /// rank(d_radial))`, all average-ranks within the passed population. Inputs must
    /// be equal length and aligned cell-for-cell with the residual.
    static func augmentedScore(
        residual: [Double], dOrient: [Double], dRadial: [Double], w: Double
    ) -> [Double] {
        let n = residual.count
        precondition(
            dOrient.count == n && dRadial.count == n,
            "augmentedScore requires equal-length vectors")
        guard n > 0 else { return [] }
        let rankR = Spearman.averageRanks(residual)
        let rankO = Spearman.averageRanks(dOrient)
        let rankD = Spearman.averageRanks(dRadial)
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            out[i] = w * rankR[i] + (1 - w) * 0.5 * (rankO[i] + rankD[i])
        }
        return out
    }

    /// ρ(augmented, consensus): Spearman ρ between the augmented score at weight `w`
    /// and the (population-relative) oracle consensus passed in. The consensus must
    /// be computed over the SAME population as `residual` (per-fixture vs pooled).
    static func rho(
        residual: [Double], dOrient: [Double], dRadial: [Double], consensus: [Double], w: Double
    ) -> Double {
        Spearman.rho(
            augmentedScore(residual: residual, dOrient: dOrient, dRadial: dRadial, w: w),
            consensus)
    }
}
