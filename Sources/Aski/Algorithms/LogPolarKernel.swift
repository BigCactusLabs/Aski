import simd

internal struct LogPolarKernel: CharacterScoring {
    let glyphBank: GlyphBank

    init(glyphBank: GlyphBank) {
        self.glyphBank = glyphBank
    }

    init<C: ASCIICharacterSet>(characterSet: C) {
        self.init(glyphBank: GlyphBank.adapting(characterSet))
    }

    /// Tone-only ranking for a cell footprint that cannot carry a descriptor,
    /// best first, at most `limit` entries.
    ///
    /// See `ConversionContext.cellSupportsShapeDescriptor`: when either cell
    /// axis is a single pixel, `histogram60` admits nothing and the query is
    /// the all-zero descriptor. That is not a tie — squared-L2 from the zero
    /// vector to a candidate is that candidate's own squared norm, and the
    /// space glyph is the *only* zero-norm reference in the set, so it sits at
    /// distance 0 and wins outright whenever the pre-filter admits it. The
    /// shape term is carrying no information about the cell at all, only about
    /// the candidates. Rather than let that stand, drop it and rank on tone.
    ///
    /// Returning up to `limit` entries rather than just the winner matters for
    /// glyph cycling: `ScheduleBuilder` only lets a cell participate when it
    /// reports at least 2 distinct candidates, so a single-entry list would
    /// silently disable cycling on every degenerate cell.
    private func degenerateToneRanking(
        stats: CellStats,
        in context: borrowing ConversionContext,
        limit: Int
    ) -> [Int] {
        return ShapeMatching.poolIndices(
            queryBrightness: stats.adjustedL,
            candidateBrightness: glyphBank.brightnessValues,
            topK: limit
        )
    }

    private func degenerateToneIndex(
        stats: CellStats,
        in context: borrowing ConversionContext
    ) -> Int {
        degenerateToneRanking(stats: stats, in: context, limit: 1).first ?? 0
    }

    func score(cell: CellCoord, stats: CellStats, in context: borrowing ConversionContext) -> Character {
        guard context.cellSupportsShapeDescriptor else {
            return character(at: degenerateToneIndex(stats: stats, in: context))
        }
        let lanes = extractShapeVector(cell: cell, in: context)
        let topK = 12 + Int((context.options.density * 24).rounded())
        let bestIndex = ShapeMatching.findBest(
            queryLanes: lanes,
            queryBrightness: stats.adjustedL,
            candidateBrightness: glyphBank.brightnessValues,
            candidateLanes: glyphBank.shapeVectorLanes,
            topK: topK
        )
        return character(at: bestIndex)
    }

    private func character(at index: Int) -> Character {
        index < glyphBank.characters.count ? glyphBank.characters[index] : Character(" ")
    }

    /// Returns the same glyph as `score`, paired with the **real** 60D
    /// squared-L2 distance between the cell descriptor and the winning glyph's
    /// shape vector.
    func scoreScored(
        cell: CellCoord,
        stats: CellStats,
        in context: borrowing ConversionContext
    ) -> (character: Character, distance: Float) {
        guard context.cellSupportsShapeDescriptor else {
            // `Float.nan` is the protocol's "no shape residual for this cell"
            // sentinel; the tone fallback computed no shape distance.
            return (character(at: degenerateToneIndex(stats: stats, in: context)), Float.nan)
        }
        let lanes = extractShapeVector(cell: cell, in: context)
        let topK = 12 + Int((context.options.density * 24).rounded())
        let scored = ShapeMatching.findBestScored(
            queryLanes: lanes,
            queryBrightness: stats.adjustedL,
            candidateBrightness: glyphBank.brightnessValues,
            candidateLanes: glyphBank.shapeVectorLanes,
            topK: topK
        )
        let character =
            scored.index < glyphBank.characters.count
            ? glyphBank.characters[scored.index]
            : Character(" ")
        return (character, scored.distance)
    }

    func match(
        cell: CellCoord,
        stats: CellStats,
        in context: borrowing ConversionContext,
        resultLimit: Int
    ) -> CellMatchResult {
        matchWithDescriptor(
            cell: cell,
            stats: stats,
            in: context,
            resultLimit: resultLimit
        ).match
    }

