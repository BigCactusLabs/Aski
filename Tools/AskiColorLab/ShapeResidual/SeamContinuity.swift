import Foundation

// MARK: - M1 oracle: source-conditioned cross-seam stroke continuity (ASTSK-43)

/// Source-conditioned cross-seam stroke-orientation continuity — the **M1**
/// instrument for the ASTSK-43 inter-cell-smoothing gate.
///
/// Measures, over a *rendered* grid at native pixel resolution, whether the
/// strokes the **source** draws across cell seams survive as continuously-oriented
/// edges in the render. Higher = source strokes stay continuous across the seam.
///
/// **Why source-conditioned (frozen 2026-06-24, `docs/Research/Discoveries.md`).**
/// The no-reference blockiness lineage (GBIM — Wu & Yuen 1997; Wang–Sheikh–Bovik,
/// ICIP 2002) is *self-referential* — it penalizes any seam-aligned edge with no
/// reference — and is documented to be gamed by low-pass/over-smoothing ("to
/// reduce blockiness, images are low-pass filtered → more blur"), which is why
/// PSNR-B / DBIQ had to add a blur term. A self-referential M1 would therefore
/// score this gate's *naturals-washout KILL case as perfect* — backwards. Weighting
/// the per-seam coherence by **source** edge strength makes washout score ≈0
/// (vanished strokes = zero continuity), which is the anti-gaming property the gate
/// needs.
///
/// **How continuity is quantified.** Structure-tensor coherence
/// `C = (λ₁−λ₂)/(λ₁+λ₂) ∈ [0,1]` over a window straddling the seam on the rendered
/// field — 1 when a single dominant orientation persists across the seam (a
/// continuous stroke), 0 when the window's gradients are isotropic/mixed (a stroke
/// that breaks or end-caps at the boundary). Built from `∇I∇Iᵀ`, the tensor is
/// invariant to gradient sign, so it folds `[0,π)` orientation for free (no manual
/// `cos²Δθ` wrap, no Di Zenzo direction-indetermination bug — `cos²Δθ` is its
/// degenerate two-pixel reduction). Complementary to M2 = GMSD (gradient-*magnitude*
/// deviation, global), so the dual-oracle independence holds.
///
/// Lab-only (`Sources/Aski` untouched) until the ASTSK-43 gate returns PASS.
enum SeamContinuity {
    /// `M1 = Σ(w·C_rendered) / Σ(w)` over every interior cell seam, where `C` is
    /// the rendered structure-tensor coherence in a `2·windowRadius`-square window
    /// straddling the seam and `w` is the source oriented-edge energy (λ₁) in the
    /// same window.
    ///
    /// - Both fields are row-major `[Float]` luma in `[0,1]`, length `width*height`.
    /// - Returns `.nan` for degenerate input (mismatched/empty, no interior seam)
    ///   or when no seam carries source-edge weight (the source-conditioned mean is
    ///   undefined — there is genuinely nothing to measure). A washed-out render
    ///   over an *edged* source returns `0`, not `.nan`.
    static func crossSeamCoherence(
        rendered: [Float], source: [Float],
        width: Int, height: Int,
        cellWidth: Int, cellHeight: Int,
        windowRadius: Int = 2
    ) -> Double {
        let n = width * height
        guard n > 0, rendered.count == n, source.count == n,
            width > 0, height > 0, cellWidth > 0, cellHeight > 0, windowRadius >= 1
        else { return .nan }

        let (rgx, rgy) = sobel(rendered, width: width, height: height)
        let (sgx, sgy) = sobel(source, width: width, height: height)

        var num = 0.0  // Σ w·C
        var den = 0.0  // Σ w

        // Interior vertical seams: boundary between columns xs-1 and xs.
        var xs = cellWidth
        while xs < width {
            for y in 0..<height {
                let (c, w) = seamWindow(
                    rgx, rgy, sgx, sgy, width: width, height: height,
                    cx: xs, cy: y, radius: windowRadius)
                num += w * c
                den += w
            }
            xs += cellWidth
        }
        // Interior horizontal seams: boundary between rows ys-1 and ys.
        var ys = cellHeight
        while ys < height {
            for x in 0..<width {
                let (c, w) = seamWindow(
                    rgx, rgy, sgx, sgy, width: width, height: height,
                    cx: x, cy: ys, radius: windowRadius)
                num += w * c
                den += w
            }
            ys += cellHeight
        }

        guard den > 0 else { return .nan }
        return num / den
    }

    // MARK: - Internals

    /// Structure-tensor coherence of the rendered field and source oriented-edge
    /// energy over a `2·radius`-square window straddling the boundary corner
    /// `(cx, cy)`. Returns `(coherence ∈ [0,1], weight ≥ 0)`.
    private static func seamWindow(
        _ rgx: [Double], _ rgy: [Double], _ sgx: [Double], _ sgy: [Double],
        width: Int, height: Int, cx: Int, cy: Int, radius: Int
    ) -> (coherence: Double, weight: Double) {
        let x0 = max(0, cx - radius), x1 = min(width - 1, cx + radius - 1)
        let y0 = max(0, cy - radius), y1 = min(height - 1, cy + radius - 1)
        var r11 = 0.0, r22 = 0.0, r12 = 0.0
        var s11 = 0.0, s22 = 0.0, s12 = 0.0
        for yy in y0...y1 {
            let row = yy * width
            for xx in x0...x1 {
                let i = row + xx
                let rx = rgx[i], ry = rgy[i]
                r11 += rx * rx
                r22 += ry * ry
                r12 += rx * ry
                let sx = sgx[i], sy = sgy[i]
                s11 += sx * sx
                s22 += sy * sy
                s12 += sx * sy
            }
        }
        let eps = 1e-9
        // C = (λ₁−λ₂)/(λ₁+λ₂); λ₁−λ₂ = √((trace-diff)²+4·offdiag²), λ₁+λ₂ = trace.
        let rDelta = ((r11 - r22) * (r11 - r22) + 4 * r12 * r12).squareRoot()
        let coherence = min(1.0, rDelta / (r11 + r22 + eps))
        // Source edge strength = largest source eigenvalue λ₁ (oriented edge energy).
        let sDelta = ((s11 - s22) * (s11 - s22) + 4 * s12 * s12).squareRoot()
        let weight = 0.5 * (s11 + s22 + sDelta)
        return (coherence, weight)
    }

    /// Sobel gradient components `(Gx, Gy)`, row-major `[Double]`, with replicated
    /// (clamped) borders — matches the lab's GMSD gradient convention.
    private static func sobel(_ src: [Float], width: Int, height: Int) -> (gx: [Double], gy: [Double]) {
        var gx = [Double](repeating: 0, count: width * height)
        var gy = [Double](repeating: 0, count: width * height)
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
                gx[y * width + x] = (tr + 2 * mr + br) - (tl + 2 * ml + bl)
                gy[y * width + x] = (bl + 2 * bc + br) - (tl + 2 * tc + tr)
            }
        }
        return (gx, gy)
    }
}
