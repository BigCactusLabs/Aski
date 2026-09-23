import Aski
import Testing
import simd
@testable import AskiColorLab

@Suite struct AskiColorLabGamutSweepCrossCheckTests {
    @Test func rayTraceMatchesPinnedColorJSReference() {
        let tolerance: Float = 1e-4

        for fixture in GamutSweepFixtures.all {
            for target in GamutSweepTarget.allCases {
                let actual = GamutSweepPolicies.rayTrace(
                    oklab: fixture.sourceOKLab,
                    target: target
                )
                let expected = ReferenceRayTrace.map(
                    oklab: fixture.sourceOKLab,
                    target: target
                )
                let delta = maxComponent(abs(actual - expected))

                #expect(
                    delta <= tolerance,
                    "\(fixture.id) \(target.csvLabel) Ray Trace drift \(delta) exceeds \(tolerance); actual=\(actual) expected=\(expected)"
                )
            }
        }
    }

    @Test func edgeSeekerMatchesPinnedColorJSReference() {
        let chromaTolerance: Float = 0.02
        let oklabComponentTolerance: Float = 0.02

        for fixture in GamutSweepFixtures.all {
            for target in GamutSweepTarget.allCases {
                let actualLinear = edgeSeekerProductionMap(
                    oklab: fixture.sourceOKLab,
                    target: target
                )
                let expectedLinear = ReferenceEdgeSeeker.map(
                    oklab: fixture.sourceOKLab,
                    target: target
                )
                let actualOKLab = target.linearRGBToOKLab(actualLinear)
                let expectedOKLab = target.linearRGBToOKLab(expectedLinear)
                let actualChroma = GamutSweepMetrics.chroma(of: actualOKLab)
                let expectedChroma = GamutSweepMetrics.chroma(of: expectedOKLab)
                let chromaDelta = abs(actualChroma - expectedChroma)
                let vectorDelta = maxComponent(abs(actualOKLab - expectedOKLab))

                #expect(
                    chromaDelta <= chromaTolerance,
                    "\(fixture.id) \(target.csvLabel) EdgeSeeker chroma drift \(chromaDelta) exceeds \(chromaTolerance); actualC=\(actualChroma) expectedC=\(expectedChroma)"
                )
                #expect(
                    vectorDelta <= oklabComponentTolerance,
                    "\(fixture.id) \(target.csvLabel) EdgeSeeker OKLab drift \(vectorDelta) exceeds \(oklabComponentTolerance); actualOKLab=\(actualOKLab) expectedOKLab=\(expectedOKLab)"
                )
            }
        }
    }

    private func edgeSeekerProductionMap(
        oklab: SIMD3<Float>,
        target: GamutSweepTarget
    ) -> SIMD3<Float> {
        switch target {
        case .sRGB:
            EdgeSeekerMapping.forSRGB.map(oklab: oklab)
        case .displayP3:
            EdgeSeekerMapping.forDisplayP3.map(oklab: oklab)
        }
    }

    private func maxComponent(_ value: SIMD3<Float>) -> Float {
        max(value.x, max(value.y, value.z))
    }
}
