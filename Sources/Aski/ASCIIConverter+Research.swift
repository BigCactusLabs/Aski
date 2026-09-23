import CoreGraphics

// Research-only reflection on the converter's resolved sampling geometry and on
// the candidate pool the matcher actually saw. Both exist so lab harnesses can
// read what production did instead of re-deriving it — the 2026-08-19 optimality
// gap run first rebuilt the brightness pool by hand and got the polarity
// convention wrong, which is exactly the class of instrument error this avoids.
//
// Neither entry point changes any rendering behavior: `samplingGeometry` runs the
// same preparation `convert` runs and reports it, and `rankedCandidateIndices`
// forwards to the existing ranked path whose winner is `convert`'s pick by
// construction.
extension ASCIIConverter {

    /// The sampling lattice `convert(_:columns:)` would resolve for `image`.
    ///
    /// `cellWidth`/`cellHeight` are the **integer** working-pixel pitch per
    /// cell, and `thumbnailWidth`/`thumbnailHeight` are the size of the raster
    /// the samplers actually read — the *sampling lattice*, which the converter
    /// draws the decoded thumbnail into at exactly `columns*cellWidth ×
    /// rows*cellHeight` (ASKI-65). It is therefore an exact multiple of the
    /// grid on both axes: `columns * cellWidth == thumbnailWidth`,
    /// `rows * cellHeight == thumbnailHeight`, and `droppedX`/`droppedY` are
    /// zero. The lattice covers the whole source, so an instrument may
    /// re-partition the native image into equal `rows × columns` blocks — but
    /// the pitch is still the floored quotient, so it must scale through this
    /// lattice rather than assume the thumbnail's own decoded size.
    ///
    /// Returns `nil` on the same branches where `convert` returns an empty grid.
    @_spi(AskiResearch)
    public func samplingGeometry(
        _ image: CGImage,
        columns: Int
    ) -> SamplingGeometry? {
        guard columns > 0, let preparation = prepareConversion(image, columns: columns, mask: nil)
        else { return nil }
        let context = preparation.context
        return SamplingGeometry(
            columns: context.columns,
            rows: context.rows,
            cellWidth: context.cellWidth,
            cellHeight: context.cellHeight,
            thumbnailWidth: context.pixelWidth,
            thumbnailHeight: context.pixelHeight
        )
    }

    /// The matcher's ranked candidate pool per cell, best-first.
    ///
    /// Element `[row][col]` holds the distinct character-set indices the matcher
    /// ranked for that cell, in its own order; `[row][col][0]` is the character
    /// `convert(_:columns:)` picks. The pool is the brightness pre-filter's
    /// output, so its *length* is the pre-filter width, which
    /// is what a pool-exclusion measurement needs.
    ///
    /// `limit` caps how many ranked entries are reported per cell; the matcher's
    /// own pre-filter width still bounds it. Returns `[]` on the empty branches.
    @_spi(AskiResearch)
    public func rankedCandidateIndices(
        _ image: CGImage,
        columns: Int,
        limit: Int
    ) -> [[[Int]]] {
        guard columns > 0, limit > 0 else { return [] }
        let result = convertWithRankedCandidates(image, columns: columns, candidateStride: limit)
        let rows = result.grid.rows
        let cols = result.grid.columns
        guard rows > 0, cols > 0 else { return [] }

        var out: [[[Int]]] = []
        out.reserveCapacity(rows)
        for row in 0..<rows {
            var rowOut: [[Int]] = []
            rowOut.reserveCapacity(cols)
            for col in 0..<cols {
                let cellIndex = row * cols + col
                let count = Int(result.candidateCounts[cellIndex])
                var cell: [Int] = []
                cell.reserveCapacity(count)
                for position in 0..<count {
                    cell.append(Int(result.candidates[cellIndex * result.candidateStride + position]))
                }
                rowOut.append(cell)
            }
            out.append(rowOut)
        }
        return out
    }

