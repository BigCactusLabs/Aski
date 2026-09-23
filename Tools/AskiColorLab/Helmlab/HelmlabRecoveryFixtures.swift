import Aski
import Foundation  // String(format:)
import simd

/// A perturbation-recovery fixture: a source that is a known small perturbation
/// of `expectedIndex` within `palette`. The correct match IS `expectedIndex`.
struct HelmlabRecoveryCase: Sendable {
    let id: String
    let paletteID: String
    let palette: [PaletteColor]
    let source: PaletteColor
    let expectedIndex: Int
}

/// Perturbation-recovery oracle (spec § ColorLab harness "Decision artifact").
/// Sources are known small perturbations of a specific palette entry; the
/// correct match is the un-perturbed entry, so recovery rate is objective
/// ground truth for the *small-ΔE* regime where Helmlab claims its edge — no
/// human labeling.
enum HelmlabRecoveryFixtures {
    private static let magnitude: Float = 0.04
    private static let floor: Float = 0.01

    /// Built across every `PaletteMatchFixtures` group (ANSI16, monochrome,
    /// synthetic sRGB, synthetic Display P3) so recovery isn't overfit to one
    /// palette. Each palette entry gets up to two **non-clamping** perturbations
    /// — one lightness-directed, one chroma-directed — so we probe both axes
    /// Helmlab's calibration targets. The un-perturbed entry is the ground
    /// truth. Perturbations that would hit a 0/1 boundary (which would distort
    /// the direction) are skipped, not clamped.
    static let all: [HelmlabRecoveryCase] = {
        var cases: [HelmlabRecoveryCase] = []
        for group in PaletteMatchFixtures.all {
            for (index, entry) in group.colors.enumerated() {
                let c = entry.components
                if let dL = lightnessDelta(c) {
                    cases.append(
                        HelmlabRecoveryCase(
                            id: "\(group.id)_recover_L_\(String(format: "%02d", index))",
                            paletteID: group.id,
                            palette: group.colors,
                            source: PaletteColor(
                                SIMD3<Float>(c.x + dL, c.y + dL, c.z + dL),
                                colorSpace: entry.colorSpace),
                            expectedIndex: index
                        ))
                }
                if let nudged = chromaPerturbed(c) {
                    cases.append(
                        HelmlabRecoveryCase(
                            id: "\(group.id)_recover_C_\(String(format: "%02d", index))",
                            paletteID: group.id,
                            palette: group.colors,
                            source: PaletteColor(nudged, colorSpace: entry.colorSpace),
                            expectedIndex: index
                        ))
                }
            }
        }
        return cases
    }()

    /// Uniform luminance shift staying in [0,1]; picks the direction with more
    /// headroom. nil if neither direction has at least `floor` room.
    private static func lightnessDelta(_ c: SIMD3<Float>) -> Float? {
        let headUp = min(1 - c.x, min(1 - c.y, 1 - c.z))
        let headDown = min(c.x, min(c.y, c.z))
        if headUp >= headDown {
            if min(magnitude, headUp) >= floor { return min(magnitude, headUp) }
            if min(magnitude, headDown) >= floor { return -min(magnitude, headDown) }
        } else {
            if min(magnitude, headDown) >= floor { return -min(magnitude, headDown) }
            if min(magnitude, headUp) >= floor { return min(magnitude, headUp) }
        }
        return nil
    }

    /// Spread channels around their mean to change chroma without clamping.
    /// nil for neutrals (no chroma axis) or if the push would exit [0,1].
    private static func chromaPerturbed(_ c: SIMD3<Float>) -> SIMD3<Float>? {
        let lo = min(c.x, min(c.y, c.z))
        let hi = max(c.x, max(c.y, c.z))
        guard hi - lo >= floor else { return nil }  // neutral: no chroma direction
        let mean = (c.x + c.y + c.z) / 3
        func push(_ v: Float) -> Float { v + (v >= mean ? magnitude : -magnitude) }
        let out = SIMD3<Float>(push(c.x), push(c.y), push(c.z))
        let outLo = min(out.x, min(out.y, out.z))
        let outHi = max(out.x, max(out.y, out.z))
        guard outLo >= 0, outHi <= 1 else { return nil }  // would clamp → skip
        return out
    }

    /// Recovery rate (0...1) for a metric: fraction of cases whose nearest
    /// palette entry equals the expected (un-perturbed) index.
    static func recoveryRate(
        resolve: (PaletteColor) -> SIMD3<Double>,
        distance: (SIMD3<Double>, SIMD3<Double>) -> Double
    ) -> Double {
        guard !all.isEmpty else { return 0 }
        var recovered = 0
        for c in all {
            let palette = c.palette.map(resolve)
            let source = resolve(c.source)
            var bestIndex = 0
            var bestDistance = distance(source, palette[0])
            for i in 1..<palette.count {
                let d = distance(source, palette[i])
                if d < bestDistance { bestDistance = d; bestIndex = i }
            }
            if bestIndex == c.expectedIndex { recovered += 1 }
        }
        return Double(recovered) / Double(all.count)
    }
}
