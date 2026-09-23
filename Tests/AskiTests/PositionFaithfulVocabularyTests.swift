import AskiToolSupport
import Foundation
import Testing

/// Guards the ASKI-52 / ASKI-26 position-faithful instrument: the candidate
/// vocabulary and the shared log-polar sampler that both sides of an ablation
/// arm call.
///
/// The instrument exists because the shipped one loses information before any
/// oracle sees it — text candidates are bounds-centred in a 64×64 square, and
/// the 60-D descriptor inscribes a single disc that admits ~39% of an
/// anisotropic query cell against ~79% of a square candidate. These tests pin
/// the two properties that make the replacement worth measuring with: glyphs
/// that differ only in WHERE their ink sits must stay apart, and the descriptor
/// length must be the arithmetic the paper's construction predicts.
@Suite struct PositionFaithfulVocabularyTests {

    /// The shipping regime's cell aspect, small enough to keep the debug-build
    /// sampling cost down while staying 1:2.
    private static let cellWidth = 12
    private static let cellHeight = 24

    /// Pairs that carry comparable ink at different places in the cell.
    private static let positionOnlyPairs: [(Character, Character)] = [
        ("▄", "▀"), ("_", "-"), (".", "'"), ("⠁", "⢀"),
    ]

    private static func descriptor(
        _ character: Character,
        placement: PositionFaithfulVocabulary.Placement = .positionFaithful,
        sampling: LogPolarCellSampling.Configuration = .tiledAISS
    ) -> [Float] {
        let size = PositionFaithfulVocabulary.rasterSize(
            cellWidth: cellWidth, cellHeight: cellHeight, placement: placement)
        let raster = PositionFaithfulVocabulary.raster(
            character: character, width: size.width, height: size.height, placement: placement)
        return LogPolarCellSampling.descriptor(
            raster, width: size.width, height: size.height, configuration: sampling)
    }

