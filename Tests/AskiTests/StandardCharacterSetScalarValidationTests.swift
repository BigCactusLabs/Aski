import Foundation
import Testing
import simd
@_spi(AskiResearch) @testable import Aski

// ASKI-23. `parse` reads `charCount` scalars but only appended the ones that
// survived `Unicode.Scalar(_:)`, then read every other per-glyph block at the
// full `charCount` — silently returning a set whose parallel arrays disagree.
// These tests pin the throw and the parallel-array invariant the matcher
// kernels index against.

// Test-local little-endian encoders mirroring the documented .bin layout
// (the production encoder lives in the BuildStandardVectors executable,
// which test targets cannot import).
extension Data {
    fileprivate mutating func appendScalarU32(_ v: UInt32) {
        var x = v.littleEndian
        Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) }
    }
    fileprivate mutating func appendScalarF32(_ v: Float) { appendScalarU32(v.bitPattern) }
}

private func scalarSetPayload(
    name: String, chars: [UInt32], brightness: [Float],
    rawDensity: [Float]?, laneFill: Float
) -> Data {
    var d = Data()
    let nameBytes = Data(name.utf8)
    d.appendScalarU32(UInt32(nameBytes.count))
    d.append(nameBytes)
    d.appendScalarU32(UInt32(chars.count))
    d.appendScalarU32(60)
    for c in chars { d.appendScalarU32(c) }
    for b in brightness { d.appendScalarF32(b) }
    for _ in 0..<(chars.count * 15 * 4) { d.appendScalarF32(laneFill) }
    if let raw = rawDensity { for r in raw { d.appendScalarF32(r) } }
    return d
}

private func scalarBlob(version: UInt32, sets: [Data]) -> Data {
    var d = Data()
    d.appendScalarU32(0xA5C1_1E01)
    d.appendScalarU32(version)
    d.appendScalarU32(UInt32(sets.count))
    for s in sets { d.append(s) }
    return d
}

/// Order-sensitive digest over every per-glyph array of a parsed set. Any
/// change to the decoded bytes — or to their ordering — moves this value.
private func digest(_ set: StandardCharacterSet) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    func mix(_ value: UInt64) {
        hash = (hash ^ value) &* 0x0000_0100_0000_01B3
    }
    mix(UInt64(set.characters.count))
    for character in set.characters {
        for scalar in character.unicodeScalars { mix(UInt64(scalar.value)) }
        mix(0xFFFF_FFFF)
    }
    for value in set.brightnessValues { mix(UInt64(value.bitPattern)) }
    for value in set.rawDensityValues { mix(UInt64(value.bitPattern)) }
    for lane in set.shapeVectorLanes {
        mix(UInt64(lane.x.bitPattern))
        mix(UInt64(lane.y.bitPattern))
        mix(UInt64(lane.z.bitPattern))
        mix(UInt64(lane.w.bitPattern))
    }
    return hash
}

/// AC#2: the contract every matcher kernel indexes against.
private func expectParallelArrays(
    _ set: StandardCharacterSet, _ label: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let n = set.characters.count
    #expect(set.brightnessValues.count == n, "\(label) brightness", sourceLocation: sourceLocation)
    #expect(set.rawDensityValues.count == n, "\(label) rawDensity", sourceLocation: sourceLocation)
    #expect(
        set.shapeVectorLanes.count == n * StandardCharacterSet.lanesPerCharacter,
        "\(label) lanes", sourceLocation: sourceLocation)
}

@Suite struct StandardCharacterSetScalarValidationTests {

