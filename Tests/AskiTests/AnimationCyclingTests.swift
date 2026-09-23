import Testing
@testable import Aski

@Suite struct AnimationCyclingTests {
    @Test func cyclingRotatesDiscreteCandidates() {
        let animated = makeAnimatedGrid()

        #expect(animated.grid(at: 0).cells[0][0].character == "A")
        #expect(animated.grid(at: 0.34).cells[0][0].character == "B")
        #expect(animated.grid(at: 0.67).cells[0][0].character == "C")
        #expect(animated.grid(at: 1.0).cells[0][0].character == "A")
    }

    @Test func nonParticipatingCellsStayOnWinner() {
        let base = ASCIIGrid(
            cells: [[ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)]],
            colorSpace: .sRGB
        )
        let snapshot = CharacterSetSnapshot(characters: ["A", "B"])
        let schedule = ScheduleBuilder.build(
            baseGrid: base,
            candidates: [0, 1],
            candidateStride: 2,
            candidateCounts: [2],
            characterSet: snapshot,
            options: AnimationOptions(duration: 1, cycling: CyclingOptions(k: 2, speed: 1, intensity: 0, randomness: 0))
        )
        let animated = AnimatedASCIIGrid(baseGrid: base, duration: 1, seed: 0, schedule: schedule, characterSet: snapshot)

        #expect(animated.grid(at: 0.5).cells[0][0].character == "A")
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
