// MARK: - HaarPSI oracle (PIXELS ONLY)
//
// Grayscale Swift port of the HaarPSI perceptual similarity index (Reisenhofer,
// Bosse, Kutyniok & Wiethoff, 2018 — "A Haar Wavelet-Based Perceptual Similarity
// Index for Image Quality Assessment", arXiv:1607.06140), ported from the MIT
// reference NumPy implementation:
//
//   rgcda/haarpsi  (https://github.com/rgcda/haarpsi)
//   file: haarPsi.py  ·  commit 2c2793108477deb81971658a7666d5f85ba2587b
//
// The MIT License requires the copyright + permission notice be reproduced in all
// substantial portions of the software; the verbatim upstream notice follows
// (attribution alone is not sufficient under the MIT terms):
//
//   MIT License
//
//   Copyright (c) 2018 Rafael Reisenhofer
//
//   Permission is hereby granted, free of charge, to any person obtaining a copy
//   of this software and associated documentation files (the "Software"), to deal
//   in the Software without restriction, including without limitation the rights
//   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//   copies of the Software, and to permit persons to whom the Software is
//   furnished to do so, subject to the following conditions:
//
//   The above copyright notice and this permission notice shall be included in all
//   copies or substantial portions of the Software.
//
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//   SOFTWARE.

import Foundation

/// HaarPSI as a **similarity** in `[0, 1]` between two equal-size grayscale buffers
/// on normalized `[0,1]` luma (`1` = identical structure, smaller = more different).
/// Correlations use `1 − haarpsi` so the axis matches the residual ("higher = worse").
///
/// **Why this oracle (the ASTSK-31 arbiter).** ASTSK-27 left Thread B INCONCLUSIVE
/// because the two incumbent structure oracles (GMSD, SSIM-structure) disagree
/// sharply on oriented/curved fixtures and neither is validated for the
/// binary-glyph-vs-continuous-tone ~24px regime. HaarPSI is the AC's sanctioned
/// "FSIM-style or equivalent" arbiter: FSIM-lineage (local similarity + importance
/// weighting, with 3rd-scale Haar magnitudes playing phase congruency's weighting
/// role), higher SROCC than FSIM/SSIM/VSI on LIVE/TID/CSIQ, only two tunable
/// constants (`C=30`, `α=4.2`), and computable at our footprint. Its failure modes
/// differ from both incumbents (multi-scale H+V channels vs GMSD's single-scale
/// Prewitt magnitude; weighted-mean pooling vs GMSD's std-dev pooling), which is
/// what lets it break the diagonal/radial tie.
///
/// **Independence guarantee (same rule as `GMSD`/`StructuralSimilarity`):** both
/// inputs are grayscale pixel buffers — `x` is the rasterized chosen glyph, `y` is
/// the source-cell pixels. This function never receives, reads, or derives the
/// shape residual, the scored distance, or any 60D shape vector.
///
/// **Scaling.** Luma is scaled to `[0,255]` internally so `C`/`α` and the reference
/// preprocessing match the upstream defaults verbatim (the same treatment `GMSD`
/// gives its `T`). We keep the natural-image defaults (no re-tuning — that is the
/// unvalidated-knob trap ASTSK-27 escaped) and rely on test-vector parity with the
/// reference for trust.
///
/// **Honest-footprint caveat (carried into the research note as an instrument
/// limitation).** After the reference 2×2-mean + dyadic-subsample preprocessing, a
/// 24×24 input becomes a 12×12 field, so HaarPSI runs at the small end of its
/// validated regime and its scale-3 weight map is coarse there. We keep the
/// reference defaults anyway and let reference-vector parity carry the trust.
public enum HaarPSI {
    /// Experimentally-determined reference constants (kept verbatim — never re-tuned).
    static let c: Double = 30.0
    static let alpha: Double = 4.2
    static let numberOfScales = 3

