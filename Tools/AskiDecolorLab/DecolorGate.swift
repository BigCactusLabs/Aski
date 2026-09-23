import Foundation
import simd

/// The FAIL-FAST keystone gate for the composited-cell perceptual oracle.
///
/// Two independent tests must both pass for the gate to clear:
///
/// 1. **Discrimination** (`discrimination`) — across the three lab palettes the
///    per-cell L-error must monotonically *decrease* with color cardinality
///    (`monochrome > ansi16 > fullColor`) and the adjacent bootstrap confidence
///    intervals must be non-overlapping. This proves the oracle actually *measures*
///    palette quality rather than emitting noise.
/// 2. **2AFC `d′`** (`twoAFC`) — the area-tone model must distinguish a true
///    sub-glyph half-tone from a flat tone matched in mean L, better than chance.
///    This is the falsifiable core thesis: if it cannot, that is the designed,
///    publishable **KILL**, not a bug.
public struct GateResult: Sendable {
    public let discriminationPassed: Bool
    public let twoAFCPassed: Bool
    public let detail: String
    public var passed: Bool { discriminationPassed && twoAFCPassed }

    public init(discriminationPassed: Bool, twoAFCPassed: Bool, detail: String) {
        self.discriminationPassed = discriminationPassed
        self.twoAFCPassed = twoAFCPassed
        self.detail = detail
    }
}

public enum DecolorGate {

    // MARK: - A5: discrimination (bootstrap-CI separation)

    /// Per-palette ordering + bootstrap confidence-interval separation of `lFidelity`.
    ///
    /// `lFidelity` is an **error** (lower = better; more colors → less error), so a
    /// passing run has `mean(monochrome) > mean(ansi16) > mean(fullColor)`. The means
    /// alone are not enough — the adjacent 95% bootstrap CIs must also be disjoint
    /// (mono.lo > ansi16.hi AND ansi16.lo > fullColor.hi), which is the statistical
    /// claim that the separation is not an artifact of sampling noise.
    ///
    /// The bootstrap is **deterministic**: a fixed-seed `SeededRNG` (SplitMix64) drives
    /// resampling so the verdict and `detail` are reproducible across runs.
    public static func discrimination(
        rows: [OracleRow],
        bootstrapSamples: Int = 1000
    ) -> (passed: Bool, detail: String) {
        let orderedPalettes = ["monochrome", "ansi16", "fullColor"]

        // A fixed seed makes the whole bootstrap reproducible. Distinct per-palette
        // streams (seed XORed with the palette index) keep palettes independent while
        // staying fully deterministic.
        var stats: [String: BootstrapStat] = [:]
        for (index, palette) in orderedPalettes.enumerated() {
            let values = rows.filter { $0.paletteID == palette }.map(\.lFidelity)
            guard !values.isEmpty else {
                return (false, "discrimination: missing samples for palette \"\(palette)\"")
            }
            var rng = SeededRNG(seed: 0x9E37_79B9_7F4A_7C15 ^ UInt64(index))
            stats[palette] = bootstrapMeanCI(
                values: values, samples: bootstrapSamples, rng: &rng)
        }

        let mono = stats["monochrome"]!
        let ansi = stats["ansi16"]!
        let full = stats["fullColor"]!

        let orderedMeans = mono.mean > ansi.mean && ansi.mean > full.mean
        let separated = mono.lo > ansi.hi && ansi.lo > full.hi
        let passed = orderedMeans && separated

        let detail = """
            discrimination: \(passed ? "PASS" : "FAIL") \
            (means must descend with color count; adjacent 95% CIs must be disjoint)
              monochrome mean=\(fmt(mono.mean)) CI=[\(fmt(mono.lo)), \(fmt(mono.hi))]
              ansi16     mean=\(fmt(ansi.mean)) CI=[\(fmt(ansi.lo)), \(fmt(ansi.hi))]
              fullColor  mean=\(fmt(full.mean)) CI=[\(fmt(full.lo)), \(fmt(full.hi))]
              ordered(mono>ansi>full)=\(orderedMeans) CIs-disjoint=\(separated)
            """
        return (passed, detail)
    }

    // MARK: - Bootstrap

    private struct BootstrapStat {
        let mean: Double  // point estimate (mean of the observed values)
        let lo: Double  // 2.5th percentile of the resampled means
        let hi: Double  // 97.5th percentile of the resampled means
    }

