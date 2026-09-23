import Foundation
import Testing
@testable import Aski

@Suite struct AnimationDeterminismTests {
    @Test func gridAtIsPureForSameTime() {
        let animated = makeAnimatedGrid()
        #expect(animated.grid(at: 0.25).cells == animated.grid(at: 0.25).cells)
    }

    @Test func materializeIsDeterministicAndIncludesEndpoint() {
        let animated = makeAnimatedGrid()
        let first = animated.materialize(frameRate: 4)
        let second = animated.materialize(frameRate: 4)

        #expect(first.map(\.cells) == second.map(\.cells))
        #expect(first.count == 5)
    }

    @Test func materializeAppendsNonCadenceAlignedEndpoint() {
        let animated = makeAnimatedGrid(
            duration: 0.6,
            ongoing: .pulse(period: 1, depth: 1)
        )
        let frames = animated.materialize(frameRate: 2)

        #expect(frames.count == 3)
        #expect(frames.last?.cells == animated.grid(at: 0.6).cells)
        #expect(frames[1].cells != frames[2].cells)
    }
}

private func makeAnimatedGrid(duration: TimeInterval = 1, ongoing: OngoingPattern? = nil) -> AnimatedASCIIGrid {
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
        options: AnimationOptions(
            duration: duration,
            cycling: CyclingOptions(k: 3, speed: 1, intensity: 1, randomness: 0),
            ongoing: ongoing
        )
    )
    return AnimatedASCIIGrid(baseGrid: base, duration: duration, seed: 0, schedule: schedule, characterSet: snapshot)
}