    /// HaarPSI similarity in `[0,1]`. `1` = identical structure, smaller = more
    /// different. Inputs are row-major `[Float]` luma in `[0,1]`, length `width*height`.
    ///
    /// **Pre-registered flat-vs-flat divergence.** When BOTH inputs are constant
    /// (the battery hits this via a space-glyph raster vs a flat source block), the
    /// reference's scale-3 weights vanish and it returns `0/0 = NaN`. A NaN would
    /// silently shrink the correlation population for ALL oracles (the harness keeps
    /// a cell only when every oracle is finite), so we define flat-vs-flat as
    /// `haarpsi = 1.0` — the same "two structureless patches have identical (absent)
    /// structure" semantics `StructuralSimilarity.structure` encodes. Documented
    /// here at the definition site and pinned by a unit test.
    public static func haarPSI(_ x: [Float], _ y: [Float], width: Int, height: Int) -> Double {
        let n = width * height
        guard n > 0, x.count == n, y.count == n, width > 0, height > 0 else { return 1 }

        // Flat-vs-flat: no comparable structure in either input → reference 0/0 NaN.
        // Defined as 1.0 (documented divergence; mirrors StructuralSimilarity.structure).
        if isConstant(x) && isConstant(y) { return 1 }

        // Scale to [0,255] (Double) so C/α match the reference verbatim.
        var ref = [Double](repeating: 0, count: n)
        var dis = [Double](repeating: 0, count: n)
        for i in 0..<n {
            ref[i] = Double(x[i]) * 255.0
            dis[i] = Double(y[i]) * 255.0
        }

        // Preprocessing: 2×2-mean 'same' conv + dyadic subsample (24×24 → 12×12).
        let (sref, w2, h2) = subsample(ref, width: width, height: height)
        let (sdis, _, _) = subsample(dis, width: width, height: height)

        // 3-scale Haar decomposition: 6 channels each, [0,1,2]=vertical scales 1..3,
        // [3,4,5]=horizontal scales 1..3.
        let coefRef = haarDecompose(sref, width: w2, height: h2)
        let coefDis = haarDecompose(sdis, width: w2, height: h2)

        let m = w2 * h2
        var sumWeighted = 0.0
        var sumWeights = 0.0
        for orientation in 0..<2 {
            let base = orientation * numberOfScales
            let scale3 = base + 2  // coarsest scale → importance weight
            let s1 = base
            let s2 = base + 1
            let wRef = coefRef[scale3]
            let wDis = coefDis[scale3]
            let a1 = coefRef[s1], b1 = coefDis[s1]
            let a2 = coefRef[s2], b2 = coefDis[s2]
            for p in 0..<m {
                let weight = max(abs(wRef[p]), abs(wDis[p]))
                let r1 = abs(a1[p]), d1 = abs(b1[p])
                let r2 = abs(a2[p]), d2 = abs(b2[p])
                let sim1 = (2 * r1 * d1 + c) / (r1 * r1 + d1 * d1 + c)
                let sim2 = (2 * r2 * d2 + c) / (r2 * r2 + d2 * d2 + c)
                let ls = (sim1 + sim2) / 2.0
                sumWeighted += sigmoid(ls) * weight
                sumWeights += weight
            }
        }

        // No structural weight anywhere → treat as flat-vs-flat (defensive; the
        // isConstant guard above already covers the literal case).
        guard sumWeights > 0 else { return 1 }
        let ratio = sumWeighted / sumWeights
        let result = logit(ratio) * logit(ratio)
        return result.isFinite ? result : 1
    }

    // MARK: - Internals

    /// True when every element equals the first (zero-variance / structureless).
    private static func isConstant(_ a: [Float]) -> Bool {
        guard let first = a.first else { return true }
        for v in a where v != first { return false }
        return true
    }

