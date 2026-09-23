@testable import AskiDecolorLab
import Aski
import Testing
import simd

// MARK: - Task A2: lab palettes

@Test func decolorPalettesAreThreeDistinct() {
    let ids = DecolorPalettes.all.map(\.id)
    #expect(ids == ["monochrome", "ansi16", "fullColor"])
}

// MARK: - Task A3: composite oracle math

@Test func compositeIsLinearLightBlend() {
    let fg = SIMD3<Float>(1, 1, 1)  // encoded white
    let bg = SIMD3<Float>(0, 0, 0)  // encoded black
    let lin = DecolorOracle.composite(fgEncoded: fg, bgEncoded: bg, inkFraction: 0.25)
    // sRGBDecode(1)=1, sRGBDecode(0)=0 -> 0.25*1 + 0.75*0 = 0.25
    #expect(abs(lin.x - 0.25) < 1e-5)
    #expect(abs(lin.y - 0.25) < 1e-5)
    #expect(abs(lin.z - 0.25) < 1e-5)
}

@Test func compositeDecodesBeforeBlending() {
    // FG mid-grey encoded 0.5 decodes to ~0.214; with k=1 the composite == decoded FG.
    let fg = SIMD3<Float>(0.5, 0.5, 0.5)
    let lin = DecolorOracle.composite(fgEncoded: fg, bgEncoded: .zero, inkFraction: 1)
    let expected = ColorConversion.sRGBDecode(0.5)
    #expect(abs(lin.x - expected) < 1e-5)
}

@Test func compositeAtK1ReturnsDecodedFG() {
    // k=1 → composite is exactly the decoded FG (BG drops out entirely).
    let fg = SIMD3<Float>(0.5, 0.25, 0.75)
    let lin = DecolorOracle.composite(fgEncoded: fg, bgEncoded: SIMD3<Float>(0.1, 0.2, 0.3), inkFraction: 1)
    #expect(abs(lin.x - ColorConversion.sRGBDecode(0.5)) < 1e-5)
    #expect(abs(lin.y - ColorConversion.sRGBDecode(0.25)) < 1e-5)
    #expect(abs(lin.z - ColorConversion.sRGBDecode(0.75)) < 1e-5)
}

@Test func compositeAtK0ReturnsDecodedBG() {
    // k=0 → composite is exactly the decoded BG (FG drops out entirely).
    let bg = SIMD3<Float>(0.5, 0.25, 0.75)
    let lin = DecolorOracle.composite(fgEncoded: SIMD3<Float>(0.9, 0.8, 0.7), bgEncoded: bg, inkFraction: 0)
    #expect(abs(lin.x - ColorConversion.sRGBDecode(0.5)) < 1e-5)
    #expect(abs(lin.y - ColorConversion.sRGBDecode(0.25)) < 1e-5)
    #expect(abs(lin.z - ColorConversion.sRGBDecode(0.75)) < 1e-5)
}

@Test func chromaIsHypotOfAB() {
    // chroma = hypot(a, b); (0.3, 0.4) is the 3-4-5 triangle → 0.5. L is ignored.
    let c = DecolorOracle.chroma(oklab: SIMD3<Float>(0.5, 0.3, 0.4))
    #expect(abs(c - 0.5) < 1e-6)
}

@Test func fidelityIsHandComputedErrors() {
    // perceived = (0.6, 0.3, 0.4), source = (0.5, 0.0, 0.0).
    //   oklabDelta = |perceived − source| = length(0.1, 0.3, 0.4) = sqrt(0.26).
    //   lFidelity  = |0.6 − 0.5| = 0.1.
    //   chroma(perceived) = hypot(0.3, 0.4) = 0.5; chroma(source) = 0.
    //   chromaFidelity = |0.5 − 0| = 0.5.
    let perceived = SIMD3<Float>(0.6, 0.3, 0.4)
    let source = SIMD3<Float>(0.5, 0.0, 0.0)
    let f = DecolorOracle.fidelity(perceivedOKLab: perceived, sourceOKLab: source)
    let expectedDelta = (0.1 * 0.1 + 0.3 * 0.3 + 0.4 * 0.4).squareRoot()  // sqrt(0.26)
    #expect(abs(f.delta - expectedDelta) < 1e-6)
    #expect(abs(f.l - 0.1) < 1e-6)
    #expect(abs(f.chroma - 0.5) < 1e-6)
}

// MARK: - Task A4: fixtures + per-cell oracle sample assembly

