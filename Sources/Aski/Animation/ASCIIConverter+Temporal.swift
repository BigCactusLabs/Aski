import CoreGraphics
import Foundation
import simd

@_spi(AskiResearch) public struct TemporalPriorState: Sendable {
    public let columns: Int
    public let rows: Int

    let emaOKLab: [SIMD3<Float>]
    let emaAdjustedL: [Float]
    let emaAlpha: [Float]
    let heldGlyphIndex: [Int]
    /// ASTSK-45: per-cell fit of the displayed glyph recorded at its first appearance
    /// (`distance(displayedGlyph, source)`), the reference the source-tether releases against.
    /// One entry per cell on the source-tether path; EMPTY on the default/tau path — so
    /// `lockDistance.count == cellCount` is a faithful "carries real locks" signal and a non-tether
    /// state threaded into a tether frame re-anchors instead of trusting filler.
    let lockDistance: [Float]

    init(
        columns: Int,
        rows: Int,
        emaOKLab: [SIMD3<Float>],
        emaAdjustedL: [Float],
        emaAlpha: [Float],
        heldGlyphIndex: [Int],
        lockDistance: [Float]
    ) {
        self.columns = columns
        self.rows = rows
        self.emaOKLab = emaOKLab
        self.emaAdjustedL = emaAdjustedL
        self.emaAlpha = emaAlpha
        self.heldGlyphIndex = heldGlyphIndex
        self.lockDistance = lockDistance
    }
}