    /// The per-cell **query** the log-polar matcher scores: the 60D shape
    /// descriptor and the tone `stats.adjustedL`, alongside the grid `convert`
    /// produces for the same input.
    ///
    /// This is the ASKI-28/30 prerequisite-0 accessor. The census battery's arms
    /// re-run selection at a different pool width (`ShapeMatching.findBestScored`
    /// with an arbitrary `topK`), under a lab-local tone-weighted score, or with
    /// the shape term removed entirely.
    /// All three take the query as a *parameter*, so a lab that cannot read it
    /// cannot run them at all: `rankedCandidateIndices` above returns the
    /// pre-filter's own output, which caps at the very width those arms vary.
    ///
    /// Behavior-neutral by construction. It runs the same `prepareConversion`
    /// `convert` runs and reports what that preparation implies, exactly as
    /// `samplingGeometry` does; no selection is performed and no rendering path
    /// observes it. `adjustedL` is the same value `convert` writes into
    /// `ASCIICell.brightness`, so the two can be cross-checked by a caller.
    ///
    /// Returns `nil` for non-`logPolar` algorithms — `dotMatrix` has no 60D
    /// query, and reporting a zero vector for it would be
    /// indistinguishable from a genuine all-zero descriptor.
    ///
    /// - Note: When `supportsShapeDescriptor` is `false` (a cell axis is a single
    ///   pixel) the descriptor is the all-zero vector for every cell and
    ///   production bypasses the shape term entirely — see
    ///   `LogPolarKernel.degenerateToneRanking`. The flag is reported rather than
    ///   silently folded in, so an arm cannot mistake that regime for a match.
    @_spi(AskiResearch)
    public func cellQueryDescriptors(
        _ image: CGImage,
        columns: Int
    ) -> CellQueryDescriptors? {
        guard columns > 0, case .logPolar = algorithm else { return nil }
        guard let preparation = prepareConversion(image, columns: columns, mask: nil) else {
            return nil
        }
        let context = preparation.context
        let cols = context.columns
        let rows = context.rows
        guard rows > 0, cols > 0 else { return nil }

        let kernel = LogPolarKernel(glyphBank: glyphBank)
        let lanesPerCell = GlyphBank.lanesPerCharacter
        var lanes: [SIMD4<Float>] = []
        lanes.reserveCapacity(rows * cols * lanesPerCell)
        var adjustedL: [Float] = []
        adjustedL.reserveCapacity(rows * cols)

        for row in 0..<rows {
            for column in 0..<cols {
                let coord = CellCoord(column: column, row: row)
                let stats = context.finalizeColor(source: context.cellSourceStats(at: coord))
                adjustedL.append(stats.adjustedL)
                lanes.append(
                    contentsOf: kernel.researchQueryShapeVector(cell: coord, in: context))
            }
        }

        return CellQueryDescriptors(
            grid: convert(image, columns: columns),
            rows: rows,
            columns: cols,
            lanesPerCell: lanesPerCell,
            lanes: lanes,
            adjustedL: adjustedL,
            supportsShapeDescriptor: context.cellSupportsShapeDescriptor
        )
    }
}

/// Per-cell matcher queries. See `ASCIIConverter.cellQueryDescriptors`.
///
/// `lanes` is flattened in row-major cell order at a stride of `lanesPerCell`,
/// matching the layout `ShapeMatching` already uses for `candidateLanes`; use
/// `lanes(row:column:)` rather than slicing by hand.
@_spi(AskiResearch)
public struct CellQueryDescriptors: Sendable {
    /// The grid `convert(_:columns:)` produces for the same image and columns.
    public let grid: ASCIIGrid
    public let rows: Int
    public let columns: Int
    public let lanesPerCell: Int
    public let lanes: [SIMD4<Float>]
    public let adjustedL: [Float]
    /// `false` when a cell axis is a single pixel, in which case every
    /// descriptor is the all-zero vector and production ranks on tone instead.
    public let supportsShapeDescriptor: Bool

    /// The 60D query descriptor for one cell, as `ShapeMatching` expects it.
    public func lanes(row: Int, column: Int) -> [SIMD4<Float>] {
        let start = (row * columns + column) * lanesPerCell
        return Array(lanes[start..<(start + lanesPerCell)])
    }

    /// The query tone for one cell — `stats.adjustedL`, the value the brightness
    /// pre-filter compares against `characterSet.brightnessValues`.
    public func adjustedL(row: Int, column: Int) -> Float {
        adjustedL[row * columns + column]
    }
}

/// The resolved per-cell sampling lattice. See `ASCIIConverter.samplingGeometry`.
@_spi(AskiResearch)
public struct SamplingGeometry: Sendable, Hashable {
    public let columns: Int
    public let rows: Int
    public let cellWidth: Int
    public let cellHeight: Int
    /// Width of the sampling-lattice raster, `columns * cellWidth`.
    public let thumbnailWidth: Int
    /// Height of the sampling-lattice raster, `rows * cellHeight`.
    public let thumbnailHeight: Int

    /// Lattice columns off the **right** edge that the converter never reads.
    /// Zero since ASKI-65: the raster is drawn at an exact multiple of the
    /// grid, so the origin-anchored walk tiles it with nothing left over. Kept
    /// so instruments can assert the property instead of assuming it.
    public var droppedX: Int { thumbnailWidth - columns * cellWidth }
    /// Lattice rows off the **bottom** edge that the converter never reads.
    /// Zero since ASKI-65, for the same reason as `droppedX`.
    public var droppedY: Int { thumbnailHeight - rows * cellHeight }
}
