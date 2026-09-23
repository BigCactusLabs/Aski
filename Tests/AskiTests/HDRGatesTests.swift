import Testing
@testable import AskiHDRLab

/// Deterministic unit tests for the decisive verdict gates — no rendering, so the
/// pass/KILL logic is exercised directly on crafted measurements.
@Suite struct HDRGatesTests {
    private func measurement(
        fixture: String = "f",
        expectation: String = "blooms",
        k: Float,
        contentHeadroom: Float,
        g1: Float = 0.01,
        g2: Float = 0.01,
        floatClean: Bool = true
    ) -> HDRMeasurement {
        HDRMeasurement(
            fixtureID: fixture, gamut: "sRGB", expectation: expectation,
            k: k, threshold: 0.5, maxHeadroom: 8,
            contentHeadroom: contentHeadroom, hdrMaxChannel: contentHeadroom,
            g1MeanDiff: g1, g2MeanDiff: g2, floatClean: floatClean, heicBytes: 1
        )
    }

    /// A healthy run: bright fixture blooms monotonically, dark stays flat.
    private func goodRows() -> [HDRMeasurement] {
        [
            measurement(fixture: "bright", expectation: "blooms", k: 0, contentHeadroom: 1.0),
            measurement(fixture: "bright", expectation: "blooms", k: 1, contentHeadroom: 1.4),
            measurement(fixture: "bright", expectation: "blooms", k: 2, contentHeadroom: 2.1),
            measurement(fixture: "bright", expectation: "blooms", k: 4, contentHeadroom: 3.3),
            measurement(fixture: "dark", expectation: "flat", k: 0, contentHeadroom: 1.0),
            measurement(fixture: "dark", expectation: "flat", k: 1, contentHeadroom: 1.0),
            measurement(fixture: "dark", expectation: "flat", k: 4, contentHeadroom: 1.0),
        ]
    }

    @Test func healthyRunPasses() {
        let verdict = HDRGates.evaluate(goodRows())
        #expect(verdict.passed)
        #expect(verdict.g1Pass && verdict.g2Pass && verdict.g3Pass && verdict.g4Pass)
    }

    @Test func authoredFixtureExpectationsPassIndependentOfBrightnessNames() {
        let rows = [
            measurement(fixture: "authored-dark-emits", expectation: "blooms", k: 0, contentHeadroom: 1.0),
            measurement(fixture: "authored-dark-emits", expectation: "blooms", k: 1, contentHeadroom: 1.8),
            measurement(fixture: "authored-dark-emits", expectation: "blooms", k: 4, contentHeadroom: 4.5),
            measurement(fixture: "authored-bright-flat", expectation: "flat", k: 0, contentHeadroom: 1.0),
            measurement(fixture: "authored-bright-flat", expectation: "flat", k: 1, contentHeadroom: 1.0),
            measurement(fixture: "authored-bright-flat", expectation: "flat", k: 4, contentHeadroom: 1.0),
            measurement(fixture: "authored-intensity-sweep", expectation: "blooms", k: 0, contentHeadroom: 1.0),
            measurement(fixture: "authored-intensity-sweep", expectation: "blooms", k: 1, contentHeadroom: 1.6),
            measurement(fixture: "authored-intensity-sweep", expectation: "blooms", k: 2, contentHeadroom: 2.4),
            measurement(fixture: "authored-intensity-sweep", expectation: "blooms", k: 4, contentHeadroom: 4.0),
        ]
        let verdict = HDRGates.evaluate(rows)
        #expect(verdict.passed)
    }

    @Test func emptyRowsKill() {
        #expect(!HDRGates.evaluate([]).passed)
    }

    @Test func g1RegressionKills() {
        var rows = goodRows()
        rows.append(measurement(fixture: "bright", k: 4, contentHeadroom: 3.3, g1: 0.5))
        let verdict = HDRGates.evaluate(rows)
        #expect(!verdict.g1Pass)
        #expect(!verdict.passed)
    }

    @Test func g2ZeroEmissionRegressionKills() {
        var rows = goodRows()
        // A k=0 sample whose tone-map identity diverges fails G2.
        rows.append(measurement(fixture: "extra", expectation: "blooms", k: 0, contentHeadroom: 1.0, g2: 0.5))
        let verdict = HDRGates.evaluate(rows)
        #expect(!verdict.g2Pass)
    }

    @Test func g2HighKDivergenceDoesNotKill() {
        var rows = goodRows()
        // k>0 tone-map divergence is recorded, not gated (Apple's tone operator).
        rows.append(measurement(fixture: "bright", expectation: "blooms", k: 4, contentHeadroom: 3.3, g2: 0.2))
        let verdict = HDRGates.evaluate(rows)
        #expect(verdict.g2Pass)
    }

    @Test func flatFixtureBloomingKills() {
        var rows = goodRows()
        rows.append(measurement(fixture: "dark", expectation: "flat", k: 2, contentHeadroom: 1.6))
        let verdict = HDRGates.evaluate(rows)
        #expect(!verdict.g3Pass)
    }

    @Test func missingZeroControlKills() {
        // A fixture with no k=0 row can't prove its SDR baseline lands at ≈1 — the
        // control check must fail loud, not silently skip (regression guard for A2).
        let rows = [
            measurement(fixture: "noctrl", expectation: "blooms", k: 1, contentHeadroom: 1.4),
            measurement(fixture: "noctrl", expectation: "blooms", k: 4, contentHeadroom: 3.3),
        ]
        let verdict = HDRGates.evaluate(rows)
        #expect(!verdict.g3Pass)
        #expect(!verdict.passed)
    }

    @Test func bloomFixtureNotBloomingKills() {
        let rows = [
            measurement(fixture: "weak", expectation: "blooms", k: 0, contentHeadroom: 1.0),
            measurement(fixture: "weak", expectation: "blooms", k: 4, contentHeadroom: 1.05),
        ]
        let verdict = HDRGates.evaluate(rows)
        #expect(!verdict.g3Pass)
    }

    @Test func floatCorruptionKills() {
        var rows = goodRows()
        rows.append(measurement(fixture: "bright", k: 4, contentHeadroom: 3.3, floatClean: false))
        let verdict = HDRGates.evaluate(rows)
        #expect(!verdict.g4Pass)
        #expect(!verdict.passed)
    }
}