    /// Matches one cell and returns the descriptor lanes extracted for that
    /// match so temporal callers can reuse them for held-glyph distances.
    func matchWithDescriptor(
        cell: CellCoord,
        stats: CellStats,
        in context: borrowing ConversionContext,
        resultLimit: Int
    ) -> (match: CellMatchResult, lanes: [SIMD4<Float>]) {
        guard context.cellSupportsShapeDescriptor else {
            // Same fallback as `score`, so the ranked path agrees with the
            // single-pick path on a degenerate footprint: `ranked[0]` is what
            // `score` returns. The tail is the rest of the tone ranking, which
            // glyph cycling needs — see `degenerateToneRanking`.
            let ranked = degenerateToneRanking(stats: stats, in: context, limit: resultLimit)
            let index = ranked.first ?? 0
            let result = CellMatchResult(
                winnerCharacter: character(at: index),
                winnerIndex: index,
                rankedIndices: ContiguousArray(ranked.isEmpty ? [index] : ranked)
            )
            return (result, [])
        }
        let lanes = extractShapeVector(cell: cell, in: context)
        return (
            match(
                fromLanes: lanes,
                cell: cell,
                stats: stats,
                in: context,
                resultLimit: resultLimit
            ),
            lanes
        )
    }

    private func match(
        fromLanes lanes: borrowing [SIMD4<Float>],
        cell: CellCoord,
        stats: CellStats,
        in context: borrowing ConversionContext,
        resultLimit: Int
    ) -> CellMatchResult {
        let brightnessLimit = 12 + Int((context.options.density * 24).rounded())
        if resultLimit == 1 {
            let bestIndex = ShapeMatching.findBest(
                queryLanes: lanes,
                queryBrightness: stats.adjustedL,
                candidateBrightness: glyphBank.brightnessValues,
                candidateLanes: glyphBank.shapeVectorLanes,
                topK: brightnessLimit
            )
            return CellMatchResult(
                winnerCharacter: glyphBank.characters[bestIndex],
                winnerIndex: bestIndex,
                rankedIndices: [bestIndex]
            )
        }

        let ranked = ShapeMatching.findRanked(
            queryLanes: lanes,
            queryBrightness: stats.adjustedL,
            candidateBrightness: glyphBank.brightnessValues,
            candidateLanes: glyphBank.shapeVectorLanes,
            brightnessLimit: brightnessLimit,
            resultLimit: resultLimit
        )
        let winnerIndex = ranked[0]
        return CellMatchResult(
            winnerCharacter: glyphBank.characters[winnerIndex],
            winnerIndex: winnerIndex,
            rankedIndices: ContiguousArray(ranked)
        )
    }

    /// Pure 60D squared-L2 distance between this cell's shape descriptor and the
    /// stored shape vector of `glyphIndex`. Unlike `scoreScored` (which surfaces a
    /// distance only for the winner) or `match` (which restricts to a brightness
    /// band / top-K pool), this is computable for **any** glyph -- including one
    /// outside the current pool, which is exactly the held-glyph case the
    /// ASTSK-41 hysteresis prior needs. Mirrors the per-lane `simd_dot`
    /// accumulation in `ShapeMatching.findBestScored`. Returns `.infinity` for an
    /// out-of-range index so an invalid held glyph never wins the deadband test.
    func distance(
        ofGlyph glyphIndex: Int,
        forCell cell: CellCoord,
        in context: borrowing ConversionContext
    ) -> Float {
        let count = glyphBank.characters.count
        guard glyphIndex >= 0, glyphIndex < count else { return .infinity }
        let lanes = extractShapeVector(cell: cell, in: context)
        return distance(fromLanes: lanes, toGlyph: glyphIndex)
    }

    /// Pure 60D squared-L2 distance from already-extracted descriptor lanes to
    /// one glyph. Preserves the cell-based helper's validation and accumulation
    /// order while avoiding repeated descriptor extraction.
    func distance(
        fromLanes lanes: borrowing [SIMD4<Float>],
        toGlyph glyphIndex: Int
    ) -> Float {
        let count = glyphBank.characters.count
        guard glyphIndex >= 0, glyphIndex < count else { return .infinity }
        let lanesPerCharacter = StandardCharacterSet.lanesPerCharacter
        // `matchWithDescriptor` returns no lanes on a degenerate cell footprint
        // (see `ConversionContext.cellSupportsShapeDescriptor`). `.infinity`
        // keeps the temporal hysteresis from holding a glyph it cannot score.
        guard lanes.count == lanesPerCharacter else { return .infinity }
        let candidateLanes = glyphBank.shapeVectorLanes
        let offset = glyphIndex * lanesPerCharacter
        var distance: Float = 0
        for laneIndex in 0..<lanesPerCharacter {
            let delta = lanes[laneIndex] - candidateLanes[offset + laneIndex]
            distance += simd_dot(delta, delta)
        }
        return distance
    }

    private func extractShapeVector(
        cell: CellCoord,
        in context: borrowing ConversionContext
    ) -> [SIMD4<Float>] {
        extractShapeVector(
            cell: cell,
            in: context,
            baseInkField: baseInkField(cell: cell, in: context)
        )
    }