extension ASCIIConverter {
    /// Research-only temporal-prior frame conversion (ASTSK-41/45). Walks the
    /// per-cell grid with the same grid-size-gated row parallelism as
    /// `convert(_:columns:)` — parallelism is *within* this frame only, never a
    /// fan-out across frames — and stays byte-identical to a serial walk.
    @_spi(AskiResearch)
    public func convertTemporalFrame(
        _ image: CGImage,
        columns: Int,
        prior: TemporalPriorState?,
        alpha: Float,
        tau: Float,
        sourceTetherRho: Float? = nil
    ) -> (grid: ASCIIGrid, state: TemporalPriorState) {
        let emptyState = TemporalPriorState(
            columns: 0,
            rows: 0,
            emaOKLab: [],
            emaAdjustedL: [],
            emaAlpha: [],
            heldGlyphIndex: [],
            lockDistance: []
        )

        func emptyResult() -> (grid: ASCIIGrid, state: TemporalPriorState) {
            (ASCIIGrid(cells: [], colorSpace: colorSpace), emptyState)
        }

        guard columns > 0 else {
            return emptyResult()
        }

        let resolvedOptions = ResolvedRenderingOptions(options)
        let resolvedPalette = ResolvedPalette(
            content: palette.content,
            needsHelmlab: paletteMatching.needsHelmlab
        )

        guard
            let (cols, rows) = gridDimensions(
                imageWidth: image.width,
                imageHeight: image.height,
                columns: columns,
                tileShape: tileShape
            )
        else {
            return emptyResult()
        }

        guard
            let maxPixelSize = thumbnailMaxPixelSize(
                image: image,
                columns: cols,
                rows: rows
            )
        else {
            return emptyResult()
        }

        let thumbnail: CGImage
        do {
            thumbnail = try ImageIOThumbnail.decode(image: image, maxPixelSize: maxPixelSize)
        } catch {
            return emptyResult()
        }

        // Same sampling lattice as `prepareConversion` — an exact multiple of
        // the grid, so no source row or column goes unread (ASKI-65).
        guard
            let lattice = samplingLattice(
                thumbnail: thumbnail,
                columns: cols,
                rows: rows,
                colorSpace: colorSpace
            )
        else {
            return emptyResult()
        }

        let context = ConversionContext(
            pixels: lattice.pixels,
            pixelWidth: lattice.pixelWidth,
            pixelHeight: lattice.pixelHeight,
            cellWidth: lattice.cellWidth,
            cellHeight: lattice.cellHeight,
            columns: cols,
            rows: rows,
            palette: resolvedPalette,
            options: resolvedOptions,
            colorSpace: colorSpace,
            colorSampling: colorSampling,
            paletteMatching: paletteMatching,
            gamutMapping: gamutMapping,
            composition: composition
        )

        let kernel = LogPolarKernel(glyphBank: glyphBank)
        let cellCount = cols * rows
        let priorMatches =
            prior?.columns == cols
            && prior?.rows == rows
            && prior?.emaOKLab.count == cellCount
            && prior?.emaAdjustedL.count == cellCount
            && prior?.emaAlpha.count == cellCount
            && prior?.heldGlyphIndex.count == cellCount
        // ASTSK-45: the source-tether path additionally needs a full lockDistance companion.
        // Kept separate from `priorMatches` so the default/tau EMA + hysteresis gate stays
        // byte-identical.
        let priorHasLock = priorMatches && prior?.lockDistance.count == cellCount
        let temporalAlpha = alpha
        let inverseAlpha = 1 - temporalAlpha

        var outputRows: [[ASCIICell]] = Array(repeating: [], count: rows)
        var nextOKLab = [SIMD3<Float>](repeating: .zero, count: cellCount)
        var nextAdjustedL = [Float](repeating: 0, count: cellCount)
        var nextAlpha = [Float](repeating: 0, count: cellCount)
        var nextHeldGlyphIndex = [Int](repeating: 0, count: cellCount)
        // ASTSK-45 semantics: lockDistance.count == cellCount MUST mean "tether path
        // wrote real locks". Pre-size only when the tether is on; empty otherwise.
        var nextLockDistance =
            sourceTetherRho != nil
            ? [Float](repeating: 0, count: cellCount) : [Float]()

        outputRows.withUnsafeMutableBufferPointer { rowsBuffer in
            nextOKLab.withUnsafeMutableBufferPointer { oklabBuffer in
                nextAdjustedL.withUnsafeMutableBufferPointer { adjustedLBuffer in
                    nextAlpha.withUnsafeMutableBufferPointer { alphaBuffer in
                        nextHeldGlyphIndex.withUnsafeMutableBufferPointer { heldBuffer in
                            nextLockDistance.withUnsafeMutableBufferPointer { lockBuffer in
                                // SAFETY: worker `row` writes rowsBase[row] and each next*Base in
                                // row*cols ..< (row+1)*cols only; rows are disjoint, all written
                                // buffers are pre-sized, and concurrentPerform joins on return.
                                nonisolated(unsafe) let rowsBase = rowsBuffer.baseAddress!
                                nonisolated(unsafe) let oklabBase = oklabBuffer.baseAddress!
                                nonisolated(unsafe) let adjustedLBase = adjustedLBuffer.baseAddress!
                                nonisolated(unsafe) let alphaBase = alphaBuffer.baseAddress!
                                nonisolated(unsafe) let heldBase = heldBuffer.baseAddress!
                                nonisolated(unsafe) let lockBase = lockBuffer.baseAddress
                                GridRowWalk.forEachRow(rows: rows, columns: cols, mode: rowWalkMode) { row in
                                    var line: [ASCIICell] = []
                                    line.reserveCapacity(cols)
                                    for column in 0..<cols {
                                        let index = row * cols + column
                                        let coord = CellCoord(column: column, row: row)
                                        let rawSource = context.cellSourceStats(at: coord)
                                        let source: CellSourceStats
                                        if priorMatches, let prior {
                                            source = CellSourceStats(
                                                oklab: temporalAlpha * rawSource.oklab + inverseAlpha * prior.emaOKLab[index],
                                                adjustedL: temporalAlpha * rawSource.adjustedL
                                                    + inverseAlpha * prior.emaAdjustedL[index],
                                                alpha: temporalAlpha * rawSource.alpha + inverseAlpha * prior.emaAlpha[index]
                                            )
                                        } else {
                                            source = rawSource
                                        }

                                        let stats = context.finalizeColor(source: source)
                                        let preparedMatch = kernel.matchWithDescriptor(
                                            cell: coord,
                                            stats: stats,
                                            in: context,
                                            resultLimit: 1
                                        )
                                        let match = preparedMatch.match
                                        let descriptorLanes = preparedMatch.lanes
                                        var chosenIndex = match.winnerIndex
                                        var chosenCharacter = match.winnerCharacter

                                        if let rho = sourceTetherRho {
                                            // ASTSK-45 source-tether (replaces the tau relative-margin block): hold the
                                            // first-appearance glyph while its fit to the *current* source stays within
                                            // rho of its commit fit; otherwise release to the per-frame argmax.
                                            if priorHasLock, let prior {
                                                let heldIndex = prior.heldGlyphIndex[index]
                                                if heldIndex >= 0, heldIndex < glyphBank.characters.count {
                                                    let heldDistance = kernel.distance(
                                                        fromLanes: descriptorLanes,
                                                        toGlyph: heldIndex
                                                    )
                                                    if heldDistance <= prior.lockDistance[index] * (1 + rho) {
                                                        chosenIndex = heldIndex
                                                        chosenCharacter = glyphBank.characters[heldIndex]
                                                    }
                                                }
                                            }
                                        } else if tau > 0, priorMatches, let prior {
                                            let heldIndex = prior.heldGlyphIndex[index]
                                            if heldIndex >= 0, heldIndex < glyphBank.characters.count {
                                                let heldDistance = kernel.distance(
                                                    fromLanes: descriptorLanes,
                                                    toGlyph: heldIndex
                                                )
                                                let winnerDistance = kernel.distance(
                                                    fromLanes: descriptorLanes,
                                                    toGlyph: match.winnerIndex
                                                )
                                                if heldDistance <= winnerDistance * (1 + tau) {
                                                    chosenIndex = heldIndex
                                                    chosenCharacter = glyphBank.characters[heldIndex]
                                                }
                                            }
                                        }

                                        // ASTSK-45: maintain lockDistance ONLY on the source-tether path, so that a state's
                                        // `lockDistance.count == cellCount` faithfully means "this state carries real
                                        // first-appearance locks" (the default/tau path leaves it empty ⇒ priorHasLock is
                                        // false ⇒ a non-tether state threaded into a tether frame re-anchors rather than
                                        // trusting filler). (Re)anchor on a genuine first appearance -- a frame where the
                                        // displayed glyph changes, or the first tethered frame after a non-tether prior. A
                                        // hold, or a release whose argmax equals the held glyph, carries the commit fit
                                        // forward untouched (first-appearance anchoring, not per-release re-anchoring -- the
                                        // frozen rule that bounds cumulative staleness).
                                        if sourceTetherRho != nil {
                                            if priorHasLock, let prior, prior.heldGlyphIndex[index] == chosenIndex {
                                                (lockBase! + index).pointee = prior.lockDistance[index]
                                            } else {
                                                (lockBase! + index).pointee =
                                                    kernel.distance(
                                                        fromLanes: descriptorLanes,
                                                        toGlyph: chosenIndex
                                                    )
                                            }
                                        }

                                        (oklabBase + index).pointee = source.oklab
                                        (adjustedLBase + index).pointee = source.adjustedL
                                        (alphaBase + index).pointee = source.alpha
                                        (heldBase + index).pointee = chosenIndex
                                        line.append(
                                            ASCIICell(
                                                character: chosenCharacter,
                                                displayColor: stats.displayColor,
                                                alpha: stats.alpha,
                                                brightness: stats.adjustedL,
                                                coverage: 1.0
                                            ))
                                    }
                                    (rowsBase + row).pointee = line
                                }
                            }
                        }
                    }
                }
            }
        }

        let state = TemporalPriorState(
            columns: cols,
            rows: rows,
            emaOKLab: nextOKLab,
            emaAdjustedL: nextAdjustedL,
            emaAlpha: nextAlpha,
            heldGlyphIndex: nextHeldGlyphIndex,
            lockDistance: nextLockDistance
        )
        return (
            ASCIIGrid(cells: outputRows, colorSpace: colorSpace, composition: composition),
            state
        )
    }
}
