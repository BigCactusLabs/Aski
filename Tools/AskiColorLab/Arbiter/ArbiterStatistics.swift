import Foundation

/// The ASKI-56 §2.3 computations.
///
/// Every figure the arbiter reports is produced here, and every one of them is a
/// closed form or an exact enumeration rather than a simulation — the human leg
/// is ~40 trials, so an approximate test would be reporting sampling noise as a
/// finding.
enum ArbiterStatistics {

    // MARK: - Exact one-sided binomial (§2.3, human verdict)

    /// `P(X ≥ successes)` for `X ~ Binomial(trials, probability)`, computed
    /// exactly by summing the point masses through a log-gamma binomial
    /// coefficient.
    ///
    /// Exact rather than normal-approximated: at n ≈ 40 the continuity-corrected
    /// normal tail is off by enough to move a p across α = 0.05, and this is the
    /// number the verdict is read from. At n = 40 the frozen α = 0.05 boundary
    /// sits between 25 successes (p ≈ 0.0769) and 26 (p ≈ 0.0403).
    static func binomialUpperTail(
        successes: Int, trials: Int, probability: Double = 0.5
    ) -> Double {
        guard trials > 0 else { return 1.0 }
        let k = max(0, successes)
        guard k <= trials else { return 0.0 }
        guard probability > 0, probability < 1 else {
            return probability <= 0 ? (k == 0 ? 1.0 : 0.0) : 1.0
        }
        var total = 0.0
        for index in k...trials {
            let logCoefficient =
                lgamma(Double(trials) + 1) - lgamma(Double(index) + 1)
                - lgamma(Double(trials - index) + 1)
            let logMass =
                logCoefficient + Double(index) * log(probability)
                + Double(trials - index) * log1p(-probability)
            total += exp(logMass)
        }
        return min(1.0, total)
    }

    // MARK: - Logistic psychometric fit (§2.3, AC#3 calibration)

    /// The fitted psychometric function `P(choose the lower-MAE side) =
    /// logistic(intercept + slope · ΔMAE)`.
    struct LogisticFit: Sendable, Equatable {
        let intercept: Double
        let slope: Double
        let converged: Bool
    }

    /// One calibration trial: which source image it came from (the bootstrap's
    /// resampling unit), its signed ΔMAE magnitude, and whether the rater picked
    /// the lower-MAE side.
    struct CalibrationTrial: Sendable, Equatable {
        let sourceKey: String
        let relativeMarginMAE: Double
        let choseLowerMAESide: Bool

        init(sourceKey: String, relativeMarginMAE: Double, choseLowerMAESide: Bool) {
            self.sourceKey = sourceKey
            self.relativeMarginMAE = relativeMarginMAE
            self.choseLowerMAESide = choseLowerMAESide
        }
    }

    /// Iteratively reweighted least squares for a two-coefficient logistic
    /// regression. IRLS rather than plain gradient descent because the design is
    /// two-dimensional and the Newton step is available in closed form, so the
    /// fit converges in a handful of iterations and its non-convergence is
    /// informative rather than a tuning artifact.
    ///
    /// Returns `nil` when the data cannot support a finite MLE — a constant
    /// response, a constant regressor, or perfect separation. Separation is the
    /// one that matters here: a separable calibration set would otherwise report
    /// an infinite slope and a JND75 of ~0, which reads as "any margin is
    /// visible" when the truth is "this data cannot say".
    static func fitLogistic(
        x: [Double], y: [Double], maxIterations: Int = 60, tolerance: Double = 1e-10
    ) -> LogisticFit? {
        guard x.count == y.count, x.count >= 4 else { return nil }
        guard Set(y).count > 1 else { return nil }
        guard let low = x.min(), let high = x.max(), high > low else { return nil }
        if isSeparable(x: x, y: y) { return nil }

        var beta = (intercept: 0.0, slope: 0.0)
        var converged = false
        for _ in 0..<maxIterations {
            // Accumulate the 2x2 weighted normal equations.
            var h00 = 0.0, h01 = 0.0, h11 = 0.0
            var g0 = 0.0, g1 = 0.0
            for index in x.indices {
                let eta = beta.intercept + beta.slope * x[index]
                let mu = 1 / (1 + exp(-eta))
                let weight = max(mu * (1 - mu), 1e-10)
                let residual = y[index] - mu
                g0 += residual
                g1 += residual * x[index]
                h00 += weight
                h01 += weight * x[index]
                h11 += weight * x[index] * x[index]
            }
            let determinant = h00 * h11 - h01 * h01
            guard abs(determinant) > 1e-14 else { return nil }
            let step0 = (h11 * g0 - h01 * g1) / determinant
            let step1 = (h00 * g1 - h01 * g0) / determinant
            beta.intercept += step0
            beta.slope += step1
            guard beta.intercept.isFinite, beta.slope.isFinite else { return nil }
            if abs(step0) < tolerance && abs(step1) < tolerance {
                converged = true
                break
            }
        }
        guard converged else { return LogisticFit(intercept: beta.intercept, slope: beta.slope, converged: false) }
        return LogisticFit(intercept: beta.intercept, slope: beta.slope, converged: true)
    }

    /// Complete/quasi-complete separation on a single regressor: some threshold
    /// splits the responses perfectly.
    private static func isSeparable(x: [Double], y: [Double]) -> Bool {
        var zeroMax = -Double.infinity
        var zeroMin = Double.infinity
        var oneMax = -Double.infinity
        var oneMin = Double.infinity
        for index in x.indices {
            if y[index] < 0.5 {
                zeroMax = max(zeroMax, x[index])
                zeroMin = min(zeroMin, x[index])
            } else {
                oneMax = max(oneMax, x[index])
                oneMin = min(oneMin, x[index])
            }
        }
        guard zeroMax.isFinite, oneMax.isFinite else { return true }
        return zeroMax < oneMin || oneMax < zeroMin
    }

