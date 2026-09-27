import simd

/// Brightness-only character pick with Floyd–Steinberg error diffusion.
///
/// Sendable safety: this is `@unchecked Sendable` because Floyd–Steinberg
/// requires cross-cell mutable state (the error buffer threading
/// quantization residue down + right). The invariant that makes it safe:
///
/// - A fresh kernel is constructed inside `ASCIIConverter.convert(_:columns:)`
///   per call, used for the single-threaded, in-order grid walk in that same
///   call, and then released. The instance is never published to another
///   isolation domain or task.
/// If a future change shares a kernel across tasks, its buffer must move behind
/// an actor or become explicit `inout` state.
internal final class DotMatrixKernel: CharacterScoring, @unchecked Sendable {
    let glyphBank: GlyphBank
    private let columns: Int
    private let rows: Int
    private let ditherStrength: Float
    /// Error buffer indexed by `row * columns + column`. Floyd–Steinberg
    /// diffuses error to neighbors:
    ///   right        → +7/16
    ///   below-left   → +3/16
    ///   below        → +5/16
    ///   below-right  → +1/16
    private var errorBuffer: [Float]
    /// Only the ranked animation path fills this cache. Its key is the base
    /// glyph, so repeated cells do not re-rank the same density neighbors.
    private var rankedCandidatesByPick: [Int: [Int]] = [:]

    init(glyphBank: GlyphBank, columns: Int, rows: Int, ditherStrength: Float) {
        self.glyphBank = glyphBank
        self.columns = columns
        self.rows = rows
        self.ditherStrength = simd_clamp(ditherStrength, 0, 1)
        self.errorBuffer = [Float](repeating: 0, count: max(1, columns * rows))
    }

    convenience init<C: ASCIICharacterSet>(
        characterSet: C,
        columns: Int,
        rows: Int,
        ditherStrength: Float
    ) {
        self.init(
            glyphBank: GlyphBank.adapting(characterSet),
            columns: columns,
            rows: rows,
            ditherStrength: ditherStrength
        )
    }

    func pick(
        cell: CellCoord,
        stats: CellStats,
        in context: borrowing ConversionContext
    ) -> (character: Character, index: Int) {
        let bufIndex = cell.row * columns + cell.column
        let target = stats.adjustedL + (bufIndex < errorBuffer.count ? errorBuffer[bufIndex] : 0)

        // Pick the brightness-nearest character.
        var bestIndex = 0
        var bestDelta = Float.infinity
        for (i, b) in glyphBank.brightnessValues.enumerated() {
            let d = abs(b - target)
            if d < bestDelta {
                bestDelta = d
                bestIndex = i
            }
        }
        let pickedBrightness = glyphBank.brightnessValues[bestIndex]
        let quantError = (target - pickedBrightness) * ditherStrength

        // Diffuse error to neighbors. Bounds-check each.
        diffuse(quantError * 7 / 16, toColumn: cell.column + 1, row: cell.row)
        diffuse(quantError * 3 / 16, toColumn: cell.column - 1, row: cell.row + 1)
        diffuse(quantError * 5 / 16, toColumn: cell.column, row: cell.row + 1)
        diffuse(quantError * 1 / 16, toColumn: cell.column + 1, row: cell.row + 1)

        // Unchecked by design: `bestIndex` comes from `brightnessValues`, which
        // the ASCIICharacterSet parallel-array precondition keeps the same length
        // as `characters` (see `ASCIICharacterSet`).
        return (glyphBank.characters[bestIndex], bestIndex)
    }

    func score(cell: CellCoord, stats: CellStats, in context: borrowing ConversionContext) -> Character {
        pick(cell: cell, stats: stats, in: context).character
    }

    /// Keep the diffused winner in slot zero; rank the other glyphs by the
    /// same normalized ink density used by `pick`. This never reads or writes
    /// the error buffer, so alternatives cannot affect later base picks.
    func rankedCandidates(around pickedIndex: Int, limit: Int) -> [Int] {
        let count = min(limit, glyphBank.characters.count)
        if count == 1 { return [pickedIndex] }
        if let cached = rankedCandidatesByPick[pickedIndex], cached.count >= count {
            return Array(cached.prefix(count))
        }

        let densities = glyphBank.brightnessValues
        let pickedDensity = densities[pickedIndex]
        var ranked = [pickedIndex]
        for index in densities.indices where index != pickedIndex {
            let distance = abs(densities[index] - pickedDensity)
            var slot = 1
            while slot < ranked.count {
                let other = ranked[slot]
                let otherDistance = abs(densities[other] - pickedDensity)
                if distance < otherDistance || (distance == otherDistance && index < other) {
                    break
                }
                slot += 1
            }
            if slot < count {
                ranked.insert(index, at: slot)
                if ranked.count > count { ranked.removeLast() }
            }
        }
        rankedCandidatesByPick[pickedIndex] = ranked
        return ranked
    }

    private func diffuse(_ delta: Float, toColumn col: Int, row: Int) {
        guard col >= 0, col < columns, row >= 0, row < rows else { return }
        let idx = row * columns + col
        if idx >= 0, idx < errorBuffer.count {
            errorBuffer[idx] += delta
        }
    }
}
