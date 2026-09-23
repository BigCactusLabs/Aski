import Foundation
import Testing
import AskiToolSupport
@testable import AskiColorLab
@testable import BuildResearchIndex

@Suite struct AskiColorLabShapeResidualTests {
    /// B5 acceptance: the `shape-residual-map` subcommand writes a combined
    /// per-cell CSV (new 8-column header), one residual heatmap PNG per battery
    /// fixture, and a `result.yaml` whose `outputs` enumerate exactly the CSV +
    /// 5 heatmaps with `runner == "AskiColorLab"`.
    @Test func shapeResidualMapWritesCsvAndHeatmap() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("residual-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        var stderr = ""
        let status = ShapeResidualCommand.run(
            arguments: ShapeResidualArguments(
                outputDirectory: dir.path,
                columns: [8],
                fixtureSize: 64,
                allowUpsampledOracleBlocks: true,  // 64px @ 8 cols → 8px blocks; plumbing test
                gitShaOverride: "test-sha"
            ),
            standardError: { stderr += $0 }
        )
        #expect(status == .success, "stderr was: \(stderr)")

        let csvURL = dir.appendingPathComponent("shape_residual.csv")
        let yamlURL = dir.appendingPathComponent("result.yaml")
        #expect(FileManager.default.fileExists(atPath: csvURL.path))
        #expect(FileManager.default.fileExists(atPath: yamlURL.path))

        // One heatmap per battery fixture, named by fixture id.
        let expectedHeatmaps = [
            "shape_residual_heatmap_checker.png",
            "shape_residual_heatmap_diagonal.png",
            "shape_residual_heatmap_radial.png",
            "shape_residual_heatmap_strokes.png",
            "shape_residual_heatmap_mixedFrequency.png",
        ]
        for name in expectedHeatmaps {
            #expect(
                FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path),
                "missing heatmap \(name)"
            )
        }

        // CSV header is exactly the locked 12-column order (leading `columns`); one
        // data row per cell.
        let csv = try String(contentsOf: csvURL, encoding: .utf8)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(
            lines.first
                == "columns,fixture_id,row,col,character,residual,ssim_full,ssim_structure,gmsd,haarpsi,d_orient,d_radial"
        )
        #expect(lines.count > 1)

        // The CSV spans every battery fixture id.
        let header = lines[0].split(separator: ",").map(String.init)
        let fixtureCol = header.firstIndex(of: "fixture_id")!
        let seenIDs = Set(lines.dropFirst().map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)[fixtureCol] })
        #expect(seenIDs == Set(["checker", "diagonal", "radial", "strokes", "mixedFrequency"]))

        // result.yaml parses through the cross-lab ResultManifest schema; outputs
        // are the per-cell CSV + the summary CSV + 5 heatmaps in battery order.
        let text = try String(contentsOf: yamlURL, encoding: .utf8)
        let manifest = try ResultManifest.from(try FrontMatterParser.parse(text))
        #expect(manifest.outputs == ["shape_residual.csv", "spearman_summary.csv"] + expectedHeatmaps)
        #expect(manifest.runner == "AskiColorLab")
        #expect(manifest.schemaVersion == "1")
        #expect(manifest.askiGitSha == "test-sha")
    }

    // MARK: - Fixture battery (B5 diverse, deterministic, non-periodic)

    /// The battery is exactly the five expected, distinct, ordered fixtures.
    @Test func fixtureBatteryHasFiveDistinctIDs() {
        let battery = StructuredFixture.battery
        #expect(battery.count == 5)
        #expect(battery.map(\.id) == ["checker", "diagonal", "radial", "strokes", "mixedFrequency"])
        #expect(Set(battery.map(\.id)).count == 5)
    }

    /// Every fixture is 256×256.
    @Test func fixtureBatteryIsAll256() {
        for f in StructuredFixture.battery {
            #expect(f.width == 256 && f.height == 256, "\(f.id) is \(f.width)×\(f.height)")
            #expect(f.luma.count == 256 * 256, "\(f.id) luma length")
        }
    }

    /// Each fixture is deterministic: rebuilding it yields identical luma.
    @Test func fixtureBatteryIsDeterministic() {
        let first = StructuredFixture.battery
        let second = StructuredFixture.battery
        for (a, b) in zip(first, second) {
            #expect(a.luma == b.luma, "\(a.id) is non-deterministic")
        }
        // Also rebuild via the public constructors directly.
        #expect(StructuredFixture.makeChecker().luma == first[0].luma)
        #expect(StructuredFixture.makeMixedFrequency().luma == first[4].luma)
    }

    /// The oracle has real range: `mixedFrequency` contains BOTH a near-flat
    /// (low-variance) cell and a high-variance (structured) cell at the analysis
    /// grid, and `checker` contributes high-variance structured cells. (Pure
    /// `checker` is perfectly periodic, so at a uniform grid its cells are either
    /// all flat or all structured depending on cell-vs-period size; the coarse
    /// 32px period yields structured cells once cells span an edge — which is the
    /// "structure survives downscaling" property we retained it for.)
    @Test func batteryFixturesGiveTheOracleRange() {
        func variance(_ v: [Float]) -> Double {
            guard v.count > 1 else { return 0 }
            let mean = v.reduce(0.0) { $0 + Double($1) } / Double(v.count)
            return v.reduce(0.0) { $0 + (Double($1) - mean) * (Double($1) - mean) } / Double(v.count)
        }
        func varianceExtremes(_ id: String, rows: Int, cols: Int) -> (min: Double, max: Double) {
            let fixture = StructuredFixture.battery.first { $0.id == id }!
            var vmin = Double.greatestFiniteMagnitude
            var vmax = -Double.greatestFiniteMagnitude
            for r in 0..<rows {
                for c in 0..<cols {
                    let block = fixture.lumaBlock(cellRow: r, cellCol: c, rows: rows, cols: cols)
                    let v = variance(block.luma)
                    vmin = min(vmin, v)
                    vmax = max(vmax, v)
                }
            }
            return (vmin, vmax)
        }

        // mixedFrequency is purpose-built for the flat/structured mix: at a fine
        // grid it has both a near-flat ramp cell and a high-variance checker cell.
        let mixed = varianceExtremes("mixedFrequency", rows: 32, cols: 32)
        #expect(mixed.min < 1e-4, "mixedFrequency: expected a near-flat cell, min var = \(mixed.min)")
        #expect(mixed.max > 1e-2, "mixedFrequency: expected a high-variance cell, max var = \(mixed.max)")

        // checker: at a coarse grid (cells span ≥1 full 32px period) every cell
        // is high-variance — structure survives downscaling. At a fine grid that
        // straddles edges some cells are flat. So the union over both grids has
        // both extremes, i.e. checker also gives the oracle range.
        let checkerCoarse = varianceExtremes("checker", rows: 4, cols: 4)
        #expect(checkerCoarse.max > 1e-2, "checker coarse grid: expected high-variance cells, max var = \(checkerCoarse.max)")
        let checkerFine = varianceExtremes("checker", rows: 64, cols: 64)
        #expect(checkerFine.min < 1e-4, "checker fine grid: expected near-flat cells, min var = \(checkerFine.min)")
    }

    // MARK: - StructuralSimilarity unit tests

    /// Identical buffers → SSIM ≈ 1.0.
    @Test func ssimIdenticalBuffersIsOne() {
        let buf: [Float] = [
            0.1, 0.9, 0.3, 0.7, 0.5, 0.2, 0.8, 0.4,
            0.6, 0.15, 0.85, 0.35, 0.65, 0.45, 0.25, 0.75,
        ]
        let result = StructuralSimilarity.ssim(buf, buf, width: 4, height: 4)
        #expect(abs(result - 1.0) < 1e-4, "identical buffers: expected ≈1.0, got \(result)")
    }

    /// Anti-correlated (checkerboard vs inverse) → SSIM < −0.9.
    @Test func ssimAntiCorrelatedCheckerboardIsNearNegativeOne() {
        // 4×4 checkerboard: alternating 0.0 and 1.0
        let x: [Float] = [
            0, 1, 0, 1,
            1, 0, 1, 0,
            0, 1, 0, 1,
            1, 0, 1, 0,
        ]
        let y: [Float] = x.map { 1.0 - $0 }
        let result = StructuralSimilarity.ssim(x, y, width: 4, height: 4)
        // Expected ≈ −0.996 (computed analytically); assert < −0.9
        #expect(result < -0.9, "anti-correlated checkerboard: expected < −0.9, got \(result)")
    }

    /// Flat buffer (σ=0) vs itself → finite and ≈ 1.0 (C1/C2 guard avoids NaN).
    @Test func ssimFlatBufferVsItselfIsOne() {
        let flat = [Float](repeating: 0.5, count: 16)
        let result = StructuralSimilarity.ssim(flat, flat, width: 4, height: 4)
        #expect(result.isFinite, "flat buffer SSIM must be finite, got \(result)")
        #expect(abs(result - 1.0) < 1e-4, "flat buffer vs itself: expected ≈1.0, got \(result)")
    }

    /// Buffer vs uniform gray → finite (no NaN, no crash).
    @Test func ssimVsUniformGrayIsFinite() {
        let buf: [Float] = [
            0.1, 0.9, 0.3, 0.7, 0.5, 0.2, 0.8, 0.4,
            0.6, 0.15, 0.85, 0.35, 0.65, 0.45, 0.25, 0.75,
        ]
        let gray = [Float](repeating: 0.5, count: 16)
        let result = StructuralSimilarity.ssim(buf, gray, width: 4, height: 4)
        #expect(result.isFinite, "SSIM vs uniform gray must be finite, got \(result)")
    }

    // MARK: - StructuralSimilarity STRUCTURE-TERM unit tests (B5 fair oracle)

    /// Identical non-flat buffers → structure ≈ 1.0.
    @Test func structureIdenticalNonFlatIsOne() {
        let buf: [Float] = [
            0.1, 0.9, 0.3, 0.7, 0.5, 0.2, 0.8, 0.4,
            0.6, 0.15, 0.85, 0.35, 0.65, 0.45, 0.25, 0.75,
        ]
        let s = StructuralSimilarity.structure(buf, buf, width: 4, height: 4)
        #expect(abs(s - 1.0) < 1e-4, "identical structure: expected ≈1.0, got \(s)")
    }

    /// A non-flat pattern vs its structural inverse (1−v) → < 0 (≈ −1): inverting
    /// a pattern flips its covariance sign, so the structure term is anti-correlated.
    @Test func structureInverseIsNegative() {
        let x: [Float] = [
            0, 1, 0, 1,
            1, 0, 1, 0,
            0, 1, 0, 1,
            1, 0, 1, 0,
        ]
        let y: [Float] = x.map { 1.0 - $0 }
        let s = StructuralSimilarity.structure(x, y, width: 4, height: 4)
        #expect(s < 0, "structural inverse: expected < 0, got \(s)")
        #expect(s < -0.9, "structural inverse should be ≈ −1, got \(s)")
    }

    /// THE KEY DIFFERENTIATOR: a flat buffer vs a *brighter* flat buffer → ≈ 1.0.
    /// Both are structureless (σ=0), so the C3 stabilizer collapses numerator and
    /// denominator to C3 → exactly 1.0, IGNORING the mean offset. Full SSIM would
    /// penalize this via its luminance term; the structure term proves it does not.
    @Test func structureFlatVsBrighterFlatIsOneLuminanceInsensitive() {
        let dark = [Float](repeating: 0.2, count: 16)
        let bright = [Float](repeating: 0.8, count: 16)
        let s = StructuralSimilarity.structure(dark, bright, width: 4, height: 4)
        #expect(s.isFinite, "structure of two flats must be finite, got \(s)")
        #expect(abs(s - 1.0) < 1e-9, "flat-vs-brighter-flat: expected exactly ≈1.0, got \(s)")

        // Contrast: full SSIM DOES penalize the same pair (luminance term < 1),
        // which is precisely the confound the structure term removes.
        let full = StructuralSimilarity.ssim(dark, bright, width: 4, height: 4)
        #expect(full < 0.99, "full SSIM should penalize the mean offset, got \(full)")
    }

    /// Structure term is luminance-insensitive on NON-flat data too: shifting one
    /// buffer's mean by a constant (clamped pattern preserved) leaves structure ≈1.
    @Test func structureIsInvariantToUniformShift() {
        let x: [Float] = [
            0.1, 0.3, 0.2, 0.4,
            0.15, 0.35, 0.25, 0.45,
            0.05, 0.25, 0.15, 0.35,
            0.2, 0.4, 0.3, 0.5,
        ]
        // Add a uniform +0.2 offset: identical spatial pattern, different mean.
        let y: [Float] = x.map { $0 + 0.2 }
        let s = StructuralSimilarity.structure(x, y, width: 4, height: 4)
        #expect(abs(s - 1.0) < 1e-6, "uniform shift must not change structure, got \(s)")
    }

    /// Structure term of (glyph vs the same glyph) → 1.0 (deterministic raster).
    @Test func structureGlyphVsItselfIsOne() {
        let g = GlyphRaster.luma(character: "X", width: 8, height: 8)
        let s = StructuralSimilarity.structure(g, g, width: 8, height: 8)
        #expect(abs(s - 1.0) < 1e-4, "glyph vs itself: expected ≈1.0, got \(s)")
    }

    // MARK: - GMSD unit tests (B5 fair oracle; 0=identical, higher=worse)

    /// Identical buffers → GMSD ≈ 0 (no gradient deviation).
    @Test func gmsdIdenticalBuffersIsZero() {
        let buf: [Float] = [
            0.1, 0.9, 0.3, 0.7, 0.5, 0.2, 0.8, 0.4,
            0.6, 0.15, 0.85, 0.35, 0.65, 0.45, 0.25, 0.75,
        ]
        let d = GMSD.gmsd(buf, buf, width: 4, height: 4)
        #expect(abs(d) < 1e-12, "identical buffers: expected ≈0, got \(d)")
    }

    /// A sharp-edge buffer vs a flat buffer → GMSD > 0 (different gradient structure).
    @Test func gmsdEdgeVsFlatIsPositive() {
        // 4×4 vertical edge: left half 0, right half 1.
        var edge = [Float](repeating: 0, count: 16)
        for y in 0..<4 { for x in 0..<4 { edge[y * 4 + x] = x < 2 ? 0 : 1 } }
        let flat = [Float](repeating: 0, count: 16)
        let d = GMSD.gmsd(edge, flat, width: 4, height: 4)
        #expect(d > 0, "edge-vs-flat: expected > 0, got \(d)")
    }

    /// Hand-checked exact value: 4×4 vertical edge (left 0 / right 1) vs flat 0.
    /// Computed independently (Prewitt, replicate borders, T=170/255², population
    /// std-dev pooling) → GMSD ≈ 0.4998547988964716. Pins the whole pipeline.
    @Test func gmsdHandCheckedEdgeVsFlat() {
        var edge = [Float](repeating: 0, count: 16)
        for y in 0..<4 { for x in 0..<4 { edge[y * 4 + x] = x < 2 ? 0 : 1 } }
        let flat = [Float](repeating: 0, count: 16)
        let d = GMSD.gmsd(edge, flat, width: 4, height: 4)
        #expect(abs(d - 0.4998547988964716) < 1e-4, "hand-checked GMSD off: got \(d)")
    }

    /// GMSD is symmetric: gmsd(x,y) == gmsd(y,x).
    @Test func gmsdIsSymmetric() {
        var edge = [Float](repeating: 0, count: 16)
        for y in 0..<4 { for x in 0..<4 { edge[y * 4 + x] = x < 2 ? 0 : 1 } }
        let flat = [Float](repeating: 0.3, count: 16)
        let ab = GMSD.gmsd(edge, flat, width: 4, height: 4)
        let ba = GMSD.gmsd(flat, edge, width: 4, height: 4)
        #expect(ab == ba, "GMSD must be symmetric, got \(ab) vs \(ba)")
    }

    /// A buffer vs a slightly-noisier version → small positive GMSD (and strictly
    /// less than the edge-vs-flat distortion above — ordering sanity).
    @Test func gmsdSlightNoiseIsSmallPositive() {
        let base: [Float] = [
            0.2, 0.25, 0.22, 0.28,
            0.3, 0.32, 0.31, 0.29,
            0.21, 0.24, 0.23, 0.26,
            0.27, 0.33, 0.3, 0.28,
        ]
        // Add a tiny deterministic perturbation to one pixel.
        var noisy = base
        noisy[5] += 0.02
        let d = GMSD.gmsd(base, noisy, width: 4, height: 4)
        #expect(d > 0, "slight noise should give positive GMSD, got \(d)")

        var edge = [Float](repeating: 0, count: 16)
        for y in 0..<4 { for x in 0..<4 { edge[y * 4 + x] = x < 2 ? 0 : 1 } }
        let big = GMSD.gmsd(edge, [Float](repeating: 0, count: 16), width: 4, height: 4)
        #expect(d < big, "slight noise (\(d)) should be << edge-vs-flat (\(big))")
    }

    // MARK: - HaarPSI unit tests (ASTSK-31 regime-appropriate arbiter oracle)

    /// Deterministic closed-form n×n fixture in [0,1] luma reproducing the Python
    /// reference's integer formula EXACTLY: value(i,j) ∈ [0,250], luma = value/255,
    /// row-major. The ×255 round-trip is the only source of the tiny parity delta.
    private func haarFixture(_ n: Int, _ formula: (Int, Int) -> Int) -> [Float] {
        var buf = [Float](repeating: 0, count: n * n)
        for i in 0..<n { for j in 0..<n { buf[i * n + j] = Float(formula(i, j)) / 255.0 } }
        return buf
    }
    // ref(i,j)=(37i+17j)%251 ; dist(i,j)=(29ij+53)%251 — see /tmp/haarpsi_refgen.py.
    private func haarRef(_ n: Int) -> [Float] { haarFixture(n) { i, j in (37 * i + 17 * j) % 251 } }
    private func haarDist(_ n: Int) -> [Float] { haarFixture(n) { i, j in (29 * i * j + 53) % 251 } }

    /// Identical non-flat buffers → exactly 1.0: logit is the exact inverse of
    /// sigmoid, so identical local similarities pool back to 1.
    @Test func haarPSIIdenticalNonFlatIsOne() {
        let x = haarRef(16)
        let s = HaarPSI.haarPSI(x, x, width: 16, height: 16)
        #expect(abs(s - 1.0) < 1e-9, "identical → 1.0, got \(s)")
    }

    /// Flat-vs-flat → 1.0: the pre-registered divergence from the reference's 0/0
    /// NaN, exercised via a space-glyph raster × flat block (so the all-oracles-
    /// finite inclusion rule does not silently shrink the population). Two flats of
    /// DIFFERENT value also → 1.0 (luminance-insensitive, mirroring
    /// `StructuralSimilarity.structure`; the reference would penalize the offset).
    @Test func haarPSIFlatVsFlatIsOne() {
        let space = GlyphRaster.luma(character: " ", width: 24, height: 24)
        let flat = [Float](repeating: 0.5, count: 24 * 24)
        let s = HaarPSI.haarPSI(space, flat, width: 24, height: 24)
        #expect(s.isFinite, "flat-vs-flat must be finite (not NaN), got \(s)")
        #expect(s == 1.0, "flat-vs-flat defined as exactly 1.0, got \(s)")

        let dark = [Float](repeating: 0.2, count: 24 * 24)
        let bright = [Float](repeating: 0.8, count: 24 * 24)
        #expect(HaarPSI.haarPSI(dark, bright, width: 24, height: 24) == 1.0)

        // Zeros-vs-zeros is the reference's LITERAL NaN case → 1.0, not NaN.
        let zeros = [Float](repeating: 0, count: 24 * 24)
        let z = HaarPSI.haarPSI(zeros, zeros, width: 24, height: 24)
        #expect(z.isFinite && z == 1.0, "zeros-vs-zeros must be 1.0 (not NaN), got \(z)")
    }

    /// HaarPSI is symmetric: haarPSI(x,y) == haarPSI(y,x).
    @Test func haarPSIIsSymmetric() {
        let x = haarRef(16), y = haarDist(16)
        let ab = HaarPSI.haarPSI(x, y, width: 16, height: 16)
        let ba = HaarPSI.haarPSI(y, x, width: 16, height: 16)
        #expect(ab == ba, "HaarPSI must be symmetric, got \(ab) vs \(ba)")
    }

    /// Bounds: result in [0,1] for an arbitrary non-flat pair.
    @Test func haarPSIIsBounded() {
        let s = HaarPSI.haarPSI(haarRef(24), haarDist(24), width: 24, height: 24)
        #expect(s >= 0.0 && s <= 1.0, "HaarPSI out of [0,1]: \(s)")
    }

    /// **Pinned reference vectors** generated ONCE from the upstream MIT reference
    /// (rgcda/haarpsi @ commit 2c2793108477deb81971658a7666d5f85ba2587b, haarPsi.py,
    /// numpy path, preprocess_with_subsampling=True; generator /tmp/haarpsi_refgen.py
    /// on numpy 2.4.2 / scipy). The 8×8 fixture makes any even-kernel convolution-
    /// boundary (crop-offset) mismatch FAIL LOUDLY — its scale-3 8×8 Haar filter runs
    /// on a 4×4 subsampled field, the most boundary-sensitive case. A wrong crop
    /// offset shifts the score by O(0.1+); the ×255-through-Float round-trip is < 1e-4.
    @Test func haarPSIMatchesPinnedReferenceVectors() {
        let f8 = HaarPSI.haarPSI(haarRef(8), haarDist(8), width: 8, height: 8)
        #expect(abs(f8 - 0.6601595645193716) < 1e-4, "8×8 reference parity off: got \(f8)")
        let f16 = HaarPSI.haarPSI(haarRef(16), haarDist(16), width: 16, height: 16)
        #expect(abs(f16 - 0.4209171140051242) < 1e-4, "16×16 reference parity off: got \(f16)")
        let f24 = HaarPSI.haarPSI(haarRef(24), haarDist(24), width: 24, height: 24)
        #expect(abs(f24 - 0.4580485047071552) < 1e-4, "24×24 reference parity off: got \(f24)")
    }

    // MARK: - LumaResample unit tests (B5 fixed-resolution oracle footprint)

    /// Resampling a constant buffer → same constant everywhere (within 1e-5).
    @Test func resampleConstantBufferIsConstant() {
        let src = [Float](repeating: 0.37, count: 8 * 8)
        let out = LumaResample.resample(src, srcWidth: 8, srcHeight: 8, dstWidth: 16, dstHeight: 16)
        #expect(out.count == 16 * 16)
        for v in out { #expect(abs(v - 0.37) < 1e-5, "constant not preserved, got \(v)") }
    }

    /// Output length is exactly dstW·dstH.
    @Test func resampleOutputLengthMatchesDestination() {
        let src = [Float](repeating: 0.5, count: 9 * 7)
        let out = LumaResample.resample(src, srcWidth: 9, srcHeight: 7, dstWidth: 16, dstHeight: 16)
        #expect(out.count == 16 * 16)
    }

    /// Resampling a buffer to its own size → identity (exact, same-size fast path).
    @Test func resampleToSameSizeIsIdentity() {
        let src: [Float] = (0..<36).map { Float($0) / 36.0 }
        let out = LumaResample.resample(src, srcWidth: 6, srcHeight: 6, dstWidth: 6, dstHeight: 6)
        #expect(out == src, "same-size resample must be identity")
    }

    /// 8×8 left-black / right-white downsampled to 4×4 preserves the dark/bright
    /// split: every left cell < every right cell in each row.
    @Test func resamplePreservesLeftDarkRightBrightSplit() {
        var src = [Float](repeating: 0, count: 8 * 8)
        for y in 0..<8 { for x in 0..<8 { src[y * 8 + x] = x < 4 ? 0 : 1 } }
        let out = LumaResample.resample(src, srcWidth: 8, srcHeight: 8, dstWidth: 4, dstHeight: 4)
        #expect(out.count == 16)
        for row in 0..<4 {
            // Left two columns are the dark side, right two are bright.
            let l0 = out[row * 4 + 0], l1 = out[row * 4 + 1]
            let r0 = out[row * 4 + 2], r1 = out[row * 4 + 3]
            #expect(l0 < r0 && l1 < r1, "row \(row): left (\(l0),\(l1)) not < right (\(r0),\(r1))")
            #expect(l0 < 0.5 && l1 < 0.5, "row \(row): left cells should be dark")
            #expect(r0 > 0.5 && r1 > 0.5, "row \(row): right cells should be bright")
        }
    }

    /// Upsampling a 2-region pattern still keeps the global dark→bright ordering
    /// (mean of the left half < mean of the right half).
    @Test func resampleUpsamplePreservesRegionOrdering() {
        var src = [Float](repeating: 0, count: 4 * 4)
        for y in 0..<4 { for x in 0..<4 { src[y * 4 + x] = x < 2 ? 0.1 : 0.9 } }
        let out = LumaResample.resample(src, srcWidth: 4, srcHeight: 4, dstWidth: 16, dstHeight: 16)
        var leftSum = 0.0, rightSum = 0.0
        for y in 0..<16 {
            for x in 0..<16 {
                if x < 8 { leftSum += Double(out[y * 16 + x]) } else { rightSum += Double(out[y * 16 + x]) }
            }
        }
        #expect(leftSum < rightSum, "upsample lost region ordering: left=\(leftSum), right=\(rightSum)")
    }

    // MARK: - GlyphRaster unit tests

    /// Same (character, width, height) → identical luma buffers (deterministic).
    @Test func glyphRasterIsDeterministic() {
        let first = GlyphRaster.luma(character: "A", width: 8, height: 8)
        let second = GlyphRaster.luma(character: "A", width: 8, height: 8)
        #expect(first == second, "GlyphRaster.luma must be deterministic for same inputs")
    }

    /// Visibly different glyphs ('X' vs '.') produce different ink totals (non-trivial render).
    @Test func glyphRasterDifferentGlyphsDifferentInk() {
        let x = GlyphRaster.luma(character: "X", width: 8, height: 8)
        let dot = GlyphRaster.luma(character: ".", width: 8, height: 8)
        let inkX = x.reduce(0, +)
        let inkDot = dot.reduce(0, +)
        #expect(inkX != inkDot, "glyphs 'X' and '.' must produce different ink totals; got inkX=\(inkX), inkDot=\(inkDot)")
    }

    /// Both SSIM columns are in the valid [-1, 1] band and GMSD ≥ 0 for every
    /// emitted row — a cheap guard that the oracles produced real numbers (not
    /// NaN) per cell.
    @Test func oracleColumnsAreBounded() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("residual-ssim-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let status = ShapeResidualCommand.run(
            arguments: ShapeResidualArguments(
                outputDirectory: dir.path,
                columns: [8],
                fixtureSize: 64,
                allowUpsampledOracleBlocks: true,  // 64px @ 8 cols → 8px blocks; plumbing test
                gitShaOverride: "test-sha"
            ),
            standardError: { _ in }
        )
        #expect(status == .success)

        let csv = try String(
            contentsOf: dir.appendingPathComponent("shape_residual.csv"),
            encoding: .utf8
        )
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let header = lines[0].split(separator: ",").map(String.init)
        let fullIndex = header.firstIndex(of: "ssim_full")!
        let structIndex = header.firstIndex(of: "ssim_structure")!
        let gmsdIndex = header.firstIndex(of: "gmsd")!
        let haarIndex = header.firstIndex(of: "haarpsi")!
        for line in lines.dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            let full = Double(fields[fullIndex])!
            let structure = Double(fields[structIndex])!
            let gmsd = Double(fields[gmsdIndex])!
            let haarpsi = Double(fields[haarIndex])!
            #expect(full >= -1.0001 && full <= 1.0001, "ssim_full out of range: \(full)")
            #expect(structure >= -1.0001 && structure <= 1.0001, "ssim_structure out of range: \(structure)")
            #expect(gmsd >= -1e-6, "gmsd must be ≥ 0, got: \(gmsd)")
            #expect(haarpsi >= -1e-6 && haarpsi <= 1.0001, "haarpsi out of [0,1]: \(haarpsi)")
        }
    }

    /// ASKI-29 AC#2: every verdict the harness reports carries the sampling
    /// regime it was measured at. Without it a ρ read at 48 of 60 reachable bins
    /// and a ρ read at 2 are indistinguishable in the record, which is how the
    /// archived descriptor kills came to be quoted against a shipping preset they
    /// never ran on.
    @Test func analysisRecordsTheResolvedFootprintAndReachableBins() throws {
        let analysis = try ShapeResidualCommand.analyze(
            columns: 8, fixtureSize: 64, allowUpsampledBlocks: true, battery: .synthetic)
        #expect(!analysis.fixtures.isEmpty)
        for fixture in analysis.fixtures {
            #expect(fixture.cellWidth > 0, "no resolved cell width for \(fixture.id)")
            #expect(fixture.cellHeight > 0, "no resolved cell height for \(fixture.id)")
            // The recorded bin count must be the census of the recorded
            // footprint, not an independently drifting number.
            let census = LatticeSupport.census(
                width: fixture.cellWidth, height: fixture.cellHeight)
            #expect(
                fixture.reachableBins == census.bins.count,
                "recorded bins disagree with the census for \(fixture.id)")
            #expect(fixture.reachableBins > 0 && fixture.reachableBins <= 60)
        }
        // And it reaches the reader: the printed verdict table carries it.
        let table = ShapeResidualCommand.spearmanTable(analysis)
        #expect(table.contains("footprint"))
        #expect(table.contains("bins/60"))
        // Including the pooled row. Every column is fixed-width, so a row that
        // stops short of the header is a row missing its regime.
        let tableLines = table.split(separator: "\n").map(String.init)
        let header = try #require(tableLines.first { $0.contains("bins/60") })
        let pooled = try #require(tableLines.first { $0.hasPrefix("POOLED") })
        #expect(
            pooled.count == header.count,
            "the pooled row is narrower than the header it prints under")
    }

    // MARK: - Spearman unit tests (B5 KILL statistic)

    /// Perfect monotonic increasing → ρ ≈ +1.
    @Test func spearmanPerfectMonotonicIncreasingIsPlusOne() {
        let x: [Double] = [1, 2, 3, 4, 5]
        let y: [Double] = [10, 20, 30, 40, 50]
        let rho = Spearman.rho(x, y)
        #expect(abs(rho - 1.0) < 1e-12, "expected ≈ +1, got \(rho)")
    }

    /// Perfect monotonic decreasing → ρ ≈ −1.
    @Test func spearmanPerfectMonotonicDecreasingIsMinusOne() {
        let x: [Double] = [1, 2, 3, 4, 5]
        let y: [Double] = [50, 40, 30, 20, 10]
        let rho = Spearman.rho(x, y)
        #expect(abs(rho - (-1.0)) < 1e-12, "expected ≈ −1, got \(rho)")
    }

    /// Nonlinear-but-monotonic (y = x³) → ρ ≈ +1. Proves the statistic is
    /// RANK-based, not linear: Pearson on the raw values would be < 1 here.
    @Test func spearmanNonlinearMonotonicIsPlusOne() {
        let x: [Double] = [1, 2, 3, 4, 5]
        let y: [Double] = [1, 8, 27, 64, 125]
        let rho = Spearman.rho(x, y)
        #expect(abs(rho - 1.0) < 1e-12, "rank-based ρ for y=x³ must be +1, got \(rho)")
    }

    /// Tie handling — the load-bearing proof. x=[1,1,2,3], y=[1,2,2,3].
    ///
    /// Average ranks: rx=[1.5,1.5,3,4], ry=[1,2.5,2.5,4] (each tied pair gets the
    /// mean of the positions it occupies). Pearson on those ranks:
    ///   mean(rx)=mean(ry)=2.5
    ///   Σ dx·dy = (−1)(−1.5)+(−1)(0)+(0.5)(0)+(1.5)(1.5) = 1.5 + 2.25 = 3.75
    ///   Σ dx²   = 1+1+0.25+2.25 = 4.5 ;  Σ dy² = 2.25+0+0+2.25 = 4.5
    ///   ρ = 3.75 / √(4.5·4.5) = 3.75 / 4.5 = 5/6 = 0.8333333333333334
    /// The `1 − 6Σd²/(n(n²−1))` shortcut would give the WRONG number under ties;
    /// asserting this exact value pins the Pearson-on-average-ranks definition.
    @Test func spearmanTieHandlingMatchesPearsonOnAverageRanks() {
        let x: [Double] = [1, 1, 2, 3]
        let y: [Double] = [1, 2, 2, 3]
        let rho = Spearman.rho(x, y)
        #expect(abs(rho - (5.0 / 6.0)) < 1e-9, "tie-handled ρ must be 5/6, got \(rho)")
    }

    /// Degenerate (zero variance in one input) → documented value `0` (no signal).
    @Test func spearmanZeroVarianceReturnsZero() {
        let x: [Double] = [5, 5, 5]
        let y: [Double] = [1, 2, 3]
        let rho = Spearman.rho(x, y)
        #expect(rho == 0, "zero-variance input must return the documented 0, got \(rho)")
    }

    /// n < 2 → documented value `0` (no signal).
    @Test func spearmanTooFewObservationsReturnsZero() {
        let one: [Double] = [1]
        let empty: [Double] = []
        #expect(Spearman.rho(one, one) == 0)
        #expect(Spearman.rho(empty, empty) == 0)
    }

    /// `Float` overload agrees with the `Double` path (single-precision math).
    @Test func spearmanFloatOverloadMatchesDouble() {
        let xf: [Float] = [1, 1, 2, 3]
        let yf: [Float] = [1, 2, 2, 3]
        let rho = Spearman.rho(xf, yf)
        #expect(abs(rho - (5.0 / 6.0)) < 1e-9, "Float overload must match, got \(rho)")
    }

    // MARK: - OracleConsensus unit tests (ASTSK-31 AC#2 — training-free consensus)

    /// Per-cell consensus = median of the three oracles' average-ranks within the
    /// population. Hand-computed:
    ///   gmsd             = [0.1,0.4,0.2,0.3] → ranks [1,4,2,3]
    ///   1−ssim_structure = [0.5,0.1,0.4,0.2] → ranks [4,1,3,2]
    ///   1−haarpsi        = [0.2,0.3,0.1,0.4] → ranks [2,3,1,4]
    ///   median per cell                      → [2,3,2,3]
    @Test func consensusMedianOfRanksMatchesHandComputed() {
        let g: [Double] = [0.1, 0.4, 0.2, 0.3]
        let s: [Double] = [0.5, 0.1, 0.4, 0.2]
        let h: [Double] = [0.2, 0.3, 0.1, 0.4]
        let consensus = OracleConsensus.medianRank(gmsd: g, oneMinusStructure: s, oneMinusHaar: h)
        #expect(consensus == [2, 3, 2, 3], "median-of-ranks off: \(consensus)")
    }

    /// Ties use `Spearman.averageRanks` semantics (a tied run shares the mean of the
    /// positions it occupies). Hand-computed:
    ///   gmsd      = [0.2,0.2,0.5] → ranks [1.5,1.5,3]
    ///   1−struct  = [0.9,0.1,0.5] → ranks [3,1,2]
    ///   1−haarpsi = [0.4,0.4,0.4] → ranks [2,2,2]   (all tied → (1+2+3)/3)
    ///   median per cell           → [2,1.5,2]
    @Test func consensusMedianOfRanksHandlesTies() {
        let g: [Double] = [0.2, 0.2, 0.5]
        let s: [Double] = [0.9, 0.1, 0.5]
        let h: [Double] = [0.4, 0.4, 0.4]
        let consensus = OracleConsensus.medianRank(gmsd: g, oneMinusStructure: s, oneMinusHaar: h)
        #expect(consensus == [2, 1.5, 2], "tie-handled median-of-ranks off: \(consensus)")
    }

    /// Exact ρ(residual, consensus). residual [10,20,30,40] vs the consensus
    /// [2,3,2,3] above → consensus avg-ranks [1.5,3.5,1.5,3.5]; Pearson on
    /// ([1,2,3,4],[1.5,3.5,1.5,3.5]) = 2/√20 = 1/√5 ≈ 0.4472136.
    @Test func consensusRhoMatchesHandComputedSpearman() {
        let residual: [Double] = [10, 20, 30, 40]
        let g: [Double] = [0.1, 0.4, 0.2, 0.3]
        let s: [Double] = [0.5, 0.1, 0.4, 0.2]
        let h: [Double] = [0.2, 0.3, 0.1, 0.4]
        let rho = OracleConsensus.rho(
            residual: residual, gmsd: g, oneMinusStructure: s, oneMinusHaar: h)
        #expect(abs(rho - 1.0 / 5.0.squareRoot()) < 1e-9, "consensus ρ off: \(rho)")
    }

    /// Population-relative: ranks are computed within the population being
    /// correlated, so a cell's consensus differs between a per-fixture subset and a
    /// larger pooled set. Cell #1's oracle values are unchanged, but two extra cells
    /// shift its rank → consensus moves from 2 (subset) to 4 (full population).
    @Test func consensusIsPopulationRelative() {
        let gSub: [Double] = [0.1, 0.5, 0.9]
        let sub = OracleConsensus.medianRank(
            gmsd: gSub, oneMinusStructure: gSub, oneMinusHaar: gSub)
        #expect(sub == [1, 2, 3])
        let gFull: [Double] = [0.1, 0.5, 0.9, 0.2, 0.3]
        let full = OracleConsensus.medianRank(
            gmsd: gFull, oneMinusStructure: gFull, oneMinusHaar: gFull)
        #expect(full[1] == 4, "cell #1 consensus must shift with the population, got \(full[1])")
        #expect(sub[1] != full[1], "per-fixture vs pooled consensus must differ for a shared cell")
    }

    // MARK: - BasisAugmentation unit tests (ASTSK-31 Phase 6 — AC#4 basis prototype)

    /// The augmentation mixes are FIXED, pre-registered constants (never fitted — a
    /// `w` tuned against the oracle would be circular).
    @Test func augmentationMixesArePreRegistered() {
        #expect(BasisAugmentation.mixes == [0.25, 0.5, 0.75])
    }

    /// Orientation-energy dispersion separates single-orientation content (energy in
    /// one bin → ~0 dispersion) from isotropic content (energy spread across bins →
    /// high dispersion). A horizontal luminance ramp has purely horizontal gradients
    /// (one orientation); concentric rings have radial gradients at every angle.
    /// Pinned bound: single < 0.05, isotropic > 0.70.
    @Test func orientationDispersionSeparatesSingleOrientationFromIsotropic() {
        let side = 24
        var ramp = [Float](repeating: 0, count: side * side)
        var rings = [Float](repeating: 0, count: side * side)
        let c = Double(side - 1) / 2.0
        for y in 0..<side {
            for x in 0..<side {
                ramp[y * side + x] = Float(x) / Float(side - 1)
                let dx = Double(x) - c, dy = Double(y) - c
                let r = (dx * dx + dy * dy).squareRoot()
                rings[y * side + x] = Int(r / 3.0) % 2 == 0 ? 1.0 : 0.0
            }
        }
        let single = BasisAugmentation.orientationDispersion(
            BasisAugmentation.orientationHistogram(ramp, width: side, height: side))
        let isotropic = BasisAugmentation.orientationDispersion(
            BasisAugmentation.orientationHistogram(rings, width: side, height: side))
        #expect(single < 0.05, "single-orientation dispersion should be ~0, got \(single)")
        #expect(isotropic > 0.70, "isotropic dispersion should be high, got \(isotropic)")
        #expect(single < isotropic)
    }

    /// Radial-frequency autocorrelation separates concentric content (oscillating
    /// radial profile → strong autocorrelation peak) from flat and single-edge
    /// content (near-constant radial profile → degenerate ~0). A single edge through
    /// the centre leaves every radius shell balanced (mean 0.5 → zero variance), so
    /// it degenerates to 0 like a flat block. Pinned: concentric > 0.4, flat == 0,
    /// edge ~0.
    @Test func radialAutocorrelationSeparatesConcentricFromFlatAndEdge() {
        let side = 24
        let c = Double(side - 1) / 2.0
        var rings = [Float](repeating: 0, count: side * side)
        var edge = [Float](repeating: 0, count: side * side)
        let flat = [Float](repeating: 0.5, count: side * side)
        for y in 0..<side {
            for x in 0..<side {
                let dx = Double(x) - c, dy = Double(y) - c
                let r = (dx * dx + dy * dy).squareRoot()
                rings[y * side + x] = Int(r / 3.0) % 2 == 0 ? 1.0 : 0.0
                edge[y * side + x] = x < side / 2 ? 0.0 : 1.0
            }
        }
        func peak(_ b: [Float]) -> Double {
            BasisAugmentation.radialAutocorrelationPeak(
                BasisAugmentation.radialProfile(b, width: side, height: side))
        }
        let concentric = peak(rings)
        let flatPeak = peak(flat)
        let edgePeak = peak(edge)
        #expect(concentric > 0.4, "concentric autocorr peak should be strong, got \(concentric)")
        #expect(flatPeak == 0, "flat radial profile is degenerate → 0, got \(flatPeak)")
        #expect(edgePeak < 1e-9, "single-edge radial profile is balanced → ~0, got \(edgePeak)")
        #expect(concentric > edgePeak)
    }

    /// Augmented score = `w·rank(residual) + (1−w)·mean(rank(d_orient), rank(d_radial))`,
    /// ranks population-relative (average-rank ties). Hand-computed at w=0.5:
    ///   residual [10,20,30,40]   → ranks [1,2,3,4]
    ///   d_orient [0.4,0.3,0.2,0.1] → ranks [4,3,2,1]
    ///   d_radial [0.1,0.2,0.3,0.4] → ranks [1,2,3,4]
    ///   mean(rank d_orient, rank d_radial) = [2.5,2.5,2.5,2.5]
    ///   0.5·[1,2,3,4] + 0.5·[2.5,2.5,2.5,2.5] = [1.75,2.25,2.75,3.25]
    @Test func augmentedScoreRankMixMatchesHandComputed() {
        let residual: [Double] = [10, 20, 30, 40]
        let dOrient: [Double] = [0.4, 0.3, 0.2, 0.1]
        let dRadial: [Double] = [0.1, 0.2, 0.3, 0.4]
        let score = BasisAugmentation.augmentedScore(
            residual: residual, dOrient: dOrient, dRadial: dRadial, w: 0.5)
        #expect(score == [1.75, 2.25, 2.75, 3.25], "augmented rank-mix off: \(score)")
    }

    // MARK: - Analysis core (4 oracles + consensus × battery × pooled Spearman)

    /// The parser-agnostic `analyze` core computes, for all three oracles, finite
    /// pooled ρ in [−1, 1], plus finite per-fixture ρ over the 5-fixture battery.
    /// Does NOT assert ρ magnitudes/signs (the controller judges those).
    @Test func analyzeComputesFinitePooledSpearmanForFourOracles() throws {
        // 64px @ 8 cols → 8px blocks, below the 24px oracle footprint; this test
        // exercises the analysis plumbing, not native validity, so it uses the
        // exploratory escape hatch (the oracle-native guard is pinned separately).
        let analysis = try ShapeResidualCommand.analyze(
            columns: 8, fixtureSize: 64, allowUpsampledBlocks: true)

        // Five fixtures, expected ids in battery order.
        #expect(analysis.fixtures.count == 5)
        #expect(analysis.fixtures.map(\.id) == ["checker", "diagonal", "radial", "strokes", "mixedFrequency"])

        // Pooled ρ for every oracle is finite and in range.
        for rho in [
            analysis.pooledRhoSSIMFull, analysis.pooledRhoSSIMStructure,
            analysis.pooledRhoGMSD, analysis.pooledRhoHaarPSI,
        ] {
            #expect(rho.isFinite, "pooled ρ must be finite, got \(rho)")
            #expect(rho >= -1.0 && rho <= 1.0, "pooled ρ out of [−1,1]: \(rho)")
        }

        // Per-fixture ρ for every oracle is finite and in range too.
        for f in analysis.fixtures {
            for rho in [f.rhoSSIMFull, f.rhoSSIMStructure, f.rhoGMSD, f.rhoHaarPSI] {
                #expect(rho.isFinite, "\(f.id) ρ must be finite, got \(rho)")
                #expect(rho >= -1.0 && rho <= 1.0, "\(f.id) ρ out of [−1,1]: \(rho)")
            }
        }

        // Cell-count bookkeeping. Each fixture's rows == its grid size; the
        // total rows == totalCells; pooled included == sum of per-fixture
        // included; and every cell is finite (logPolar emits no NaN/inf, the
        // oracles are finite), so included == total and excluded == 0.
        var sumRows = 0
        var sumIncluded = 0
        var nonFinite = 0
        for f in analysis.fixtures {
            #expect(f.rows.count == f.gridRows * f.gridColumns, "\(f.id) row count")
            sumRows += f.rows.count
            sumIncluded += f.includedCells
            nonFinite +=
                f.rows.filter {
                    !$0.residual.isFinite || !$0.ssimFull.isFinite
                        || !$0.ssimStructure.isFinite || !$0.gmsd.isFinite
                        || !$0.haarpsi.isFinite
                }.count
        }
        #expect(sumRows == analysis.totalCells)
        #expect(analysis.includedCells == sumIncluded)
        #expect(analysis.includedCells == analysis.totalCells - nonFinite)
        #expect(analysis.includedCells + analysis.excludedCells == analysis.totalCells)
        #expect(nonFinite == 0, "battery should yield no non-finite cells, got \(nonFinite)")
    }

    /// Phase 6 wiring: every cell carries finite, non-negative d_orient/d_radial,
    /// and `analyze` reports a finite augmented ρ(·, consensus) in [−1,1] for each
    /// pre-registered mix — per fixture, per pool, and pooled.
    @Test func analyzeReportsAugmentedRhosAndBasisColumns() throws {
        let analysis = try ShapeResidualCommand.analyze(
            columns: 8, fixtureSize: 64, allowUpsampledBlocks: true)
        for f in analysis.fixtures {
            for r in f.rows {
                #expect(r.dOrient.isFinite && r.dOrient >= 0, "\(f.id) d_orient: \(r.dOrient)")
                #expect(r.dRadial.isFinite && r.dRadial >= 0, "\(f.id) d_radial: \(r.dRadial)")
            }
            #expect(f.augmentedRhos.count == BasisAugmentation.mixes.count)
            for rho in f.augmentedRhos {
                #expect(rho.isFinite && rho >= -1 && rho <= 1, "\(f.id) aug ρ out of range: \(rho)")
            }
        }
        #expect(analysis.pooledAugmentedRhos.count == BasisAugmentation.mixes.count)
        for rho in analysis.pooledAugmentedRhos {
            #expect(rho.isFinite && rho >= -1 && rho <= 1, "pooled aug ρ out of range: \(rho)")
        }
        for p in analysis.pools {
            #expect(p.augmentedRhos.count == BasisAugmentation.mixes.count)
        }
    }

    /// No-downscale invariant: `analyze` picks an oversample that keeps
    /// max(cols,rows)·oversample ≥ the fixture, so the converter never thumbnails —
    /// the residual and the oracle read the SAME pixels. (Regression for PR #31
    /// review comment 3381723610.)
    @Test func analyzeUsesDynamicOversampleToAvoidDownscale() throws {
        // 64px @ 16 cols → 4px blocks; uses the escape hatch because this pins the
        // MATCHER-side no-downscale (oversample) invariant, which is separate from
        // the oracle-native block guard.
        let analysis = try ShapeResidualCommand.analyze(
            columns: 16, fixtureSize: 64, allowUpsampledBlocks: true)
        #expect(analysis.fixtures.count == 5)
        // columns=16, square 64px fixture, .wide tiles → max(cols,rows)=16 → ceil(64/16)=4.
        #expect(analysis.oversample == 4)
        for f in analysis.fixtures {
            let maxPixelSize = max(f.gridColumns, f.gridRows) * analysis.oversample
            #expect(
                maxPixelSize >= 64,
                "\(f.id): max(cols,rows)·oversample \(maxPixelSize) must be ≥ 64"
            )
        }
    }

    /// Pins the original bug AND its fix: the default oversample=2 WOULD downscale
    /// the 256px fixtures at columns=80 (160 < 256); the chosen oversample=4 does
    /// not (320 ≥ 256). And the dynamic chooser is downscale-free across the
    /// research note's column sweep. (PR #31 review comment 3381723610.)
    @Test func wouldDownscalePredicatePinsTheBugAndFix() {
        #expect(ShapeResidualCommand.wouldDownscale(columns: 80, fixtureSide: 256, oversample: 2))
        #expect(!ShapeResidualCommand.wouldDownscale(columns: 80, fixtureSide: 256, oversample: 4))
        for columns in [24, 32, 48, 64, 80, 96, 128] {
            let os = ShapeResidualCommand.noDownscaleOversample(columns: columns)
            #expect(
                !ShapeResidualCommand.wouldDownscale(columns: columns, fixtureSide: 256, oversample: os),
                "columns=\(columns) oversample=\(os) should not downscale"
            )
        }
    }

    /// `--fixture-size` scales the battery self-similarly: every fixture renders
    /// at the requested native side, and absolute pixel periods scale with it
    /// (checker's 32px period at 256 → 64px at 512). This is what lets a source
    /// block reach ≥ the 24px oracle footprint at canonical columns.
    @Test func fixtureSizeScalesSelfSimilar() {
        let battery = StructuredFixture.makeBattery(side: 512)
        #expect(battery.count == 5)
        for f in battery {
            #expect(f.width == 512)
            #expect(f.height == 512)
            #expect(f.luma.count == 512 * 512)
        }
        // checker period doubles with side (32px → 64px): (32,0) stays in the
        // first bright cell; (64,0) flips to the dark cell.
        let checker = battery[0]
        #expect(checker.id == "checker")
        let bright = checker.luma[0]  // (0,0)
        #expect(checker.luma[32] == bright)  // still inside the 64px bright cell
        #expect(checker.luma[64] != bright)  // next cell flips
    }

    /// No-downscale invariant holds on an oracle-native fixture: at columns=8 on a
    /// 256px battery, `analyze` picks oversample=32 (ceil(256/8)) so the converter
    /// samples at ≥ native resolution and each source block is ≥24px native.
    @Test func analyzeAtNativeFixtureSizeIsNoDownscale() throws {
        let analysis = try ShapeResidualCommand.analyze(columns: 8, fixtureSize: 256)
        #expect(analysis.fixtures.count == 5)
        #expect(analysis.oversample == 32)
        for f in analysis.fixtures {
            let maxPixelSize = max(f.gridColumns, f.gridRows) * analysis.oversample
            #expect(
                maxPixelSize >= 256,
                "\(f.id): max(cols,rows)·oversample \(maxPixelSize) must be ≥ 256"
            )
        }
    }

    /// The dynamic oversample chooser keeps a 2048px fixture downscale-free at
    /// canonical columns, where the default oversample=2 would massively downscale it.
    @Test func wouldDownscalePinsLargeFixture() {
        let os = ShapeResidualCommand.noDownscaleOversample(columns: 80, fixtureSide: 2048)
        #expect(os == 26)
        #expect(!ShapeResidualCommand.wouldDownscale(columns: 80, fixtureSide: 2048, oversample: os))
        #expect(ShapeResidualCommand.wouldDownscale(columns: 80, fixtureSide: 2048, oversample: 2))
    }

    /// Regression (PR #41 review): a tall non-square corpus PNG must size its oversample
    /// from BOTH dimensions. The `.wide` grid's row count tracks HEIGHT (a 2048×6144 PNG
    /// at columns=80 → 109 rows), so a width-only oversample (26) leaves
    /// `max(cols,rows)·os = 109·26 = 2834 < 6144` and `analyze` would throw
    /// `.converterWouldDownscale` spuriously. Sizing from both dims picks 57
    /// (`109·57 = 6213 ≥ 6144`). The committed corpus is square; this guards the
    /// arbitrary-PNG `--corpus-dir` path.
    @Test func noDownscaleOversampleSizesTallFixtureFromBothDimensions() {
        let heightAware = ShapeResidualCommand.noDownscaleOversample(
            columns: 80, fixtureSide: 2048, fixtureHeight: 6144)
        let widthOnly = ShapeResidualCommand.noDownscaleOversample(columns: 80, fixtureSide: 2048)
        #expect(heightAware == 57)
        #expect(widthOnly == 26)  // square behaviour unchanged (defaults height to side)
        // Height-aware clears the no-downscale invariant on the binding (height) axis…
        #expect(109 * heightAware >= 6144)
        // …whereas the old width-only oversample would not — the bug this fixes.
        #expect(109 * widthOnly < 6144)
    }

    // MARK: - Oracle-native validity guard + escape hatch (ASTSK-31 Phase 3)

    /// At the 256px default, columns=80 makes each source block ~3px native — far
    /// below the 24px oracle footprint — so `analyze` throws
    /// `.oracleBlockWouldUpsample` rather than feeding the oracle upsampled
    /// (invented) pixels. The documented bare `--columns 80` invocation against the
    /// 256px default was always scientifically invalid; this makes it an error.
    @Test func analyzeThrowsWhenOracleBlockWouldUpsample() {
        do {
            _ = try ShapeResidualCommand.analyze(columns: 80, fixtureSize: 256)
            Issue.record("expected analyze to throw .oracleBlockWouldUpsample")
        } catch let error as ShapeResidualError {
            guard case .oracleBlockWouldUpsample = error else {
                Issue.record("expected .oracleBlockWouldUpsample, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    /// The escape hatch runs (no throw) and stamps the manifest EXPLORATORY in both
    /// the summary and the recorded command, so an upsampled-block run can never
    /// masquerade as the decisive run that feeds the pre-registered verdict rule.
    @Test func escapeHatchRunsAndStampsManifestExploratory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("residual-exploratory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        var stderr = ""
        let status = ShapeResidualCommand.run(
            arguments: ShapeResidualArguments(
                outputDirectory: dir.path,
                columns: [8],
                fixtureSize: 64,  // 64px → 8px blocks; would throw WITHOUT the hatch
                allowUpsampledOracleBlocks: true,
                gitShaOverride: "test-sha"
            ),
            standardError: { stderr += $0 }
        )
        #expect(status == .success, "stderr was: \(stderr)")

        let text = try String(
            contentsOf: dir.appendingPathComponent("result.yaml"), encoding: .utf8)
        #expect(text.contains("EXPLORATORY"), "manifest summary not stamped exploratory: \(text)")
        #expect(
            text.contains("--allow-upsampled-oracle-blocks"),
            "manifest command not stamped with the escape-hatch flag")
    }

    /// The static guard predicate: violating 256px configs upsample (width binds —
    /// 256/cols < 24); the native 2048px decisive sweep does not. Blocks partition
    /// the native grid, so the binding (smallest) block is `fixtureSide/gridColumns`
    /// under `.wide` (gridColumns ≥ gridRows for a square fixture).
    @Test func oracleBlockUpsamplePredicatePinsViolatingAndNativeConfigs() {
        // 256px violating configs (real grids: cols=32 → 14 rows; cols=80 → 35 rows).
        #expect(
            ShapeResidualCommand.oracleBlockWouldUpsample(
                fixtureSide: 256, gridRows: 14, gridColumns: 32))
        #expect(
            ShapeResidualCommand.oracleBlockWouldUpsample(
                fixtureSide: 256, gridRows: 35, gridColumns: 80))
        // Native 2048px decisive sweep: width binds (floor(2048/cols)); real rows ≤
        // cols under .wide, so rows=cols is a CONSERVATIVE upper bound on the row
        // count → if this passes, the real (smaller-row) grid passes too.
        for cols in [44, 52, 64, 72, 80] {
            #expect(
                !ShapeResidualCommand.oracleBlockWouldUpsample(
                    fixtureSide: 2048, gridRows: cols, gridColumns: cols),
                "columns=\(cols) @ 2048px must be oracle-native (floor(2048/\(cols))=\(2048 / cols) ≥ 24)"
            )
        }
        // Exact boundary at 2048px: floor(2048/85)=24 ≥ 24 passes; floor(2048/86)=23 trips it.
        #expect(
            !ShapeResidualCommand.oracleBlockWouldUpsample(
                fixtureSide: 2048, gridRows: 80, gridColumns: 85))
        #expect(
            ShapeResidualCommand.oracleBlockWouldUpsample(
                fixtureSide: 2048, gridRows: 80, gridColumns: 86))
    }

    /// Regression (PR #41 review): the oracle-block guard derives the row-block height
    /// from the fixture HEIGHT, not its width. A short-but-wide grid can have native-width
    /// blocks (≥ 24) yet sub-footprint row blocks (< 24); the old width-only square
    /// assumption missed it (it divided the WIDTH by `gridRows`). Latent on the
    /// arbitrary-PNG `--corpus-dir` path (committed corpus is square).
    @Test func oracleBlockGuardUsesHeightForRowBlocks() {
        // width blocks 2400/80 = 30px (native); height blocks 600/40 = 15px (< 24 → upsample).
        #expect(
            ShapeResidualCommand.oracleBlockWouldUpsample(
                fixtureSide: 2400, gridRows: 40, gridColumns: 80, fixtureHeight: 600))
        // Width-only (square) mis-reads the row block as 2400/40 = 60px and misses it.
        #expect(
            !ShapeResidualCommand.oracleBlockWouldUpsample(
                fixtureSide: 2400, gridRows: 40, gridColumns: 80))
    }

    // MARK: - Battery composition: glyphSheet + real loader + selection (ASTSK-31 Phase 5)

    /// `glyphSheet` is a deterministic 2048px line-art fixture rendered from the
    /// same "Courier" Core Text path the matcher's vectors come from. Rebuilding
    /// it yields byte-identical luma; it carries deep ink AND near-flat margin
    /// blocks (so the oracle has range and the flat-vs-flat branch is exercised),
    /// and it is tagged the line-art pool (excluded from the natural pool).
    @Test func glyphSheetFixtureIsDeterministicWithInkAndFlatBlocks() {
        let a = GlyphSheetFixture.make(side: 2048)
        let b = GlyphSheetFixture.make(side: 2048)
        #expect(a.luma == b.luma, "glyphSheet must be deterministic")
        #expect(a.id == "glyphSheet")
        #expect(a.pool == .lineArt)
        #expect(a.width == 2048 && a.height == 2048, "glyphSheet is \(a.width)×\(a.height)")
        #expect(a.luma.count == 2048 * 2048)
        // Ink present (deep dark text) AND background present (bright margin).
        #expect(a.luma.min()! < 0.2, "no deep ink (min luma \(a.luma.min()!))")
        #expect(a.luma.max()! > 0.8, "no bright background (max luma \(a.luma.max()!))")
        // At a coarse grid there is both a near-flat margin block and an inked,
        // high-variance text block.
        func variance(_ v: [Float]) -> Double {
            let mean = v.reduce(0.0) { $0 + Double($1) } / Double(v.count)
            return v.reduce(0.0) { $0 + (Double($1) - mean) * (Double($1) - mean) } / Double(v.count)
        }
        var vmin = Double.greatestFiniteMagnitude
        var vmax = -Double.greatestFiniteMagnitude
        let (rows, cols) = (24, 24)
        for r in 0..<rows {
            for c in 0..<cols {
                let block = a.lumaBlock(cellRow: r, cellCol: c, rows: rows, cols: cols)
                let v = variance(block.luma)
                vmin = min(vmin, v)
                vmax = max(vmax, v)
            }
        }
        #expect(vmin < 1e-4, "no near-flat block (min block variance \(vmin))")
        #expect(vmax > 1e-2, "no high-variance inked block (max block variance \(vmax))")
    }

    /// The `RealFixture` loader resolves the committed `nasa-structure-v1` corpus
    /// (default path via the package-root walk-up), loads each PNG at native size
    /// with no resampling, ids = file stems in sorted order, tagged the natural
    /// pool, and is deterministic (load twice → identical luma).
    @Test func realFixtureLoaderResolvesCorpusWithStemIDsAt2048() throws {
        // Explicit path (robust to the runner CWD) and the default (nil) walk-up
        // must agree on the committed corpus.
        let assets = try Self.structureCorpusAssetsDir()
        let explicit = try RealFixture.load(corpusDirectory: assets.path)
        let byDefault = try RealFixture.load(corpusDirectory: nil)
        #expect(explicit.map(\.id) == byDefault.map(\.id), "default walk-up must match explicit path")

        #expect(explicit.count == 3)
        #expect(explicit.map(\.id) == ["earth-limb-sunrise", "phoenix-night-grid", "vavilov-crater"])
        for f in explicit {
            #expect(f.pool == .natural, "\(f.id) must be the natural pool")
            #expect(f.width == 2048 && f.height == 2048, "\(f.id) is \(f.width)×\(f.height)")
            #expect(f.luma.count == 2048 * 2048)
        }
        // Deterministic: reload and compare the first fixture's luma byte-for-byte.
        let reload = try RealFixture.load(corpusDirectory: assets.path)
        #expect(reload[0].luma == explicit[0].luma, "loader must be deterministic")
    }

    /// A missing corpus directory throws the dedicated `.corpusAssetUnreadable`
    /// rather than silently yielding an empty natural pool.
    @Test func realFixtureLoaderThrowsCorpusAssetUnreadableForMissingDirectory() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-corpus-\(UUID().uuidString)/assets")
        do {
            _ = try RealFixture.load(corpusDirectory: missing.path)
            Issue.record("expected RealFixture.load to throw .corpusAssetUnreadable")
        } catch let error as ShapeResidualError {
            guard case .corpusAssetUnreadable = error else {
                Issue.record("expected .corpusAssetUnreadable, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    /// `--battery` selects the fixture composition in a documented, deterministic
    /// order: `synthetic` = the 5 structured fixtures (synthetic pool); `real` =
    /// glyphSheet (line-art) + the 3 natural fixtures (sorted); `all` = synthetic
    /// then glyphSheet then natural. Pool labels follow the source.
    @Test func batterySelectionComposesDeterministicOrderWithPools() throws {
        let assets = try Self.structureCorpusAssetsDir()

        let synthetic = try ShapeResidualCommand.makeBattery(
            selection: .synthetic, side: 2048, corpusDirectory: assets.path)
        #expect(synthetic.map(\.id) == ["checker", "diagonal", "radial", "strokes", "mixedFrequency"])
        #expect(synthetic.allSatisfy { $0.pool == .synthetic })

        let real = try ShapeResidualCommand.makeBattery(
            selection: .real, side: 2048, corpusDirectory: assets.path)
        #expect(
            real.map(\.id) == ["glyphSheet", "earth-limb-sunrise", "phoenix-night-grid", "vavilov-crater"])
        #expect(real[0].pool == .lineArt)
        #expect(real.dropFirst().allSatisfy { $0.pool == .natural })

        let all = try ShapeResidualCommand.makeBattery(
            selection: .all, side: 2048, corpusDirectory: assets.path)
        #expect(
            all.map(\.id) == [
                "checker", "diagonal", "radial", "strokes", "mixedFrequency",
                "glyphSheet", "earth-limb-sunrise", "phoenix-night-grid", "vavilov-crater",
            ])
        // all == synthetic ++ real (same order, same pools).
        #expect(all.map(\.id) == synthetic.map(\.id) + real.map(\.id))
    }

    /// The default battery is `synthetic` (5 fixtures, one synthetic pool) — the
    /// pre-Phase-5 behaviour is unchanged when `--battery` is omitted.
    @Test func analyzeDefaultsToSyntheticBatteryWithOnePool() throws {
        let analysis = try ShapeResidualCommand.analyze(columns: 8, fixtureSize: 256)
        #expect(analysis.fixtures.count == 5)
        #expect(analysis.fixtures.allSatisfy { $0.pool == .synthetic })
        #expect(analysis.pools.map(\.pool) == [.synthetic])
        #expect(analysis.pools[0].includedCells == analysis.includedCells)
    }

    /// `--battery all` runs every pool and reports per-pool pooled ρ. Uses a small
    /// column count so both the 256px synthetic/line-art fixtures and the 2048px
    /// real fixtures stay oracle-native without the escape hatch, keeping the
    /// unit-suite cost bounded.
    @Test func analyzeAllBatteryReportsPerPoolStats() throws {
        let assets = try Self.structureCorpusAssetsDir()
        let analysis = try ShapeResidualCommand.analyze(
            columns: 8, fixtureSize: 256, battery: .all, corpusDirectory: assets.path)
        #expect(analysis.fixtures.count == 9)
        #expect(analysis.pools.map(\.pool) == [.synthetic, .natural, .lineArt])
        for pool in analysis.pools {
            #expect(pool.includedCells > 0, "\(pool.pool) had no included cells")
            for rho in [pool.rhoGMSD, pool.rhoSSIMStructure, pool.rhoHaarPSI, pool.rhoConsensus] {
                #expect(rho.isFinite, "\(pool.pool) ρ must be finite, got \(rho)")
                #expect(rho >= -1.0 && rho <= 1.0, "\(pool.pool) ρ out of range: \(rho)")
            }
        }
        // Per-pool included cells partition the grand pooled population.
        #expect(analysis.pools.reduce(0) { $0 + $1.includedCells } == analysis.includedCells)
    }

    // MARK: - Column sweep + spearman_summary.csv (ASTSK-31 Phase 7)

    /// Canonical heatmap column = 80 when swept, else the max swept column.
    @Test func canonicalColumnPrefers80ThenMax() {
        #expect(ShapeResidualCommand.canonicalColumn([44, 52, 64, 72, 80]) == 80)
        #expect(ShapeResidualCommand.canonicalColumn([8, 10]) == 10)
        #expect(ShapeResidualCommand.canonicalColumn([64]) == 64)
    }

    /// Manifest `datasets` references the committed corpus for any natural-pool
    /// battery, and is empty for the synthetic-only battery.
    @Test func datasetsListedOnlyForNaturalPoolBatteries() {
        #expect(ShapeResidualCommand.manifestDatasets(battery: .synthetic, corpusDirectory: nil).isEmpty)
        #expect(
            ShapeResidualCommand.manifestDatasets(battery: .real, corpusDirectory: nil)
                == [ShapeResidualCommand.naturalCorpusDataset])
        #expect(
            ShapeResidualCommand.manifestDatasets(battery: .all, corpusDirectory: nil)
                == [ShapeResidualCommand.naturalCorpusDataset])
    }

    /// A repeatable `--columns` sweep prepends a `columns` per-cell CSV column,
    /// writes a `spearman_summary.csv` with one row per (battery, pool/fixture,
    /// columns, oracle) — including the consensus and three augmentation mixes —
    /// carries included/excluded counts, emits heatmaps at the canonical column
    /// only, and records the full invocation + summary CSV in the manifest. Uses
    /// natively-valid 256px columns {8,10} (32 / 25px blocks ≥ 24px footprint), no
    /// escape hatch.
    @Test func sweepWritesLeadingColumnsAndPerColumnSummary() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("residual-sweep-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        var stderr = ""
        let status = ShapeResidualCommand.run(
            arguments: ShapeResidualArguments(
                outputDirectory: dir.path,
                columns: [8, 10],
                gitShaOverride: "test-sha"
            ),
            standardError: { stderr += $0 }
        )
        #expect(status == .success, "stderr was: \(stderr)")

        // Per-cell CSV: leading `columns` column, values span the swept set.
        let csv = try String(
            contentsOf: dir.appendingPathComponent("shape_residual.csv"), encoding: .utf8)
        let csvLines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(
            csvLines.first
                == "columns,fixture_id,row,col,character,residual,ssim_full,ssim_structure,gmsd,haarpsi,d_orient,d_radial"
        )
        let csvCols = Set(
            csvLines.dropFirst().map {
                $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)[0]
            })
        #expect(csvCols == Set(["8", "10"]))

        // spearman_summary.csv: header + the per-(fixture|pool, column, oracle) grid.
        let summaryURL = dir.appendingPathComponent("spearman_summary.csv")
        #expect(FileManager.default.fileExists(atPath: summaryURL.path))
        let summary = try String(contentsOf: summaryURL, encoding: .utf8)
        let sLines = summary.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(
            sLines.first
                == "battery,pool,fixture,columns,oracle,rho,included_cells,excluded_cells,"
                + "cell_width,cell_height,reachable_bins")
        let rows = sLines.dropFirst().map {
            $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        }
        // 5 synthetic fixtures + 1 pooled row, × 8 oracles, × 2 columns = 96 rows.
        #expect(rows.count == 96, "summary rows: \(rows.count)")
        // Oracle set includes the four oracles, the consensus, and the three mixes.
        let oracles = Set(rows.map { $0[4] })
        #expect(oracles.isSuperset(of: ["ssim_full", "ssim_structure", "gmsd", "haarpsi"]))
        #expect(oracles.isSuperset(of: ["consensus", "aug_w0.25", "aug_w0.5", "aug_w0.75"]))
        // Pooled rows use fixture=POOLED with the synthetic pool label (8 oracles × 2 cols).
        let pooledRows = rows.filter { $0[2] == "POOLED" }
        #expect(pooledRows.count == 16, "pooled rows: \(pooledRows.count)")
        #expect(pooledRows.allSatisfy { $0[1] == "synthetic" })
        // Every row carries the battery, a swept column, and integer counts.
        #expect(rows.allSatisfy { $0[0] == "synthetic" })
        #expect(rows.allSatisfy { ["8", "10"].contains($0[3]) })
        #expect(rows.allSatisfy { Int($0[6]) != nil && Int($0[7]) != nil })
        // Every row is the full width of the header and carries the regime it
        // was measured at (ASKI-29 AC#2) — the synthetic battery is one footprint
        // throughout, so no row falls back to `mixed`.
        #expect(rows.allSatisfy { $0.count == ShapeResidualCommand.summaryCsvHeader.count })
        #expect(
            rows.allSatisfy {
                (Int($0[8]) ?? 0) > 0 && (Int($0[9]) ?? 0) > 0
                    && (1...60).contains(Int($0[10]) ?? 0)
            }, "a summary row is missing its sampling regime")

        // Heatmaps at the canonical column only (max swept = 10): 5 fixtures, no
        // column suffix, written once.
        let heatmaps = (try FileManager.default.contentsOfDirectory(atPath: dir.path)).filter {
            $0.hasPrefix("shape_residual_heatmap_") && $0.hasSuffix(".png")
        }
        #expect(Set(heatmaps).count == 5, "expected 5 heatmaps, got \(heatmaps)")

        // Manifest: outputs = per-cell CSV + summary CSV + 5 heatmaps; datasets empty
        // (synthetic); command records both swept columns.
        let manifestText = try String(
            contentsOf: dir.appendingPathComponent("result.yaml"), encoding: .utf8)
        let manifest = try ResultManifest.from(try FrontMatterParser.parse(manifestText))
        #expect(manifest.outputs.first == "shape_residual.csv")
        #expect(manifest.outputs.contains("spearman_summary.csv"))
        #expect(manifest.outputs.filter { $0.hasPrefix("shape_residual_heatmap_") }.count == 5)
        #expect(manifest.datasets.isEmpty)
        #expect(manifest.command?.contains("--columns 8") == true)
        #expect(manifest.command?.contains("--columns 10") == true)
    }

    /// Package-root walk-up to the committed structure corpus assets dir (mirrors
    /// `ResearchRegistryTests.packageRoot()`), used to feed the loader an explicit
    /// path independent of the test runner's working directory.
    private static func structureCorpusAssetsDir() throws -> URL {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appending(path: "Package.swift").path) {
                return url.appending(path: "docs/Research/Corpus/nasa-structure-v1/assets")
            }
            url.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
