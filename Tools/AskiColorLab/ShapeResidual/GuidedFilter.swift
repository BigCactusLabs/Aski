import Foundation

// MARK: - Self-guided guided filter (ASTSK-43 Fork B candidate pre-pass)

/// Self-guided guided filter (He, Sun & Tang, *Guided Image Filtering*, IEEE
/// TPAMI 2013) over a single-channel, row-major `[Float]` field.
///
/// Selected by the 2026-06-24 frontier-search bolster (`docs/Research/Discoveries.md`)
/// as the candidate ASTSK-43 inter-cell coupling pre-pass, run on the *continuous
/// pre-quantization* field before the per-cell matcher. Rationale over the
/// rejected alternatives:
///
/// - **O(N) independent of radius** (two box-mean passes), vs brute-force
///   bilateral's O(N·r²).
/// - **No gradient reversal, by construction.** In the self-guided case the
///   per-window linear coefficient is `a = var / (var + ε)`. Clamping `var ≥ 0`
///   keeps `a ∈ [0, 1)`, so the detail-layer gradient `(1 − a)·∂p` keeps the
///   *same sign* as the input — the flaw the TPAMI paper calls "inherent and
///   cannot be safely avoided by tuning parameters" for the bilateral filter.
/// - **Edge-preserving:** at a window straddling an edge `var` is large ⇒ `a ≈ 1`
///   ⇒ output ≈ input (the step survives); in a flat window `var ≈ 0` ⇒ `a ≈ 0`
///   ⇒ output = local mean (noise smoothed).
///
/// Lab-only (`Sources/Aski` untouched) until the ASTSK-43 gate returns PASS.
///
/// **Known caveat (frontier-search):** the box window is rotationally asymmetric
/// and slightly biases to the x/y axis; a Gaussian-weighted window restores
/// symmetry at extra cost. Tracked for the gate if diagonal seams stair-step.
enum GuidedFilter {
    /// Self-guided guided filter. Guidance == input `src`, so the linear model
    /// collapses to `a = var/(var+ε)`, `b = (1−a)·mean`. Border windows are
    /// normalized by their valid in-bounds pixel count (the reference
    /// implementation's `N = boxfilter(ones)` normalization).
    ///
    /// - Returns `[]` for degenerate / mismatched input (matches the lab's other
    ///   oracle functions). Otherwise a same-size filtered field.
    static func selfGuided(
        _ src: [Float], width: Int, height: Int, radius: Int, epsilon: Float
    ) -> [Float] {
        let n = width * height
        guard n > 0, src.count == n, width > 0, height > 0, radius >= 0 else { return [] }

        let meanI = boxMean(src, width: width, height: height, radius: radius)
        var ii = [Float](repeating: 0, count: n)
        for i in 0..<n { ii[i] = src[i] * src[i] }
        let meanII = boxMean(ii, width: width, height: height, radius: radius)

        var a = [Float](repeating: 0, count: n)
        var b = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let varI = max(0, meanII[i] - meanI[i] * meanI[i])  // clamp float rounding
            let ai = varI / (varI + epsilon)  // self-guided: cov == var
            a[i] = ai
            b[i] = (1 - ai) * meanI[i]
        }
        let meanA = boxMean(a, width: width, height: height, radius: radius)
        let meanB = boxMean(b, width: width, height: height, radius: radius)

        var out = [Float](repeating: 0, count: n)
        for i in 0..<n { out[i] = meanA[i] * src[i] + meanB[i] }
        return out
    }

    /// Box (mean) filter over a `(2·radius+1)²` window, each output normalized by
    /// the count of valid in-bounds pixels in its window. Same-size output.
    ///
    /// Computed via a summed-area table (integral image), so it is **O(N)
    /// independent of `radius`** — the property the guided filter is selected for
    /// (a brute-force window would be O(N·r²) and is impractical at native
    /// resolution with a cell-scale radius). The table is accumulated in `Double`
    /// so large fields (e.g. 2048²) don't lose precision when summed.
    static func boxMean(_ src: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        let n = width * height
        var out = [Float](repeating: 0, count: n)
        guard n > 0, src.count == n, width > 0, height > 0, radius >= 0 else { return out }

        // Summed-area table: sat[(y+1)*iw + (x+1)] = Σ src over [0…y]×[0…x].
        let iw = width + 1
        var sat = [Double](repeating: 0, count: iw * (height + 1))
        for y in 0..<height {
            var rowSum = 0.0
            let srcRow = y * width
            let satRow = (y + 1) * iw
            let aboveRow = y * iw
            for x in 0..<width {
                rowSum += Double(src[srcRow + x])
                sat[satRow + (x + 1)] = sat[aboveRow + (x + 1)] + rowSum
            }
        }
        for y in 0..<height {
            let y0 = max(0, y - radius), y1 = min(height - 1, y + radius)
            for x in 0..<width {
                let x0 = max(0, x - radius), x1 = min(width - 1, x + radius)
                // Inclusive region sum [x0…x1]×[y0…y1] from the four SAT corners.
                let sum =
                    sat[(y1 + 1) * iw + (x1 + 1)] - sat[y0 * iw + (x1 + 1)]
                    - sat[(y1 + 1) * iw + x0] + sat[y0 * iw + x0]
                let count = (x1 - x0 + 1) * (y1 - y0 + 1)
                out[y * width + x] = count > 0 ? Float(sum / Double(count)) : 0
            }
        }
        return out
    }
}
