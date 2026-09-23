import Testing
@testable import Aski

@Suite struct AnimationEdgeCaseTests {
    @Test func nonFiniteAndNegativeTimesClampToZero() {
        let animated = makeAnimatedGrid()
        let zero = animated.grid(at: 0).cells

        #expect(animated.grid(at: -100).cells == zero)
        #expect(animated.grid(at: .nan).cells == zero)
        #expect(animated.grid(at: .infinity).cells == zero)
        #expect(animated.grid(at: -.infinity).cells == zero)
    }

    @Test func emptyGridReturnsEmptyFrames() {
        let base = ASCIIGrid(cells: [], colorSpace: .sRGB)
        let snapshot = CharacterSetSnapshot(characters: ["A"])
        let schedule = ScheduleBuilder.build(
            baseGrid: base,
            candidates: [],
            candidateStride: 1,
            candidateCounts: [],
            characterSet: snapshot,
            options: AnimationOptions(duration: 1)
        )
        let animated = AnimatedASCIIGrid(baseGrid: base, duration: 1, seed: 0, schedule: schedule, characterSet: snapshot)

        #expect(animated.grid(at: 0).cells.isEmpty)
        #expect(animated.materialize(frameRate: 2).count == 3)
    }
}

private func makeAnimatedGrid() -> AnimatedASCIIGrid {
    let base = ASCIIGrid(
        cells: [[ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)]],
        colorSpace: .sRGB
    )
    let snapshot = CharacterSetSnapshot(characters: ["A", "B", "C"])
    let schedule = ScheduleBuilder.build(
        baseGrid: base,
        candidates: [0, 1, 2],
        candidateStride: 3,
        candidateCounts: [3],
        characterSet: snapshot,
        options: AnimationOptions(duration: 1, cycling: CyclingOptions(k: 3, speed: 1, intensity: 1, randomness: 0))
    )
    return AnimatedASCIIGrid(baseGrid: base, duration: 1, seed: 0, schedule: schedule, characterSet: snapshot)
}
