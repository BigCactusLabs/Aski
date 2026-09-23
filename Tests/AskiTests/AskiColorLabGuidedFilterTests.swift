import Foundation
import Testing
@testable import AskiColorLab

/// ASTSK-43 Fork B — self-guided guided filter (He–Sun–Tang) as the candidate
/// cross-cell coupling pre-pass. These tests pin the load-bearing properties the
/// frontier-search bolster (2026-06-24, `docs/Research/Discoveries.md`) selected
/// the guided filter *for*, versus the rejected alternatives:
///
/// - **identity on a flat field** (var → 0 ⇒ a → 0 ⇒ q = local mean = input);
/// - **no gradient reversal** — a linear ramp stays monotonic (bilateral's
///   inherent flaw the guided filter is proven to avoid);
/// - **edge preservation** — a sharp step survives where a 3×3 box blur would
///   smear the 1.0 jump down to ≈0.33;
/// - **noise smoothing** once ε exceeds the local variance (the actual point of
///   the pre-pass).
@Suite struct AskiColorLabGuidedFilterTests {

    @Test func selfGuidedIsIdentityOnFlatField() {
        let w = 5, h = 4
        let src = [Float](repeating: 0.5, count: w * h)
        let out = GuidedFilter.selfGuided(src, width: w, height: h, radius: 1, epsilon: 0.01)
        #expect(out.count == src.count)
        for v in out { #expect(abs(v - 0.5) < 1e-5) }
    }

    @Test func selfGuidedKeepsLinearRampMonotonic() {
        // Horizontal linear ramp 0…1 across 8 columns, 4 rows.
        let w = 8, h = 4
        var src = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { src[y * w + x] = Float(x) / Float(w - 1) } }
        let out = GuidedFilter.selfGuided(src, width: w, height: h, radius: 1, epsilon: 1e-4)
        // No gradient reversal: each row stays non-decreasing left→right.
        for y in 0..<h {
            for x in 0..<(w - 1) {
                #expect(
                    out[y * w + (x + 1)] >= out[y * w + x] - 1e-4,
                    "ramp reversed at row \(y) col \(x)")
            }
        }
    }

    @Test func selfGuidedPreservesSharpStepEdge() {
        // Vertical step: left 4 cols = 0, right 4 cols = 1; 4 rows.
        let w = 8, h = 4
        var src = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let v: Float = x < 4 ? 0 : 1
                src[y * w + x] = v
            }
        }
        let out = GuidedFilter.selfGuided(src, width: w, height: h, radius: 1, epsilon: 1e-5)
        // Deep flat regions untouched → full range survives.
        let lo = out.min()!, hi = out.max()!
        #expect(hi - lo >= 0.9, "range collapsed: \(lo)…\(hi)")
        // Edge stays sharp: some adjacent-column jump remains large.
        var maxJump: Float = 0
        for y in 0..<h {
            for x in 0..<(w - 1) {
                maxJump = max(maxJump, abs(out[y * w + (x + 1)] - out[y * w + x]))
            }
        }
        #expect(maxJump >= 0.8, "step smeared; max adjacent jump only \(maxJump)")
    }

    @Test func selfGuidedSmoothsSubThresholdNoise() {
        // Flat 0.5 field with ±0.1 checkerboard noise (variance ≈ 0.01).
        let w = 6, h = 6
        var src = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w { src[y * w + x] = 0.5 + (((x + y) % 2 == 0) ? 0.1 : -0.1) }
        }
        // ε ≫ local variance → strong pull toward the local mean.
        let out = GuidedFilter.selfGuided(src, width: w, height: h, radius: 1, epsilon: 0.05)
        func variance(_ a: [Float]) -> Float {
            let m = a.reduce(0, +) / Float(a.count)
            return a.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Float(a.count)
        }
        #expect(variance(out) < variance(src), "filter did not reduce noise variance")
    }

    @Test func selfGuidedReturnsEmptyForMismatchedInput() {
        #expect(GuidedFilter.selfGuided([0, 1, 2], width: 2, height: 2, radius: 1, epsilon: 0.01).isEmpty)
        #expect(GuidedFilter.selfGuided([], width: 0, height: 0, radius: 1, epsilon: 0.01).isEmpty)
    }
}
