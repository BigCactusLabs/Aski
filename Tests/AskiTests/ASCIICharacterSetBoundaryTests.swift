import CoreText
import Testing
import simd

@testable import Aski

/// ASKI-53: custom `ASCIICharacterSet` conformances reach the matcher only
/// after the converter accepts a complete per-glyph parallel-array layout.
@Suite struct ASCIICharacterSetBoundaryTests {
    #if !SWT_NO_EXIT_TESTS
        @Test func eachMalformedParallelArrayFailsAtTheConverterBoundary() async {
            await #expect(processExitsWith: .failure) {
                _ = ASCIIConverter(
                    characterSet: MalformedCharacterSet(brightnessValues: []),
                    palette: BuiltInPalette.fullColor)
            }
            await #expect(processExitsWith: .failure) {
                _ = ASCIIConverter(
                    characterSet: MalformedCharacterSet(rawDensityValues: []),
                    palette: BuiltInPalette.fullColor)
            }
            await #expect(processExitsWith: .failure) {
                _ = ASCIIConverter(
                    characterSet: MalformedCharacterSet(shapeVectorLanes: []),
                    palette: BuiltInPalette.fullColor)
            }
        }

        @Test func emptyCharacterSetFailsAtTheConverterBoundary() async {
            await #expect(processExitsWith: .failure) {
                _ = ASCIIConverter(
                    characterSet: MalformedCharacterSet(
                        characters: [], brightnessValues: [],
                        rawDensityValues: [], shapeVectorLanes: []),
                    palette: BuiltInPalette.fullColor)
            }
        }

        @Test func postInitAssignmentFailsAtTheConverterBoundary() async {
            await #expect(processExitsWith: .failure) {
                var converter = ASCIIConverter(
                    characterSet: MalformedCharacterSet(),
                    palette: BuiltInPalette.fullColor)
                converter.characterSet = MalformedCharacterSet(brightnessValues: [])
            }
        }
    #endif

    @Test func builtInAndRasterizedCharacterSetsRemainByteIdenticalAtTheBoundary() {
        let builtIn = StandardCharacterSet.standard
        let builtInConverter = ASCIIConverter(
            characterSet: builtIn, palette: BuiltInPalette.fullColor)
        #expect(builtInConverter.characterSet.characters == builtIn.characters)
        #expect(builtInConverter.characterSet.brightnessValues == builtIn.brightnessValues)
        #expect(builtInConverter.characterSet.rawDensityValues == builtIn.rawDensityValues)
        #expect(builtInConverter.characterSet.shapeVectorLanes == builtIn.shapeVectorLanes)

        let font = CTFontCreateWithName("Courier" as CFString, 32, nil)
        let rasterized = RasterizedCharacterSet(
            characters: [" ", "|", "@"], font: font)
        let rasterizedConverter = ASCIIConverter(
            characterSet: rasterized, palette: BuiltInPalette.fullColor)
        #expect(rasterizedConverter.characterSet.characters == rasterized.characters)
        #expect(rasterizedConverter.characterSet.brightnessValues == rasterized.brightnessValues)
        #expect(rasterizedConverter.characterSet.rawDensityValues == rasterized.rawDensityValues)
        #expect(rasterizedConverter.characterSet.shapeVectorLanes == rasterized.shapeVectorLanes)
    }
}

private struct MalformedCharacterSet: ASCIICharacterSet {
    let characters: [Character]
    let brightnessValues: [Float]
    let rawDensityValues: [Float]
    let shapeVectorLanes: [SIMD4<Float>]

    init(
        characters: [Character] = ["x"],
        brightnessValues: [Float] = [0],
        rawDensityValues: [Float] = [0],
        shapeVectorLanes: [SIMD4<Float>] = Array(
            repeating: .zero,
            count: StandardCharacterSet.lanesPerCharacter)
    ) {
        self.characters = characters
        self.brightnessValues = brightnessValues
        self.rawDensityValues = rawDensityValues
        self.shapeVectorLanes = shapeVectorLanes
    }
}
