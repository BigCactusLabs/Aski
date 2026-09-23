import Aski
import CoreGraphics
import Foundation

// MARK: - Candidate vocabulary at the true cell aspect (ASKI-52 / ASKI-26)

/// Builds the candidate side of a matcher arm — one raster, one brightness and
/// one descriptor per glyph — at a stated *placement convention* and the TRUE
/// cell aspect, so the convention itself can be ablated instead of assumed.
///
/// The shipped matcher indexes text candidates as bounds-centred 64×64 squares
/// (`RasterizedCharacterSet.rasterize`), which erases both position and aspect:
/// `▄` and `▀` become the same centred bar. Braille candidates go through
/// `BrailleRasterizer` and are position-faithful already, which is why braille
/// recovers under every oracle at production geometry while text charsets
/// collapse. ``Placement`` makes that difference a parameter.
///
/// **Brightness rule (unified, one rule for text and braille):** the mean ink of
/// the FULL cell raster the entry carries. The shipped path has two rules —
/// text brightness is `cellDensity` over a font-metric cell rect centred inside
/// the 64×64 canvas (`RasterizedCharacterSet.cellDensity`), braille brightness
/// is the whole-canvas mean (`BuildStandardVectors`) — so text and braille
/// brightness are not on the same scale. Here both are the whole-raster mean,
/// which is the quantity a source cell's own mean luma is directly comparable
/// to. ``Entry/normalizedBrightness`` additionally divides by the vocabulary's
/// densest glyph, reproducing the shipped cross-character normalization.
public enum PositionFaithfulVocabulary {

    /// How a glyph is placed inside its raster.
    public enum Placement: String, Sendable, CaseIterable {
        /// The renderer's own convention, at the true cell aspect: baseline +
        /// left edge via ``GlyphCellRaster``, braille via `BrailleRasterizer`
        /// over the full cell rect. Position and aspect are both preserved.
        case positionFaithful
        /// Bounds-centred inside the true cell rect (``GlyphRaster``). Aspect is
        /// preserved, position is not. Braille has no bounds-centred form in
        /// production, so it takes the position-faithful dot path here too —
        /// which is exactly why the ASKI-52 collapse is a text-only finding.
        case boundsCentredRect
        /// The matcher's own convention: bounds-centred in a 64×64 square for
        /// text, a 64×64 `BrailleRasterizer` raster for braille. Neither
        /// position nor aspect survives on the text side.
        case boundsCentredSquare
    }

    /// The matcher's candidate raster side, per `RasterizedCharacterSet`.
    public static let matcherRasterSize = 64

    public struct Entry: Sendable {
        public let character: Character
        public let width: Int
        public let height: Int
        /// Row-major luma, ink → 1, `width × height`.
        public let raster: [Float]
        /// Mean ink over the full raster. See the type's brightness rule.
        public let brightness: Float
        /// `brightness` divided by the vocabulary's densest glyph, or `0` when
        /// every glyph is blank. Mirrors the shipped cross-character rescale.
        public let normalizedBrightness: Float
        /// Sampled by ``LogPolarCellSampling`` — the same function the query
        /// side of the arm calls, at the same configuration.
        public let descriptor: [Float]
    }

    /// Builds the vocabulary for `characters` at a `cellWidth × cellHeight`
    /// cell. Under ``Placement/boundsCentredSquare`` the entries are 64×64
    /// regardless of the cell passed, because that is the convention being
    /// modelled; the cell size still governs the other two placements.
    public static func build(
        characters: [Character],
        cellWidth: Int,
        cellHeight: Int,
        placement: Placement = .positionFaithful,
        sampling: LogPolarCellSampling.Configuration = .tiledAISS,
        supersample: Int = 4
    ) -> [Entry] {
        let size = rasterSize(cellWidth: cellWidth, cellHeight: cellHeight, placement: placement)
        let rasters = characters.map {
            raster(
                character: $0, width: size.width, height: size.height,
                placement: placement, supersample: supersample)
        }
        let brightness = rasters.map { meanInk($0) }
        let maxBrightness = brightness.max() ?? 0
        return characters.enumerated().map { index, character in
            Entry(
                character: character,
                width: size.width,
                height: size.height,
                raster: rasters[index],
                brightness: brightness[index],
                normalizedBrightness: maxBrightness > 0 ? brightness[index] / maxBrightness : 0,
                descriptor: LogPolarCellSampling.descriptor(
                    rasters[index], width: size.width, height: size.height,
                    configuration: sampling))
        }
    }

    /// The raster geometry a placement uses for a given cell.
    public static func rasterSize(cellWidth: Int, cellHeight: Int, placement: Placement) -> (
        width: Int, height: Int
    ) {
        switch placement {
        case .positionFaithful, .boundsCentredRect:
            return (max(1, cellWidth), max(1, cellHeight))
        case .boundsCentredSquare:
            return (matcherRasterSize, matcherRasterSize)
        }
    }

    /// One glyph raster under one placement. Braille (U+2800–U+28FF) is
    /// dispatched on the FIRST scalar, matching `ImageRenderer`.
    public static func raster(
        character: Character, width: Int, height: Int,
        placement: Placement, supersample: Int = 4
    ) -> [Float] {
        let brailleScalar = character.unicodeScalars.first.flatMap {
            (0x2800...0x28FF).contains($0.value) ? $0.value : nil
        }
        switch placement {
        case .positionFaithful:
            return GlyphCellRaster.luma(
                character: character, width: width, height: height, supersample: supersample)
        case .boundsCentredRect:
            // Deliberately the SAME rasterization path and the SAME point size as
            // `.positionFaithful`, differing only in the centring rule. Routing
            // this through `GlyphRaster` instead would have compared a 24pt
            // native raster against an effectively 20pt supersampled one at a
            // 12x24 cell (`GlyphRaster` defaults the point size to the canvas
            // height; `GlyphCellRaster` derives it as height / 1.2 and renders
            // 4x before downsampling), so the rung (ii) -> (iii) delta would have
            // confounded scale, hinting and clipping with placement — the one
            // thing it exists to isolate. Braille is unaffected either way.
            return GlyphCellRaster.luma(
                character: character, width: width, height: height,
                supersample: supersample, boundsCentred: brailleScalar == nil)
        case .boundsCentredSquare:
            if let brailleScalar {
                return BrailleRasterizer.rasterize(
                    codepoint: brailleScalar, size: min(width, height))
            }
            // This placement is the one that claims to BE the shipped candidate
            // convention, so it takes production's point size rather than the
            // canvas-derived default. `BuildStandardVectors` rasterizes the
            // committed `.bin` vectors at 32pt into a 64x64 canvas; letting the
            // point size follow the canvas would put this raster at 64pt, twice
            // production's, and the rung would silently be measuring a scale
            // change as well as the convention it is supposed to isolate.
            return GlyphRaster.luma(
                character: character, width: width, height: height,
                pointSize: GlyphRaster.productionShapeVectorPointSize)
        }
    }

    /// The unified brightness rule: mean ink over the whole raster.
    public static func meanInk(_ raster: [Float]) -> Float {
        guard !raster.isEmpty else { return 0 }
        return raster.reduce(0, +) / Float(raster.count)
    }
}
