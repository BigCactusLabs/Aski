import Foundation
import Testing
@testable import AskiColorLab

/// ASTSK-43 Fork B — M1 instrument: SOURCE-CONDITIONED cross-seam stroke-orientation
/// continuity. These tests pin the load-bearing properties the frontier-search
/// bolster (2026-06-24, `docs/Research/Discoveries.md` sub-entry) froze the metric
/// *for*, before any measurement on the real battery:
///
/// - **continuity ordering** — a stroke rendered continuously across a cell seam
///   scores higher than the same stroke broken at the seam (the whole point);
/// - **anti-washout** — a washed-out (uniform) render scores ≈0 *where the source
///   has edges*, because source-conditioning makes vanished strokes count as zero
///   continuity (a self-referential blockiness score would call washout perfect —
///   the documented gaming failure this gate must KILL on);
/// - **undefined when nothing to measure** — a flat source (no seam-crossing edge)
///   returns NaN, not a fake 0 or 1;
/// - **orientation folding** — a 45° diagonal stroke is handled (structure tensor
///   built from ∇I∇Iᵀ folds [0,π) for free), covering Aski's known off-axis weak spot.
///
/// All fields are row-major `[Float]` luma in [0,1], the lab's standard layout.
@Suite struct AskiColorLabSeamContinuityTests {

    // MARK: - Synthetic field builders

    /// Full-width horizontal band (rows `r0..<r1` = 1, else 0). Crosses every
    /// vertical seam continuously.
    private func horizontalBand(width: Int, height: Int, r0: Int, r1: Int) -> [Float] {
        var f = [Float](repeating: 0, count: width * height)
        for y in r0..<r1 { for x in 0..<width { f[y * width + x] = 1 } }
        return f
    }

    /// Same band but only for columns `< xBreak` (blank to the right) — the stroke
    /// breaks at the vertical seam `xBreak`.
    private func horizontalBandBrokenAt(width: Int, height: Int, r0: Int, r1: Int, xBreak: Int) -> [Float] {
        var f = [Float](repeating: 0, count: width * height)
        for y in r0..<r1 { for x in 0..<xBreak { f[y * width + x] = 1 } }
        return f
    }

    /// 45° diagonal stroke (|x − y| ≤ halfWidth). Crosses the central seams.
    private func diagonalStroke(width: Int, height: Int, halfWidth: Int) -> [Float] {
        var f = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width where abs(x - y) <= halfWidth { f[y * width + x] = 1 }
        }
        return f
    }

    // MARK: - Tests

    @Test func continuousStrokeScoresHigherThanBrokenStroke() {
        let w = 16, h = 16, cw = 8, ch = 8
        let source = horizontalBand(width: w, height: h, r0: 6, r1: 10)
        let continuous = source
        let broken = horizontalBandBrokenAt(width: w, height: h, r0: 6, r1: 10, xBreak: cw)

        let m1Continuous = SeamContinuity.crossSeamCoherence(
            rendered: continuous, source: source, width: w, height: h, cellWidth: cw, cellHeight: ch)
        let m1Broken = SeamContinuity.crossSeamCoherence(
            rendered: broken, source: source, width: w, height: h, cellWidth: cw, cellHeight: ch)

        #expect(m1Continuous.isFinite && m1Broken.isFinite)
        #expect(m1Continuous > m1Broken, "continuous \(m1Continuous) should beat broken \(m1Broken)")
    }

    @Test func perfectContinuityApproachesUnity() {
        let w = 16, h = 16
        let source = horizontalBand(width: w, height: h, r0: 6, r1: 10)
        let m1 = SeamContinuity.crossSeamCoherence(
            rendered: source, source: source, width: w, height: h, cellWidth: 8, cellHeight: 8)
        // A perfectly continuous, purely horizontal edge has a single dominant
        // orientation across the seam → coherence near 1.
        #expect(m1 > 0.7, "perfect continuity scored only \(m1)")
        #expect(m1 <= 1.0 + 1e-6)
    }

    @Test func washedOutRenderScoresNearZeroWhereSourceHasEdges() {
        let w = 16, h = 16
        let source = horizontalBand(width: w, height: h, r0: 6, r1: 10)
        // Over-smoothed/washed-out render: uniform field, all strokes gone.
        let washout = [Float](repeating: 0.5, count: w * h)
        let m1 = SeamContinuity.crossSeamCoherence(
            rendered: washout, source: source, width: w, height: h, cellWidth: 8, cellHeight: 8)
        // Source still has strong seam-crossing edges (weight > 0), but the render
        // has zero oriented structure there → continuity is zero, NOT "perfect".
        #expect(m1.isFinite)
        #expect(m1 < 1e-6, "washout must score ≈0, scored \(m1)")
    }

    @Test func returnsNaNWhenSourceHasNoSeamCrossingEdges() {
        let w = 16, h = 16
        let flatSource = [Float](repeating: 0.3, count: w * h)
        let render = horizontalBand(width: w, height: h, r0: 6, r1: 10)
        let m1 = SeamContinuity.crossSeamCoherence(
            rendered: render, source: flatSource, width: w, height: h, cellWidth: 8, cellHeight: 8)
        // No source edge anywhere → no weight → the source-conditioned mean is undefined.
        #expect(m1.isNaN, "flat source should be undefined (NaN), got \(m1)")
    }

    @Test func continuousDiagonalScoresHigherThanBrokenDiagonal() {
        let w = 16, h = 16, cw = 8, ch = 8
        let source = diagonalStroke(width: w, height: h, halfWidth: 1)
        let continuous = source
        // Break the diagonal: drop everything in the right half of the grid.
        var broken = source
        for y in 0..<h { for x in cw..<w { broken[y * w + x] = 0 } }

        let m1Continuous = SeamContinuity.crossSeamCoherence(
            rendered: continuous, source: source, width: w, height: h, cellWidth: cw, cellHeight: ch)
        let m1Broken = SeamContinuity.crossSeamCoherence(
            rendered: broken, source: source, width: w, height: h, cellWidth: cw, cellHeight: ch)

        #expect(m1Continuous.isFinite && m1Broken.isFinite)
        #expect(m1Continuous > m1Broken, "continuous diagonal \(m1Continuous) should beat broken \(m1Broken)")
    }

    @Test func returnsNaNForDegenerateInput() {
        #expect(
            SeamContinuity.crossSeamCoherence(
                rendered: [0, 1, 2], source: [0, 1], width: 2, height: 2,
                cellWidth: 1, cellHeight: 1
            ).isNaN)
        #expect(
            SeamContinuity.crossSeamCoherence(
                rendered: [], source: [], width: 0, height: 0,
                cellWidth: 1, cellHeight: 1
            ).isNaN)
        // Cell size larger than the image → no interior seam → undefined.
        let f = [Float](repeating: 1, count: 16)
        #expect(
            SeamContinuity.crossSeamCoherence(
                rendered: f, source: f, width: 4, height: 4,
                cellWidth: 8, cellHeight: 8
            ).isNaN)
    }
}