    // AC#1 / AC#4: a surrogate is not a valid Unicode scalar. Parsing must
    // fail loudly instead of returning a short `characters` array.
    @Test func surrogateScalarThrowsInsteadOfDesynchronizing() throws {
        let data = scalarBlob(
            version: 2,
            sets: [
                scalarSetPayload(
                    name: "test", chars: [0x20, 0xD800, 0x40], brightness: [0, 0.5, 1],
                    rawDensity: [0, 0.5, 1], laneFill: 0.25)
            ])
        #expect(throws: StandardCharacterSet.LoadError.invalidScalar) {
            _ = try StandardCharacterSet.parse(data: data, setName: "test")
        }
    }

    // AC#1: the other rejected class — a code point above U+10FFFF.
    @Test func outOfRangeScalarThrowsInsteadOfDesynchronizing() throws {
        let data = scalarBlob(
            version: 2,
            sets: [
                scalarSetPayload(
                    name: "test", chars: [0x20, 0x0011_0000], brightness: [0, 1],
                    rawDensity: [0, 1], laneFill: 0.25)
            ])
        #expect(throws: StandardCharacterSet.LoadError.invalidScalar) {
            _ = try StandardCharacterSet.parse(data: data, setName: "test")
        }
    }

    // AC#2: a well-formed blob still parses, and its arrays stay parallel.
    @Test func wellFormedBlobKeepsArraysParallel() throws {
        let data = scalarBlob(
            version: 2,
            sets: [
                scalarSetPayload(
                    name: "test", chars: [0x20, 0x2E, 0x40], brightness: [0, 0.5, 1],
                    rawDensity: [0, 0.4, 1], laneFill: 0.25)
            ])
        let set = try StandardCharacterSet.parse(data: data, setName: "test")
        #expect(set.characters == [" ", ".", "@"])
        expectParallelArrays(set, "hand-built v2")
    }

    // AC#2: every shipped set satisfies the invariant the kernels rely on.
    @Test func builtInSetsSatisfyParallelArrayInvariant() {
        for (name, set) in builtInStandardSets {
            expectParallelArrays(set, name)
            #expect(!set.characters.isEmpty, "\(name) is empty")
        }
    }

    // AC#4, anchored to the shipped bytes rather than to a captured baseline:
    // an independent decoder reads each .bin straight off disk per the
    // documented layout, and every per-glyph array must be bit-exact against
    // what `parse` produced. No epsilon anywhere — this is the instrument that
    // would catch a decode shift even if the pinned digests had been recorded
    // from already-changed code.
    @Test func shippedBinariesDecodeBitExactAgainstAnIndependentDecoder() throws {
        for (name, set) in builtInStandardSets {
            let reference = try ReferenceBinDecoder.decode(setNamed: name)

            #expect(reference.characters == set.characters, "\(name) characters")
            #expect(reference.characters.count == set.characters.count, "\(name) glyph count")

            #expect(
                reference.brightness.map(\.bitPattern) == set.brightnessValues.map(\.bitPattern),
                "\(name) brightnessValues")
            #expect(
                reference.rawDensity.map(\.bitPattern) == set.rawDensityValues.map(\.bitPattern),
                "\(name) rawDensityValues")

            #expect(reference.lanes.count == set.shapeVectorLanes.count, "\(name) lane count")
            for (index, lane) in reference.lanes.enumerated() where index < set.shapeVectorLanes.count {
                let actual = set.shapeVectorLanes[index]
                #expect(lane.x.bitPattern == actual.x.bitPattern, "\(name) lane \(index).x")
                #expect(lane.y.bitPattern == actual.y.bitPattern, "\(name) lane \(index).y")
                #expect(lane.z.bitPattern == actual.z.bitPattern, "\(name) lane \(index).z")
                #expect(lane.w.bitPattern == actual.w.bitPattern, "\(name) lane \(index).w")
            }

            // The retired v3 structure block remains in the historical binary
            // and the independent decoder still validates its complete shape.
            #expect(reference.orientationHistograms?.count == set.characters.count * 8)
            #expect(reference.radialPeaks?.count == set.characters.count)
        }
    }

    // AC#4: the shipped .bin files must decode byte-identically after the
    // parser change. These digests cover the production-retained arrays; the
    // independent decoder above separately validates the retired v3 block.
    @Test func builtInSetsDecodeByteIdentically() {
        let expected: [String: UInt64] = builtInStandardSetDigests
        for (name, set) in builtInStandardSets {
            #expect(digest(set) == expected[name], "\(name) decoded bytes moved")
        }
    }
}

