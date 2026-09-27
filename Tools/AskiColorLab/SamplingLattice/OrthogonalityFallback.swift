import CoreGraphics
import Foundation
import simd

@_spi(AskiResearch) import Aski

/// The two ASKI-79/80 candidate selectors, pure and lab-only. The frozen rule
/// is `docs/Research/2026-09-27-aski-79-80-orthogonality-fallback-rule.md` §3.
///
/// **Arm 1 (orthogonality → tone fallback).** Build production's brightness
/// pool. If the cell's query shares no bin with any non-blank pooled candidate
/// (`q·g == 0` for every pooled `g` with `|g|² > 0`), the shape distance can
/// only rank candidates by their own norm, so pick the tone-nearest pooled
/// glyph instead — `poolIndices(...)[0]`, the order `degenerateToneRanking`
/// already uses. Otherwise keep production's shape argmin. The blank then wins
/// a cell only where it is the tone-nearest candidate.
///
/// **Arm 2 (arm 1 + Floyd–Steinberg tone centring).** A serial raster walk that
/// mirrors `DotMatrixKernel.pick`: the carried error shifts the tone that
/// centres the pool and the tone the fallback ranks against, and the residual
/// `target − brightness[pick]` diffuses 7/16 right, 3/16 below-left, 5/16 below
/// and 1/16 below-right, dropped at the grid edge. Serial by construction, so
/// it can only ever be measured here.
enum OrthogonalityFallback {

    /// `true` when `queryLanes` is orthogonal to every non-blank candidate in
    /// `pool`. Exact zero: bins are non-negative masses, so the dot product is
    /// zero exactly when the supports are disjoint.
    static func isOrthogonal(
        queryLanes: [SIMD4<Float>],
        pool: [Int],
        candidateLanes: [SIMD4<Float>],
        blank: Set<Int>
    ) -> Bool {
        let lanesPerCharacter = queryLanes.count
        for candidate in pool where !blank.contains(candidate) {
            var dot: Float = 0
            for lane in 0..<lanesPerCharacter {
                dot += simd_dot(
                    queryLanes[lane], candidateLanes[candidate * lanesPerCharacter + lane])
            }
            if dot != 0 { return false }
        }
        return true
    }

    /// Arm 1's pick for one cell whose pool is centred on `tone`.
    static func pick(
        queryLanes: [SIMD4<Float>],
        tone: Float,
        candidateLanes: [SIMD4<Float>],
        brightnessValues: [Float],
        blank: Set<Int>,
        topK: Int
    ) -> Int {
        let width = max(1, min(topK, brightnessValues.count))
        let pool = ShapeMatching.poolIndices(
            queryBrightness: tone, candidateBrightness: brightnessValues, topK: width)
        if isOrthogonal(
            queryLanes: queryLanes, pool: pool, candidateLanes: candidateLanes, blank: blank)
        {
            return pool[0]
        }
        return ShapeMatching.findBestScored(
            queryLanes: queryLanes,
            queryBrightness: tone,
            candidateBrightness: brightnessValues,
            candidateLanes: candidateLanes,
            topK: width
        ).index
    }

    /// Arm 2's picks for a whole grid, walked serially in raster order.
    ///
    /// `queryLanes[row * columns + column]` and `tones[...]` are the matcher's
    /// per-cell query and `adjustedL`. `strength` scales the diffused residual
    /// exactly as `DotMatrixKernel`'s `ditherStrength` does; at 0 this is arm 1.
    static func errorDiffusedPicks(
        rows: Int,
        columns: Int,
        queryLanes: [[SIMD4<Float>]],
        tones: [Float],
        candidateLanes: [SIMD4<Float>],
        brightnessValues: [Float],
        blank: Set<Int>,
        topK: Int,
        strength: Float
    ) -> [[Int]] {
        precondition(queryLanes.count == rows * columns && tones.count == rows * columns)
        var error = [Float](repeating: 0, count: max(1, rows * columns))
        var picks = [[Int]](repeating: [Int](repeating: 0, count: columns), count: rows)
        func diffuse(_ delta: Float, row: Int, column: Int) {
            guard row >= 0, row < rows, column >= 0, column < columns else { return }
            error[row * columns + column] += delta
        }
        for row in 0..<rows {
            for column in 0..<columns {
                let cell = row * columns + column
                let target = tones[cell] + error[cell]
                let picked = pick(
                    queryLanes: queryLanes[cell], tone: target, candidateLanes: candidateLanes,
                    brightnessValues: brightnessValues, blank: blank, topK: topK)
                picks[row][column] = picked
                let residual = (target - brightnessValues[picked]) * strength
                diffuse(residual * 7 / 16, row: row, column: column + 1)
                diffuse(residual * 3 / 16, row: row + 1, column: column - 1)
                diffuse(residual * 5 / 16, row: row + 1, column: column)
                diffuse(residual * 1 / 16, row: row + 1, column: column + 1)
            }
        }
        return picks
    }
}

