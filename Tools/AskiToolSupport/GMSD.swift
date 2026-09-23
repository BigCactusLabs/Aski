// MARK: - GMSD oracle (PIXELS ONLY)

/// Gradient Magnitude Similarity Deviation (Xue, Zhang, Mou & Bovik, 2013) as a
/// **distortion index** between two equal-size grayscale buffers on normalized
/// [0,1] luma.
///
/// **Sign convention (load-bearing for B5):** GMSD is a *deviation*, not a
/// similarity. `0` = identical gradient structure (perfect match); **larger =
/// more different = worse match**. It is the standard deviation of the per-pixel
/// gradient-magnitude-similarity map, so it is bounded below by 0 and grows as
/// the two gradient fields disagree. Because the matcher residual is also
/// "higher = worse", B5 correlates `residual` against GMSD *directly* and a valid
/// residual yields a POSITIVE Spearman ρ (both axes share the same orientation).
///
/// **Why gradient magnitudes.** Glyph ink vs continuous-tone source differ in
/// absolute brightness and contrast (a binary raster vs a gray patch), but a
/// good match still places *edges where the source has edges*. Gradient
/// magnitude is offset-insensitive (it differences neighbors) and contrast-robust
/// via the GMS stabilizer, so GMSD asks the fair "do the edges line up" question
/// the IQA literature recommends for structure-focused comparison.
///
/// **Independence guarantee (same rule as `StructuralSimilarity`):** both inputs
/// are grayscale pixel buffers — `x` is the rasterized chosen glyph, `y` is the
/// source-cell pixels. This function never receives, reads, or derives the shape
/// residual, the scored distance, or any 60D shape vector. GMSD is a function of
/// glyph-raster pixels and source pixels, full stop.
public enum GMSD {
    /// GMSD between `x` and `y` (both row-major `[Float]` luma in [0,1], length
    /// `width*height`). Returns `0` for degenerate/mismatched inputs.
    ///
    /// - Sign: `0` = identical gradient structure, larger = more different.
    public static func gmsd(_ x: [Float], _ y: [Float], width: Int, height: Int) -> Double {
        let n = width * height
        guard n > 0, x.count == n, y.count == n, width > 0, height > 0 else { return 0 }

        let gmX = gradientMagnitude(x, width: width, height: height)
        let gmY = gradientMagnitude(y, width: width, height: height)

        // Per-pixel Gradient Magnitude Similarity (GMS) map.
        var gms = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let a = gmX[i]
            let b = gmY[i]
            gms[i] = (2 * a * b + Self.t) / (a * a + b * b + Self.t)
        }

        // GMSD = deviation pooling: the standard deviation of the GMS map.
        let count = Double(n)
        var sum = 0.0
        for v in gms { sum += v }
        let mean = sum / count
        var varSum = 0.0
        for v in gms { let d = v - mean; varSum += d * d }
        // Population std dev (divide by N) is the canonical GMSD pooling.
        return (varSum / count).squareRoot()
    }

    // MARK: - Constant

    /// Stabilizer for the GMS map. The canonical GMSD paper uses `T = 170` on
    /// images in **[0,255]** with Prewitt gradients. Prewitt gradient magnitude
    /// scales linearly with the pixel range, so on [0,1] luma the magnitudes are
    /// `1/255` of their [0,255] counterparts. In `(2·a·b + T)/(a² + b² + T)` the
    /// gradient terms are *products of two magnitudes*, i.e. they scale as
    /// `range²`. To keep the GMS values range-invariant, `T` must scale by the
    /// same `1/255² = 1/65025`. Hence `T = 170/65025 ≈ 0.002615`, matching the
    /// brief's `170/255² ≈ 0.0026` for [0,1] gradient magnitudes.
    static let t: Double = 170.0 / (255.0 * 255.0)

    // MARK: - Internals

    /// Prewitt gradient magnitude map: `sqrt(Gx² + Gy²)` at every pixel, with
    /// **replicated (clamped) borders** (out-of-range neighbor indices clamp to
    /// the nearest valid pixel). Returns one Double per pixel, row-major.
    ///
    /// Prewitt kernels (×1, no normalization — the constant `T` is derived for
    /// this exact scaling):
    ///   Gx = [-1 0 +1; -1 0 +1; -1 0 +1]
    ///   Gy = [-1 -1 -1;  0 0  0; +1 +1 +1]
    static func gradientMagnitude(_ src: [Float], width: Int, height: Int) -> [Double] {
        var out = [Double](repeating: 0, count: width * height)
        @inline(__always) func at(_ xx: Int, _ yy: Int) -> Double {
            let cx = min(max(xx, 0), width - 1)
            let cy = min(max(yy, 0), height - 1)
            return Double(src[cy * width + cx])
        }
        for y in 0..<height {
            for x in 0..<width {
                let tl = at(x - 1, y - 1), tc = at(x, y - 1), tr = at(x + 1, y - 1)
                let ml = at(x - 1, y), mr = at(x + 1, y)
                let bl = at(x - 1, y + 1), bc = at(x, y + 1), br = at(x + 1, y + 1)
                let gx = (tr + mr + br) - (tl + ml + bl)
                let gy = (bl + bc + br) - (tl + tc + tr)
                out[y * width + x] = (gx * gx + gy * gy).squareRoot()
            }
        }
        return out
    }
}
