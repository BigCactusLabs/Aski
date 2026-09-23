import Foundation
import Testing

@testable import AskiColorLab

/// Guards ASKI-56 §2.3's computations: the exact one-sided binomial the human
/// verdict is read from, the IRLS logistic fit the JND75 band comes out of, and
/// the by-source-image bootstrap.
///
/// These are the numbers a bar adjustment (§5.2) would be argued from, so each
/// is checked against a value derived independently of the implementation: the
/// binomial against published tail probabilities at n = 40, the logistic fit
/// against the coefficients its own synthetic data was generated from, and
/// JND75 against the closed form `(ln 3 − b0) / b1`.
@Suite struct AskiColorLabArbiterStatisticsTests {

    // MARK: - Exact one-sided binomial

    /// The α = 0.05 spot-check the protocol is calibrated around: at n = 40,
    /// 26 successes clears and 25 does not. The two tail probabilities are the
    /// exact rationals `sum(C(40, i), i = k...40) / 2^40`, evaluated in exact
    /// integer arithmetic outside this implementation:
    /// `P(X ≥ 26) = 0.040345233876`, `P(X ≥ 25) = 0.076929972081`.
    @Test func exactOneSidedBinomialPutsTheAlphaBoundaryBetween25And26Of40() {
        let at26 = ArbiterStatistics.binomialUpperTail(successes: 26, trials: 40)
        let at25 = ArbiterStatistics.binomialUpperTail(successes: 25, trials: 40)
        #expect(abs(at26 - 0.040345233876) < 1e-9)
        #expect(abs(at25 - 0.076929972081) < 1e-9)
        #expect(at26 < 0.05)
        #expect(at25 >= 0.05)
    }

