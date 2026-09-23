import Testing
import simd
@testable import AskiAccessLab

@Suite struct AskiAccessLabCVDModelTests {
    @Test func modelMetadataIsPinned() {
        #expect(CVDModel.modelID == "brettel1997_dichromacy_srgb")
        #expect(ColorVisionDeficiency.allCases.map(\.rawValue) == ["protanopia", "deuteranopia", "tritanopia"])
    }

    @Test(arguments: ColorVisionDeficiency.allCases)
    func blackWhiteAndNeutralRemainStable(_ deficiency: ColorVisionDeficiency) {
        #expect(CVDModel.simulateEncodedSRGB(.zero, deficiency: deficiency) == .zero)
        #expect(distance(CVDModel.simulateEncodedSRGB(.one, deficiency: deficiency), .one) < 0.0001)
        let gray = SIMD3<Float>(0.5, 0.5, 0.5)
        #expect(distance(CVDModel.simulateEncodedSRGB(gray, deficiency: deficiency), gray) < 0.02)
    }

    @Test(arguments: ColorVisionDeficiency.allCases)
    func saturatedRedChangesUnderEveryDichromacy(_ deficiency: ColorVisionDeficiency) {
        let simulated = CVDModel.simulateEncodedSRGB(SIMD3<Float>(1, 0, 0), deficiency: deficiency)
        #expect(distance(simulated, SIMD3<Float>(1, 0, 0)) > 0.05)
        #expect(simulated.x >= 0 && simulated.x <= 1)
        #expect(simulated.y >= 0 && simulated.y <= 1)
        #expect(simulated.z >= 0 && simulated.z <= 1)
    }

    @Test func severityIsFixedAtOnePointZero() {
        #expect(CVDModel.severity == "1.0")
    }

    private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        simd_length(a - b)
    }
}
