import Testing
@testable import Aski

@Suite struct AnimationOptionsTests {
    @Test func defaultsMatchSpec() {
        let options = AnimationOptions(duration: 2)

        #expect(options.duration == 2)
        #expect(options.seed == 0)
        #expect(options.cycling == .default)
        #expect(options.entrance == nil)
        #expect(options.ongoing == nil)
        #expect(CyclingOptions.default.k == 6)
        #expect(CyclingOptions.default.speed == 1.0)
        #expect(CyclingOptions.default.intensity == 0.6)
        #expect(CyclingOptions.default.randomness == 0.5)
    }

    @Test func animationAnchorConstantsMatchUnitCoordinateNames() {
        #expect(AnimationAnchor.center == AnimationAnchor(x: 0.5, y: 0.5))
        #expect(AnimationAnchor.topLeading == AnimationAnchor(x: 0, y: 0))
        #expect(AnimationAnchor.topTrailing == AnimationAnchor(x: 1, y: 0))
        #expect(AnimationAnchor.bottomLeading == AnimationAnchor(x: 0, y: 1))
        #expect(AnimationAnchor.bottomTrailing == AnimationAnchor(x: 1, y: 1))
    }

    @Test func easingCurvesStayInUnitRangeForRepresentativeInputs() {
        for easing in [AnimationEasing.linear, .easeIn, .easeOut, .easeInOut] {
            #expect(easing.apply(0) == 0)
            #expect(easing.apply(1) == 1)
            #expect((0...1).contains(easing.apply(0.5)))
        }
    }
}
