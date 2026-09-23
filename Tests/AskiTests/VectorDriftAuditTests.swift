import CoreText
import Foundation
import Testing
@testable import BuildStandardVectors

@Suite struct VectorDriftAuditTests {
    @Test func argumentParserSeparatesAuditFromRegeneration() throws {
        #expect(try BuildStandardVectors.parseArguments([]) == .regenerate(charset: nil))
        #expect(try BuildStandardVectors.parseArguments(["--charset", "dots"]) == .regenerate(charset: "dots"))
        #expect(
            try BuildStandardVectors.parseArguments(["--audit", "--output-dir", "/tmp/out", "--charset", "standard"])
                == .audit(outputDirectory: "/tmp/out", charset: "standard"))
        #expect(throws: BuildStandardVectors.ArgumentError.missingOutputDirectory) {
            try BuildStandardVectors.parseArguments(["--audit"])
        }
        #expect(throws: BuildStandardVectors.ArgumentError.invalidArguments) {
            try BuildStandardVectors.parseArguments(["--output-dir", "/tmp/out"])
        }
    }

    @Test func inMemoryEncoderRoundTripsThroughIndependentAuditDecoder() throws {
        let spec = try #require(BuildStandardVectors.allSets.first { $0.name == "minimal" })
        let font = CTFontCreateWithName("Courier" as CFString, 32, nil)
        let data = BuildStandardVectors.generateSingleCharsetBin(spec: spec, font: font)
        let decoded = try VectorBin.decode(data)
        #expect(decoded.name == "minimal")
        #expect(decoded.glyphs.count == spec.characters.count)
        #expect(Set(decoded.glyphs.map(\.scalar)).count == spec.characters.count)
        #expect(decoded.glyphs.allSatisfy { $0.shape.count == 60 })
        #expect(decoded.glyphs.allSatisfy { $0.orientationHistogram.count == 8 })
    }

    @Test func comparisonIsScalarKeyedAndDetectsOrderChanges() throws {
        let spec = try #require(BuildStandardVectors.allSets.first { $0.name == "minimal" })
        let font = CTFontCreateWithName("Courier" as CFString, 32, nil)
        let data = BuildStandardVectors.generateSingleCharsetBin(spec: spec, font: font)
        let same = try VectorDriftAudit.compare(name: "minimal", committedData: data, freshData: data)
        #expect(same.byteIdentical)
        #expect(!same.sortPermutationChanged)
        #expect(same.maximum == 0)

        let reordered = try reorderFirstTwoGlyphRecords(data)
        let changed = try VectorDriftAudit.compare(name: "minimal", committedData: data, freshData: reordered)
        #expect(!changed.byteIdentical)
        #expect(changed.sortPermutationChanged)
        #expect(changed.maximum == 0)
    }

    @Test func escalationThresholdIsStrictAndOrderIsIndependent() {
        let below = SetDrift(
            name: "test", byteIdentical: false, sortPermutationChanged: false,
            glyphs: [drift(maximum: VectorDriftAuditResult.tolerance)])
        #expect(!VectorDriftAuditResult(sets: [below]).triggerFired)

        let above = SetDrift(
            name: "test", byteIdentical: false, sortPermutationChanged: false,
            glyphs: [drift(maximum: VectorDriftAuditResult.tolerance.nextUp)])
        #expect(VectorDriftAuditResult(sets: [above]).triggerFired)

        let reordered = SetDrift(name: "test", byteIdentical: false, sortPermutationChanged: true, glyphs: [])
        #expect(VectorDriftAuditResult(sets: [reordered]).triggerFired)
    }

    @Test(
        "Every ShapeData float channel rejects NaN",
        arguments: NonFiniteChannel.allCases)
    func nonFiniteComponentsFailClosed(channel: NonFiniteChannel) throws {
        let spec = try #require(BuildStandardVectors.allSets.first { $0.name == "minimal" })
        let font = CTFontCreateWithName("Courier" as CFString, 32, nil)
        let valid = BuildStandardVectors.generateSingleCharsetBin(spec: spec, font: font)
        let decoded = try VectorBin.decode(valid)
        var glyphs = decoded.glyphs
        let glyph = glyphs[0]
        var shape = glyph.shape
        var orientation = glyph.orientationHistogram
        if channel == .shape { shape[0] = .nan }
        if channel == .orientation { orientation[0] = .nan }
        glyphs[0] = VectorBinGlyph(
            scalar: glyph.scalar,
            brightness: channel == .brightness ? .nan : glyph.brightness,
            shape: shape,
            rawDensity: channel == .rawDensity ? .nan : glyph.rawDensity,
            orientationHistogram: orientation,
            radialPeak: channel == .radialPeak ? .nan : glyph.radialPeak)
        let poisoned = encode(name: decoded.name, glyphs: glyphs)

        #expect(throws: VectorDriftAuditError.self) {
            try VectorDriftAudit.compare(
                name: decoded.name, committedData: valid, freshData: poisoned)
        }
    }

    enum NonFiniteChannel: String, CaseIterable, CustomTestStringConvertible {
        case brightness
        case shape
        case rawDensity
        case orientation
        case radialPeak

        var testDescription: String { rawValue }
    }

    private func drift(maximum: Float) -> GlyphDrift {
        GlyphDrift(
            set: "test", scalar: 0x20, brightness: maximum, rawDensity: 0,
            shape: 0, orientation: 0, radialPeak: 0)
    }

    /// Swap complete glyph records while preserving scalar-keyed values. This
    /// constructs a valid v3 file whose only semantic change is sort order.
    private func reorderFirstTwoGlyphRecords(_ data: Data) throws -> Data {
        let decoded = try VectorBin.decode(data)
        var glyphs = decoded.glyphs
        glyphs.swapAt(0, 1)
        return encode(name: decoded.name, glyphs: glyphs)
    }

    private func encode(name: String, glyphs: [VectorBinGlyph]) -> Data {
        var data = Data()
        data.append(u32: 0xA5C1_1E01)
        data.append(u32: 3)
        data.append(u32: 1)
        let nameData = Data(name.utf8)
        data.append(u32: UInt32(nameData.count))
        data.append(nameData)
        data.append(u32: UInt32(glyphs.count))
        data.append(u32: 60)
        glyphs.forEach { data.append(u32: $0.scalar) }
        glyphs.forEach { data.append(f32: $0.brightness) }
        glyphs.forEach { glyph in glyph.shape.forEach { data.append(f32: $0) } }
        glyphs.forEach { data.append(f32: $0.rawDensity) }
        glyphs.forEach { glyph in glyph.orientationHistogram.forEach { data.append(f32: $0) } }
        glyphs.forEach { data.append(f32: $0.radialPeak) }
        return data
    }
}