    /// Zero-padded 'same' 2D convolution matching the reference's MATLAB-parity
    /// `convolve2d` (which rotates inputs by 180°, runs `scipy.signal.convolve2d`
    /// `same`, and rotates back — net effect: a true convolution, zero-padded, with
    /// the MATLAB `conv2('same')` crop whose offset is `⌊k/2⌋`, NOT scipy's bare
    /// `(k−1)//2`). The crop offset is the load-bearing detail the even-sized Haar
    /// filters (2/4/8) are sensitive to; the 8×8 reference vector pins it.
    ///
    ///   out[a,b] = Σ_{p,q} K[p,q] · A(a + ⌊kh/2⌋ − p, b + ⌊kw/2⌋ − q)
    ///
    /// with `A(·) = 0` outside `[0,height) × [0,width)` (zero padding).
    static func convolveSame(
        _ a: [Double], width: Int, height: Int,
        kernel: [Double], kw: Int, kh: Int
    ) -> [Double] {
        var out = [Double](repeating: 0, count: width * height)
        let offR = kh / 2
        let offC = kw / 2
        for row in 0..<height {
            for col in 0..<width {
                var acc = 0.0
                for p in 0..<kh {
                    let sr = row + offR - p
                    if sr < 0 || sr >= height { continue }
                    let rowBase = sr * width
                    let kBase = p * kw
                    for q in 0..<kw {
                        let sc = col + offC - q
                        if sc < 0 || sc >= width { continue }
                        acc += kernel[kBase + q] * a[rowBase + sc]
                    }
                }
                out[row * width + col] = acc
            }
        }
        return out
    }

    /// 2×2 mean-filter 'same' conv followed by dyadic subsampling (`[::2, ::2]`):
    /// rows/cols `0, 2, 4, …`, so an `H×W` field becomes `⌈H/2⌉×⌈W/2⌉`.
    static func subsample(
        _ a: [Double], width: Int, height: Int
    ) -> (data: [Double], width: Int, height: Int) {
        let mean: [Double] = [0.25, 0.25, 0.25, 0.25]
        let conv = convolveSame(a, width: width, height: height, kernel: mean, kw: 2, kh: 2)
        let w2 = (width + 1) / 2
        let h2 = (height + 1) / 2
        var out = [Double](repeating: 0, count: w2 * h2)
        var dstRow = 0
        var srcRow = 0
        while srcRow < height {
            var dstCol = 0
            var srcCol = 0
            while srcCol < width {
                out[dstRow * w2 + dstCol] = conv[srcRow * width + srcCol]
                dstCol += 1
                srcCol += 2
            }
            dstRow += 1
            srcRow += 2
        }
        return (out, w2, h2)
    }

    /// 3-scale Haar decomposition. Returns 6 channels: `[0,1,2]` vertical scales
    /// 1..3, `[3,4,5]` horizontal scales 1..3. The vertical filter at scale `s` is
    /// a `2^s × 2^s` block, top half `−2^{−s}` / bottom half `+2^{−s}` (zero-sum);
    /// the horizontal filter is its transpose. Convolution flips the kernel, so the
    /// filters are passed as-defined (matching the reference, which never pre-flips).
    static func haarDecompose(_ a: [Double], width: Int, height: Int) -> [[Double]] {
        var channels = [[Double]](repeating: [], count: 2 * numberOfScales)
        for scale in 1...numberOfScales {
            let s = 1 << scale  // 2^scale
            let val = pow(2.0, Double(-scale))  // 2^{-scale}
            let half = s / 2
            var vertical = [Double](repeating: 0, count: s * s)
            var horizontal = [Double](repeating: 0, count: s * s)
            for p in 0..<s {
                let rowSign = (p < half) ? -val : val
                for q in 0..<s {
                    vertical[p * s + q] = rowSign
                    horizontal[p * s + q] = (q < half) ? -val : val
                }
            }
            channels[scale - 1] = convolveSame(
                a, width: width, height: height, kernel: vertical, kw: s, kh: s)
            channels[scale - 1 + numberOfScales] = convolveSame(
                a, width: width, height: height, kernel: horizontal, kw: s, kh: s)
        }
        return channels
    }

    /// Logistic function with steepness `α` (reference `sigmoid`).
    private static func sigmoid(_ v: Double) -> Double {
        1.0 / (1.0 + Foundation.exp(-alpha * v))
    }

    /// Inverse logistic (reference `logit`); exact inverse of `sigmoid`, so an
    /// identical-input image scores exactly `1.0`.
    private static func logit(_ v: Double) -> Double {
        Foundation.log(v / (1.0 - v)) / alpha
    }
}