    /// Research reflection: the 60D query descriptor for `cell`, built by the
    /// same private extractor `score`/`scoreScored`/`match` build theirs with.
    ///
    /// Pure read — it selects nothing, mutates nothing, and is never called from
    /// a conversion path. It exists so `ASCIIConverter.cellQueryDescriptors` can
    /// hand a lab the actual query the matcher scored, instead of the lab
    /// re-deriving it and getting a convention subtly wrong (the failure mode
    /// recorded in `ASCIIConverter+Research.swift`).
    func researchQueryShapeVector(
        cell: CellCoord,
        in context: borrowing ConversionContext
    ) -> [SIMD4<Float>] {
        extractShapeVector(cell: cell, in: context)
    }

    private func extractShapeVector(
        cell: CellCoord,
        in context: borrowing ConversionContext,
        baseInkField: [Float]
    ) -> [SIMD4<Float>] {
        let edgeEmphasis = context.options.edgeEmphasis
        var grayscale = baseInkField

        // edgeEmphasis blends Sobel-Feldman gradient magnitude into the
        // pixel weights before histogram accumulation. At 0, weights are
        // unchanged (matches Task 3 verbatim path). At 1, weights are pure
        // gradient magnitude, normalized to peak 1.
        if edgeEmphasis > 0 {
            let sobel = sobelMagnitude(grayscale, width: context.cellWidth, height: context.cellHeight)
            let peak = sobel.max() ?? 0
            if peak > 0 {
                for i in 0..<grayscale.count {
                    let g = grayscale[i]
                    let s = sobel[i] / peak
                    grayscale[i] = g * (1 - edgeEmphasis) + s * edgeEmphasis
                }
            }
        }

        let descriptor = ShapeContext.histogram60(grayscale, width: context.cellWidth, height: context.cellHeight)
        var lanes: [SIMD4<Float>] = []
        lanes.reserveCapacity(StandardCharacterSet.lanesPerCharacter)
        for index in stride(from: 0, to: StandardCharacterSet.shapeVectorDimension, by: 4) {
            lanes.append(
                SIMD4(
                    descriptor[index],
                    descriptor[index + 1],
                    descriptor[index + 2],
                    descriptor[index + 3]
                ))
        }
        return lanes
    }

    /// The base ink field for a cell, before the optional edge blend.
    ///
    /// `shapeQueryPolarity` decides which end of the source counts as ink.
    /// `.inverted` — the shipped default — stores `1 − Rec.601 luma`, so DARK
    /// source regions carry the descriptor mass; `.direct` stores the raw
    /// luma, putting the query on the ink-high axis the candidate rasters, the
    /// tone pre-filter and the renderer already use (ASKI-60).
    private func baseInkField(
        cell: CellCoord, in context: borrowing ConversionContext
    ) -> [Float] {
        var grayscale = [Float](repeating: 0, count: context.cellWidth * context.cellHeight)
        for dy in 0..<context.cellHeight {
            for dx in 0..<context.cellWidth {
                let x = cell.column * context.cellWidth + dx
                let y = cell.row * context.cellHeight + dy
                let offset = (y * context.pixelWidth + x) * 4
                let red = Float(context.pixels[offset]) / 255
                let green = Float(context.pixels[offset + 1]) / 255
                let blue = Float(context.pixels[offset + 2]) / 255
                let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
                grayscale[dy * context.cellWidth + dx] =
                    context.options.shapeQueryPolarity == .inverted ? 1 - luminance : luminance
            }
        }
        return grayscale
    }

    private func sobelMagnitude(_ pixels: [Float], width w: Int, height h: Int) -> [Float] {
        var out = [Float](repeating: 0, count: w * h)
        guard w >= 3, h >= 3 else { return out }
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let gx =
                    -pixels[(y - 1) * w + (x - 1)] + pixels[(y - 1) * w + (x + 1)]
                    + -2 * pixels[y * w + (x - 1)] + 2 * pixels[y * w + (x + 1)]
                    + -pixels[(y + 1) * w + (x - 1)] + pixels[(y + 1) * w + (x + 1)]
                let gy =
                    -pixels[(y - 1) * w + (x - 1)] - 2 * pixels[(y - 1) * w + x] - pixels[(y - 1) * w + (x + 1)]
                    + pixels[(y + 1) * w + (x - 1)] + 2 * pixels[(y + 1) * w + x] + pixels[(y + 1) * w + (x + 1)]
                out[y * w + x] = (gx * gx + gy * gy).squareRoot()
            }
        }
        return out
    }

}
