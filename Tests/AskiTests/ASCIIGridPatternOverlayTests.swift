import Testing
@testable import Aski

@Suite struct ASCIIGridPatternOverlayTests {
    /// A small grid with distinct, non-trivial cells so both modulation and
    /// field-preservation are observable.
    private func makeGrid(rows: Int = 2, columns: Int = 3) -> ASCIIGrid {
        var cells: [[ASCIICell]] = []
        for r in 0..<rows {
            var line: [ASCIICell] = []
            for c in 0..<columns {
                line.append(
                    ASCIICell(
                        character: Character(UnicodeScalar(65 + r * columns + c)!),
                        displayColor: SIMD3<Float>(Float(c) / 4, 0.5, Float(r) / 4),
                        alpha: 0.8,
                        brightness: 0.6,
                        coverage: 0.9
                    ))
            }
            cells.append(line)
        }
        return ASCIIGrid(cells: cells, colorSpace: .displayP3)
    }

    @Test func modulatesAlphaAndIsDeterministic() {
        let base = makeGrid()
        let pattern = OngoingPattern.wave(amplitude: 0.5, frequency: 1, direction: .horizontal)

        let a = base.applyingOngoingPattern(pattern, at: 0.125)
        let b = base.applyingOngoingPattern(pattern, at: 0.125)

        // Determinism: identical (pattern, t) yields identical cells.
        #expect(a.cells == b.cells)
        // Modulation actually happened: at least one cell's alpha moved off the base.
        let changed = zip(a.cells.flatMap { $0 }, base.cells.flatMap { $0 })
            .contains { $0.alpha != $1.alpha }
        #expect(changed)
    }

    @Test func phaseAdvancesWithTime() {
        let base = makeGrid()
        let pattern = OngoingPattern.pulse(period: 1, depth: 1)

        let t0 = base.applyingOngoingPattern(pattern, at: 0)
        let tHalf = base.applyingOngoingPattern(pattern, at: 0.5)

        let differs = zip(t0.cells.flatMap { $0 }, tHalf.cells.flatMap { $0 })
            .contains { $0.alpha != $1.alpha }
        #expect(differs)
    }

    @Test func unitMultiplierLeavesGridUnchanged() {
        let base = makeGrid()
        // A depth-0 pulse and an amplitude-0 wave both evaluate to a unit
        // multiplier, so the grid must come back unchanged (no-op identity).
        let patterns: [OngoingPattern] = [
            .pulse(period: 1, depth: 0),
            .wave(amplitude: 0, frequency: 1, direction: .horizontal),
        ]
        for pattern in patterns {
            let out = base.applyingOngoingPattern(pattern, at: 0.37)
            #expect(out.cells == base.cells)
        }
    }

    @Test func preservesGlyphsColorsAndGridMetadata() {
        let base = makeGrid()
        let out = base.applyingOngoingPattern(
            .wave(amplitude: 0.5, frequency: 2, direction: .vertical), at: 0.4)

        #expect(out.rows == base.rows)
        #expect(out.columns == base.columns)
        #expect(out.colorSpace == base.colorSpace)
        #expect(out.composition == base.composition)
        for (outCell, baseCell) in zip(out.cells.flatMap { $0 }, base.cells.flatMap { $0 }) {
            #expect(outCell.character == baseCell.character)
            #expect(outCell.displayColor == baseCell.displayColor)
            #expect(outCell.brightness == baseCell.brightness)
            #expect(outCell.coverage == baseCell.coverage)
            #expect((0...1).contains(outCell.alpha))
        }
    }
}
