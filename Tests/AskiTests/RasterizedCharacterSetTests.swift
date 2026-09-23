import Testing
import CoreText
import simd
@testable import Aski

@Suite struct RasterizedCharacterSetTests {
    @Test func rasterizesKnownRampIntoSortedBrightness() {
        let font = CTFontCreateWithName("Courier" as CFString, 32, nil)
        let set = RasterizedCharacterSet(characters: Array(" .:-=+*#@"), font: font)
        #expect(set.characters.count == 9)
        #expect(set.brightnessValues.count == 9)
        // Space has no ink.
        #expect(set.brightnessValues.first! < 0.05)
        // @ is a visually dense character — its normalized value should be
        // substantial even though # outranks it on raw pixel coverage
        // (@ has an interior hole, # doesn't).
        #expect(set.brightnessValues.last! > 0.3)
        // Cross-character normalization contract: the densest glyph in the
        // set — whichever it is — lands at exactly 1.0. Asserting the max
        // directly catches any regression that drops or reorders the
        // normalization step.
        #expect(set.brightnessValues.max()! == 1.0)
    }

    @Test func shapeVectorLaneCount() {
        let font = CTFontCreateWithName("Courier" as CFString, 32, nil)
        let chars: [Character] = ["A", "B", "C"]
        let set = RasterizedCharacterSet(characters: chars, font: font)
        #expect(set.shapeVectorLanes.count == 3 * 15)  // 3 chars × 15 lanes each
    }

    @Test func twoDifferentCharactersHaveDifferentShapeVectors() {
        let font = CTFontCreateWithName("Courier" as CFString, 32, nil)
        let set = RasterizedCharacterSet(characters: ["I", "O"], font: font)
        let iLanes = Array(set.shapeVectorLanes[0..<15])
        let oLanes = Array(set.shapeVectorLanes[15..<30])
        var delta: Float = 0
        for j in 0..<15 {
            let d = iLanes[j] - oLanes[j]
            delta += simd_length_squared(d)
        }
        #expect(delta > 0.01)  // they must differ
    }

    /// Core Text accepts non-finite and huge point sizes, then reports metrics
    /// that cannot be converted to `Int`. Rasterization must degrade instead
    /// of trapping while reading those external metrics.
    @Test func outOfDomainCoreTextMetricsDegradeWithoutTrapping() {
        for size in [CGFloat.infinity, .nan, .greatestFiniteMagnitude] {
            let font = CTFontCreateWithName("Courier" as CFString, size, nil)
            let set = RasterizedCharacterSet(characters: ["M"], font: font)

            #expect(set.characters == ["M"], "font size \(size)")
            #expect(set.rawDensityValues.allSatisfy { $0.isFinite }, "font size \(size)")
            #expect(set.brightnessValues.allSatisfy { $0.isFinite }, "font size \(size)")
        }
    }

    #if !SWT_NO_EXIT_TESTS
        @Test func emptyCharactersFailPrecondition() async {
            await #expect(processExitsWith: .failure) {
                let font = CTFontCreateWithName("Courier" as CFString, 32, nil)
                _ = RasterizedCharacterSet(characters: [], font: font)
            }
        }
    #endif
}
