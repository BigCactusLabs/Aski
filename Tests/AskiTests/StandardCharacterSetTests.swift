import Testing
import simd
@testable import Aski

@Suite struct StandardCharacterSetTests {
    @Test func standardLoadsFromBundle() {
        let s = StandardCharacterSet.standard
        #expect(s.characters.count >= 90)
        #expect(s.characters.count == s.brightnessValues.count)
        #expect(s.shapeVectorLanes.count == s.characters.count * 15)
    }

    @Test func minimalHasTenCharacters() {
        let m = StandardCharacterSet.minimal
        #expect(m.characters.count == 10)
    }

    @Test func blocksHasUnicodeBlockElements() {
        let b = StandardCharacterSet.blocks
        #expect(b.characters.contains("█"))
    }

    @Test func brightnessMonotonicallyIncreasesInMinimal() {
        let m = StandardCharacterSet.minimal
        for i in 1..<m.brightnessValues.count {
            #expect(m.brightnessValues[i] >= m.brightnessValues[i - 1])
        }
    }

    // Anchor-value tests catching float-roundtrip / serializer bit-pattern bugs that
    // count + monotonicity assertions don't. Per Task 2.3 anchor-test pattern.

    @Test func minimalStartsWithSpaceAtBrightnessZero() {
        let m = StandardCharacterSet.minimal
        #expect(m.characters.first == " ")
        #expect(m.brightnessValues.first == 0.0)
    }

    @Test func standardEndsWithDensestCharacterAtMaxBrightness() {
        let s = StandardCharacterSet.standard
        #expect(s.brightnessValues.last == 1.0)
    }

    @Test func dotsLoadsAndStartsWithSpace() {
        let s = StandardCharacterSet.dots
        #expect(s.characters.first == " ")
        #expect(s.characters.count > 1)
        #expect(s.shapeVectorLanes.count == s.characters.count * 15)
    }

    @Test func linesLoadsAndStartsWithSpace() {
        let s = StandardCharacterSet.lines
        #expect(s.characters.first == " ")
        #expect(s.characters.count > 1)
        #expect(s.shapeVectorLanes.count == s.characters.count * 15)
    }

    @Test func diagonalLoadsAndStartsWithSpace() {
        let s = StandardCharacterSet.diagonal
        #expect(s.characters.first == " ")
        #expect(s.characters.count > 1)
    }

    @Test func crossLoadsAndStartsWithSpace() {
        let s = StandardCharacterSet.cross
        #expect(s.characters.first == " ")
        #expect(s.characters.count > 1)
    }

    @Test func diamondLoadsAndStartsWithSpace() {
        let s = StandardCharacterSet.diamond
        #expect(s.characters.first == " ")
        #expect(s.characters.count > 1)
    }

    @Test func mixedLoadsAndStartsWithSpace() {
        let s = StandardCharacterSet.mixed
        #expect(s.characters.first == " ")
        #expect(s.characters.count > 1)
    }

    @Test func brailleHas256Codepoints() {
        let b = StandardCharacterSet.braille
        #expect(b.characters.count == 256)
        #expect(b.shapeVectorLanes.count == 256 * 15)
        let firstScalar = b.characters.first!.unicodeScalars.first!.value
        #expect(firstScalar == 0x2800)
    }

    @Test func brightnessValuesAreSortedAscendingForEachNewCharset() {
        for set in [
            StandardCharacterSet.dots, .lines, .diagonal, .cross,
            .diamond, .mixed, .braille,
        ] {
            for i in 1..<set.brightnessValues.count {
                #expect(set.brightnessValues[i] >= set.brightnessValues[i - 1])
            }
        }
    }

    // v2 regen gate: fails while the bundled files are v1 (fallback makes
    // rawDensityValues == brightnessValues); passes once the raw block ships.
    @Test func builtInSetsCarryAbsoluteRawDensity() {
        let s = StandardCharacterSet.standard
        #expect(s.rawDensityValues.count == s.characters.count)
        #expect(s.rawDensityValues != s.brightnessValues)
        let maxRaw = s.rawDensityValues.max()!
        #expect(maxRaw > 0 && maxRaw < 1)  // Courier's densest glyph covers well under the full cell
        for (raw, norm) in zip(s.rawDensityValues, s.brightnessValues) {
            #expect(abs(raw - norm * maxRaw) < 1e-5)
        }
        for set in [
            StandardCharacterSet.minimal, .blocks, .dots, .lines,
            .diagonal, .cross, .diamond, .mixed, .braille,
        ] {
            #expect(set.rawDensityValues.count == set.characters.count)
            #expect(set.rawDensityValues.allSatisfy { $0 >= 0 && $0 <= 1 })
            // raw density preserves the brightness sort order, up to
            // normalized-brightness quantization ties (distinct raw values can
            // normalize to the same brightness float — e.g. braille — so the
            // sort can't order within the tie; inversions are one-ulp scale)
            for i in 1..<set.rawDensityValues.count {
                #expect(set.rawDensityValues[i] >= set.rawDensityValues[i - 1] - 1e-6)
            }
        }
    }
}
