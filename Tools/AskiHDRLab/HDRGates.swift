import Foundation

/// One measured `(fixture, k)` sample.
struct HDRMeasurement: Sendable {
    let fixtureID: String
    let gamut: String
    let expectation: String  // "blooms" | "flat"
    let k: Float
    let threshold: Float
    let maxHeadroom: Float
    let contentHeadroom: Float
    let hdrMaxChannel: Float
    let g1MeanDiff: Float
    let g2MeanDiff: Float
    // G4 verifies the *renderer's* headroom-clamp + finite contract held on real
    // output — not an independent oracle. The renderer pre-clamps to `maxHeadroom`
    // and pre-guards NaN/Inf, so on faithful output this is always true; its value
    // is as a clamp/finite-*regression* guard. The detector (`HDRArtifacts.floatStats`)
    // is proven to actually fire by `HDRArtifactsTests` on crafted bad buffers.
    let floatClean: Bool  // G4: no NaN/Inf and no value above the ceiling
    let heicBytes: Int
}

/// The decisive verdict gates, **frozen before the run**. A failure KILLs
/// *default-on* promotion; the SPI render path ships opt-in regardless (matching
/// every prior Aski research thread). `check` maps `!passed` to a nonzero exit.
enum HDRGates {
    struct Thresholds: Sendable {
        /// G1: max tolerated mean per-channel diff (0...1) between the embedded
        /// SDR base (what an SDR display shows) and the SDR render, across all k.
        /// The measured HEVC-lossy re-encode floor is ≈0.016; 0.025 is the
        /// perceptual-near bound with codec-variance margin. A broken gain map
        /// blows past it.
        var g1Tolerance: Float = 0.025
        /// G2: max tolerated mean diff for the tone-map round-trip **at k=0 only**
        /// (zero emission). At k=0 the HDR variant equals the SDR, so the full
        /// encode → `expandToHDR` → `CIToneMapHeadroom(target:1)` pipeline must be
        /// identity within ε — a genuine plumbing gate. At k>0 the tone operator
        /// legitimately compresses highlights (that is Apple's display tone-map,
        /// not an Aski-fidelity claim), so it is recorded as data, not gated.
        var g2Tolerance: Float = 0.025
        /// G3: a blooming fixture's peak content headroom must exceed this.
        var bloomHeadroomMin: Float = 1.3
        /// G3: a flat (dark) fixture must never exceed this at any k.
        var flatHeadroomMax: Float = 1.1
        /// G3: the k=0 control must land at ≈1 for every fixture.
        var controlHeadroomMax: Float = 1.05
        /// G3: allowed dip when checking monotonicity-in-k (measurement noise).
        var monotonicSlack: Float = 0.03

        static let frozen = Thresholds()
    }

    struct Verdict: Sendable {
        let g1Pass: Bool
        let g2Pass: Bool
        let g3Pass: Bool
        let g4Pass: Bool
        let detail: String
        var passed: Bool { g1Pass && g2Pass && g3Pass && g4Pass }
    }

    static func evaluate(_ rows: [HDRMeasurement], thresholds: Thresholds = .frozen) -> Verdict {
        guard !rows.isEmpty else {
            return Verdict(
                g1Pass: false, g2Pass: false, g3Pass: false, g4Pass: false,
                detail: "no measurements gathered")
        }

        // G1 (all k) and G4 are per-row aggregates; G2 gates only the k=0
        // zero-emission identity (see Thresholds.g2Tolerance).
        let g1Worst = rows.map(\.g1MeanDiff).max() ?? .infinity
        let g2ZeroEmission = rows.filter { $0.k == 0 }.map(\.g2MeanDiff).max() ?? .infinity
        let g1Pass = g1Worst <= thresholds.g1Tolerance
        let g2Pass = g2ZeroEmission <= thresholds.g2Tolerance
        let g4Failures = rows.filter { !$0.floatClean }
        let g4Pass = g4Failures.isEmpty

        // G3 is per-fixture: control ≈1, blooms peak > min and monotonic, flat ≤ max.
        var g3Failures: [String] = []
        let byFixture = Dictionary(grouping: rows, by: \.fixtureID)
        for (fixture, fixtureRows) in byFixture.sorted(by: { $0.key < $1.key }) {
            let sorted = fixtureRows.sorted { $0.k < $1.k }
            let expectation = sorted.first?.expectation ?? "blooms"

            // The k=0 zero-emission control is mandatory: it is the per-fixture
            // proof that the SDR baseline lands at ≈1. A missing control must KILL
            // loudly — silently skipping it would let a malformed run pass G3.
            if let control = sorted.first(where: { $0.k == 0 }) {
                if control.contentHeadroom > thresholds.controlHeadroomMax {
                    g3Failures.append("\(fixture): k=0 control headroom \(fmt(control.contentHeadroom)) > \(fmt(thresholds.controlHeadroomMax))")
                }
            } else {
                g3Failures.append("\(fixture): missing k=0 control row (cannot verify the SDR baseline lands at ≈1)")
            }

            if expectation == "flat" {
                if let worst = sorted.map(\.contentHeadroom).max(), worst > thresholds.flatHeadroomMax {
                    g3Failures.append("\(fixture): flat fixture bloomed to \(fmt(worst)) > \(fmt(thresholds.flatHeadroomMax))")
                }
            } else {
                if let peak = sorted.map(\.contentHeadroom).max(), peak <= thresholds.bloomHeadroomMin {
                    g3Failures.append("\(fixture): peak headroom \(fmt(peak)) did not exceed \(fmt(thresholds.bloomHeadroomMin))")
                }
                var prev = -Float.infinity
                for row in sorted {
                    if row.contentHeadroom < prev - thresholds.monotonicSlack {
                        g3Failures.append("\(fixture): headroom not monotonic in k (\(fmt(prev)) → \(fmt(row.contentHeadroom)) at k=\(fmt(row.k)))")
                        break
                    }
                    prev = max(prev, row.contentHeadroom)
                }
            }
        }
        let g3Pass = g3Failures.isEmpty

        var lines: [String] = []
        lines.append("G1 fallback fidelity:  \(g1Pass ? "PASS" : "KILL") (worst SDR-base mean diff \(fmt(g1Worst)) vs tol \(fmt(thresholds.g1Tolerance)))")
        lines.append("G2 round-trip (k=0):   \(g2Pass ? "PASS" : "KILL") (zero-emission tone-map identity diff \(fmt(g2ZeroEmission)) vs tol \(fmt(thresholds.g2Tolerance)))")
        lines.append("G3 headroom:           \(g3Pass ? "PASS" : "KILL")\(g3Failures.isEmpty ? "" : " — " + g3Failures.joined(separator: "; "))")
        lines.append("G4 float integrity:    \(g4Pass ? "PASS" : "KILL")\(g4Failures.isEmpty ? "" : " — \(g4Failures.count) row(s) with NaN/Inf/over-ceiling")")
        let overall = g1Pass && g2Pass && g3Pass && g4Pass
        lines.append("verdict: \(overall ? "PASS" : "KILL")")

        return Verdict(
            g1Pass: g1Pass, g2Pass: g2Pass, g3Pass: g3Pass, g4Pass: g4Pass,
            detail: lines.joined(separator: "\n"))
    }

    private static func fmt(_ value: Float) -> String { String(format: "%.4f", value) }
}
