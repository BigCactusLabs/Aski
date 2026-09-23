internal protocol CharacterScoring: Sendable {
    func score(cell: CellCoord, stats: CellStats, in context: borrowing ConversionContext) -> Character
}

internal protocol CellCapturing: Sendable {
    func capture(
        cell: CellCoord, stats: CellStats, in context: borrowing ConversionContext, cellIndex: Int
    ) -> Character
}

internal struct PlainCellCapture<Kernel: CharacterScoring>: CellCapturing {
    let kernel: Kernel

    @inline(__always)
    func capture(
        cell: CellCoord, stats: CellStats, in context: borrowing ConversionContext, cellIndex _: Int
    ) -> Character {
        kernel.score(cell: cell, stats: stats, in: context)
    }
}

// SAFETY: pointer captures are immutable and address pre-sized buffers whose
// disjoint row ranges remain alive until the synchronous GridRowWalk joins.
internal struct RankedLogPolarCapture: CellCapturing, @unchecked Sendable {
    let kernel: LogPolarKernel
    let stride: Int
    let candidatesBase, countsBase: UnsafeMutablePointer<UInt16>

    @inline(__always)
    func capture(
        cell: CellCoord, stats: CellStats, in context: borrowing ConversionContext, cellIndex: Int
    ) -> Character {
        let match = kernel.match(cell: cell, stats: stats, in: context, resultLimit: stride)
        writePaddedCandidates(match.rankedIndices, at: cellIndex)
        return match.winnerCharacter
    }

    private func writePaddedCandidates(_ ranked: ContiguousArray<Int>, at cellIndex: Int) {
        let winner = ranked[0]
        let distinctCount = ranked.indices.reduce(into: 0) { count, position in
            if !ranked[..<position].contains(ranked[position]) { count += 1 }
        }
        countsBase[cellIndex] = UInt16(distinctCount)
        let base = cellIndex * stride
        for slot in 0..<stride {
            candidatesBase[base + slot] = UInt16(slot < ranked.count ? ranked[slot] : winner)
        }
    }
}

// DotMatrixKernel remains confined to the forced-serial caller-selected walk.
internal struct RankedDotMatrixCapture: CellCapturing, @unchecked Sendable {
    let kernel: DotMatrixKernel
    let stride: Int
    let candidatesBase, countsBase: UnsafeMutablePointer<UInt16>

    @inline(__always)
    func capture(
        cell: CellCoord, stats: CellStats, in context: borrowing ConversionContext, cellIndex: Int
    ) -> Character {
        let picked = kernel.pick(cell: cell, stats: stats, in: context)
        countsBase[cellIndex] = 1
        let base = cellIndex * stride
        for slot in 0..<stride { candidatesBase[base + slot] = UInt16(picked.index) }
        return picked.character
    }
}

internal struct ResidualLogPolarCapture: CellCapturing, @unchecked Sendable {
    let kernel: LogPolarKernel
    let residualBase: UnsafeMutablePointer<Float>

    @inline(__always)
    func capture(
        cell: CellCoord, stats: CellStats, in context: borrowing ConversionContext, cellIndex: Int
    ) -> Character {
        let result = kernel.scoreScored(cell: cell, stats: stats, in: context)
        residualBase[cellIndex] = result.distance
        return result.character
    }
}

internal struct ResidualDotMatrixCapture: CellCapturing, @unchecked Sendable {
    let kernel: DotMatrixKernel
    let residualBase: UnsafeMutablePointer<Float>

    @inline(__always)
    func capture(
        cell: CellCoord, stats: CellStats, in context: borrowing ConversionContext, cellIndex: Int
    ) -> Character {
        let picked = kernel.pick(cell: cell, stats: stats, in: context)
        residualBase[cellIndex] = .nan
        return picked.character
    }
}

internal enum ConversionEngine {
    static func renderRows<Capture: CellCapturing>(
        preparation: PreparedConversion, mode: GridRowWalk.Mode, capture: Capture
    ) -> [[ASCIICell]] {
        let context = preparation.context
        let columns = context.columns
        let rows = context.rows
        let sampledCoverage = preparation.sampledCoverage
        var outputRows = [[ASCIICell]](repeating: [], count: rows)

        outputRows.withUnsafeMutableBufferPointer { rowsBuffer in
            // SAFETY: rows are pre-sized and each worker owns one disjoint row.
            nonisolated(unsafe) let rowsBase = rowsBuffer.baseAddress!
            GridRowWalk.forEachRow(rows: rows, columns: columns, mode: mode) { row in
                var line: [ASCIICell] = []
                line.reserveCapacity(columns)
                for column in 0..<columns {
                    let cellIndex = row * columns + column
                    let coord = CellCoord(column: column, row: row)
                    let stats = context.finalizeColor(source: context.cellSourceStats(at: coord))
                    let character = capture.capture(
                        cell: coord, stats: stats, in: context, cellIndex: cellIndex
                    )
                    line.append(
                        ASCIICell(
                            character: character,
                            displayColor: stats.displayColor,
                            alpha: stats.alpha,
                            brightness: stats.adjustedL,
                            coverage: sampledCoverage?[cellIndex] ?? 1
                        ))
                }
                (rowsBase + row).pointee = line
            }
        }
        return outputRows
    }
}
