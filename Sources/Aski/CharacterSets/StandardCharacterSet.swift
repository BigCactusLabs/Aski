import Foundation
import simd

public struct StandardCharacterSet: ASCIICharacterSet, GlyphBankProviding {
    internal let glyphBank: GlyphBank

    public var characters: [Character] { glyphBank.characters }
    public var brightnessValues: [Float] { glyphBank.brightnessValues }
    public var rawDensityValues: [Float] { glyphBank.rawDensityValues }
    public var shapeVectorLanes: [SIMD4<Float>] { glyphBank.shapeVectorLanes }

    private init(glyphBank: GlyphBank) {
        self.glyphBank = glyphBank
    }

    static func loadOrFatal(name: String) -> StandardCharacterSet {
        do {
            return try load(name: name)
        } catch {
            fatalError("Aski: failed to load built-in character set '\(name)': \(error)")
        }
    }

    private static func load(name: String) throws -> StandardCharacterSet {
        guard
            let url = Bundle.module.url(
                forResource: name,
                withExtension: "bin",
                subdirectory: "ShapeData"
            )
        else {
            throw LoadError.missingResource
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try parse(data: data, setName: name)
    }

    static func parse(data: Data, setName: String) throws -> StandardCharacterSet {
        var cursor = 0
        func readU32() throws -> UInt32 {
            guard cursor + 4 <= data.count else { throw LoadError.truncated }
            let value = data.withUnsafeBytes { raw in
                raw.loadUnaligned(fromByteOffset: cursor, as: UInt32.self).littleEndian
            }
            cursor += 4
            return value
        }
        func readF32() throws -> Float {
            let bits = try readU32()
            return Float(bitPattern: bits)
        }
        func readBytes(_ n: Int) throws -> Data {
            guard cursor + n <= data.count else { throw LoadError.truncated }
            let sub = data.subdata(in: cursor..<(cursor + n))
            cursor += n
            return sub
        }

        let magic = try readU32()
        guard magic == 0xA5C11E01 else { throw LoadError.badMagic }
        let version = try readU32()
        guard version == 1 || version == 2 || version == 3 else { throw LoadError.unknownVersion }
        let setCount = try readU32()

        for _ in 0..<setCount {
            let nameLen = try readU32()
            let nameBytes = try readBytes(Int(nameLen))
            let name = String(data: nameBytes, encoding: .utf8) ?? ""
            let charCount = try readU32()
            let dim = try readU32()
            guard dim == UInt32(StandardCharacterSet.shapeVectorDimension) else { throw LoadError.badDimension }

            if name == setName {
                var characters: [Character] = []
                characters.reserveCapacity(Int(charCount))
                for _ in 0..<charCount {
                    let scalar = try readU32()
                    // Skipping an unrepresentable scalar would leave `characters`
                    // shorter than every other per-glyph block, which the matcher
                    // kernels index in lockstep. Reject the file instead.
                    guard let s = Unicode.Scalar(scalar) else { throw LoadError.invalidScalar }
                    characters.append(Character(s))
                }
                var brightness: [Float] = []
                for _ in 0..<charCount { brightness.append(try readF32()) }
                var lanes: [SIMD4<Float>] = []
                for _ in 0..<(Int(charCount) * StandardCharacterSet.lanesPerCharacter) {
                    let x = try readF32(); let y = try readF32()
                    let z = try readF32(); let w = try readF32()
                    lanes.append(SIMD4<Float>(x, y, z, w))
                }
                // v2 appends a raw-density block; v1 falls back to the
                // normalized brightness (no absolute density available).
                var rawDensity = brightness
                if version >= 2 {
                    rawDensity = []
                    rawDensity.reserveCapacity(Int(charCount))
                    for _ in 0..<charCount { rawDensity.append(try readF32()) }
                }
                // v3 carried a retired structure-assist channel block. Read it
                // to preserve strict truncation validation and compatibility
                // with the checked-in historical binaries, but do not retain
                // the obsolete per-glyph arrays in production memory.
                if version >= 3 {
                    for _ in 0..<(Int(charCount) * 9) { _ = try readF32() }
                }
                return StandardCharacterSet(
                    glyphBank: GlyphBank(
                        characters: characters,
                        brightnessValues: brightness,
                        rawDensityValues: rawDensity,
                        shapeVectorLanes: lanes,
                        provenance: .committedAsset(setName: setName, formatVersion: version)
                    )
                )
            } else {
                // Skip this set (per char: u32 scalar + f32 brightness
                // + 15 lanes + f32 raw density in v2 + 8-f32 hist + f32 peak in v3)
                let bytesPerLane = MemoryLayout<SIMD4<Float>>.size
                let rawDensityBytes = version >= 2 ? 4 : 0
                let channelBytes = version >= 3 ? (8 * 4 + 4) : 0
                let skipBytes = Int(charCount) * (4 + 4 + rawDensityBytes + channelBytes + StandardCharacterSet.lanesPerCharacter * bytesPerLane)
                _ = try readBytes(skipBytes)
            }
        }
        throw LoadError.setNotFound
    }

    enum LoadError: Error, Equatable {
        case missingResource
        case truncated
        case badMagic
        case unknownVersion
        case badDimension
        case setNotFound
        /// The scalar block carried a value that is not a valid Unicode scalar
        /// (a surrogate, or above U+10FFFF). Appending only the survivors would
        /// desynchronize `characters` from the parallel per-glyph arrays.
        case invalidScalar
    }
}
