import AskiToolSupport
import Foundation

@_spi(AskiResearch) import Aski

/// Reference-recovery screen: the disqualifier every candidate per-cell oracle
/// has to survive before it is allowed to define "optimal" (ASKI-27 AC#2).
///
/// The premise is the weakest possible demand on a full-reference metric. Make
/// the source cell *be* a rendered glyph, push it through the scoring path the
/// production oracle uses — `LumaResample` down to the scoring footprint,
/// candidates rasterized at that footprint — and ask the oracle to name the
/// glyph it was handed. A metric that cannot recover a glyph from a picture of
/// that glyph is not measuring glyph choice, and every ranking number it has
/// ever produced is a ranking of something else.
///
/// This is not a hypothetical failure mode. GMSD and HaarPSI are gradient and
/// wavelet metrics: two flat rasters have identical (absent) gradient structure
/// regardless of how far apart their tones are, so a blank cell and a solid cell
/// can score identically against a flat source. Ding, Ma, Wang & Simoncelli
/// (IJCV 2021) name exactly this — luminance blindness — when they rank GMSD
/// last of eleven metrics used as an optimization objective.
///
/// Four source constructions are run, and separating them is the whole point —
/// a single arm cannot tell "the oracle is blind" apart from "the footprint threw
/// the information away before the oracle saw it":
///
/// - `footprint` — the reference rendered directly at the scoring footprint, so
///   `LumaResample` is an identity and the two sides are pixel-identical. This is
///   the **gating** arm. Nothing here is lost by geometry; a failure is the
///   oracle failing to tell two different pictures apart, which disqualifies it
///   from defining an optimum.
/// - `square` — the reference rendered at a native-scale square raster and
///   resampled down to the footprint. Adds the real resample path at fixed
///   aspect. A failure here that the gating arm did not show is the **footprint**
///   destroying glyph identity, not the oracle.
/// - `cell` — the reference rendered into the native block the converter actually
///   reads for a cell (tall and narrow at the shipping regime) and resampled to
///   the square footprint. Closest to production geometry, and reported as a
///   diagnostic rather than a gate because `GlyphRaster` sizes the font to the
///   raster *height*: in a 1:2 block a wide glyph is clipped at the sides by the
///   rasterizer, and the ink fraction it lands on is not calibrated against the
///   square candidate. That confound is informative — it is exactly the
///   condition a tone-sensitive oracle is fragile under — but it is not evidence
///   about blindness.
/// - `roundTrip` — the footprint raster stretched into the cell block and
///   resampled straight back. This is a **blur-tolerance control, not production
///   geometry**: the source is built *from* the footprint raster, so it never
///   carries more information than the footprint already had, and the round trip
///   only softens it anisotropically. A failure here is real evidence that an
///   oracle is blind to blur and to the tone shift blur causes. It is **not**
///   evidence about the production downscale, which starts from a genuine native
///   block of photographic content — that path is `cell`'s, with the rasterizer
///   confound above.
enum ReferenceRecovery {

    /// How the reference glyph was turned into a source cell.
    enum SourceShape: String, Sendable, CaseIterable {
        /// Rendered at the scoring footprint; the resample is an identity. Gating.
        case footprint
        /// Native-scale square raster → footprint.
        case square
        /// The converter's resolved native cell block → footprint. Diagnostic.
        case cell
        /// Footprint raster stretched to the cell block and resampled back — a
        /// blur-tolerance control, not the production downscale (the source
        /// never carries more than the footprint it was built from).
        case roundTrip
        /// ASKI-32: the calibrated production-geometry arm. The reference is
        /// drawn TYPOGRAPHICALLY into the converter's resolved native cell
        /// block (`GlyphCellRaster` — production output convention: baseline +
        /// advance positioning, braille via `BrailleRasterizer`), then
        /// downscaled once to the footprint. Its information content is set by
        /// the block, not the footprint, and the height-keyed font-sizing
        /// confound of `cell` is gone. Candidates are the MATCHER's candidate
        /// convention per BuildStandardVectors — bounds-centred square
        /// `GlyphRaster` for text glyphs, square `BrailleRasterizer` rasters
        /// for braille — so this arm measures the oracle against the raster
        /// vocabulary the matcher actually indexes.
        case calibratedCell
        /// ASKI-32: same reference as `calibratedCell`, but the candidates are
        /// rendered through the SAME typographic convention at footprint scale
        /// (drawn into a footprint-scale cell block, resampled to the square
        /// footprint). The §7-rule-2 "both sides through one path" arm: the
        /// only asymmetry left is the resolution the two sides were drawn at.
        /// Divergence between this arm and `calibratedCell` isolates what the
        /// matcher's bounds-centred square candidate convention costs.
        case calibratedSamePath
    }