@Test func fixtureProducesOneRowPerCell() throws {
    // columns=64 keeps the no-downscale invariant: 96×48 fixtures need
    // max(cols, rows) * oversample(2) >= 96, and 64*2 = 128 >= 96. (columns=8
    // would give 16 < 96 and trip the converterWouldDownscale assert.)
    let rows = try DecolorFixtures.samples(
        palette: DecolorPalettes.monochrome, columns: 64,
        backgroundEncoded: SIMD3<Float>(0.063, 0.063, 0.063),
        gitSHA: "test", command: "test")
    #expect(!rows.isEmpty)
    for r in rows {
        #expect(r.inkFraction >= 0 && r.inkFraction <= 1)
        #expect(r.fgHex.hasPrefix("#") && r.fgHex.count == 7)
        #expect(r.deficiency == "none")
    }
}

// MARK: - Task A5: discrimination gate (bootstrap-CI separation)

private func discriminationRows(_ palette: String, mean: Double) -> [OracleRow] {
    (0..<200).map { i in
        var r = OracleRow.zero
        r.paletteID = palette
        r.lFidelity = mean + Double(i % 5) * 0.001  // tight, deterministic spread
        return r
    }
}

@Test func discriminationSeparatesPalettes() {
    // lFidelity is an ERROR: more colors → lower error. So a separating run has
    // monochrome (most error) > ansi16 > fullColor (least error), with tight,
    // non-overlapping bootstrap CIs.
    let good =
        discriminationRows("monochrome", mean: 0.30)
        + discriminationRows("ansi16", mean: 0.15)
        + discriminationRows("fullColor", mean: 0.03)
    #expect(DecolorGate.discrimination(rows: good).passed)

    // Overlapping means → no separation → fail.
    let bad =
        discriminationRows("monochrome", mean: 0.10)
        + discriminationRows("ansi16", mean: 0.10)
        + discriminationRows("fullColor", mean: 0.10)
    #expect(!DecolorGate.discrimination(rows: bad).passed)
}

@Test func discriminationIsDeterministic() {
    // The seeded bootstrap must be reproducible: identical inputs → identical detail.
    let rows =
        discriminationRows("monochrome", mean: 0.30)
        + discriminationRows("ansi16", mean: 0.15)
        + discriminationRows("fullColor", mean: 0.03)
    let a = DecolorGate.discrimination(rows: rows)
    let b = DecolorGate.discrimination(rows: rows)
    #expect(a.passed == b.passed)
    #expect(a.detail == b.detail)
}

@Test func discriminationFailsOnMissingPalette() {
    // A palette absent from the rows cannot be separated → fail (no crash).
    let rows =
        discriminationRows("monochrome", mean: 0.30)
        + discriminationRows("ansi16", mean: 0.15)
    #expect(!DecolorGate.discrimination(rows: rows).passed)
}

// MARK: - Task A6: 2AFC d′ calibration gate (the falsifiable KILL)

@Test func twoAFCBeatsChance() {
    // The area-tone model should separate a true half-tone (whose appearance IS
    // the linear area composite) from a flat tone matched in mean L. Because
    // OKLab L is concave in linear luminance, the model's residual is ~0 on the
    // half-tone but ~the Jensen gap on the flat tone → a large d′.
    let result = DecolorGate.twoAFC()
    #expect(result.passed)
    #expect(result.dPrime > 0.5)
}

@Test func twoAFCIsDeterministic() {
    // Seeded stimulus generation → identical d′ across runs.
    let a = DecolorGate.twoAFC()
    let b = DecolorGate.twoAFC()
    #expect(a.dPrime == b.dPrime)
    #expect(a.detail == b.detail)
}

@Test func twoAFCHonorsThreshold() {
    // An impossibly high threshold must flip the verdict to KILL — proving the
    // gate is not hard-wired to pass.
    let killed = DecolorGate.twoAFC(dPrimeThreshold: 1_000_000)
    #expect(!killed.passed)
    // detail must state that a sub-threshold d′ is a KILL, not a bug.
    #expect(killed.detail.uppercased().contains("KILL"))
}

// MARK: - evaluate(rows:)

@Test func evaluatePassesOnGoodRows() {
    let good =
        discriminationRows("monochrome", mean: 0.30)
        + discriminationRows("ansi16", mean: 0.15)
        + discriminationRows("fullColor", mean: 0.03)
    let result = DecolorGate.evaluate(rows: good)
    #expect(result.discriminationPassed)
    #expect(result.twoAFCPassed)
    #expect(result.passed)
}

@Test func evaluateFailsWhenDiscriminationFails() {
    let bad =
        discriminationRows("monochrome", mean: 0.10)
        + discriminationRows("ansi16", mean: 0.10)
        + discriminationRows("fullColor", mean: 0.10)
    let result = DecolorGate.evaluate(rows: bad)
    #expect(!result.discriminationPassed)
    #expect(!result.passed)
}
