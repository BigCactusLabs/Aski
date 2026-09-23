import Foundation
@testable import Aski

/// Shared fixtures for the animation byte-identical golden (ASKI-18 AC#5,
/// ASKI-19 AC#4). The animation surface has no snapshot or golden coverage, so
/// these values are captured from the pre-change code and frozen here.
internal enum AnimationGoldenFixtures {
    static let sampleTimes: [TimeInterval] = [0, 0.13, 0.5, 0.87, 1.0, 2.5]

    static let rows = 2
    static let columns = 3

    /// Varied per-cell alpha/brightness so a change in cell ordering or in the
    /// alpha multiply shows up, rather than a uniform grid that hides it.
    static func baseGrid() -> ASCIIGrid {
        var cells: [[ASCIICell]] = []
        for row in 0..<rows {
            var line: [ASCIICell] = []
            for column in 0..<columns {
                let index = row * columns + column
                line.append(
                    ASCIICell(
                        character: "A",
                        displayColor: .one,
                        alpha: Float(0.2 + 0.1 * Double(index)),
                        brightness: Float(0.15 + 0.07 * Double(index)),
                        coverage: 1
                    ))
            }
            cells.append(line)
        }
        return ASCIIGrid(cells: cells, colorSpace: .sRGB)
    }

    private static func animated(duration: TimeInterval, ongoing: OngoingPattern?) -> AnimatedASCIIGrid {
        let base = baseGrid()
        let snapshot = CharacterSetSnapshot(characters: ["A", "B", "C", "D"])
        // Deliberately non-uniform candidate ordering per cell.
        let candidates: ContiguousArray<UInt16> = [
            0, 1, 2, 1, 2, 3, 2, 3, 0, 3, 0, 1, 0, 2, 3, 1, 3, 2,
        ]
        let schedule = ScheduleBuilder.build(
            baseGrid: base,
            candidates: candidates,
            candidateStride: 3,
            candidateCounts: ContiguousArray(repeating: 3, count: rows * columns),
            characterSet: snapshot,
            options: AnimationOptions(
                duration: duration,
                seed: 12_345,
                cycling: CyclingOptions(k: 3, speed: 1, intensity: 1, randomness: 0.5),
                ongoing: ongoing
            )
        )
        return AnimatedASCIIGrid(
            baseGrid: base, duration: duration, seed: 12_345, schedule: schedule, characterSet: snapshot)
    }

    /// A participating multi-candidate cycling grid, with an ongoing pulse so
    /// the pattern multiply is part of the frozen value too.
    static func cyclingGrid() -> AnimatedASCIIGrid {
        animated(duration: 3, ongoing: .pulse(period: 1.25, depth: 0.6))
    }

    /// A realistic duration through materialize(frameRate:) — 2 s at 12 fps.
    static func materializeGrid() -> AnimatedASCIIGrid {
        animated(duration: 2, ongoing: .wave(amplitude: 0.4, frequency: 2, direction: .vertical))
    }
}
