import Foundation
import Testing
@testable import Aski

/// ASKI-6 / ASKI-19: finite inputs the public boundary accepts must never
/// produce trapping arithmetic deeper in the animation pipeline.
@Suite struct AnimationExtremeValueTests {
    // MARK: ASKI-6 — grid(at:) is total over finite time

    @Test func gridAtMaximumFiniteTimeReturnsAValidGrid() {
        let animated = makeAnimatedGrid(speed: 1, randomness: 1)
        let frame = animated.grid(at: .greatestFiniteMagnitude)

        #expect(frame.rows == 1)
        #expect(frame.columns == 1)
        #expect(["A", "B", "C"].contains(frame.cells[0][0].character))
    }

    @Test func gridAtMaximumFiniteTimeIsDeterministic() {
        let animated = makeAnimatedGrid(speed: 1, randomness: 1)

        #expect(animated.grid(at: .greatestFiniteMagnitude).cells == animated.grid(at: .greatestFiniteMagnitude).cells)
    }

    @Test func gridAtLargeFiniteTimeIsTotalAtTheExtremesOfTheAcceptedSpeedRange() {
        for speed in [CyclingOptions.minSpeed, CyclingOptions.maxSpeed] {
            let animated = makeAnimatedGrid(speed: speed, randomness: 1)
            let frame = animated.grid(at: .greatestFiniteMagnitude)

            #expect(["A", "B", "C"].contains(frame.cells[0][0].character))
        }
    }

    // MARK: ASKI-6 AC#2 — unrepresentable speeds are rejected at the boundary

    #if !SWT_NO_EXIT_TESTS
        @Test func speedTooLargeForARepresentablePeriodIsRejected() async {
            await #expect(processExitsWith: .failure) {
                _ = CyclingOptions(k: 3, speed: 1e300, intensity: 1, randomness: 0)
            }
        }

        @Test func speedTooSmallForARepresentablePeriodIsRejected() async {
            await #expect(processExitsWith: .failure) {
                _ = CyclingOptions(k: 3, speed: 1e-300, intensity: 1, randomness: 0)
            }
        }
    #endif

    @Test func defaultAndOrdinarySpeedsStayInsideTheAcceptedRange() {
        #expect(CyclingOptions.minSpeed < CyclingOptions.default.speed)
        #expect(CyclingOptions.default.speed < CyclingOptions.maxSpeed)
    }

    // MARK: ASKI-19 — materialize bounds the frame count before allocating

    #if !SWT_NO_EXIT_TESTS
        @Test func materializeRejectsADurationWhoseFrameProductOverflowsInt() async {
            await #expect(processExitsWith: .failure) {
                _ = makeAnimatedGrid(duration: 1e300).materialize(frameRate: 60)
            }
        }

        @Test func materializeRejectsAFrameCountJustPastTheCap() async {
            await #expect(processExitsWith: .failure) {
                // 5000 * 2 = 10,000 cadence steps -> 10,001 frames, one past the cap.
                _ = makeAnimatedGrid(duration: 5000).materialize(frameRate: 2)
            }
        }
    #endif

    @Test func materializeAcceptsAFrameCountExactlyAtTheCap() {
        // 4999.5 * 2 = 9,999 cadence steps -> exactly 10,000 frames.
        let frames = makeAnimatedGrid(duration: 4999.5).materialize(frameRate: 2)

        #expect(frames.count == AnimatedASCIIGrid.maxMaterializedFrameCount)
    }

    @Test func materializeAcceptsAnEndpointNudgedAFewULPsPastTheCap() {
        // The endpoint sits eight ULPs or less above 9,999 cadence steps, so it
        // is snapped back onto that step and costs one frame, not two. A cap
        // computed from `ceil` would round it up to 10,001 and reject a request
        // that in fact lands exactly on the documented limit.
        let frames = makeAnimatedGrid(duration: Double(9999).nextUp).materialize(frameRate: 1)

        #expect(frames.count == AnimatedASCIIGrid.maxMaterializedFrameCount)
    }
}

private func makeAnimatedGrid(
    duration: TimeInterval = 1,
    speed: Double = 1,
    randomness: Double = 0
) -> AnimatedASCIIGrid {
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
            cycling: CyclingOptions(k: 3, speed: speed, intensity: 1, randomness: randomness)
        )
    )
    return AnimatedASCIIGrid(baseGrid: base, duration: duration, seed: 0, schedule: schedule, characterSet: snapshot)
}