    struct Row: Sendable {
        let charset: String
        let oracle: String
        let shape: String
        let sourceWidth: Int
        let sourceHeight: Int
        let glyphs: Int
        /// References the oracle ranks strictly below at least one other glyph.
        /// Any non-zero count disqualifies the oracle on the gating arm.
        let strictMisses: Int
        /// References that are in the optimal set but share it. A soft fail:
        /// the oracle did not prefer a wrong glyph, it merely cannot separate.
        let tiedRecoveries: Int
        let uniqueRecoveries: Int
        /// References the screen could not score cleanly: the oracle returned a
        /// non-finite score for the reference itself, or for *every* competing
        /// candidate. Neither is a recovery — with no finite competitor the
        /// reference is trivially unbeaten — so they are bucketed here instead
        /// of being credited as unique. `unique + tied + MISS + invalid`
        /// always equals `glyphs`.
        let invalidReferences: Int
        /// Competition rank of the reference in the oracle's own ordering,
        /// averaged over the charset. 1.0 is perfect recovery. An invalid
        /// reference is charged the worst possible rank (`glyphs`) rather than
        /// dropped, so an oracle that fails everywhere prints the worst mean
        /// rank instead of a better-than-perfect one.
        let meanReferenceRank: Double
        let worstReferenceRank: Int
        /// Distinct rasters in the charset at this source shape. A charset whose
        /// glyphs collide before the oracle sees them cannot be uniquely
        /// recovered by ANY metric, so ties up to this deficit are structural.
        let distinctSources: Int
        /// The worst single confusion, as `reference→preferred`, for the row's
        /// highest-ranked reference. A count says an oracle failed; this says
        /// what it confused, which is what makes the failure diagnosable.
        let worstConfusion: String
        /// ASKI-32 AC#2 calibration statement: mean and worst absolute
        /// difference between the reference's ink fraction (mean luma at the
        /// footprint, after its resample) and the ink fraction of the candidate
        /// raster it must out-score. A tone-sensitive oracle can only be asked
        /// to recover a glyph whose reference and candidate agree on how much
        /// ink the glyph has; these columns are what "calibrated" means here,
        /// and they are what the confounded `cell` arm never controlled.
        let meanInkDelta: Double
        let maxInkDelta: Double
    }

