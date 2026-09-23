import Foundation
import Testing
import simd
@testable import Aski

// Test-local little-endian encoders mirroring the documented .bin layout
// (the production encoder lives in the BuildStandardVectors executable,
// which test targets cannot import).
extension Data {
    fileprivate mutating func appendU32(_ v: UInt32) {
        var x = v.littleEndian
        Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) }
    }
    fileprivate mutating func appendF32(_ v: Float) { appendU32(v.bitPattern) }
}

/// One set payload: nameLen, name, charCount, dim=60, scalars, brightness,
/// lanes (15×4 f32 per char), v2 raw-density block (when non-nil), and the v3
/// channel block (when non-nil): per-glyph 8-f32 orientation hist block then
/// per-glyph f32 radial-peak block.
private func setPayload(
    name: String, chars: [UInt32], brightness: [Float],
    rawDensity: [Float]?, laneFill: Float,
    orientationHistograms: [Float]? = nil, radialPeaks: [Float]? = nil
) -> Data {
    var d = Data()
    let nameBytes = Data(name.utf8)
    d.appendU32(UInt32(nameBytes.count))
    d.append(nameBytes)
    d.appendU32(UInt32(chars.count))
    d.appendU32(60)
    for c in chars { d.appendU32(c) }
    for b in brightness { d.appendF32(b) }
    for _ in 0..<(chars.count * 15 * 4) { d.appendF32(laneFill) }
    if let raw = rawDensity { for r in raw { d.appendF32(r) } }
    if let hists = orientationHistograms { for h in hists { d.appendF32(h) } }
    if let peaks = radialPeaks { for p in peaks { d.appendF32(p) } }
    return d
}

private func blob(version: UInt32, sets: [Data]) -> Data {
    var d = Data()
    d.appendU32(0xA5C1_1E01)
    d.appendU32(version)
    d.appendU32(UInt32(sets.count))
    for s in sets { d.append(s) }
    return d
}

private func expectCommittedProvenance(
    _ set: StandardCharacterSet,
    name: String,
    version: UInt32,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .committedAsset(let setName, let formatVersion) = set.glyphBank.provenance else {
        Issue.record("parsed set was not marked as committed", sourceLocation: sourceLocation)
        return
    }
    #expect(setName == name, sourceLocation: sourceLocation)
    #expect(formatVersion == version, sourceLocation: sourceLocation)
}

@Suite struct StandardCharacterSetV2ParseTests {
    @Test func v1BlobLoadsWithRawDensityEqualToBrightness() throws {
        let data = blob(
            version: 1,
            sets: [
                setPayload(
                    name: "test", chars: [0x20, 0x40], brightness: [0, 1],
                    rawDensity: nil, laneFill: 0.25)
            ])
        let set = try StandardCharacterSet.parse(data: data, setName: "test")
        #expect(set.brightnessValues == [0, 1])
        #expect(set.rawDensityValues == set.brightnessValues)
        expectCommittedProvenance(set, name: "test", version: 1)
    }

    @Test func v2BlobLoadsDistinctRawDensityBlock() throws {
        let data = blob(
            version: 2,
            sets: [
                setPayload(
                    name: "test", chars: [0x20, 0x40], brightness: [0, 1],
                    rawDensity: [0, 0.42], laneFill: 0.25)
            ])
        let set = try StandardCharacterSet.parse(data: data, setName: "test")
        #expect(set.characters == [" ", "@"])
        #expect(set.brightnessValues == [0, 1])
        #expect(set.rawDensityValues == [0, 0.42])
        #expect(set.shapeVectorLanes.count == 2 * 15)
        #expect(set.shapeVectorLanes[0] == SIMD4<Float>(repeating: 0.25))
        expectCommittedProvenance(set, name: "test", version: 2)
    }

    // All real files have set_count = 1, so the multi-set skip stride is only
    // ever exercised here: the v2 skip must stride over the raw block too.
    @Test func v2SkipPathStridesOverRawDensityBlock() throws {
        let first = setPayload(
            name: "first", chars: [0x21], brightness: [0.5],
            rawDensity: [0.1], laneFill: 0)
        let second = setPayload(
            name: "second", chars: [0x20, 0x40], brightness: [0, 1],
            rawDensity: [0, 0.42], laneFill: 0.25)
        let data = blob(version: 2, sets: [first, second])
        let set = try StandardCharacterSet.parse(data: data, setName: "second")
        #expect(set.characters == [" ", "@"])
        #expect(set.rawDensityValues == [0, 0.42])
    }

    @Test func truncatedV2RawBlockThrows() {
        var data = blob(
            version: 2,
            sets: [
                setPayload(
                    name: "test", chars: [0x20, 0x40], brightness: [0, 1],
                    rawDensity: [0, 0.42], laneFill: 0.25)
            ])
        data.removeLast(4)
        #expect(throws: StandardCharacterSet.LoadError.truncated) {
            _ = try StandardCharacterSet.parse(data: data, setName: "test")
        }
    }

    @Test func unknownVersionStillRejected() {
        let data = blob(version: 4, sets: [])
        #expect(throws: StandardCharacterSet.LoadError.unknownVersion) {
            _ = try StandardCharacterSet.parse(data: data, setName: "test")
        }
    }

    @Test func v3BlobSkipsRetiredChannelsAndKeepsCoreData() throws {
        let hists: [Float] = [
            1, 0, 0, 0, 0, 0, 0, 0,  // glyph 0
            0, 0, 0, 0, 1, 0, 0, 0,  // glyph 1
        ]
        let peaks: [Float] = [0.1, 0.9]
        let data = blob(
            version: 3,
            sets: [
                setPayload(
                    name: "test", chars: [0x20, 0x40], brightness: [0, 1],
                    rawDensity: [0, 0.42], laneFill: 0.25,
                    orientationHistograms: hists, radialPeaks: peaks)
            ])
        let set = try StandardCharacterSet.parse(data: data, setName: "test")
        #expect(set.characters == [" ", "@"])
        #expect(set.brightnessValues == [0, 1])
        #expect(set.rawDensityValues == [0, 0.42])
        #expect(set.shapeVectorLanes.count == 2 * 15)
        expectCommittedProvenance(set, name: "test", version: 3)
    }

    @Test func v3SkipPathStridesOverChannelBlock() throws {
        let first = setPayload(
            name: "first", chars: [0x21], brightness: [0.5], rawDensity: [0.1], laneFill: 0,
            orientationHistograms: Array(repeating: 0, count: 8), radialPeaks: [0.2])
        let second = setPayload(
            name: "second", chars: [0x20, 0x40], brightness: [0, 1], rawDensity: [0, 0.42], laneFill: 0.25,
            orientationHistograms: [
                1, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 1, 0, 0, 0,
            ], radialPeaks: [0.1, 0.9])
        let data = blob(version: 3, sets: [first, second])
        let set = try StandardCharacterSet.parse(data: data, setName: "second")
        #expect(set.characters == [" ", "@"])
        #expect(set.rawDensityValues == [0, 0.42])
    }

    @Test func truncatedV3RetiredChannelBlockThrows() {
        var data = blob(
            version: 3,
            sets: [
                setPayload(
                    name: "test", chars: [0x20], brightness: [0],
                    rawDensity: [0], laneFill: 0,
                    orientationHistograms: Array(repeating: 0, count: 8),
                    radialPeaks: [0.1])
            ])
        data.removeLast(4)
        #expect(throws: StandardCharacterSet.LoadError.truncated) {
            _ = try StandardCharacterSet.parse(data: data, setName: "test")
        }
    }
}
