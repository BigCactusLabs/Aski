import Testing
@testable import Aski

@Suite struct AnimationScheduleTests {
    @Test func bitSetStoresAndReadsBits() {
        var bitSet = BitSet(count: 130)
        #expect(bitSet.count == 130)
        #expect(bitSet.contains(64) == false)

        bitSet.set(64, to: true)
        bitSet.set(129, to: true)

        #expect(bitSet.contains(64) == true)
        #expect(bitSet.contains(129) == true)
        #expect(bitSet.contains(63) == false)
    }

    @Test func randomStreamsAreDeterministicAndSalted() {
        let a = SplitMix64.unitDouble(seed: 7, row: 3, column: 5, salt: .phase)
        let b = SplitMix64.unitDouble(seed: 7, row: 3, column: 5, salt: .phase)
        let period = SplitMix64.unitDouble(seed: 7, row: 3, column: 5, salt: .period)
        let intensity = SplitMix64.unitDouble(seed: 7, row: 3, column: 5, salt: .intensity)

        #expect(a == b)
        #expect(a != period)
        #expect(period != intensity)
        #expect((0..<1).contains(a))
        #expect((0..<1).contains(period))
        #expect((0..<1).contains(intensity))
    }

    @Test func schedulePadsShortCandidateListsWithWinner() {
        let grid = makeGrid(characters: ["A"])
        let snapshot = CharacterSetSnapshot(characters: ["A", "B", "C"])
        let schedule = ScheduleBuilder.build(
            baseGrid: grid,
            candidates: [1, 1, 1],
            candidateStride: 3,
            candidateCounts: [1],
            characterSet: snapshot,
            options: AnimationOptions(duration: 1, cycling: CyclingOptions(k: 3, speed: 1, intensity: 1, randomness: 0))
        )

        #expect(schedule.candidateStride == 3)
        #expect(schedule.candidates == [1, 1, 1])
        #expect(schedule.participates.contains(0) == false)
    }

    @Test func scheduleUsesBasePeriodWhenRandomnessIsZero() {
        let grid = makeGrid(characters: ["A", "B", "C", "D"])
        let snapshot = CharacterSetSnapshot(characters: ["A", "B", "C"])
        let schedule = ScheduleBuilder.build(
            baseGrid: grid,
            candidates: [0, 1, 0, 1, 0, 1, 0, 1],
            candidateStride: 2,
            candidateCounts: [2, 2, 2, 2],
            characterSet: snapshot,
            options: AnimationOptions(duration: 1, seed: 99, cycling: CyclingOptions(k: 2, speed: 2, intensity: 1, randomness: 0))
        )

        #expect(schedule.periods.allSatisfy { abs($0 - 0.5) < 0.000_001 })
        #expect(schedule.participates.contains(0))
    }

    @Test func scheduleDisablesCyclingWhenIntensityIsZero() {
        let grid = makeGrid(characters: ["A", "B"])
        let snapshot = CharacterSetSnapshot(characters: ["A", "B"])
        let schedule = ScheduleBuilder.build(
            baseGrid: grid,
            candidates: [0, 1, 0, 1],
            candidateStride: 2,
            candidateCounts: [2, 2],
            characterSet: snapshot,
            options: AnimationOptions(duration: 1, cycling: CyclingOptions(k: 2, speed: 1, intensity: 0, randomness: 0))
        )

        #expect(schedule.participates.contains(0) == false)
        #expect(schedule.participates.contains(1) == false)
    }

    private func makeGrid(characters: [Character]) -> ASCIIGrid {
        let cells = [
            characters.map {
                ASCIICell(character: $0, displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
            }
        ]
        return ASCIIGrid(cells: cells, colorSpace: .sRGB)
    }
}