    /// Two descriptors are "apart" only if they differ by more than float noise;
    /// `!=` alone would pass on a single ULP and hide a near-collapse.
    private static func l1Distance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return .infinity }
        return zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) }
    }

    // MARK: - Position-distinguishing pairs

    /// ASKI-52's core claim, stated as a requirement on the new convention:
    /// pairs that carry the same ink at different places in the cell must have
    /// distinguishable descriptors. `▄`/`▀` is a pure vertical swap, `_`/`-` a
    /// baseline-vs-midline swap, `.`/`'` a bottom-vs-top mark, and braille dot 1
    /// vs dot 8 opposite corners of the dot grid.
    @Test func positionOnlyPairsStayApartUnderTheTiledConvention() {
        for pair in Self.positionOnlyPairs {
            let a = Self.descriptor(pair.0)
            let b = Self.descriptor(pair.1)
            #expect(a.count == b.count && !a.isEmpty)
            // Both descriptors are L1-normalized to 1, so the maximum possible
            // distance is 2; 0.1 is a tenth of that — comfortably above noise
            // and far below "these are different glyphs".
            #expect(
                Self.l1Distance(a, b) > 0.1,
                "\(pair.0) and \(pair.1) collapsed under the tiled convention: L1 \(Self.l1Distance(a, b))"
            )
        }
    }

    /// The rasters themselves must differ before the sampler is even involved —
    /// otherwise a passing descriptor test would be proving nothing about the
    /// placement convention.
    @Test func positionOnlyPairsProduceDifferentRasters() {
        for pair in Self.positionOnlyPairs {
            let a = PositionFaithfulVocabulary.raster(
                character: pair.0, width: Self.cellWidth, height: Self.cellHeight,
                placement: .positionFaithful)
            let b = PositionFaithfulVocabulary.raster(
                character: pair.1, width: Self.cellWidth, height: Self.cellHeight,
                placement: .positionFaithful)
            #expect(a != b, "\(pair.0) and \(pair.1) rasterized identically")
        }
    }

    /// The support mismatch ASKI-26 names, made concrete: a baseline-hugging
    /// glyph sits outside the single inscribed disc of a 1:2 cell, so the
    /// shipped convention can hand the matcher an all-zero descriptor for it.
    /// The tiled construction covers the whole cell and cannot. This is the
    /// instrument's reason to exist; if the tiled side ever went zero here the
    /// arms downstream would be measuring nothing.
    @Test func theTiledConventionSamplesInkTheSingleDiscMisses() {
        let tiled = Self.descriptor("_", sampling: .tiledAISS)
        #expect(tiled.reduce(0, +) > 0.99, "the tiled descriptor for `_` carries no mass")
        let disc = Self.descriptor("_", sampling: .singleDisc)
        #expect(disc.count == LogPolarCellSampling.binsPerWindow)
        // Recorded, not asserted as a failure: whatever the disc admits, the
        // tiled construction must admit strictly more of the cell.
        #expect(
            LogPolarCellSampling.dimension(
                width: Self.cellWidth, height: Self.cellHeight, configuration: .tiledAISS)
                > disc.count)
    }

    // MARK: - Brightness

    /// One rule for text and braille — mean ink over the full raster — so a
    /// solid block, a blank and an all-dots braille cell order the way their ink
    /// does. Under the shipped split rule these are not on one scale.
    @Test func brightnessOrdersFullDensityAboveBlank() throws {
        let entries = PositionFaithfulVocabulary.build(
            characters: ["█", " ", "⣿", "."],
            cellWidth: Self.cellWidth, cellHeight: Self.cellHeight)
        let byCharacter = Dictionary(uniqueKeysWithValues: entries.map { ($0.character, $0) })
        let full = try #require(byCharacter["█"])
        let blank = try #require(byCharacter[" "])
        let dots = try #require(byCharacter["⣿"])
        let dot = try #require(byCharacter["."])

        #expect(blank.brightness == 0, "a blank cell carries ink: \(blank.brightness)")
        // Not 1.0: under the renderer's own geometry rule the em box is
        // `height / 1.2` tall, so a full block cannot cover the last sixth of
        // the cell. That gap is the renderer's, and the instrument reproduces
        // it rather than hiding it.
        #expect(full.brightness > 0.8, "the full block is not near-solid: \(full.brightness)")
        #expect(full.brightness > dots.brightness)
        #expect(dots.brightness > dot.brightness)
        #expect(dot.brightness > blank.brightness)
        // Cross-character normalization puts the densest glyph at exactly 1.
        #expect(full.normalizedBrightness == 1)
        #expect(blank.normalizedBrightness == 0)
    }

    // MARK: - Descriptor dimensionality

    /// The paper's arithmetic: `N = (Tw/2)(Th/2)` windows, 5 radial × 12
    /// angular each, concatenated. A 12×24 cell is the paper's own worked
    /// example — 72 windows, 4320-D — so it is pinned by its published number
    /// rather than by whatever this implementation happens to produce.
    @Test func tiledDescriptorDimensionMatchesThePaperArithmetic() {
        let grid = LogPolarCellSampling.windowGrid(width: 12, height: 24, stride: 2)
        #expect(grid.columns == 6 && grid.rows == 12)
        #expect(grid.columns * grid.rows == 72)
        #expect(LogPolarCellSampling.binsPerWindow == 60)
        let dimension = LogPolarCellSampling.dimension(
            width: 12, height: 24, configuration: .tiledAISS)
        #expect(dimension == 4320)
        let sampled = LogPolarCellSampling.descriptor(
            PositionFaithfulVocabulary.raster(
                character: "A", width: 12, height: 24, placement: .positionFaithful),
            width: 12, height: 24, configuration: .tiledAISS)
        #expect(sampled.count == dimension)
        // The single-disc ablation keeps the shipped 60-D length on the same cell.
        #expect(
            LogPolarCellSampling.dimension(width: 12, height: 24, configuration: .singleDisc) == 60)
    }

    /// Blur is a configuration of the shared sampler, applied to whichever side
    /// calls it — so the no-blur ablation must be the same length and a
    /// genuinely different vector, not a silent no-op.
    @Test func theBlurAblationChangesTheDescriptorWithoutChangingItsLength() {
        let raster = PositionFaithfulVocabulary.raster(
            character: "A", width: Self.cellWidth, height: Self.cellHeight,
            placement: .positionFaithful)
        let blurred = LogPolarCellSampling.descriptor(
            raster, width: Self.cellWidth, height: Self.cellHeight, configuration: .tiledAISS)
        let sharp = LogPolarCellSampling.descriptor(
            raster, width: Self.cellWidth, height: Self.cellHeight, configuration: .tiledAISSNoBlur)
        #expect(blurred.count == sharp.count)
        #expect(
            Self.l1Distance(blurred, sharp) > 0,
            "the 7×7 pre-blur is inert — the blurred and sharp arms are the same measurement")
        #expect(LogPolarCellSampling.defaultBlurSigma == 1.2)
    }

    /// The blur must preserve total ink (a normalized kernel with clamped
    /// borders), so a blurred arm differs from a sharp one in structure and not
    /// in tone.
    @Test func theGaussianPreBlurPreservesInkMass() {
        let raster = PositionFaithfulVocabulary.raster(
            character: "M", width: Self.cellWidth, height: Self.cellHeight,
            placement: .positionFaithful)
        let blurred = LogPolarCellSampling.gaussianBlur(
            raster, width: Self.cellWidth, height: Self.cellHeight,
            sigma: LogPolarCellSampling.defaultBlurSigma)
        let before = PositionFaithfulVocabulary.meanInk(raster)
        let after = PositionFaithfulVocabulary.meanInk(blurred)
        #expect(abs(before - after) < 0.02, "the pre-blur moved ink mass: \(before) → \(after)")
    }

    // MARK: - Placement conventions

    /// The placement parameter has to be real: the matcher's square convention
    /// must actually collapse `▄`/`▀` (that collapse IS the ASKI-52 finding),
    /// while the position-faithful one keeps them apart. If the square arm ever
    /// stopped collapsing, the ablation ladder would have no bottom rung.
    ///
    /// The collapse is near-total rather than bit-exact — bounds-centring lands
    /// the two bars on sub-pixel-different offsets, so a handful of antialiased
    /// edge pixels survive. Comparing mean absolute difference states the
    /// finding as what it is (the position signal is gone, not merely reduced)
    /// instead of resting on a rasterizer producing identical bytes.
    @Test func theMatcherSquarePlacementCollapsesWhatThePositionFaithfulOneKeeps() {
        func meanAbsoluteDifference(_ a: [Float], _ b: [Float]) -> Float {
            guard a.count == b.count, !a.isEmpty else { return .infinity }
            return zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) } / Float(a.count)
        }
        let squareGap = meanAbsoluteDifference(
            PositionFaithfulVocabulary.raster(
                character: "▄", width: 64, height: 64, placement: .boundsCentredSquare),
            PositionFaithfulVocabulary.raster(
                character: "▀", width: 64, height: 64, placement: .boundsCentredSquare))
        let faithfulGap = meanAbsoluteDifference(
            PositionFaithfulVocabulary.raster(
                character: "▄", width: Self.cellWidth, height: Self.cellHeight,
                placement: .positionFaithful),
            PositionFaithfulVocabulary.raster(
                character: "▀", width: Self.cellWidth, height: Self.cellHeight,
                placement: .positionFaithful))
        // ~0.012 in practice: an antialiasing seam, not a distinction. Stated
        // relative to the faithful gap as well, so the claim is "the position
        // signal is an order of magnitude gone", not a bare epsilon.
        #expect(
            squareGap < 0.03,
            "the matcher's bounds-centred square no longer collapses the half blocks (gap \(squareGap)) — the ASKI-52 premise changed"
        )
        #expect(
            squareGap * 20 < faithfulGap,
            "the square gap (\(squareGap)) is not an order of magnitude below the faithful gap (\(faithfulGap))"
        )
        // The half blocks carry ~0.53 ink each at opposite ends of the cell, so
        // a position-faithful pair has to separate by most of that.
        #expect(
            faithfulGap > 0.5,
            "the position-faithful placement lost the half-block distinction: gap \(faithfulGap)")
    }

    /// Braille is position-faithful in production under every placement, which
    /// is why the ASKI-52 collapse is a text-only finding. Pinning it keeps a
    /// future arm from reporting a braille "recovery" as evidence about text.
    @Test func brailleIsPositionFaithfulUnderEveryPlacement() {
        for placement in PositionFaithfulVocabulary.Placement.allCases {
            let size = PositionFaithfulVocabulary.rasterSize(
                cellWidth: Self.cellWidth, cellHeight: Self.cellHeight, placement: placement)
            let dot1 = PositionFaithfulVocabulary.raster(
                character: "⠁", width: size.width, height: size.height, placement: placement)
            let dot8 = PositionFaithfulVocabulary.raster(
                character: "⢀", width: size.width, height: size.height, placement: placement)
            #expect(dot1 != dot8, "braille collapsed under \(placement.rawValue)")
        }
    }
}
