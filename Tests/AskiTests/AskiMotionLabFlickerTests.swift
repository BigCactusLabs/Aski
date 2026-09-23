import Aski
import Testing
@testable import AskiMotionLab

@Suite struct AskiMotionLabFlickerTests {
    private func grids(_ options: AnimationOptions, fps: Int = 12) -> [ASCIIGrid] {
        DefaultConverter()
            .animate(SyntheticImage.make(), columns: 32, options: options)
            .materialize(frameRate: fps)
    }

    @Test func staticGridHasZeroChurnOnBothAxes() {
        let metrics = FlickerMetrics.compute(
            frames: grids(
                AnimationOptions(duration: 1.0, seed: 0, cycling: nil, entrance: nil, ongoing: nil)
            ))
        #expect(metrics.meanGlyphChurn == 0)
        #expect(metrics.maxGlyphChurn == 0)
        #expect(metrics.meanAlphaChurn == 0)
        #expect(metrics.maxAlphaChurn == 0)
    }

    @Test func revealIsolatesTheAlphaAxis() {
        let metrics = FlickerMetrics.compute(frames: grids(MotionPresets.reveal(duration: 1.0, seed: 0)))
        #expect(metrics.meanAlphaChurn > 0)
        #expect(metrics.meanGlyphChurn == 0)
    }

    @Test func cycleIsolatesTheGlyphAxis() {
        let metrics = FlickerMetrics.compute(frames: grids(MotionPresets.cycle(duration: 1.0, seed: 0)))
        #expect(metrics.meanGlyphChurn > 0)
        #expect(metrics.meanAlphaChurn == 0)
    }

    @Test func fewerThanTwoFramesReturnsZero() {
        let metrics = FlickerMetrics.compute(frames: [])
        #expect(metrics.meanGlyphChurn == 0)
        #expect(metrics.meanAlphaChurn == 0)
    }
}
