import CoreText
import Testing
import simd

@testable import Aski

@Suite struct GlyphBankTests {
    @Test func committedBankKeepsItsTagAndFormatWithoutInventingRasterProvenance() {
        let cases: [(String, StandardCharacterSet)] = [
            ("standard", .standard),
            ("minimal", .minimal),
            ("blocks", .blocks),
            ("dots", .dots),
            ("lines", .lines),
            ("diagonal", .diagonal),
            ("cross", .cross),
            ("diamond", .diamond),
            ("mixed", .mixed),
            ("braille", .braille),
        ]

        for (name, characterSet) in cases {
            let provenance = characterSet.glyphBank.provenance
            guard case .committedAsset(let setName, let formatVersion) = provenance else {
                Issue.record("\(name) was not marked as a committed asset")
                continue
            }
            #expect(setName == name)
            #expect(formatVersion == 3)
        }
    }

    @Test func runtimeBankRecordsObservedCoreTextConventionAsDynamic() throws {
        let font = CTFontCreateWithName("Courier" as CFString, 32, nil)
        let characterSet = RasterizedCharacterSet(characters: [" ", "M", "@"], font: font)
        let provenance = characterSet.glyphBank.provenance

        guard case .runtimeCoreText(let rasterization) = provenance else {
            Issue.record("runtime character set was not marked as dynamic Core Text data")
            return
        }
        #expect(rasterization.width == 64)
        #expect(rasterization.height == 64)
        #expect(rasterization.densityCellWidth > 0)
        #expect(rasterization.densityCellHeight > 0)
        #expect(rasterization.placement == .imageBoundsCentered)
        #expect(rasterization.baseline == .derivedFromImageBounds)
        #expect(rasterization.antialiasing == .coreGraphicsDefault)
        #expect(rasterization.colorSpace == .deviceGray8Bit)
        #expect(!rasterization.font.postScriptName.isEmpty)
        #expect(rasterization.font.pointSize == 32)
        #expect(rasterization.font.transformFingerprint != 0)

        let largeFont = CTFontCreateWithName("Courier" as CFString, 1_024, nil)
        let largeSet = RasterizedCharacterSet(characters: ["M"], font: largeFont)
        guard case .runtimeCoreText(let largeRasterization) = largeSet.glyphBank.provenance else {
            Issue.record("large runtime character set lost Core Text provenance")
            return
        }
        #expect(largeRasterization.densityCellWidth == 64)
        #expect(largeRasterization.densityCellHeight == 64)
    }

    @Test func externalConformanceIsSnapshottedOnceAndMarkedCallerDefined() {
        let characterSet = ExternalCharacterSet(character: "x", brightness: 0.25)
        let converter = ASCIIConverter(
            characterSet: characterSet,
            palette: BuiltInPalette.fullColor,
            algorithm: .dotMatrix
        )

        guard case .externalSnapshot = converter.glyphBank.provenance else {
            Issue.record("external conformance was not marked as an external snapshot")
            return
        }
        expectSharedBuffers(characterSet, converter.glyphBank)
        let bankIdentity = converter.glyphBank
        _ = converter.convert(TestImages.horizontalGradient(width: 32, height: 16), columns: 8)
        _ = converter.convert(TestImages.horizontalGradient(width: 32, height: 16), columns: 8)
        #expect(converter.glyphBank === bankIdentity)

        var projectedBrightness = characterSet.brightnessValues
        projectedBrightness[0] = 0.75
        #expect(converter.glyphBank.brightnessValues == [0.25])
    }

    @Test func libraryCharacterSetsAndConverterShareExactBankIdentityAndAllBuffers() {
        let builtIn = StandardCharacterSet.standard
        let builtInConverter = ASCIIConverter(
            characterSet: builtIn,
            palette: BuiltInPalette.fullColor
        )
        #expect(builtIn.glyphBank === builtInConverter.glyphBank)
        expectSharedBuffers(builtIn, builtIn.glyphBank)
        expectSharedBuffers(builtIn, builtInConverter.glyphBank)

        let font = CTFontCreateWithName("Courier" as CFString, 32, nil)
        let rasterized = RasterizedCharacterSet(characters: [" ", "M", "@"], font: font)
        let rasterizedConverter = ASCIIConverter(
            characterSet: rasterized,
            palette: BuiltInPalette.fullColor
        )
        #expect(rasterized.glyphBank === rasterizedConverter.glyphBank)
        expectSharedBuffers(rasterized, rasterized.glyphBank)
        expectSharedBuffers(rasterized, rasterizedConverter.glyphBank)
    }

    @Test func validCharacterSetAssignmentRefreshesTheBankUsedForConversion() {
        var converter = ASCIIConverter(
            characterSet: ExternalCharacterSet(character: "x", brightness: 0),
            palette: BuiltInPalette.fullColor,
            algorithm: .dotMatrix
        )
        converter.characterSet = ExternalCharacterSet(character: "y", brightness: 1)

        let grid = converter.convert(
            TestImages.horizontalGradient(width: 32, height: 16),
            columns: 8
        )
        #expect(grid.cells.flatMap { $0 }.allSatisfy { $0.character == "y" })
    }
}

private struct ExternalCharacterSet: ASCIICharacterSet {
    let characters: [Character]
    let brightnessValues: [Float]
    let rawDensityValues: [Float]
    let shapeVectorLanes: [SIMD4<Float>]

    init(character: Character, brightness: Float) {
        self.characters = [character]
        self.brightnessValues = [brightness]
        self.rawDensityValues = [brightness]
        self.shapeVectorLanes = Array(repeating: .zero, count: GlyphBank.lanesPerCharacter)
    }
}

private func expectSharedBuffers<C: ASCIICharacterSet>(
    _ characterSet: C,
    _ glyphBank: GlyphBank,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        sharesStorage(characterSet.characters, glyphBank.characters),
        "characters buffer was copied",
        sourceLocation: sourceLocation
    )
    #expect(
        sharesStorage(characterSet.brightnessValues, glyphBank.brightnessValues),
        "brightness buffer was copied",
        sourceLocation: sourceLocation
    )
    #expect(
        sharesStorage(characterSet.rawDensityValues, glyphBank.rawDensityValues),
        "raw-density buffer was copied",
        sourceLocation: sourceLocation
    )
    #expect(
        sharesStorage(characterSet.shapeVectorLanes, glyphBank.shapeVectorLanes),
        "shape-lane buffer was copied",
        sourceLocation: sourceLocation
    )
}

private func sharesStorage<Element>(_ lhs: [Element], _ rhs: [Element]) -> Bool {
    lhs.withUnsafeBufferPointer { left in
        rhs.withUnsafeBufferPointer { right in
            left.baseAddress == right.baseAddress
        }
    }
}
