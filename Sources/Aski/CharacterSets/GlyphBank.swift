import simd

/// Immutable internal reference owner of every array indexed by glyph position.
///
/// Library-owned character sets and their converters share this identity.
/// Public array projections use Swift copy-on-write storage, so callers share
/// the bank's buffers until they mutate their own returned values.
internal final class GlyphBank: Sendable {
    static let shapeVectorDimension = 60
    static let lanesPerCharacter = shapeVectorDimension / 4
    static let rasterSize = 64

    enum Placement: Sendable, Equatable {
        case imageBoundsCentered
    }

    enum Baseline: Sendable, Equatable {
        case derivedFromImageBounds
    }

    enum Antialiasing: Sendable, Equatable {
        case coreGraphicsDefault
    }

    enum RasterColorSpace: Sendable, Equatable {
        case deviceGray8Bit
    }

    struct FontObservation: Sendable {
        let postScriptName: String
        let pointSize: Double
        /// A fixed FNV-style fingerprint of the six CTFont affine-transform
        /// `Double` bit patterns.
        let transformFingerprint: UInt64
    }

    struct Rasterization: Sendable {
        let densityCellWidth: Int
        let densityCellHeight: Int
        let font: FontObservation

        var width: Int { GlyphBank.rasterSize }
        var height: Int { GlyphBank.rasterSize }
        var placement: Placement { .imageBoundsCentered }
        var baseline: Baseline { .derivedFromImageBounds }
        var antialiasing: Antialiasing { .coreGraphicsDefault }
        var colorSpace: RasterColorSpace { .deviceGray8Bit }
    }

    enum Provenance: Sendable {
        /// Selection is bound to committed bytes. ShapeData v3 does not encode
        /// raster facts, so none are inferred from the current host.
        case committedAsset(setName: String, formatVersion: UInt32)
        /// Core Text output can change with the OS and toolchain. This value is
        /// an observation of the current construction, not a stable font key.
        case runtimeCoreText(Rasterization)
        /// The external conformance owns its raster and stability contracts.
        case externalSnapshot
    }

    let characters: [Character]
    let brightnessValues: [Float]
    let rawDensityValues: [Float]
    let shapeVectorLanes: [SIMD4<Float>]
    let provenance: Provenance

    init(
        characters: [Character],
        brightnessValues: [Float],
        rawDensityValues: [Float],
        shapeVectorLanes: [SIMD4<Float>],
        provenance: Provenance
    ) {
        let characterCount = characters.count
        precondition(
            characterCount > 0,
            "ASCIICharacterSet parallel-array invariant violated: characters must not be empty"
        )
        var mismatches: [String] = []
        if brightnessValues.count != characterCount {
            mismatches.append("brightnessValues")
        }
        if rawDensityValues.count != characterCount {
            mismatches.append("rawDensityValues")
        }
        if shapeVectorLanes.count != characterCount * Self.lanesPerCharacter {
            mismatches.append("shapeVectorLanes")
        }
        precondition(
            mismatches.isEmpty,
            "ASCIICharacterSet parallel-array invariant violated: \(mismatches.joined(separator: ", ")) must match characters"
        )

        self.characters = characters
        self.brightnessValues = brightnessValues
        self.rawDensityValues = rawDensityValues
        self.shapeVectorLanes = shapeVectorLanes
        self.provenance = provenance
    }

    static func adapting<C: ASCIICharacterSet>(_ characterSet: C) -> GlyphBank {
        if let provider = characterSet as? any GlyphBankProviding {
            return provider.glyphBank
        }
        return GlyphBank(
            characters: characterSet.characters,
            brightnessValues: characterSet.brightnessValues,
            rawDensityValues: characterSet.rawDensityValues,
            shapeVectorLanes: characterSet.shapeVectorLanes,
            provenance: .externalSnapshot
        )
    }
}

/// Internal fast path for the two library-owned public character-set values.
/// External conformers remain source compatible and are snapshotted once.
internal protocol GlyphBankProviding: ASCIICharacterSet {
    var glyphBank: GlyphBank { get }
}