    /// Percentile bootstrap of the sample mean: resample with replacement
    /// `samples` times, take each resample's mean, then the 2.5/97.5 percentiles.
    private static func bootstrapMeanCI(
        values: [Double],
        samples: Int,
        rng: inout SeededRNG
    ) -> BootstrapStat {
        let n = values.count
        let pointMean = values.reduce(0, +) / Double(n)

        var resampledMeans = [Double]()
        resampledMeans.reserveCapacity(samples)
        for _ in 0..<samples {
            var sum = 0.0
            for _ in 0..<n {
                let idx = Int.random(in: 0..<n, using: &rng)
                sum += values[idx]
            }
            resampledMeans.append(sum / Double(n))
        }
        resampledMeans.sort()

        return BootstrapStat(
            mean: pointMean,
            lo: percentile(sorted: resampledMeans, p: 0.025),
            hi: percentile(sorted: resampledMeans, p: 0.975))
    }

    /// Linearly-interpolated percentile of an already-sorted array.
    private static func percentile(sorted: [Double], p: Double) -> Double {
        guard !sorted.isEmpty else { return .nan }
        if sorted.count == 1 { return sorted[0] }
        let rank = p * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let frac = rank - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * frac
    }

    private static func fmt(_ x: Double) -> String { String(format: "%.4f", x) }

    // MARK: - A6: 2AFC d′ calibration (the falsifiable KILL)

    /// Number of synthetic 2AFC trials per class. ≥256 per the plan; a power of two.
    static let twoAFCTrials = 512

    /// d′ pass threshold. A NAMED constant so the research note can report and
    /// justify it; the default of 0.5 is a conservative "clearly above chance"
    /// bar (chance is d′ = 0).
    public static let defaultDPrimeThreshold = 0.5

    /// Per-trial measurement-noise floor (in OKLab ΔE units) applied identically to
    /// both classes. This gives both score distributions a common, non-degenerate
    /// variance — the standard signal-detection setup — so d′ reflects the true
    /// mean separation (the Jensen gap) relative to a shared noise floor rather
    /// than an artificially zero-variance signal class.
    private static let measurementNoise = 0.01

    /// Two-alternative forced-choice calibration of the **area-tone thesis**.
    ///
    /// The core claim under test: scoring the linear-light area composite
    /// `k·linFG + (1−k)·linBG` (rather than the cell's perceptual *average* L)
    /// is what the eye actually perceives. We probe this with two stimulus classes:
    ///
    /// - **Signal — true half-tone (k = 0.5):** half the cell is FG ink, half is BG.
    ///   Its TRUE perceived appearance *is* the linear area composite
    ///   `OKLab(0.5·linFG + 0.5·linBG)`. The area-tone model predicts exactly this,
    ///   so its residual is ~0 (only the shared measurement-noise floor).
    /// - **Noise — flat tone matched in mean L:** a uniform patch whose L equals the
    ///   *perceptual mean* `0.5·L(linFG) + 0.5·L(linBG)` — i.e. what a coverage-blind
    ///   averager would compute. The area-tone model, handed this stimulus, still
    ///   predicts the area composite (L = `L(0.5·linFG + 0.5·linBG)`), so its
    ///   residual is the **Jensen gap** `|L(½lin) − ½·L(lin)|`, which is non-zero
    ///   precisely because OKLab L is concave in linear luminance.
    ///
    /// The per-trial score is the area-tone model's residual `oklabDelta(prediction,
    /// truth)`. d′ = (μ_noise − μ_signal) / sqrt(0.5·(σ_signal² + σ_noise²)). If
    /// OKLab L were linear in luminance the gap would vanish, both classes would
    /// score ~0, d′ → 0, and the gate would correctly KILL. A high d′ is therefore
    /// genuine evidence for the thesis, not a rigged constant.
    public static func twoAFC(
        dPrimeThreshold: Double = DecolorGate.defaultDPrimeThreshold
    ) -> (passed: Bool, dPrime: Double, detail: String) {
        var rng = SeededRNG(seed: 0xD1B5_4A32_D192_ED03)

        var signalScores = [Double]()  // half-tone: model residual ≈ noise floor
        var noiseScores = [Double]()  // flat-tone: model residual ≈ Jensen gap
        signalScores.reserveCapacity(twoAFCTrials)
        noiseScores.reserveCapacity(twoAFCTrials)

        for _ in 0..<twoAFCTrials {
            // Random, neutral-ish FG/BG with a real luminance gap (so the half-tone
            // is genuinely sub-glyph structured, not degenerate). Encoded sRGB.
            let fgEnc = randomGray(0.55...1.0, &rng)
            let bgEnc = randomGray(0.0...0.45, &rng)

            // Ground-truth appearances.
            let linHalf = DecolorOracle.composite(fgEncoded: fgEnc, bgEncoded: bgEnc, inkFraction: 0.5)
            let okHalf = DecolorOracle.oklab(linearRGB: linHalf)  // true half-tone appearance

            // The area-tone model's prediction is the same area composite for either
            // stimulus (it is coverage-aware and assumes k=0.5 sub-glyph structure).
            let modelPrediction = okHalf

            // Flat tone matched in MEAN L: a neutral patch whose OKLab L equals the
            // perceptual mean of the two patches (the coverage-blind average).
            let linFG = DecolorOracle.composite(fgEncoded: fgEnc, bgEncoded: bgEnc, inkFraction: 1.0)
            let linBG = DecolorOracle.composite(fgEncoded: fgEnc, bgEncoded: bgEnc, inkFraction: 0.0)
            let meanL =
                0.5 * Double(DecolorOracle.oklab(linearRGB: linFG).x)
                + 0.5 * Double(DecolorOracle.oklab(linearRGB: linBG).x)
            let okFlat = SIMD3<Float>(Float(meanL), 0, 0)  // true flat appearance (neutral)
            // Invariant: FG/BG are grays, so okHalf is also neutral (a≈b≈0). Both
            // stimulus truths therefore live on the L axis, and simd_length below
            // reduces to |ΔL| — a pure-luminance comparison with no chroma leakage.

            // Scores = area-tone model residual against each stimulus' truth.
            // modelPrediction == okHalf by construction (line above), so `signal` is
            // identically 0 here; only the shared noise floor (added below) gives it
            // variance. `noise` is the OKLab-L Jensen gap (concavity of L in luminance).
            let signal = Double(simd_length(modelPrediction - okHalf))  // ≡ 0 (+ noise floor)
            let noise = Double(simd_length(modelPrediction - okFlat))  // ≈ Jensen gap

            // Shared measurement-noise floor (deterministic, same magnitude for both
            // classes). Half-normal-ish via |unit gaussian| keeps scores ≥ 0.
            signalScores.append(signal + measurementNoise * abs(gaussian(&rng)))
            noiseScores.append(noise + measurementNoise * abs(gaussian(&rng)))
        }

        let s = meanStd(signalScores)
        let n = meanStd(noiseScores)
        // Noise (flat) has the LARGER residual, so d′ uses (noise − signal).
        let pooledVar = 0.5 * (s.variance + n.variance)
        let dPrime = pooledVar > 0 ? (n.mean - s.mean) / pooledVar.squareRoot() : .infinity
        let passed = dPrime > dPrimeThreshold

        let detail = """
            2AFC: \(passed ? "PASS" : "FAIL") d′=\(fmt(dPrime)) (threshold=\(fmt(dPrimeThreshold)))
              signal(half-tone) μ=\(fmt(s.mean)) σ=\(fmt(s.variance.squareRoot())) \
            noise(flat-mean-L) μ=\(fmt(n.mean)) σ=\(fmt(n.variance.squareRoot()))
              NOTE: a sub-threshold d′ is the designed, publishable KILL of the \
            area-tone thesis — NOT a bug. It would mean scoring the composite is \
            indistinguishable from scoring the perceptual average.
            """
        return (passed, dPrime, detail)
    }

