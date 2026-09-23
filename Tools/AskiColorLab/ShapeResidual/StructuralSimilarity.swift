// MARK: - SSIM oracle (PIXELS ONLY)

/// The standard windowless (global) Structural SIMilarity index between two
/// equal-size grayscale buffers on normalized [0,1] luma (dynamic range L = 1.0,
/// stabilizers C1 = (0.01·L)², C2 = (0.03·L)²).
///
/// **Independence guarantee (load-bearing for B5):** both inputs are grayscale
/// pixel buffers — `x` is the rasterized chosen glyph, `y` is the source-cell
/// pixels. This function never receives, reads, or derives the shape residual,
/// the `scoreScored` distance, or any 60D shape vector. SSIM is a function of
/// glyph-raster pixels and source pixels, full stop.
enum StructuralSimilarity {
    static func ssim(_ x: [Float], _ y: [Float], width: Int, height: Int) -> Float {
        let n = width * height
        guard n > 0, x.count == n, y.count == n else { return 0 }
        let count = Float(n)

        var sumX: Float = 0, sumY: Float = 0
        for i in 0..<n { sumX += x[i]; sumY += y[i] }
        let muX = sumX / count
        let muY = sumY / count

        var varX: Float = 0, varY: Float = 0, cov: Float = 0
        for i in 0..<n {
            let dx = x[i] - muX
            let dy = y[i] - muY
            varX += dx * dx
            varY += dy * dy
            cov += dx * dy
        }
        // Sample variance/covariance (N-1) is conventional for SSIM; for N == 1
        // there is no spread, fall back to a degenerate-but-defined value.
        guard n > 1 else { return muX == muY ? 1 : 0 }
        let denom = count - 1
        varX /= denom
        varY /= denom
        cov /= denom

        let L: Float = 1.0
        let c1 = (0.01 * L) * (0.01 * L)
        let c2 = (0.03 * L) * (0.03 * L)
        let numerator = (2 * muX * muY + c1) * (2 * cov + c2)
        let denominator = (muX * muX + muY * muY + c1) * (varX + varY + c2)
        guard denominator != 0 else { return 0 }
        return numerator / denominator
    }

    /// The **structure-only** SSIM component:
    /// `s(x,y) = (σ_xy + C3) / (σ_x · σ_y + C3)`, with `C3 = C2 / 2` (the
    /// standard choice from Wang et al. 2004, where the full SSIM factors into
    /// luminance · contrast · structure and the structure factor uses C3 = C2/2).
    /// Range is roughly [−1, 1]: `1` = identical structure (perfectly correlated
    /// spatial pattern), `0` = uncorrelated, negative = anti-structured.
    ///
    /// **Why drop μ and the contrast-magnitude term (load-bearing for B5).**
    /// Full SSIM multiplies in a luminance term `(2μ_xμ_y+C1)/(μ_x²+μ_y²+C1)` and
    /// a contrast term `(2σ_xσ_y+C2)/(σ_x²+σ_y²+C2)`. Both penalize a *binary*
    /// glyph raster (ink/background, μ near the ink-fraction, large σ) compared to
    /// a *continuous-tone* gray source cell (μ near mid-gray, smaller σ) for
    /// reasons that are pure brightness/contrast offset, not spatial mismatch. The
    /// IQA literature (and SSIM's own derivation) treats those as separable
    /// confounds; the structure term `s` is by construction invariant to a uniform
    /// shift of either signal's mean and to a positive rescale of either's
    /// amplitude, so it measures only whether the *pattern* lines up. That is the
    /// fair question for "did the matcher pick a glyph whose ink lands where the
    /// source has structure", which is what B5 correlates against.
    ///
    /// **Degenerate (σ=0) handling.** When either buffer is flat its σ is 0, so
    /// σ_xy is also 0 (covariance with a constant is 0). Both numerator and
    /// denominator collapse to `C3`, giving exactly `1`. So *any* flat buffer vs
    /// *any* other flat buffer (regardless of their mean offset) returns `1.0` —
    /// the C3 stabilizer encodes "two structureless patches have identical
    /// (absent) structure", which is the intended luminance-insensitive answer.
    static func structure(_ x: [Float], _ y: [Float], width: Int, height: Int) -> Double {
        let n = width * height
        guard n > 0, x.count == n, y.count == n else { return 0 }
        let count = Double(n)

        var sumX = 0.0, sumY = 0.0
        for i in 0..<n { sumX += Double(x[i]); sumY += Double(y[i]) }
        let muX = sumX / count
        let muY = sumY / count

        // Sample (N−1) covariance/variance, matching `ssim` above. For N == 1 the
        // single-pixel patch carries no structure → defined as 1 (identical).
        guard n > 1 else { return 1 }
        let denom = count - 1

        var varX = 0.0, varY = 0.0, cov = 0.0
        for i in 0..<n {
            let dx = Double(x[i]) - muX
            let dy = Double(y[i]) - muY
            varX += dx * dx
            varY += dy * dy
            cov += dx * dy
        }
        varX /= denom
        varY /= denom
        cov /= denom

        // C3 = C2 / 2, the standard structure-term stabilizer for L = 1.0.
        let c2 = (0.03) * (0.03)
        let c3 = c2 / 2.0
        let sigmaX = varX.squareRoot()
        let sigmaY = varY.squareRoot()
        return (cov + c3) / (sigmaX * sigmaY + c3)
    }
}
