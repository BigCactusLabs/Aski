import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import Aski

/// ASKI-18: `wave(frequency:)` and `pulse(period:)` are structural — they define
/// the pattern's schedule — so every public entry point that accepts an
/// `OngoingPattern` rejects an unevaluable one up front, instead of killing the
/// process deep inside a per-cell render loop.
@Suite struct AnimationOngoingPatternContractTests {
    private static func cell() -> ASCIICell {
        ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
    }

    private static func grid() -> ASCIIGrid {
        ASCIIGrid(cells: [[cell(), cell()], [cell(), cell()]], colorSpace: .sRGB)
    }

    #if !SWT_NO_EXIT_TESTS

        // The animate + grid(at:) path: rejection lands in AnimationOptions.init,
        // before any conversion work, the same place `duration` is checked.
        @Test func animationOptionsRejectsPeriodZero() async {
            await #expect(processExitsWith: .failure) {
                _ = AnimationOptions(duration: 1, ongoing: .pulse(period: 0, depth: 1))
            }
        }

        @Test func animationOptionsRejectsPeriodNegative() async {
            await #expect(processExitsWith: .failure) {
                _ = AnimationOptions(duration: 1, ongoing: .pulse(period: -1, depth: 1))
            }
        }

        @Test func animationOptionsRejectsPeriodNaN() async {
            await #expect(processExitsWith: .failure) {
                _ = AnimationOptions(duration: 1, ongoing: .pulse(period: .nan, depth: 1))
            }
        }

        @Test func animationOptionsRejectsPeriodInfinite() async {
            await #expect(processExitsWith: .failure) {
                _ = AnimationOptions(duration: 1, ongoing: .pulse(period: .infinity, depth: 1))
            }
        }

        @Test func animationOptionsRejectsFrequencyZero() async {
            await #expect(processExitsWith: .failure) {
                _ = AnimationOptions(duration: 1, ongoing: .wave(amplitude: 0.5, frequency: 0, direction: .horizontal))
            }
        }

        @Test func animationOptionsRejectsFrequencyNegative() async {
            await #expect(processExitsWith: .failure) {
                _ = AnimationOptions(duration: 1, ongoing: .wave(amplitude: 0.5, frequency: -1, direction: .horizontal))
            }
        }

        @Test func animationOptionsRejectsFrequencyNaN() async {
            await #expect(processExitsWith: .failure) {
                _ = AnimationOptions(duration: 1, ongoing: .wave(amplitude: 0.5, frequency: .nan, direction: .horizontal))
            }
        }

        @Test func animationOptionsRejectsFrequencyInfinite() async {
            await #expect(processExitsWith: .failure) {
                _ = AnimationOptions(duration: 1, ongoing: .wave(amplitude: 0.5, frequency: .infinity, direction: .horizontal))
            }
        }

        // ASCIIGrid.applyingOngoingPattern, the direct public overlay entry point.
        @Test func applyingOngoingPatternRejectsPeriodZero() async {
            await #expect(processExitsWith: .failure) {
                let cell = ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
                let grid = ASCIIGrid(cells: [[cell, cell]], colorSpace: .sRGB)
                _ = grid.applyingOngoingPattern(.pulse(period: 0, depth: 1), at: 0.25)
            }
        }

        @Test func applyingOngoingPatternRejectsPeriodNegative() async {
            await #expect(processExitsWith: .failure) {
                let cell = ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
                let grid = ASCIIGrid(cells: [[cell, cell]], colorSpace: .sRGB)
                _ = grid.applyingOngoingPattern(.pulse(period: -1, depth: 1), at: 0.25)
            }
        }

        @Test func applyingOngoingPatternRejectsPeriodNaN() async {
            await #expect(processExitsWith: .failure) {
                let cell = ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
                let grid = ASCIIGrid(cells: [[cell, cell]], colorSpace: .sRGB)
                _ = grid.applyingOngoingPattern(.pulse(period: .nan, depth: 1), at: 0.25)
            }
        }

        @Test func applyingOngoingPatternRejectsPeriodInfinite() async {
            await #expect(processExitsWith: .failure) {
                let cell = ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
                let grid = ASCIIGrid(cells: [[cell, cell]], colorSpace: .sRGB)
                _ = grid.applyingOngoingPattern(.pulse(period: .infinity, depth: 1), at: 0.25)
            }
        }

        @Test func applyingOngoingPatternRejectsFrequencyZero() async {
            await #expect(processExitsWith: .failure) {
                let cell = ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
                let grid = ASCIIGrid(cells: [[cell, cell]], colorSpace: .sRGB)
                _ = grid.applyingOngoingPattern(.wave(amplitude: 0.5, frequency: 0, direction: .horizontal), at: 0.25)
            }
        }

        @Test func applyingOngoingPatternRejectsFrequencyNegative() async {
            await #expect(processExitsWith: .failure) {
                let cell = ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
                let grid = ASCIIGrid(cells: [[cell, cell]], colorSpace: .sRGB)
                _ = grid.applyingOngoingPattern(.wave(amplitude: 0.5, frequency: -1, direction: .horizontal), at: 0.25)
            }
        }

        @Test func applyingOngoingPatternRejectsFrequencyNaN() async {
            await #expect(processExitsWith: .failure) {
                let cell = ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
                let grid = ASCIIGrid(cells: [[cell, cell]], colorSpace: .sRGB)
                _ = grid.applyingOngoingPattern(.wave(amplitude: 0.5, frequency: .nan, direction: .horizontal), at: 0.25)
            }
        }

        @Test func applyingOngoingPatternRejectsFrequencyInfinite() async {
            await #expect(processExitsWith: .failure) {
                let cell = ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
                let grid = ASCIIGrid(cells: [[cell, cell]], colorSpace: .sRGB)
                _ = grid.applyingOngoingPattern(.wave(amplitude: 0.5, frequency: .infinity, direction: .horizontal), at: 0.25)
            }
        }

        // ASCIIVideoFrame.applyingOngoingPattern, the per-frame entry `convertVideo`
        // and the labs' render drivers call once per decoded frame.
        @Test func videoFrameRejectsPeriodZero() async {
            await #expect(processExitsWith: .failure) {
                let cell = ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
                let grid = ASCIIGrid(cells: [[cell, cell]], colorSpace: .sRGB)
                _ = ASCIIVideoFrame(grid: grid, time: .zero).applyingOngoingPattern(.pulse(period: 0, depth: 1))
            }
        }

        @Test func videoFrameRejectsPeriodNegative() async {
            await #expect(processExitsWith: .failure) {
                let cell = ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
                let grid = ASCIIGrid(cells: [[cell, cell]], colorSpace: .sRGB)
                _ = ASCIIVideoFrame(grid: grid, time: .zero).applyingOngoingPattern(.pulse(period: -1, depth: 1))
            }
        }

        @Test func videoFrameRejectsPeriodNaN() async {
            await #expect(processExitsWith: .failure) {
                let cell = ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
                let grid = ASCIIGrid(cells: [[cell, cell]], colorSpace: .sRGB)
                _ = ASCIIVideoFrame(grid: grid, time: .zero).applyingOngoingPattern(.pulse(period: .nan, depth: 1))
            }
        }

        @Test func videoFrameRejectsPeriodInfinite() async {
            await #expect(processExitsWith: .failure) {
                let cell = ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
                let grid = ASCIIGrid(cells: [[cell, cell]], colorSpace: .sRGB)
                _ = ASCIIVideoFrame(grid: grid, time: .zero).applyingOngoingPattern(.pulse(period: .infinity, depth: 1))
            }
        }

        @Test func videoFrameRejectsFrequencyZero() async {
            await #expect(processExitsWith: .failure) {
                let cell = ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
                let grid = ASCIIGrid(cells: [[cell, cell]], colorSpace: .sRGB)
                _ = ASCIIVideoFrame(grid: grid, time: .zero).applyingOngoingPattern(.wave(amplitude: 0.5, frequency: 0, direction: .horizontal))
            }
        }

        @Test func videoFrameRejectsFrequencyNegative() async {
            await #expect(processExitsWith: .failure) {
                let cell = ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
                let grid = ASCIIGrid(cells: [[cell, cell]], colorSpace: .sRGB)
                _ = ASCIIVideoFrame(grid: grid, time: .zero).applyingOngoingPattern(.wave(amplitude: 0.5, frequency: -1, direction: .horizontal))
            }
        }

        @Test func videoFrameRejectsFrequencyNaN() async {
            await #expect(processExitsWith: .failure) {
                let cell = ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
                let grid = ASCIIGrid(cells: [[cell, cell]], colorSpace: .sRGB)
                _ = ASCIIVideoFrame(grid: grid, time: .zero).applyingOngoingPattern(.wave(amplitude: 0.5, frequency: .nan, direction: .horizontal))
            }
        }

        @Test func videoFrameRejectsFrequencyInfinite() async {
            await #expect(processExitsWith: .failure) {
                let cell = ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
                let grid = ASCIIGrid(cells: [[cell, cell]], colorSpace: .sRGB)
                _ = ASCIIVideoFrame(grid: grid, time: .zero).applyingOngoingPattern(.wave(amplitude: 0.5, frequency: .infinity, direction: .horizontal))
            }
        }

        // The contract does not depend on the grid having any cells: an empty
        // grid used to short-circuit past the check and accept a bad pattern.
        @Test func applyingOngoingPatternRejectsAnUnevaluablePatternOnAnEmptyGrid() async {
            await #expect(processExitsWith: .failure) {
                _ = ASCIIGrid(cells: [], colorSpace: .sRGB)
                    .applyingOngoingPattern(.pulse(period: 0, depth: 1), at: 0)
            }
        }

        @Test func videoFrameRejectsAnUnevaluablePatternOnAnEmptyGrid() async {
            await #expect(processExitsWith: .failure) {
                _ = ASCIIVideoFrame(grid: ASCIIGrid(cells: [], colorSpace: .sRGB), time: .zero)
                    .applyingOngoingPattern(.wave(amplitude: 0.5, frequency: 0, direction: .horizontal))
            }
        }

        // convertVideo threads one caller pattern into every frame, so it has to
        // fail at the call rather than part-way through an export. The source
        // does not exist: the check runs before any decode is attempted.
        @Test func convertVideoRejectsAnUnevaluablePatternBeforeDecoding() async {
            await #expect(processExitsWith: .failure) {
                _ = try? await convertVideo(
                    at: URL(fileURLWithPath: "/nonexistent/aski-18-source.mp4"),
                    to: URL(fileURLWithPath: "/nonexistent/aski-18-output.mp4"),
                    using: DefaultConverter(),
                    columns: 8,
                    font: .system(size: 10),
                    backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                    scale: 1,
                    pattern: .pulse(period: 0, depth: 1)
                )
            }
        }

        // AnimationOptions.ongoing is a public `var`, so a valid options value
        // can be mutated out of domain AFTER init. The entry points that
        // consume it re-check, exactly as they re-check CyclingOptions.speed.
        @Test func scheduleBuilderRejectsAPatternMutatedInAfterConstruction() async {
            await #expect(processExitsWith: .failure) {
                let cell = ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
                let base = ASCIIGrid(cells: [[cell]], colorSpace: .sRGB)
                var options = AnimationOptions(duration: 1, ongoing: .pulse(period: 1, depth: 1))
                options.ongoing = .pulse(period: 0, depth: 1)
                _ = ScheduleBuilder.build(
                    baseGrid: base,
                    candidates: [0, 1],
                    candidateStride: 2,
                    candidateCounts: [2],
                    characterSet: CharacterSetSnapshot(characters: ["A", "B"]),
                    options: options
                )
            }
        }

        @Test func scheduleBuilderRejectsAMutatedInWaveFrequency() async {
            await #expect(processExitsWith: .failure) {
                let cell = ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)
                let base = ASCIIGrid(cells: [[cell]], colorSpace: .sRGB)
                var options = AnimationOptions(duration: 1)
                options.ongoing = .wave(amplitude: 0.5, frequency: .nan, direction: .horizontal)
                _ = ScheduleBuilder.build(
                    baseGrid: base,
                    candidates: [0, 1],
                    candidateStride: 2,
                    candidateCounts: [2],
                    characterSet: CharacterSetSnapshot(characters: ["A", "B"]),
                    options: options
                )
            }
        }

        // The full public animate entry point, with a real image, so the guard
        // is proven on the path an app actually takes.
        @Test func animateRejectsAPatternMutatedInAfterConstruction() async {
            await #expect(processExitsWith: .failure) {
                var options = AnimationOptions(duration: 1, ongoing: .pulse(period: 1, depth: 1))
                options.ongoing = .pulse(period: -1, depth: 1)
                _ = DefaultConverter().animate(
                    TestImages.horizontalGradient(width: 32, height: 32), columns: 8, options: options)
            }
        }

        @Test func videoFrameStillTreatsANilPatternAsIdentityRatherThanRejecting() {
            let frame = ASCIIVideoFrame(grid: Self.grid(), time: .zero)
            #expect(frame.applyingOngoingPattern(nil).grid.cells == frame.grid.cells)
        }
    #endif

    // MARK: valid patterns are untouched

    @Test func validPatternsStillModulateAndAreDeterministic() {
        let base = Self.grid()
        let pattern = OngoingPattern.pulse(period: 1, depth: 1)

        #expect(
            base.applyingOngoingPattern(pattern, at: 0.5).cells
                == base.applyingOngoingPattern(pattern, at: 0.5).cells)
        #expect(base.applyingOngoingPattern(pattern, at: 0.5).cells.flatMap { $0 }.allSatisfy { $0.alpha == 0 })
        #expect(base.applyingOngoingPattern(pattern, at: 0).cells.flatMap { $0 }.allSatisfy { $0.alpha == 1 })
    }

    @Test func aestheticKnobsAreStillSanitizedRatherThanRejected() {
        let base = Self.grid()

        // amplitude and depth keep clamping: a NaN falls back to its default and
        // the call succeeds, unlike the structural frequency/period knobs.
        #expect(base.applyingOngoingPattern(.pulse(period: 1, depth: .nan), at: 0.5).rows == 2)
        #expect(
            base.applyingOngoingPattern(
                .wave(amplitude: .nan, frequency: 1, direction: .horizontal), at: 0.5
            ).rows == 2)
    }
}