    /// The regressor value at which the fitted curve reaches `probability` —
    /// PSE at 0.5 and **JND75 at 0.75** (§2.3). Closed form:
    /// `(logit(p) − intercept) / slope`. `nil` for a flat or non-finite fit,
    /// never a division by zero.
    static func level(_ fit: LogisticFit, probability: Double) -> Double? {
        guard probability > 0, probability < 1 else { return nil }
        guard fit.slope != 0, fit.slope.isFinite, fit.intercept.isFinite else { return nil }
        let value = (log(probability / (1 - probability)) - fit.intercept) / fit.slope
        return value.isFinite ? value : nil
    }

    // MARK: - Bootstrap, resampled BY SOURCE IMAGE (§2.3)

    /// Bootstrap resamples of `trials`, drawn by SOURCE IMAGE.
    ///
    /// The unit matters more than the count. Several pairs off one photograph
    /// are several looks at one scene, not independent observations, so
    /// resampling pairs would report a band several times narrower than the data
    /// supports — and that band is what §5.2 would adjust the 3.0% bar against.
    /// Each draw takes `sourceCount` sources with replacement and takes ALL of
    /// each drawn source's trials.
    static func bootstrapResample(
        trials: [CalibrationTrial], seed: UInt64, draws: Int
    ) -> [[CalibrationTrial]] {
        var grouped: [String: [CalibrationTrial]] = [:]
        for trial in trials { grouped[trial.sourceKey, default: []].append(trial) }
        let keys = grouped.keys.sorted()
        guard !keys.isEmpty, draws > 0 else { return [] }

        var random = Arbiter.SeededRandom(seed: seed)
        var out: [[CalibrationTrial]] = []
        out.reserveCapacity(draws)
        for _ in 0..<draws {
            var sample: [CalibrationTrial] = []
            for _ in keys.indices {
                let index = Int(random.next() % UInt64(keys.count))
                sample.append(contentsOf: grouped[keys[index]] ?? [])
            }
            out.append(sample)
        }
        return out
    }

    /// The JND75 band: the point estimate on the full data plus a percentile
    /// interval over by-source bootstrap resamples. Reported as a band, never a
    /// scalar (§2.3).
    struct JND75Band: Sendable, Equatable {
        let point: Double
        let low: Double
        let high: Double
        /// Resamples whose fit CONVERGED and yielded a finite level — the band's
        /// actual denominator, which is smaller than `requestedResamples`
        /// whenever a resample was separable or failed to converge.
        let usableResamples: Int
        let requestedResamples: Int

        /// Whether the raw percentile interval actually contains the full-data
        /// point estimate. Reported, never enforced.
        var containsPointEstimate: Bool { low <= point && point <= high }
    }

    static func jnd75Band(
        trials: [CalibrationTrial], seed: UInt64, resamples: Int,
        lowerPercentile: Double = 0.025, upperPercentile: Double = 0.975
    ) -> JND75Band? {
        func jnd(_ sample: [CalibrationTrial]) -> Double? {
            let x = sample.map(\.relativeMarginMAE)
            let y = sample.map { $0.choseLowerMAESide ? 1.0 : 0.0 }
            guard let fit = fitLogistic(x: x, y: y), fit.converged else { return nil }
            return level(fit, probability: 0.75)
        }
        guard let point = jnd(trials) else { return nil }

        var estimates: [Double] = []
        for sample in bootstrapResample(trials: trials, seed: seed, draws: resamples) {
            if let value = jnd(sample), value.isFinite { estimates.append(value) }
        }
        guard !estimates.isEmpty else { return nil }
        estimates.sort()
        func percentile(_ fraction: Double) -> Double {
            let position = fraction * Double(estimates.count - 1)
            let lower = Int(position.rounded(.down))
            let upper = min(estimates.count - 1, lower + 1)
            let weight = position - Double(lower)
            return estimates[lower] * (1 - weight) + estimates[upper] * weight
        }
        // The RAW percentile interval. An earlier build clamped the edges onto
        // the point estimate so the band always contained it — which hid the one
        // thing a bootstrap is there to reveal. Resamples landing systematically
        // off the full-data fit is bootstrap bias, and bias is a reason to
        // distrust the fit, not a rendering problem to widen away.
        return JND75Band(
            point: point,
            low: percentile(lowerPercentile),
            high: percentile(upperPercentile),
            usableResamples: estimates.count,
            requestedResamples: resamples)
    }

    // MARK: - §5.2, the 3.0 percent bar

    /// The three frozen dispositions of §5.2. There is no fourth.
    enum BarAssessment: String, Sendable, Codable {
        /// Band entirely below the bar — a passing arm is visibly different.
        case perceptuallyGrounded = "perceptually-grounded"
        /// Band entirely above the bar — the bar admits invisible wins.
        case barAdmitsInvisibleWins = "bar-admits-invisible-wins"
        /// Band straddles the bar — retain, and require the arbiter for any
        /// default promotion (Cheon et al. ambiguity interval).
        case straddlesTheBar = "straddles-the-bar"
    }

    static func assessBar(
        band: (low: Double, high: Double), barFraction: Double
    ) -> BarAssessment {
        if band.high < barFraction { return .perceptuallyGrounded }
        if band.low > barFraction { return .barAdmitsInvisibleWins }
        return .straddlesTheBar
    }
}
