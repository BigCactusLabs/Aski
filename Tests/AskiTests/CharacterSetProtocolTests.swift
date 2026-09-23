import CoreText
import Testing
import simd
@testable import Aski

@Suite struct CharacterSetProtocolTests {
    struct MockSet: ASCIICharacterSet {
        let characters: [Character] = ["A", "B"]
        let brightnessValues: [Float] = [0.3, 0.7]
        let shapeVectorLanes: [SIMD4<Float>] = Array(repeating: .zero, count: 30)
        // 15 SIMD4 per char × 2 chars = 30 lanes
    }

    @Test func conformingTypeUpholdsLayoutInvariants() {
        let m = MockSet()
        #expect(m.brightnessValues.count == m.characters.count)
        #expect(m.shapeVectorLanes.count == m.characters.count * MockSet.lanesPerCharacter)
        #expect(MockSet.shapeVectorDimension == MockSet.lanesPerCharacter * 4)
    }

    @Test func rawDensityDefaultsToBrightnessFallback() {
        let m = MockSet()
        #expect(m.rawDensityValues == m.brightnessValues)
    }

    @Test func rasterizedSetExposesPreNormalizationDensity() {
        let font = CTFontCreateWithName("Courier" as CFString, 32, nil)
        let set = RasterizedCharacterSet(characters: [" ", ".", "@"], font: font)
        #expect(set.rawDensityValues.count == set.characters.count)
        #expect(set.rawDensityValues[0] == 0)  // space has no ink
        let maxRaw = set.rawDensityValues.max()!
        #expect(maxRaw > 0 && maxRaw < 1)  // absolute coverage, not normalized
        #expect(set.brightnessValues.max()! == 1.0)  // normalized scale unchanged
        for (raw, norm) in zip(set.rawDensityValues, set.brightnessValues) {
            #expect(abs(raw - norm * maxRaw) < 1e-6)  // raw = norm × maxRaw
        }
    }
}
