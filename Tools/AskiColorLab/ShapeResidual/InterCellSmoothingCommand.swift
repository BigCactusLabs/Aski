import Aski
import AskiToolSupport
import CoreGraphics
import Foundation

// MARK: - ASTSK-43 inter-cell-smoothing screen (Unit 3 runner)

/// The cheap, lab-only A/B screen pre-registered in
/// `docs/Research/2026-06-24-astsk43-inter-cell-smoothing.md`: run the SAME
/// converter on the raw fixture (baseline) and on a guided-filter-smoothed copy
/// (treatment), composite both rendered grids, and score each against the ORIGINAL
/// source with M1 (seam continuity), GMSD, and HaarPSI. The verdict applies the
/// frozen `InterCellGate` rule. `Sources/Aski` is untouched (no knob): the only
/// difference between arms is the converter's input image.
enum InterCellSmoothingScreen {
    /// Oracle footprint per cell in the composited render (matches the lab's
    /// `oracleCellSize`); seams therefore fall at multiples of this.
    static let cellPx = 24
    /// Guided-filter ε, FROZEN before measurement (see the pre-registration).
    static let epsilon: Float = 0.01

    struct Reading: Sendable {
        let m1: Double
        let gmsd: Double
        let haarpsi: Double
    }
    struct FixtureResult: Sendable {
        let id: String
        let pool: FixturePool
        let baseline: Reading
        let treatment: Reading
    }
    struct Report: Sendable {
        let fixtures: [FixtureResult]
        let baseline: ArmMetrics
        let treatment: ArmMetrics
        let worstNaturals: (id: String, gmsdDelta: Double)?
        let verdict: InterCellVerdict
    }

    /// Smoothed copy of a fixture: guided-filter its luma (radius ≈ one cell so the
    /// window spans cell boundaries = inter-cell scale), rebuild a gray image.
    static func smoothedImage(of fixture: ResidualFixture, columns: Int) -> CGImage {
        let radius = max(1, Int((Double(fixture.width) / Double(columns)).rounded()))
        let smoothed = GuidedFilter.selfGuided(
            fixture.luma, width: fixture.width, height: fixture.height,
            radius: radius, epsilon: epsilon)
        let gray = smoothed.map { v -> UInt8 in UInt8(max(0, min(255, (v * 255).rounded()))) }
        return ResidualFixture.fromGrayBytes(
            id: fixture.id + "-smoothed", width: fixture.width, height: fixture.height,
            pool: fixture.pool, gray: gray
        ).image
    }