    /// Boundary behavior: the whole tail at k = 0, a single point mass at
    /// k = n, and a symmetric midpoint above one half.
    @Test func binomialTailHandlesTheBoundaries() {
        #expect(abs(ArbiterStatistics.binomialUpperTail(successes: 0, trials: 10) - 1.0) < 1e-12)
        #expect(
            abs(ArbiterStatistics.binomialUpperTail(successes: 10, trials: 10) - 1.0 / 1024.0)
                < 1e-12)
        #expect(ArbiterStatistics.binomialUpperTail(successes: 5, trials: 10) > 0.5)
        // No trials: nothing to reject.
        #expect(ArbiterStatistics.binomialUpperTail(successes: 0, trials: 0) == 1.0)
    }

    // MARK: - IRLS logistic fit

    /// The fit must recover the coefficients its data was generated from. The
    /// design is dense and deterministic — many trials at each x, with the
    /// success count set to the true probability — so recovery is tight and the
    /// test does not depend on an RNG.
    @Test func irlsRecoversKnownLogisticCoefficients() throws {
        let trueIntercept = -0.8
        let trueSlope = 130.0
        var x: [Double] = []
        var y: [Double] = []
        for step in 0...20 {
            let value = Double(step) * 0.002  // ΔMAE in 0 ... 0.04
            let probability = 1 / (1 + exp(-(trueIntercept + trueSlope * value)))
            let trials = 400
            let successes = Int((probability * Double(trials)).rounded())
            for index in 0..<trials {
                x.append(value)
                y.append(index < successes ? 1 : 0)
            }
        }

        let fit = try #require(ArbiterStatistics.fitLogistic(x: x, y: y))
        #expect(fit.converged)
        #expect(abs(fit.intercept - trueIntercept) < 0.05, "intercept \(fit.intercept)")
        #expect(abs(fit.slope - trueSlope) < 3.0, "slope \(fit.slope)")
    }

    /// JND75 is the ΔMAE at which the fitted choice probability reaches 0.75 —
    /// the closed form `(ln 3 − b0) / b1`. PSE is the same construction at 0.5.
    @Test func jnd75IsTheDeltaMAEAtSeventyFivePercent() throws {
        let fit = ArbiterStatistics.LogisticFit(intercept: -0.8, slope: 130, converged: true)
        let jnd = try #require(ArbiterStatistics.level(fit, probability: 0.75))
        #expect(abs(jnd - (log(3.0) + 0.8) / 130) < 1e-12)

        let pse = try #require(ArbiterStatistics.level(fit, probability: 0.5))
        #expect(abs(pse - 0.8 / 130) < 1e-12)

        // A flat curve has no level to report — never a division by zero.
        let flat = ArbiterStatistics.LogisticFit(intercept: 0.2, slope: 0, converged: true)
        #expect(ArbiterStatistics.level(flat, probability: 0.75) == nil)
    }

    /// Separable data has no finite MLE. The fit must report that rather than
    /// running away to an infinite slope and handing back a JND75 of ~0.
    @Test func perfectlySeparableDataDoesNotConverge() {
        let x = [0.0, 0.001, 0.002, 0.05, 0.051, 0.052]
        let y = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0]
        let fit = ArbiterStatistics.fitLogistic(x: x, y: y)
        #expect(fit == nil || fit?.converged == false)
    }

    // MARK: - Bootstrap by source image

    /// The bootstrap resamples SOURCE IMAGES, not pairs. Five pairs off one
    /// photo are five looks at one scene, so pair-level resampling would report
    /// a band several times too narrow. The property that separates the two:
    /// a resample draws whole sources, so a resample can never mix a fraction
    /// of one source's trials.
    @Test func bootstrapResamplesWholeSourceImages() {
        let trials = (0..<6).flatMap { sourceIndex in
            (0..<8).map { trialIndex in
                ArbiterStatistics.CalibrationTrial(
                    sourceKey: "source-\(sourceIndex)",
                    relativeMarginMAE: 0.002 * Double(trialIndex),
                    choseLowerMAESide: trialIndex % 3 != 0)
            }
        }
        let draws = ArbiterStatistics.bootstrapResample(trials: trials, seed: 99, draws: 40)
        #expect(draws.count == 40)
        for draw in draws {
            var counts: [String: Int] = [:]
            for trial in draw { counts[trial.sourceKey, default: 0] += 1 }
            for (key, count) in counts {
                #expect(count % 8 == 0, "source \(key) entered a resample in fragments")
            }
            #expect(draw.count == trials.count)
        }
        // Different seeds must produce different resamples.
        let other = ArbiterStatistics.bootstrapResample(trials: trials, seed: 100, draws: 40)
        #expect(draws.map { $0.map(\.sourceKey) } != other.map { $0.map(\.sourceKey) })
    }

    /// The reported figure is a BAND, never a scalar, and the point estimate
    /// sits inside it.
    @Test func jnd75IsReportedAsABandContainingThePointEstimate() throws {
        var trials: [ArbiterStatistics.CalibrationTrial] = []
        // Sources differ in slope. If every source carried the same curve the
        // by-source bootstrap would be a no-op and the "band" would collapse to
        // the point estimate — which is exactly the failure mode a pair-level
        // bootstrap hides.
        for sourceIndex in 0..<6 {
            let slope = 110.0 + 8.0 * Double(sourceIndex)
            for step in 0...20 {
                let delta = Double(step) * 0.002
                let probability = 1 / (1 + exp(-(-0.8 + slope * delta)))
                for index in 0..<20 {
                    trials.append(
                        ArbiterStatistics.CalibrationTrial(
                            sourceKey: "source-\(sourceIndex)",
                            relativeMarginMAE: delta,
                            choseLowerMAESide: Double(index) < probability * 20))
                }
            }
        }
        let band = try #require(
            ArbiterStatistics.jnd75Band(trials: trials, seed: 5, resamples: 60))
        #expect(band.low < band.point)
        #expect(band.point < band.high)
        #expect(band.low > 0)
        #expect(abs(band.point - (log(3.0) + 0.8) / 130) < 0.005)
    }

    // MARK: - The 3.0% bar assessment (§5.2)

    /// The three frozen dispositions, read off the band's position relative to
    /// the 3.0% margin. No fourth outcome exists.
    @Test func barAssessmentFollowsTheFrozenDispositions() {
        #expect(
            ArbiterStatistics.assessBar(band: (low: 0.010, high: 0.025), barFraction: 0.030)
                == .perceptuallyGrounded)
        #expect(
            ArbiterStatistics.assessBar(band: (low: 0.035, high: 0.060), barFraction: 0.030)
                == .barAdmitsInvisibleWins)
        #expect(
            ArbiterStatistics.assessBar(band: (low: 0.020, high: 0.045), barFraction: 0.030)
                == .straddlesTheBar)
    }
}