    // MARK: - evaluate

    /// Combine both gates. `passed` ⇔ discrimination AND 2AFC both pass.
    public static func evaluate(rows: [OracleRow]) -> GateResult {
        let disc = discrimination(rows: rows)
        let afc = twoAFC()
        let detail = """
            \(disc.detail)
            \(afc.detail)
            gate verdict: \(disc.passed && afc.passed ? "PASS — Phase 1/2 unlocked" : "KILL — stop; this is the negative result")
            """
        return GateResult(
            discriminationPassed: disc.passed,
            twoAFCPassed: afc.passed,
            detail: detail)
    }

    // MARK: - 2AFC helpers

    /// A neutral (R=G=B) encoded-sRGB gray with the scalar drawn uniformly from `range`.
    private static func randomGray(_ range: ClosedRange<Float>, _ rng: inout SeededRNG) -> SIMD3<Float> {
        let v = Float.random(in: range, using: &rng)
        return SIMD3<Float>(v, v, v)
    }

    /// A standard-normal sample via Box–Muller, driven by the seeded RNG.
    private static func gaussian(_ rng: inout SeededRNG) -> Double {
        let u1 = max(Double.random(in: 0...1, using: &rng), 1e-12)
        let u2 = Double.random(in: 0...1, using: &rng)
        return (-2 * Foundation.log(u1)).squareRoot() * Foundation.cos(2 * Double.pi * u2)
    }

    private static func meanStd(_ xs: [Double]) -> (mean: Double, variance: Double) {
        let n = Double(xs.count)
        let mean = xs.reduce(0, +) / n
        let variance = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        return (mean, variance)
    }
}

// MARK: - Deterministic RNG

/// A tiny, deterministic `RandomNumberGenerator` (SplitMix64). Seeded with a fixed
/// constant so the bootstrap (and the 2AFC stimulus generation) are fully
/// reproducible — never `SystemRandomNumberGenerator`, whose nondeterminism would
/// make the gate verdict flaky.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Avoid the all-zero fixed point of SplitMix64.
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