private let builtInStandardSets: [(String, StandardCharacterSet)] = [
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

/// Byte-identity anchors over the production-retained arrays decoded from the
/// shipped `.bin` files. A moved digest means production data changed.
private let builtInStandardSetDigests: [String: UInt64] = [
    "standard": 16_113_103_862_721_637_779,
    "minimal": 9_850_705_579_460_354_033,
    "blocks": 5_496_972_667_999_447_041,
    "dots": 8_575_647_882_169_214_072,
    "lines": 17_332_845_810_637_751_058,
    "diagonal": 4_895_077_522_804_014_930,
    "cross": 11_438_693_951_657_484_535,
    "diamond": 7_002_919_424_131_877_306,
    "mixed": 17_193_294_658_175_621_367,
    "braille": 8_407_570_339_633_478_998,
]

/// A second, deliberately independent reader for the `.bin` layout: it opens
/// the shipped file from the source tree and walks it with its own cursor, so
/// an agreement with `StandardCharacterSet.parse` is evidence about the bytes
/// on disk, not about a value captured from an earlier build.
private enum ReferenceBinDecoder {
    struct Decoded {
        var characters: [Character] = []
        var brightness: [Float] = []
        var rawDensity: [Float] = []
        var lanes: [SIMD4<Float>] = []
        var orientationHistograms: [Float]?
        var radialPeaks: [Float]?
    }

    struct DecodeFailure: Error { let reason: String }

    static var shapeDataDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AskiTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Sources/Aski/Resources/ShapeData")
    }

    static func decode(setNamed name: String) throws -> Decoded {
        let url = shapeDataDirectory.appendingPathComponent("\(name).bin")
        let data = try Data(contentsOf: url)
        var cursor = 0

        func u32() throws -> UInt32 {
            guard cursor + 4 <= data.count else { throw DecodeFailure(reason: "short read") }
            var value: UInt32 = 0
            for byte in 0..<4 {
                value |= UInt32(data[data.startIndex + cursor + byte]) << (8 * UInt32(byte))
            }
            cursor += 4
            return value
        }
        func f32() throws -> Float { Float(bitPattern: try u32()) }

        guard try u32() == 0xA5C1_1E01 else { throw DecodeFailure(reason: "bad magic") }
        let version = try u32()
        let setCount = try u32()

        for _ in 0..<setCount {
            let nameLength = Int(try u32())
            guard cursor + nameLength <= data.count else {
                throw DecodeFailure(reason: "short name")
            }
            let nameBytes = data.subdata(in: (data.startIndex + cursor)..<(data.startIndex + cursor + nameLength))
            cursor += nameLength
            let setName = String(data: nameBytes, encoding: .utf8) ?? ""
            let charCount = Int(try u32())
            let dimension = Int(try u32())
            guard dimension == 60 else { throw DecodeFailure(reason: "bad dimension") }

            var decoded = Decoded()
            for _ in 0..<charCount {
                let scalar = try u32()
                guard let unicode = Unicode.Scalar(scalar) else {
                    throw DecodeFailure(reason: "shipped set \(setName) carries an invalid scalar")
                }
                decoded.characters.append(Character(unicode))
            }
            for _ in 0..<charCount { decoded.brightness.append(try f32()) }
            for _ in 0..<(charCount * 15) {
                decoded.lanes.append(
                    SIMD4<Float>(try f32(), try f32(), try f32(), try f32()))
            }
            if version >= 2 {
                for _ in 0..<charCount { decoded.rawDensity.append(try f32()) }
            } else {
                decoded.rawDensity = decoded.brightness
            }
            if version >= 3 {
                var histograms: [Float] = []
                for _ in 0..<(charCount * 8) { histograms.append(try f32()) }
                var peaks: [Float] = []
                for _ in 0..<charCount { peaks.append(try f32()) }
                decoded.orientationHistograms = histograms
                decoded.radialPeaks = peaks
            }

            if setName == name { return decoded }
        }
        throw DecodeFailure(reason: "set \(name) not found")
    }
}
