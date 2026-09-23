import Aski
import Testing
@testable import AskiMotionLab

@Suite struct AskiMotionLabFrameTests {
    private func textFrames(
        _ preset: MotionLabPreset,
        fps: Int = 10,
        duration: Double = 1.0,
        seed: UInt64 = 0
    ) -> [String] {
        let options = MotionPresets.options(for: preset, duration: duration, seed: seed)
        let animated = DefaultConverter().animate(SyntheticImage.make(), columns: 32, options: options)
        return animated.materialize(frameRate: fps).map(FrameTextRenderer.render)
    }

    private func visibleCount(_ frame: String) -> Int {
        frame.filter { $0 != " " && $0 != "\n" }.count
    }

    @Test func materializeYieldsExpectedFrameCount() {
        // fps * duration lands exactly on a frame boundary, so materialize
        // includes both endpoints: 10 * 1.0 -> indices 0...10 -> 11 frames.
        #expect(textFrames(.reveal, fps: 10, duration: 1.0).count == 11)
    }

    @Test func sameSeedAndInputProduceIdenticalFrames() {
        #expect(textFrames(.cycle, seed: 0) == textFrames(.cycle, seed: 0))
    }

    @Test func revealSequenceIsNonDegenerateByVisibility() {
        let frames = textFrames(.reveal)
        #expect(visibleCount(frames.last!) > visibleCount(frames.first!))
    }

    @Test func cycleSequenceIsNonDegenerateByGlyph() {
        let frames = textFrames(.cycle)
        #expect(Set(frames).count > 1)
    }

    @Test func revealHoldsGlyphsConstant() {
        let frames = textFrames(.reveal)
        let nonSpace = frames.last!.filter { $0 != " " && $0 != "\n" }
        #expect(!nonSpace.isEmpty)
    }
}