    /// The native source-block size the converter resolves for one cell at this
    /// regime, taken from the converter's own `samplingGeometry` through
    /// `SampledSource` rather than recomputed, so it cannot drift from the
    /// lattice the selection-ceiling probe scores against.
    static func nativeCellBlock(columns: Int, oversample: Int, nativeSide: Int) -> (
        width: Int, height: Int
    )? {
        let gray = [UInt8](repeating: 128, count: nativeSide * nativeSide)
        let fixture = ResidualFixture.fromGrayBytes(
            id: "reference-recovery-probe", width: nativeSide, height: nativeSide,
            pool: .synthetic, gray: gray)
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.monochrome,
            colorSpace: .sRGB,
            oversample: oversample
        )
        guard let geometry = converter.samplingGeometry(fixture.image, columns: columns),
            let block = SampledSource.lumaBlock(
                fixture, cellRow: 0, cellCol: 0, geometry: geometry)
        else { return nil }
        return (block.width, block.height)
    }

    static func run(
        columns: Int,
        oversample: Int,
        footprint: Int,
        nativeSide: Int,
        charsetNames: [String]
    ) throws -> [Row] {
        // The square arm is rendered at a native-scale raster so the resample is
        // a genuine downscale, matching the production direction of travel; the
        // cell arm uses the converter's own resolved block.
        let squareSide = footprint * 4
        let cellBlock = nativeCellBlock(
            columns: columns, oversample: oversample, nativeSide: nativeSide)

        var rows: [Row] = []
        for charsetName in charsetNames {
            let characterSet = try SelectionCeiling.characterSet(named: charsetName)
            let glyphs = characterSet.characters
            let footprintCandidates = glyphs.map {
                GlyphRaster.luma(character: $0, width: footprint, height: footprint)
            }
            // The MATCHER's candidate convention, per BuildStandardVectors:
            // braille shape/brightness data is generated by BrailleRasterizer
            // (square raster, position-faithful dots), everything else by a
            // bounds-centred Core Text raster. The legacy arms keep the
            // GlyphRaster candidates unchanged so every archived screen row
            // reproduces byte-for-byte; only `calibratedCell` — the arm whose
            // claim is "against the rasters the matcher indexes" — scores
            // against this set. (Caught by pre-merge cross-model review: the
            // first run of the arm scored braille against Core Text fallback
            // rasters, which are nobody's convention.)
            let matcherCandidates = glyphs.enumerated().map { index, glyph -> [Float] in
                if let scalar = glyph.unicodeScalars.first,
                    (0x2800...0x28FF).contains(scalar.value)
                {
                    return BrailleRasterizer.rasterize(codepoint: scalar.value, size: footprint)
                }
                return footprintCandidates[index]
            }

            for shape in SourceShape.allCases {
                let size: (width: Int, height: Int)
                switch shape {
                case .footprint: size = (footprint, footprint)
                case .square: size = (squareSide, squareSide)
                case .cell, .roundTrip, .calibratedCell, .calibratedSamePath:
                    guard let cellBlock else { continue }
                    size = cellBlock
                }

                // Every arm except `calibratedSamePath` scores against the
                // production candidate rasters — `GlyphRaster` at the square
                // footprint, exactly what the matcher indexes. The same-path
                // arm re-renders the candidates through the typographic cell
                // convention at footprint scale (a footprint-height block at
                // the resolved cell aspect, resampled to the square footprint)
                // so both sides of the comparison share one drawing path.
                let candidates: [[Float]]
                if shape == .calibratedSamePath {
                    let candidateBlock = (
                        width: max(
                            1,
                            Int(
                                (Double(footprint) * Double(size.width)
                                    / Double(size.height)).rounded())),
                        height: footprint
                    )
                    candidates = glyphs.map { glyph -> [Float] in
                        let raster = GlyphCellRaster.luma(
                            character: glyph,
                            width: candidateBlock.width, height: candidateBlock.height)
                        return LumaResample.resample(
                            raster,
                            srcWidth: candidateBlock.width, srcHeight: candidateBlock.height,
                            dstWidth: footprint, dstHeight: footprint)
                    }
                } else if shape == .calibratedCell {
                    candidates = matcherCandidates
                } else {
                    candidates = footprintCandidates
                }

                let sources = glyphs.map { glyph -> [Float] in
                    if shape == .calibratedCell || shape == .calibratedSamePath {
                        // ASKI-32: the reference is drawn typographically into
                        // the converter's resolved native block — baseline and
                        // advance positioning, braille through the production
                        // dot rasterizer — and downscaled ONCE. The source's
                        // information content is set by the block; the
                        // height-keyed clipping of the `cell` arm cannot occur
                        // because the point size derives from the block height
                        // through the renderer's own geometry rule.
                        let raster = GlyphCellRaster.luma(
                            character: glyph, width: size.width, height: size.height)
                        return LumaResample.resample(
                            raster, srcWidth: size.width, srcHeight: size.height,
                            dstWidth: footprint, dstHeight: footprint)
                    }
                    if shape == .roundTrip {
                        // Rasterizer held FIXED at the candidate's own render, so
                        // the only thing this arm adds over `footprint` is the
                        // anisotropic trip through the cell's aspect. It is the
                        // control that says whether a `cell`-arm failure is the
                        // geometry or the way the glyph was drawn into it.
                        let raster = GlyphRaster.luma(
                            character: glyph, width: footprint, height: footprint)
                        let stretched = LumaResample.resample(
                            raster, srcWidth: footprint, srcHeight: footprint,
                            dstWidth: size.width, dstHeight: size.height)
                        return LumaResample.resample(
                            stretched, srcWidth: size.width, srcHeight: size.height,
                            dstWidth: footprint, dstHeight: footprint)
                    }
                    let raster = GlyphRaster.luma(
                        character: glyph, width: size.width, height: size.height)
                    return LumaResample.resample(
                        raster, srcWidth: size.width, srcHeight: size.height,
                        dstWidth: footprint, dstHeight: footprint)
                }
                // Glyphs that already collide as rasters bound what any oracle
                // can separate, so the deficit is reported next to the ties.
                let distinctSources = Set(sources).count

                // AC#2 calibration statement, measured rather than assumed: how
                // far each reference's ink fraction sits from the candidate it
                // must out-score. Oracle-independent, so it is computed once
                // per arm and reported on every oracle row of that arm.
                var inkDeltaTotal = 0.0
                var maxInkDelta = 0.0
                for (index, source) in sources.enumerated() {
                    let sourceInk = source.reduce(0, +) / Float(max(1, source.count))
                    let candidate = candidates[index]
                    let candidateInk = candidate.reduce(0, +) / Float(max(1, candidate.count))
                    let delta = Double(abs(sourceInk - candidateInk))
                    inkDeltaTotal += delta
                    maxInkDelta = max(maxInkDelta, delta)
                }
                let meanInkDelta = glyphs.isEmpty ? 0 : inkDeltaTotal / Double(glyphs.count)

                for oracle in SelectionCeiling.Oracle.allCases {
                    var strictMisses = 0, tied = 0, unique = 0, invalid = 0
                    var rankTotal = 0, worstRank = 1
                    var worstConfusion = "-"
                    // An unscoreable reference is charged the WORST rank rather
                    // than dropped from the average. Dropping it while the mean
                    // still divided by the full charset let an oracle that failed
                    // on every glyph print a mean rank better than perfect.
                    let worstPossibleRank = max(1, glyphs.count)
                    for (referenceIndex, source) in sources.enumerated() {
                        let scores = candidates.map {
                            oracle.score($0, source, footprint: footprint)
                        }
                        let referenceScore = scores[referenceIndex]
                        guard referenceScore.isFinite else {
                            invalid += 1
                            rankTotal += worstPossibleRank
                            worstRank = max(worstRank, worstPossibleRank)
                            continue
                        }
                        // A candidate the oracle cannot score is not a competitor,
                        // but it is not a win either: if EVERY competitor is
                        // non-finite the reference is unbeaten by default, which
                        // would otherwise be recorded as a clean recovery.
                        var comparable = 0
                        var better = 0, equal = 0
                        var preferred = referenceIndex
                        var preferredScore = referenceScore
                        for (index, score) in scores.enumerated() where index != referenceIndex {
                            guard score.isFinite else { continue }
                            comparable += 1
                            let isBetter: Bool
                            let beatsPreferred: Bool
                            switch oracle.polarity {
                            case .lowerIsBetter:
                                isBetter = score < referenceScore
                                beatsPreferred = score < preferredScore
                            case .higherIsBetter:
                                isBetter = score > referenceScore
                                beatsPreferred = score > preferredScore
                            }
                            if isBetter {
                                better += 1
                                if beatsPreferred {
                                    preferred = index
                                    preferredScore = score
                                }
                            } else if score == referenceScore {
                                equal += 1
                                if preferred == referenceIndex { preferred = index }
                            }
                        }
                        guard comparable > 0 || glyphs.count == 1 else {
                            invalid += 1
                            rankTotal += worstPossibleRank
                            worstRank = max(worstRank, worstPossibleRank)
                            continue
                        }
                        let rank = better + 1
                        rankTotal += rank
                        if rank > worstRank || (worstConfusion == "-" && preferred != referenceIndex) {
                            worstConfusion = "\(glyphs[referenceIndex])→\(glyphs[preferred])"
                        }
                        worstRank = max(worstRank, rank)
                        if better > 0 {
                            strictMisses += 1
                        } else if equal > 0 {
                            tied += 1
                        } else {
                            unique += 1
                        }
                    }
                    rows.append(
                        Row(
                            charset: charsetName, oracle: oracle.rawValue, shape: shape.rawValue,
                            sourceWidth: size.width, sourceHeight: size.height,
                            glyphs: glyphs.count,
                            strictMisses: strictMisses, tiedRecoveries: tied,
                            uniqueRecoveries: unique, invalidReferences: invalid,
                            meanReferenceRank: glyphs.isEmpty
                                ? 0 : Double(rankTotal) / Double(glyphs.count),
                            worstReferenceRank: worstRank,
                            distinctSources: distinctSources,
                            worstConfusion: worstConfusion,
                            meanInkDelta: meanInkDelta,
                            maxInkDelta: maxInkDelta))
                }
            }
        }
        return rows
    }

    static func format(_ rows: [Row]) -> String {
        var lines = ["# Reference-recovery screen (ASKI-27 AC#2)"]
        lines.append(
            "charset | oracle | shape | source | glyphs | distinct | unique | tied | MISS | invalid | meanRank | worstRank | worstConfusion | meanInkΔ | maxInkΔ"
        )
        for row in rows {
            lines.append(
                String(
                    format: "%@ | %@ | %@ | %dx%d | %d | %d | %d | %d | %d | %d | %.3f | %d | %@ | %.4f | %.4f",
                    row.charset, row.oracle, row.shape, row.sourceWidth, row.sourceHeight,
                    row.glyphs, row.distinctSources, row.uniqueRecoveries, row.tiedRecoveries,
                    row.strictMisses, row.invalidReferences, row.meanReferenceRank,
                    row.worstReferenceRank, row.worstConfusion,
                    row.meanInkDelta, row.maxInkDelta))
        }
        return lines.joined(separator: "\n")
    }
}
