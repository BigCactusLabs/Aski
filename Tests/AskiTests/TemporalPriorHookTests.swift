import CoreGraphics
import Foundation
import Testing
import simd

@_spi(AskiResearch) @testable import Aski

@Suite struct TemporalPriorHookTests {
    @Test func distanceOfGlyphMatchesScoredWinnerDistance() {
        let context = Self.context()
        let kernel = LogPolarKernel(characterSet: StandardCharacterSet.standard)
        let cell = CellCoord(column: 0, row: 0)
        let stats = CellStats(displayColor: .one, alpha: 1, adjustedL: 0.5, rawL: 0.5)

        let match = kernel.match(cell: cell, stats: stats, in: context, resultLimit: 1)
        let scored = kernel.scoreScored(cell: cell, stats: stats, in: context)
        let distance = kernel.distance(ofGlyph: match.winnerIndex, forCell: cell, in: context)

        #expect(distance.isFinite)
        #expect(distance >= 0)
        #expect(abs(distance - scored.distance) < 1e-4)
    }

    @Test func precomputedDescriptorMatchesCellBasedMatchAndDistances() {
        let context = Self.context()
        let kernel = LogPolarKernel(characterSet: StandardCharacterSet.standard)
        let cell = CellCoord(column: 0, row: 0)
        let stats = CellStats(displayColor: .one, alpha: 1, adjustedL: 0.5, rawL: 0.5)

        let directMatch = kernel.match(cell: cell, stats: stats, in: context, resultLimit: 1)
        let prepared = kernel.matchWithDescriptor(
            cell: cell,
            stats: stats,
            in: context,
            resultLimit: 1
        )

        #expect(prepared.match.winnerIndex == directMatch.winnerIndex)
        #expect(prepared.match.winnerCharacter == directMatch.winnerCharacter)
        #expect(prepared.match.rankedIndices == directMatch.rankedIndices)

        for glyphIndex in StandardCharacterSet.standard.characters.indices {
            let directDistance = kernel.distance(
                ofGlyph: glyphIndex,
                forCell: cell,
                in: context
            )
            let preparedDistance = kernel.distance(
                fromLanes: prepared.lanes,
                toGlyph: glyphIndex
            )
            #expect(preparedDistance.bitPattern == directDistance.bitPattern)
        }
        #expect(kernel.distance(fromLanes: prepared.lanes, toGlyph: -1) == .infinity)
        #expect(
            kernel.distance(
                fromLanes: prepared.lanes,
                toGlyph: StandardCharacterSet.standard.characters.count
            ) == .infinity
        )
    }

    @Test func distanceOfGlyphOutOfRangeIsInfinity() {
        let context = Self.context()
        let kernel = LogPolarKernel(characterSet: StandardCharacterSet.standard)
        let cell = CellCoord(column: 0, row: 0)
        let count = StandardCharacterSet.standard.characters.count

        #expect(kernel.distance(ofGlyph: -1, forCell: cell, in: context) == .infinity)
        #expect(kernel.distance(ofGlyph: count, forCell: cell, in: context) == .infinity)
    }

    @Test func controlArmIsByteIdenticalToConvert() {
        let converter = DefaultConverter()
        let img = Self.rampImage(side: 64)
        let noPrior: TemporalPriorState? = nil

        let baseline = converter.convert(img, columns: 8)
        let treated = converter.convertTemporalFrame(
            img,
            columns: 8,
            prior: noPrior,
            alpha: 1,
            tau: 0
        )

        Self.expectByteIdentical(baseline, treated.grid)
        #expect(treated.state.columns == baseline.columns)
        #expect(treated.state.rows == baseline.rows)
    }

    @Test func controlArmMatchesConvertAcrossAspectRatiosAndPortraitPaintsGlyphs() {
        let preset = VesperPreset.canonical
        let converter = preset.makeConverter()
        let fixtures: [(name: String, image: CGImage)] = [
            ("square", TestImages.structuredPortraitProxy(width: 240, height: 240)),
            ("landscape", TestImages.structuredPortraitProxy(width: 320, height: 240)),
            ("portrait", TestImages.structuredPortraitProxy(width: 240, height: 320)),
        ]

        for fixture in fixtures {
            let baseline = converter.convert(fixture.image, columns: preset.columns)
            let temporal = converter.convertTemporalFrame(
                fixture.image,
                columns: preset.columns,
                prior: nil,
                alpha: 1,
                tau: 0
            )

            Self.expectByteIdentical(baseline, temporal.grid)
            if fixture.name == "portrait" {
                let cells = temporal.grid.cells.flatMap { $0 }
                let paintedCount = cells.count(where: { $0.character != " " })
                #expect(paintedCount > cells.count / 4, "portrait temporal output should paint glyphs")
            }
        }
    }

    @Test func alphaOneThreadedStillMatchesConvert() {
        let converter = DefaultConverter()
        let img = Self.rampImage(side: 64)
        let noPrior: TemporalPriorState? = nil

        let first = converter.convertTemporalFrame(
            img,
            columns: 8,
            prior: noPrior,
            alpha: 1,
            tau: 0
        )
        let second = converter.convertTemporalFrame(
            img,
            columns: 8,
            prior: first.state,
            alpha: 1,
            tau: 0
        )

        let baseline = converter.convert(img, columns: 8)
        Self.expectCharactersEqual(baseline, first.grid)
        Self.expectCharactersEqual(baseline, second.grid)
    }

    @Test func hysteresisHoldsGlyphAcrossASmallChange() {
        let converter = DefaultConverter()
        let firstImage = Self.rampImage(side: 96)
        let firstBaseline = converter.convert(firstImage, columns: 16)
        let noPrior: TemporalPriorState? = nil

        var shiftedImage = firstImage
        var secondBaseline = firstBaseline
        var baselineChanges = 0
        for shift in 1...24 {
            let candidate = Self.shiftedRampImage(side: 96, shift: shift)
            let candidateBaseline = converter.convert(candidate, columns: 16)
            let changes = Self.changedCells(firstBaseline, candidateBaseline)
            if changes > 0 {
                shiftedImage = candidate
                secondBaseline = candidateBaseline
                baselineChanges = changes
                break
            }
        }

        #expect(baselineChanges > 0)

        let firstTreated = converter.convertTemporalFrame(
            firstImage,
            columns: 16,
            prior: noPrior,
            alpha: 1,
            tau: 0
        )
        let secondTreated = converter.convertTemporalFrame(
            shiftedImage,
            columns: 16,
            prior: firstTreated.state,
            alpha: 1,
            tau: 10_000
        )

        let treatedChanges = Self.changedCells(firstTreated.grid, secondTreated.grid)
        #expect(treatedChanges < baselineChanges)
        #expect(baselineChanges == Self.changedCells(firstBaseline, secondBaseline))
    }

    // MARK: - ASTSK-45 source-tether (rho) hook

    /// AC#4: the new `sourceTetherRho` lever is off-by-default; passing `nil` leaves the
    /// rendered grid byte-identical to plain `convert`.
    @Test func sourceTetherNilIsByteIdenticalToConvert() {
        let converter = DefaultConverter()
        let img = Self.rampImage(side: 64)

        let baseline = converter.convert(img, columns: 8)
        let treated = converter.convertTemporalFrame(
            img,
            columns: 8,
            prior: nil,
            alpha: 1,
            tau: 0,
            sourceTetherRho: nil
        )

        Self.expectByteIdentical(baseline, treated.grid)
    }

    /// The tether holds the first-appearance glyph across a small source move, so fewer cells
    /// change than the per-frame-independent baseline recomputes.
    @Test func sourceTetherHoldsGlyphAcrossASmallChange() {
        let converter = DefaultConverter()
        let firstImage = Self.rampImage(side: 96)
        let (shiftedImage, baselineChanges) = Self.firstShiftThatChangesBaseline(converter)
        #expect(baselineChanges > 0)

        let firstTreated = converter.convertTemporalFrame(
            firstImage, columns: 16, prior: nil, alpha: 1, tau: 0, sourceTetherRho: 2.0)
        let secondTreated = converter.convertTemporalFrame(
            shiftedImage, columns: 16, prior: firstTreated.state, alpha: 1, tau: 0,
            sourceTetherRho: 2.0)

        let treatedChanges = Self.changedCells(firstTreated.grid, secondTreated.grid)
        #expect(treatedChanges < baselineChanges)
    }

    /// Monotonicity: the rho=2 hold-set is a superset of the rho=0 hold-set (lockDist >= 0),
    /// so a larger rho can only suppress more changes, never fewer.
    @Test func largerRhoSuppressesNoFewerChangesThanSmallerRho() {
        let converter = DefaultConverter()
        let firstImage = Self.rampImage(side: 96)
        let (shiftedImage, baselineChanges) = Self.firstShiftThatChangesBaseline(converter)
        #expect(baselineChanges > 0)

        func treatedChanges(rho: Float) -> Int {
            let first = converter.convertTemporalFrame(
                firstImage, columns: 16, prior: nil, alpha: 1, tau: 0, sourceTetherRho: rho)
            let second = converter.convertTemporalFrame(
                shiftedImage, columns: 16, prior: first.state, alpha: 1, tau: 0,
                sourceTetherRho: rho)
            return Self.changedCells(first.grid, second.grid)
        }

        #expect(treatedChanges(rho: 2.0) <= treatedChanges(rho: 0))
    }

    /// First-appearance anchoring (the frozen §3 rule): when the displayed glyph is unchanged
    /// (a hold, or a release whose argmax equals the held glyph), `lockDistance` is carried
    /// forward untouched -- NOT re-recorded to the current, degraded fit. The rejected ratchet
    /// alternative (re-anchor on every release) would fail the exact-equality assertion.
    @Test func lockDistanceIsAnchoredToFirstAppearanceNotReRecordedOnHold() {
        let converter = DefaultConverter()
        let firstImage = Self.rampImage(side: 96)
        let (shiftedImage, _) = Self.firstShiftThatChangesBaseline(converter)

        let first = converter.convertTemporalFrame(
            firstImage, columns: 16, prior: nil, alpha: 1, tau: 0, sourceTetherRho: 0)
        let second = converter.convertTemporalFrame(
            shiftedImage, columns: 16, prior: first.state, alpha: 1, tau: 0, sourceTetherRho: 0)

        #expect(first.state.lockDistance.count == first.state.heldGlyphIndex.count)
        #expect(second.state.lockDistance.count == second.state.heldGlyphIndex.count)

        var heldCells = 0
        var releasedCells = 0
        let count = min(first.state.lockDistance.count, second.state.lockDistance.count)
        for cell in 0..<count {
            if second.state.heldGlyphIndex[cell] == first.state.heldGlyphIndex[cell] {
                heldCells += 1
                #expect(second.state.lockDistance[cell] == first.state.lockDistance[cell])
            } else {
                releasedCells += 1
                #expect(second.state.lockDistance[cell].isFinite)
            }
        }
        #expect(heldCells > 0)
        #expect(releasedCells > 0)
    }

    /// A state returned by the non-tether (nil-ρ / τ) path carries no real first-appearance locks.
    /// If the tether is enabled on a later frame threading that state, the first tethered frame must
    /// re-anchor every cell to a real commit fit — NOT treat the default path's filler entries as
    /// valid locks (which would leave `heldDist ≤ lockDist·(1+ρ)` comparing against 0 and silently
    /// disable the tether for unchanged cells). Anchoring after a non-tether frame on a static source
    /// must match a fresh tethered start exactly.
    @Test func sourceTetherReAnchorsWhenEnabledAfterNonTetherFrame() {
        let converter = DefaultConverter()
        let img = Self.rampImage(side: 96)

        let untethered = converter.convertTemporalFrame(
            img, columns: 16, prior: nil, alpha: 1, tau: 0, sourceTetherRho: nil)
        let enabledAfter = converter.convertTemporalFrame(
            img, columns: 16, prior: untethered.state, alpha: 1, tau: 0, sourceTetherRho: 2.0)
        let freshStart = converter.convertTemporalFrame(
            img, columns: 16, prior: nil, alpha: 1, tau: 0, sourceTetherRho: 2.0)

        #expect(freshStart.state.lockDistance.contains { $0 > 0 })  // non-vacuous: real anchors exist
        #expect(enabledAfter.state.lockDistance == freshStart.state.lockDistance)
    }

    /// Smallest `shift` whose per-frame-independent baseline differs from the unshifted frame,
    /// with the resulting changed-cell count. Shared by the source-tether hold/anchor tests.
    private static func firstShiftThatChangesBaseline(
        _ converter: DefaultConverter
    ) -> (image: CGImage, baselineChanges: Int) {
        let firstImage = rampImage(side: 96)
        let firstBaseline = converter.convert(firstImage, columns: 16)
        for shift in 1...24 {
            let candidate = shiftedRampImage(side: 96, shift: shift)
            let changes = changedCells(firstBaseline, converter.convert(candidate, columns: 16))
            if changes > 0 {
                return (candidate, changes)
            }
        }
        return (firstImage, 0)
    }

    private static func context() -> ConversionContext {
        let cellWidth = 16
        let cellHeight = 16
        return ConversionContext(
            pixels: [UInt8](repeating: 128, count: cellWidth * cellHeight * 4),
            pixelWidth: cellWidth,
            pixelHeight: cellHeight,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            columns: 1,
            rows: 1,
            palette: .passThrough,
            options: ResolvedRenderingOptions(.default),
            colorSpace: .sRGB
        )
    }

    private static func image(_ rgba: [UInt8], width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private static func rampImage(side: Int) -> CGImage {
        rampImage(side: side, shift: 0)
    }

    private static func shiftedRampImage(side: Int, shift: Int) -> CGImage {
        rampImage(side: side, shift: shift)
    }

    private static func rampImage(side: Int, shift: Int) -> CGImage {
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        let span = Double(max(1, side + side - 2))
        for y in 0..<side {
            for x in 0..<side {
                let shiftedX = (x + shift) % side
                let value = UInt8(
                    min(255, max(0, Int((Double(shiftedX + y) / span) * 255))))
                let offset = (y * side + x) * 4
                rgba[offset] = value
                rgba[offset + 1] = value
                rgba[offset + 2] = value
                rgba[offset + 3] = 255
            }
        }
        return image(rgba, width: side, height: side)
    }

    private static func changedCells(_ lhs: ASCIIGrid, _ rhs: ASCIIGrid) -> Int {
        var changes = 0
        for row in 0..<min(lhs.rows, rhs.rows) {
            for column in 0..<min(lhs.columns, rhs.columns) {
                if lhs.cells[row][column].character != rhs.cells[row][column].character {
                    changes += 1
                }
            }
        }
        changes += abs(lhs.rows * lhs.columns - rhs.rows * rhs.columns)
        return changes
    }

    private static func expectCharactersEqual(_ lhs: ASCIIGrid, _ rhs: ASCIIGrid) {
        #expect(lhs.columns == rhs.columns)
        #expect(lhs.rows == rhs.rows)
        for row in 0..<min(lhs.rows, rhs.rows) {
            for column in 0..<min(lhs.columns, rhs.columns) {
                #expect(lhs.cells[row][column].character == rhs.cells[row][column].character)
            }
        }
    }

    private static func expectByteIdentical(_ lhs: ASCIIGrid, _ rhs: ASCIIGrid) {
        #expect(lhs.columns == rhs.columns)
        #expect(lhs.rows == rhs.rows)
        #expect(lhs.colorSpace == rhs.colorSpace)
        #expect(lhs.composition == rhs.composition)
        for row in 0..<min(lhs.rows, rhs.rows) {
            for column in 0..<min(lhs.columns, rhs.columns) {
                let lhsCell = lhs.cells[row][column]
                let rhsCell = rhs.cells[row][column]
                #expect(lhsCell.character == rhsCell.character)
                #expect(lhsCell.displayColor.x.bitPattern == rhsCell.displayColor.x.bitPattern)
                #expect(lhsCell.displayColor.y.bitPattern == rhsCell.displayColor.y.bitPattern)
                #expect(lhsCell.displayColor.z.bitPattern == rhsCell.displayColor.z.bitPattern)
                #expect(lhsCell.alpha.bitPattern == rhsCell.alpha.bitPattern)
                #expect(lhsCell.brightness.bitPattern == rhsCell.brightness.bitPattern)
                #expect(lhsCell.coverage.bitPattern == rhsCell.coverage.bitPattern)
            }
        }
    }
}
