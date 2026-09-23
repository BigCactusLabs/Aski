import CoreGraphics
import Testing
@testable import Aski

@Suite
struct AnimationMaskCompositionTests {
    @Test
    func animateWithColumnsLessThanOneReturnsEmptyGrid() {
        let image = TestImages.horizontalGradient(width: 20, height: 20)
        let animated = DefaultConverter().animate(image, columns: 0, options: AnimationOptions(duration: 1))

        #expect(animated.baseGrid.cells.isEmpty)
        #expect(animated.grid(at: 0.5).cells.isEmpty)
    }

    @Test
    func maskedCoverageIsCarriedThroughFrames() {
        let image = TestImages.horizontalGradient(width: 80, height: 80)
        let maskImage = TestImages.verticalSplitMask(width: 80, height: 80)
        let ground = CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.75)
        let mask = MaskOptions(
            image: maskImage,
            fallback: .transparent,
            groundColor: ground,
            softEdges: true
        )
        let animated = DefaultConverter().animate(
            image,
            columns: 12,
            options: AnimationOptions(
                duration: 1,
                cycling: CyclingOptions(k: 3, speed: 1, intensity: 1, randomness: 0)
            ),
            mask: mask
        )
        let frame = animated.grid(at: 0.5)

        #expect(frame.cells.flatMap { $0 }.map(\.coverage) == animated.baseGrid.cells.flatMap { $0 }.map(\.coverage))
        if case .some(.transparent) = frame.maskFallback {
        } else {
            Issue.record("expected transparent fallback")
        }
        #expect(frame.maskUsesHardEdges == animated.baseGrid.maskUsesHardEdges)
        #expect(frame.maskGroundColor?.alpha == animated.baseGrid.maskGroundColor?.alpha)
    }

    @Test
    func ongoingPatternPreservesAllMaskCompositionFields() {
        let fallback = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        let ground = CGColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        let cell = ASCIICell(
            character: "#",
            displayColor: SIMD3<Float>(1, 1, 1),
            alpha: 1,
            brightness: 0.5,
            coverage: 0.25
        )
        let grid = ASCIIGrid(
            cells: [[cell]],
            colorSpace: .sRGB,
            maskFallback: .solid(fallback),
            maskGroundColor: ground,
            maskUsesHardEdges: true
        )

        let copy = grid.applyingOngoingPattern(.pulse(period: 1, depth: 0.5), at: 0.25)

        #expect(copy.maskFallback != nil)
        #expect(copy.maskGroundColor?.alpha == 0.5)
        #expect(copy.maskUsesHardEdges)
    }
}