    /// Convert one input image, composite its chosen glyphs, and score vs the
    /// ORIGINAL source resampled to the rendered footprint.
    static func scoreArm(input: CGImage, fixture: ResidualFixture, columns: Int) -> Reading? {
        let oversample = ShapeResidualCommand.noDownscaleOversample(
            columns: columns, fixtureSide: fixture.width, fixtureHeight: fixture.height)
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.monochrome,
            colorSpace: .sRGB,
            oversample: oversample
        )
        let grid = converter.convert(input, columns: columns)
        guard grid.rows > 0, grid.columns > 0 else { return nil }
        let characters = grid.cells.map { $0.map(\.character) }
        let (rendered, w, h) = GridComposite.compose(characters: characters, cellPx: cellPx) {
            GlyphRaster.luma(character: $0, width: cellPx, height: cellPx)
        }
        guard w > 0, h > 0 else { return nil }
        let source = LumaResample.resample(
            fixture.luma, srcWidth: fixture.width, srcHeight: fixture.height,
            dstWidth: w, dstHeight: h)
        return Reading(
            m1: SeamContinuity.crossSeamCoherence(
                rendered: rendered, source: source, width: w, height: h,
                cellWidth: cellPx, cellHeight: cellPx),
            gmsd: GMSD.gmsd(rendered, source, width: w, height: h),
            haarpsi: HaarPSI.haarPSI(rendered, source, width: w, height: h)
        )
    }

    static func run(columns: Int, corpusDirectory: String?) throws -> Report {
        let battery = try ShapeResidualCommand.makeBattery(
            selection: .real, side: StructuredFixture.side, corpusDirectory: corpusDirectory)

        var results: [FixtureResult] = []
        var unscored: [String] = []
        for fixture in battery {
            guard let base = scoreArm(input: fixture.image, fixture: fixture, columns: columns),
                let treat = scoreArm(
                    input: smoothedImage(of: fixture, columns: columns), fixture: fixture, columns: columns)
            else {
                unscored.append(fixture.id)
                continue
            }
            results.append(
                FixtureResult(id: fixture.id, pool: fixture.pool, baseline: base, treatment: treat))
        }

        // Instrument integrity: a fixture that cannot be scored must FAIL the run, not
        // be silently dropped. Dropping fixtures can empty a whole pool, and an empty
        // pool's `pooledMean` is all-NaN; the frozen `InterCellGate` washout checks then
        // never trip (every NaN comparison is false), so the screen would emit a verdict
        // from the surviving pool alone instead of failing a partial battery.
        guard unscored.isEmpty else {
            throw ShapeResidualError.interCellFixtureUnscored(fixtureIDs: unscored, columns: columns)
        }

        let baselineArm = ArmMetrics(
            lineArt: pooledMean(results, pool: .lineArt) { $0.baseline },
            naturals: pooledMean(results, pool: .natural) { $0.baseline })
        let treatmentArm = ArmMetrics(
            lineArt: pooledMean(results, pool: .lineArt) { $0.treatment },
            naturals: pooledMean(results, pool: .natural) { $0.treatment })

        let worst =
            results
            .filter { $0.pool == .natural }
            .map { ($0.id, $0.treatment.gmsd - $0.baseline.gmsd) }
            .max { $0.1 < $1.1 }

        return Report(
            fixtures: results, baseline: baselineArm, treatment: treatmentArm,
            worstNaturals: worst,
            verdict: InterCellGate.decide(baseline: baselineArm, treatment: treatmentArm))
    }

    /// Human-readable report for the verdict doc / stdout.
    static func format(_ report: Report, columns: Int) -> String {
        func r(_ v: Double) -> String { v.isFinite ? String(format: "%.4f", v) : "nan" }
        func pool(_ name: String, _ b: PoolMetrics, _ t: PoolMetrics) -> String {
            "  \(name.padding(toLength: 9, withPad: " ", startingAt: 0))"
                + " M1 \(r(b.m1))→\(r(t.m1))  GMSD \(r(b.gmsd))→\(r(t.gmsd))  HaarPSI \(r(b.haarpsi))→\(r(t.haarpsi))"
        }
        var out = "ASTSK-43 inter-cell-smoothing screen — columns=\(columns), cellPx=\(cellPx), ε=\(epsilon)\n"
        out += "Per-fixture (baseline→treatment):\n"
        for f in report.fixtures {
            out +=
                "  [\(f.pool.rawValue)] \(f.id)"
                + "  ΔM1=\(r(f.treatment.m1 - f.baseline.m1))"
                + "  ΔGMSD=\(r(f.treatment.gmsd - f.baseline.gmsd))"
                + "  ΔHaarPSI=\(r(f.treatment.haarpsi - f.baseline.haarpsi))\n"
        }
        out += "Pooled means (baseline→treatment):\n"
        out += pool("line-art", report.baseline.lineArt, report.treatment.lineArt) + "\n"
        out += pool("naturals", report.baseline.naturals, report.treatment.naturals) + "\n"
        if let w = report.worstNaturals {
            out += "Worst naturals (GMSD regress): \(w.id)  ΔGMSD=\(r(w.gmsdDelta))\n"
        }
        switch report.verdict {
        case .pass: out += "VERDICT: PASS\n"
        case .kill(let why): out += "VERDICT: KILL — \(why)\n"
        case .rerun(let why): out += "VERDICT: RERUN (instrument failure) — \(why)\n"
        }
        return out
    }

    /// Mean of one arm's readings over a pool. M1 NaNs (fixtures with no
    /// seam-crossing source edge) are excluded from the M1 mean only.
    private static func pooledMean(
        _ results: [FixtureResult], pool: FixturePool, _ arm: (FixtureResult) -> Reading
    ) -> PoolMetrics {
        let readings = results.filter { $0.pool == pool }.map(arm)
        guard !readings.isEmpty else { return PoolMetrics(m1: .nan, gmsd: .nan, haarpsi: .nan) }
        let m1s = readings.map(\.m1).filter { $0.isFinite }
        let m1 = m1s.isEmpty ? Double.nan : m1s.reduce(0, +) / Double(m1s.count)
        let gmsd = readings.map(\.gmsd).reduce(0, +) / Double(readings.count)
        let haar = readings.map(\.haarpsi).reduce(0, +) / Double(readings.count)
        return PoolMetrics(m1: m1, gmsd: gmsd, haarpsi: haar)
    }
}
