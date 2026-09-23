import CoreGraphics
import Foundation
import Testing

@_spi(AskiResearch) @testable import Aski

/// ASKI-25, ASKI-65. Two structural properties of the sampling lattice, both of
/// which used to fail silently:
///
/// 1. The sampled raster is an exact multiple of the grid on both axes, so the
///    origin-anchored walk tiles it with nothing left over and no source row or
///    column goes unread. ASKI-25 documented the opposite contract — a floored
///    pitch against the thumbnail's own size, leaving a bottom/right remainder
///    of up to 10% of image height unsampled; ASKI-65 removed the remainder by
///    drawing the thumbnail into a lattice-sized raster instead.
/// 2. A cell footprint with a one-pixel axis admits no pixel through
///    `ShapeContext.histogram60`'s radius gate, so the descriptor is all zeros
///    and equidistant from every glyph. That used to resolve to the space
///    glyph for the whole image; it now takes a brightness-only pick.
///
/// Evidence and measured numbers: `docs/Research/2026-08-19-sampling-lattice-support-collapse.md` §5.
@Suite struct SamplingLatticeContractTests {

    private func converter(oversample: Int) -> ASCIIConverter<StandardCharacterSet, BuiltInPalette> {
        ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.monochrome,
            colorSpace: .sRGB,
            oversample: oversample
        )
    }

    // MARK: - AC#1 — the sampled raster is an exact multiple of the grid

    /// The contract, stated as arithmetic. The cell pitch stays the floored
    /// integer quotient — uniform across the grid, so the cell-height parity
    /// split that killed the fractional lattice cannot fire — but the raster is
    /// drawn at exactly `columns*cellWidth × rows*cellHeight`, so the
    /// origin-anchored walk covers all of it and both drops are zero. A change
    /// that went back to sampling the thumbnail at its own decoded size, or one
    /// that moved the sampled origin off `(0, 0)`, would break this.
    @Test(arguments: [
        (1024, 1024, 80, 2),
        (1024, 1024, 80, 4),
        (1024, 1024, 80, 16),
        (1024, 1024, 40, 2),
        (1536, 512, 80, 2),
        (512, 1536, 80, 2),
        (975, 1280, 60, 4),
    ])
    func latticeIsAnExactMultipleOfTheGrid(
        width: Int, height: Int, columns: Int, oversample: Int
    ) throws {
        let source = TestImages.structuredPortraitProxy(width: width, height: height)
        let geometry = try #require(
            converter(oversample: oversample).samplingGeometry(source, columns: columns))

        let arm = "\(width)x\(height) c\(columns) o\(oversample)"
        #expect(
            geometry.columns * geometry.cellWidth == geometry.thumbnailWidth,
            "\(arm): lattice width \(geometry.thumbnailWidth) is not \(geometry.columns) whole cells"
        )
        #expect(
            geometry.rows * geometry.cellHeight == geometry.thumbnailHeight,
            "\(arm): lattice height \(geometry.thumbnailHeight) is not \(geometry.rows) whole cells"
        )
        #expect(geometry.droppedX == 0, "\(arm): droppedX \(geometry.droppedX) must be zero")
        #expect(geometry.droppedY == 0, "\(arm): droppedY \(geometry.droppedY) must be zero")
        #expect(geometry.cellWidth > 0)
        #expect(geometry.cellHeight > 0)
    }

    /// The shipping arm the ASKI-25 research note measured — 1024² square,
    /// `columns: 80`, `oversample: 2`. The pitch is unchanged at 2×4; what
    /// changed is that the 16 thumbnail rows that used to fall off the bottom
    /// are now folded into the 144-row lattice instead of being dropped.
    @Test func shippingArmDropsNothing() throws {
        let source = TestImages.structuredPortraitProxy(width: 1024, height: 1024)
        let geometry = try #require(converter(oversample: 2).samplingGeometry(source, columns: 80))

        #expect(geometry.cellWidth == 2)
        #expect(geometry.cellHeight == 4)
        #expect(geometry.thumbnailWidth == 160)
        #expect(geometry.thumbnailHeight == 144)
        #expect(geometry.droppedX == 0)
        #expect(geometry.droppedY == 0)
        #expect(geometry.rows * geometry.cellHeight == geometry.thumbnailHeight)
        #expect(geometry.columns * geometry.cellWidth == geometry.thumbnailWidth)
    }

    /// The reported defect (issue #36): a bright band occupying the last grid
    /// row's worth of source height must reach the bottom grid row. Under the
    /// old origin-anchored truncation the 3072×2048 / `columns: 384` arm
    /// dropped ~9% of the image height off the bottom — several whole grid rows
    /// — so the band was never sampled and the bottom row read as dark, while
    /// the renderer still drew the grid over the full source aspect.
    @Test func bottomSourceBandReachesTheBottomGridRow() throws {
        let width = 3072
        let height = 2048
        let columns = 384
        let sut = converter(oversample: 2)

        // Resolve the grid first: the band is sized to exactly the last grid
        // row's share of source height, so a single dropped row hides it.
        let probe = TestImages.structuredPortraitProxy(width: width, height: height)
        let geometry = try #require(sut.samplingGeometry(probe, columns: columns))
        let rows = geometry.rows
        let bandTop = (height * (rows - 1)) / rows

        let source = TestImages.bottomBandProxy(
            width: width, height: height, bandTop: bandTop)
        let grid = sut.convert(source, columns: columns)
        #expect(grid.cells.count == rows)

        let bottom = try #require(grid.cells.last)
        let above = grid.cells[rows - 2]
        let bottomMean = bottom.reduce(Float(0)) { $0 + $1.brightness } / Float(bottom.count)
        let aboveMean = above.reduce(Float(0)) { $0 + $1.brightness } / Float(above.count)

        #expect(
            bottomMean > 0.8,
            "the bottom grid row must carry the bright band, got mean brightness \(bottomMean)")
        #expect(
            aboveMean < 0.4,
            "the row above the band must stay dark, got mean brightness \(aboveMean)")
    }

    // MARK: - AC#2/#3 — the degenerate footprint is handled, not silently blank

    /// The reported degenerate case, and its whole neighbourhood: at
    /// `oversample: 1` the thumbnail budget lands the cell pitch on 1×2 for
    /// essentially every source aspect and column count, so *every* cell holds
    /// a zero descriptor. Before ASKI-25 that rendered a full-size grid of
    /// nothing but spaces. The contract now has exactly two admissible
    /// outcomes: the geometry is refused outright (an empty grid the caller can
    /// detect — 975×1280 at `columns: 120` resolves `cellWidth == 0` and bails),
    /// or the grid paints glyphs picked on brightness. A populated all-space
    /// grid is the failure.
    @Test(arguments: [
        (975, 1280, 120),  // the reported case: refused geometry
        (975, 1280, 80),  // same source, 1x2 pitch: must paint
        (1024, 1024, 80),
        (512, 1536, 80),
        (1536, 512, 80),
    ])
    func oversampleOneIsNeverSilentlyBlank(width: Int, height: Int, columns: Int) {
        let source = TestImages.structuredPortraitProxy(width: width, height: height)
        let grid = converter(oversample: 1).convert(source, columns: columns)
        let cells = grid.cells.flatMap { $0 }

        guard !cells.isEmpty else { return }  // refused geometry: an explicit empty grid.
        let painted = cells.filter { $0.character != " " }
        #expect(
            !painted.isEmpty,
            "\(width)x\(height) c\(columns) o1: a populated grid must resolve real glyphs, not \(cells.count) spaces"
        )
    }

    /// Directly exercises the fallback trigger, independent of any thumbnail
    /// arithmetic: a footprint whose narrow axis is one pixel reaches zero bins
    /// in `histogram60`, and the context flag that gates the fallback is a pure
    /// function of that footprint. `min(cellWidth, cellHeight) > 1` is the
    /// exact complement of `histogram60`'s own `minDimension > 1` early return.
    @Test func zeroSupportFootprintsAreDetectedFromGeometryAlone() {
        for (width, height) in [(1, 1), (1, 8), (2, 1), (8, 1)] {
            let saturated = [Float](repeating: 1, count: width * height)
            let histogram = ShapeContext.histogram60(saturated, width: width, height: height)
            #expect(
                histogram.allSatisfy { $0 == 0 },
                "\(width)x\(height) should admit nothing through the radius gate")
            #expect(!(min(width, height) > 1))
        }
        // The complement: the shipping footprint does carry support, so the
        // fallback must not fire there and the frozen preset is untouched.
        for (width, height) in [(2, 2), (2, 4), (8, 17)] {
            let saturated = [Float](repeating: 1, count: width * height)
            let histogram = ShapeContext.histogram60(saturated, width: width, height: height)
            #expect(histogram.contains { $0 > 0 }, "\(width)x\(height) should reach bins")
            #expect(min(width, height) > 1)
        }
    }

    // MARK: - The degenerate fallback's own contract

    private func degenerateContext(_ options: RenderingOptions = .default) -> ConversionContext {
        ConversionContext(
            pixels: [UInt8](repeating: 255, count: 4 * 1 * 8),
            pixelWidth: 1,
            pixelHeight: 8,
            cellWidth: 1,
            cellHeight: 8,
            columns: 1,
            rows: 1,
            options: ResolvedRenderingOptions(options),
            colorSpace: .sRGB
        )
    }

    private func stats(_ adjustedL: Float) -> CellStats {
        CellStats(
            displayColor: SIMD3<Float>(repeating: adjustedL),
            alpha: 1,
            adjustedL: adjustedL,
            rawL: adjustedL
        )
    }

    /// With a degenerate footprint the log-polar kernel ranks on tone alone, so
    /// a bright cell and a dark cell must resolve to different glyphs. Under
    /// the old all-zero-descriptor path both resolved to the same glyph — the
    /// space, the set's only zero-norm reference — regardless of tone.
    @Test func degenerateFootprintPicksOnTone() {
        let kernel = LogPolarKernel(characterSet: StandardCharacterSet.standard)
        let context = degenerateContext()
        #expect(context.cellSupportsShapeDescriptor == false)

        let coord = CellCoord(column: 0, row: 0)
        let bright = kernel.score(cell: coord, stats: stats(0.95), in: context)
        let dark = kernel.score(cell: coord, stats: stats(0.05), in: context)
        #expect(bright != dark)
    }

    /// Glyph cycling only lets a cell participate when it reports at least 2
    /// distinct candidates (`ScheduleBuilder`, `distinctCount >= 2`). A
    /// degenerate cell that surfaced only its winner would silently disable
    /// cycling everywhere, so the fallback must fill the caller's `resultLimit`
    /// with the rest of the tone ranking — and `ranked[0]` must still be the
    /// glyph `score` picks, so the two paths cannot disagree.
    @Test func degenerateFallbackReturnsRankedCandidatesForCycling() {
        let kernel = LogPolarKernel(characterSet: StandardCharacterSet.standard)
        let context = degenerateContext()
        let coord = CellCoord(column: 0, row: 0)
        let cellStats = stats(0.6)

        for resultLimit in [1, 2, 6] {
            let match = kernel.match(
                cell: coord, stats: cellStats, in: context, resultLimit: resultLimit)
            #expect(
                match.rankedIndices.count == resultLimit,
                "resultLimit \(resultLimit) produced \(match.rankedIndices.count) candidates")
            #expect(Set(match.rankedIndices).count == match.rankedIndices.count, "duplicates ranked")
            #expect(match.rankedIndices.first == match.winnerIndex)
            #expect(
                match.winnerCharacter == kernel.score(cell: coord, stats: cellStats, in: context),
                "ranked path disagrees with score at resultLimit \(resultLimit)")
        }
    }

}
