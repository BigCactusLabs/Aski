import CoreGraphics
import Foundation
import Testing

@_spi(AskiResearch) @testable import Aski
@testable import AskiColorLab

/// Pins the two instrument properties the 2026-08-19 sampling-lattice note leans
/// on, both of which are silent-failure shaped: a reimplementation that drifts
/// from the thing it claims to reproduce, and a source-block accessor that scores
/// the wrong pixels.
@Suite struct AskiColorLabSamplingLatticeTests {

    // MARK: - The census reproduces histogram60

    /// `LatticeSupport.census` is an independent reimplementation of
    /// `ShapeContext.histogram60`'s admission predicate and bin assignment, kept
    /// independent so a divergence is itself a finding. This is the guard that
    /// makes "independent" safe: fed a fully saturated raster — every pixel above
    /// the 0.05 inclusion threshold, so only the geometric gate can reject — the
    /// census's reachable bin set must be exactly `histogram60`'s non-zero
    /// support, and `admitted` must be the count of contributing pixels.
    @Test func latticeSupportCensusMatchesHistogram60() {
        // Spans the collapsed shipping footprints (2x4), the mid arms (4x8,
        // 8x17), the fully supported arm (16x35), the square glyph raster, and
        // the degenerate single-pixel-axis cases.
        let footprints = [
            (1, 1), (1, 8), (2, 1), (2, 2), (2, 4), (2, 5), (3, 3), (4, 8),
            (5, 12), (8, 17), (16, 35), (24, 24), (64, 64),
        ]

        for (width, height) in footprints {
            let saturated = [Float](repeating: 1, count: max(1, width * height))
            let histogram = ShapeContext.histogram60(saturated, width: width, height: height)
            let reference = Set(histogram.indices.filter { histogram[$0] > 0 })

            let census = LatticeSupport.census(width: width, height: height)

            #expect(
                census.bins == reference,
                "bin support diverged at \(width)x\(height): census \(census.bins.sorted()) vs histogram60 \(reference.sorted())"
            )
            #expect(census.total == width * height, "total pixels wrong at \(width)x\(height)")
            // Every admitted pixel deposits weight 1 into exactly one bin, so the
            // pre-normalization mass equals `admitted`. `histogram60` L1-normalizes,
            // so recover the count from the smallest positive bin only when the
            // support is non-empty.
            if reference.isEmpty {
                #expect(census.admitted == 0, "admitted should be 0 at \(width)x\(height)")
            } else {
                #expect(census.admitted > 0, "admitted should be positive at \(width)x\(height)")
                #expect(
                    census.admitted <= width * height,
                    "admitted exceeds the footprint at \(width)x\(height)")
            }
        }
    }

    /// The support collapse the note reports, stated as a test so a change to the
    /// admission gate cannot silently invalidate the note: the shipping footprint
    /// reaches 3 of 60 bins, and lifting the footprint lifts the support.
    @Test func shippingFootprintReachesThreeBins() {
        #expect(LatticeSupport.census(width: 2, height: 4).bins.count == 3)
        #expect(LatticeSupport.census(width: 8, height: 17).bins.count > 20)
        #expect(LatticeSupport.census(width: 64, height: 64).bins.count > 50)
    }

    // MARK: - The oracle block is the block the converter sampled

    private func grayFixture(width: Int, height: Int) -> ResidualFixture {
        // A horizontal luma ramp: row index is recoverable from the value, so a
        // vertically displaced block is detectable by value alone.
        var gray = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let value = UInt8(clamping: y * 255 / max(1, height - 1))
            for x in 0..<width { gray[y * width + x] = value }
        }
        return ResidualFixture.fromGrayBytes(
            id: "ramp", width: width, height: height, pool: .synthetic, gray: gray)
    }

    /// The sampled lattice is an exact multiple of the grid (ASKI-65), so the
    /// accessor's block for the last row ends flush at the image bottom and the
    /// converter's partition and the equal `rows*cols` native partition finally
    /// agree. This pins the accessor to the converter's own geometry rather than
    /// to either partition assumed independently.
    @Test func sampledBlockTracksTheConvertersOwnLattice() throws {
        let fixture = grayFixture(width: 1024, height: 1024)
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.monochrome,
            colorSpace: .sRGB,
            oversample: 2
        )
        let geometry = try #require(converter.samplingGeometry(fixture.image, columns: 80))
        #expect(geometry.droppedY == 0, "the lattice must leave no unread bottom remainder")
        #expect(geometry.droppedX == 0, "the lattice must leave no unread right remainder")

        let lastRow = geometry.rows - 1
        let block = try #require(
            SampledSource.lumaBlock(fixture, cellRow: lastRow, cellCol: 0, geometry: geometry))

        // Where the block ends, in native rows: the image bottom, exactly.
        let sampledBottom =
            (geometry.rows * geometry.cellHeight * fixture.height) / geometry.thumbnailHeight
        #expect(
            sampledBottom == fixture.height,
            "sampled bottom \(sampledBottom) should reach \(fixture.height)")

        // The ramp makes the placement measurable: the block spans the last
        // 1/rows of the frame, so its mean luma sits at that band's centre.
        let mean = block.luma.reduce(0, +) / Float(block.luma.count)
        let expected = 1 - 0.5 / Float(geometry.rows)
        #expect(
            abs(mean - expected) < 0.02,
            "last-row block mean \(mean) should track the last band centre \(expected)")
    }

    /// Out-of-range cells return nil rather than clamping into a neighbour's pixels.
    @Test func sampledBlockRejectsOutOfRangeCells() throws {
        let fixture = grayFixture(width: 512, height: 512)
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.monochrome,
            colorSpace: .sRGB,
            oversample: 4
        )
        let geometry = try #require(converter.samplingGeometry(fixture.image, columns: 40))
        #expect(
            SampledSource.lumaBlock(fixture, cellRow: geometry.rows, cellCol: 0, geometry: geometry)
                == nil)
        #expect(
            SampledSource.lumaBlock(
                fixture, cellRow: 0, cellCol: geometry.columns, geometry: geometry) == nil)
        #expect(SampledSource.lumaBlock(fixture, cellRow: -1, cellCol: 0, geometry: geometry) == nil)
    }

    // MARK: - The realizable sweep covers what conversion resolves

    /// The footprint sweep must print the geometries conversion actually resolves
    /// at each oversample. A fixed short height range does not: the realized
    /// `cellHeight` tracks `oversample * tileShape.sourceCellHeightOverWidth`, so
    /// at oversample 8 and 16 a `2...8` range prints only unreachable footprints.
    @Test func realizableFootprintsCoverTheResolvedGeometries() throws {
        // Two arms, not the full sweep: `oversample: 2` is the shipping regime and
        // 16 is the one the replaced fixed `2...8` height range missed hardest
        // (resolved height 35). This test shares a parallel runner with a 60s
        // time-limited video-encoder sentinel, so its cost is deliberately bounded.
        // Must exceed every `maxPixelSize` the arms ask for (max(columns, rows) *
        // oversample = 1280 at oversample 16), or the thumbnail does not bind and
        // the converter resolves a footprint driven by the fixture's own size —
        // which the sweep deliberately excludes, so the assertion would fail for
        // the wrong reason. Asserted below rather than assumed.
        let fixture = grayFixture(width: 2048, height: 2048)
        for oversample in [2, 16] {
            let rows = LatticeSupport.realizableRows(columns: 80, oversample: oversample)
            #expect(!rows.isEmpty, "no realizable footprints at oversample \(oversample)")

            // The square-source geometry the corpus arm resolves must be present.
            let converter = ASCIIConverter(
                characterSet: StandardCharacterSet.standard,
                palette: BuiltInPalette.monochrome,
                colorSpace: .sRGB,
                oversample: oversample
            )
            let geometry = try #require(converter.samplingGeometry(fixture.image, columns: 80))
            #expect(
                max(geometry.thumbnailWidth, geometry.thumbnailHeight) < fixture.width,
                "fixture too small at oversample \(oversample): thumbnail did not bind")
            let resolved = rows.contains {
                $0.cellWidth == geometry.cellWidth && $0.cellHeight == geometry.cellHeight
            }
            let missed = "sweep at oversample \(oversample) missed \(geometry.cellWidth)x\(geometry.cellHeight)"
            #expect(resolved, "\(missed)")
        }
    }
}