/// A before/after render of the frozen preset for owner review (ASKI-79/80 rule
/// §3.2): production's grid, and the same grid with arm 1's pick substituted
/// in every cell. Colour, alpha, brightness and coverage come from the
/// converter's own cells and do not depend on the glyph, so the two renders
/// differ in glyph choice alone.
enum OrthogonalityRenderPair {

    struct Result {
        let production: CGImage
        let fallback: CGImage
        let cells: Int
        let changedCells: Int
        /// Whether the production half is byte-identical to the preset's own
        /// `render(_:)` entry point, i.e. the pair was built on the real path.
        let productionMatchesEntryPoint: Bool
        /// The fallback grid's characters, row-major, for a text record.
        let fallbackText: String
        let productionText: String
    }

    static func render(_ image: CGImage, preset: VesperPreset = .canonical) -> Result? {
        let converter = preset.makeConverter()
        guard let queries = converter.cellQueryDescriptors(image, columns: preset.columns)
        else { return nil }
        let characterSet = converter.characterSet
        let candidateLanes = characterSet.shapeVectorLanes
        let brightness = characterSet.brightnessValues
        let glyphs = characterSet.characters
        let blank = PickTexture.zeroNormGlyphs(
            candidateLanes: candidateLanes, lanesPerCharacter: StandardCharacterSet.lanesPerCharacter)
        let topK = 12 + Int((converter.options.density * 24).rounded())
        let grid = queries.grid

        var changed = 0
        var cells: [[ASCIICell]] = []
        for row in 0..<grid.rows {
            var rowCells: [ASCIICell] = []
            for column in 0..<grid.columns {
                let cell = grid.cells[row][column]
                let picked = OrthogonalityFallback.pick(
                    queryLanes: queries.lanes(row: row, column: column),
                    tone: queries.adjustedL(row: row, column: column),
                    candidateLanes: candidateLanes, brightnessValues: brightness,
                    blank: blank, topK: topK)
                if glyphs[picked] != cell.character { changed += 1 }
                rowCells.append(
                    ASCIICell(
                        character: glyphs[picked], displayColor: cell.displayColor,
                        alpha: cell.alpha, brightness: cell.brightness, coverage: cell.coverage))
            }
            cells.append(rowCells)
        }
        let fallbackGrid = ASCIIGrid(
            cells: cells, colorSpace: grid.colorSpace, composition: grid.composition,
            maskFallback: grid.maskFallback, maskGroundColor: grid.maskGroundColor,
            maskUsesHardEdges: grid.maskUsesHardEdges)

        func draw(_ grid: ASCIIGrid) -> CGImage {
            grid.renderImage(
                font: preset.font, backgroundColor: preset.backgroundColor, scale: preset.scale,
                preserveSourceAspect: true)
        }
        let production = draw(grid)
        let entryPoint = preset.render(image)
        func text(_ grid: ASCIIGrid) -> String {
            grid.cells.map { String($0.map(\.character)) }.joined(separator: "\n")
        }
        return Result(
            production: production, fallback: draw(fallbackGrid), cells: grid.rows * grid.columns,
            changedCells: changed,
            productionMatchesEntryPoint: pixelsEqual(production, entryPoint),
            fallbackText: text(fallbackGrid), productionText: text(grid))
    }

    private static func pixelsEqual(_ left: CGImage, _ right: CGImage) -> Bool {
        guard left.width == right.width, left.height == right.height,
            let leftData = left.dataProvider?.data, let rightData = right.dataProvider?.data
        else { return false }
        return (leftData as Data) == (rightData as Data)
    }
}
