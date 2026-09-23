import CoreGraphics
import Testing
import simd

@_spi(AskiResearch) @testable import Aski

/// Guards the ASKI-28/30 prerequisite-0 reflection accessor
/// (`ASCIIConverter.cellQueryDescriptors`).
///
/// The census battery's arms F, T and K are not the converter's own pick: they
/// re-run the matcher's selection with a different pool width, a different tone
/// weight, or no shape term at all. Every one of them needs the two per-cell
/// quantities the matcher itself consumes — the 60D query descriptor and the
/// tone `stats.adjustedL` — and neither was reachable from a lab before this
/// accessor existed.
///
/// Two properties matter and are asserted separately here, because a reflection
/// accessor that is merely *present* is worthless if either fails:
///
///  1. **Behavior neutrality.** Reading the descriptors must not perturb what
///     the converter renders. If it did, every number the battery produces would
///     describe an instrument that only exists while it is being measured.
///  2. **Fidelity.** The values handed back must be the values the matcher
///     actually scored. A descriptor that is merely *plausible* would let an arm
///     silently measure a different selector than production's — the exact
///     class of instrument error the 2026-08-19 run hit when it rebuilt the
///     brightness pool by hand and inverted the polarity convention.
@Suite struct ASCIIConverterQueryDescriptorTests {

    /// Off-axis structure with a broad tone ramp, so cells differ in BOTH the
    /// descriptor and the tone — a flat fixture would let a broken accessor pass
    /// by returning one constant.
    private func rampedStructureImage(side: Int) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let center = Double(side) / 2
        for y in 0..<side {
            for x in 0..<side {
                let dx = Double(x) - center, dy = Double(y) - center
                let radius = (dx * dx + dy * dy).squareRoot()
                let rings = (sin(radius * .pi / 7) + 1) / 2
                let ramp = Double(x + y) / Double(2 * side)
                let value = min(1, max(0, 0.55 * rings + 0.45 * ramp))
                context.setFillColor(CGColor(red: value, green: value, blue: value, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return context.makeImage()!
    }

    private func converter(
        _ characterSet: StandardCharacterSet = .standard
    ) -> ASCIIConverter<StandardCharacterSet, BuiltInPalette> {
        ASCIIConverter(
            characterSet: characterSet,
            palette: BuiltInPalette.monochrome,
            colorSpace: .sRGB,
            oversample: 2
        )
    }

    /// Property 1: pure reflection. The grid the accessor reports and the grid a
    /// plain `convert` produces must be the same grid, and calling the accessor
    /// must leave a subsequent `convert` byte-identical to one taken before it.
    @Test func readingDescriptorsLeavesRenderingByteIdentical() throws {
        let image = rampedStructureImage(side: 192)
        let converter = converter()

        let before = converter.convert(image, columns: 24)
        let reflection = try #require(converter.cellQueryDescriptors(image, columns: 24))
        let after = converter.convert(image, columns: 24)

        #expect(before.cells == after.cells, "the accessor perturbed a later conversion")
        #expect(
            reflection.grid.cells == before.cells,
            "the accessor reported a different grid than convert produced")
    }

    /// Property 2, tone half: `adjustedL` is the same value the converter
    /// already publishes per cell as `ASCIICell.brightness`, which is assigned
    /// straight from `stats.adjustedL`. This is the cross-check that the
    /// accessor read the matcher's tone and not some re-derived luma.
    @Test func adjustedLMatchesTheBrightnessTheGridPublishes() throws {
        let image = rampedStructureImage(side: 192)
        let converter = converter()
        let reflection = try #require(converter.cellQueryDescriptors(image, columns: 24))

        var distinct = Set<Float>()
        for row in 0..<reflection.rows {
            for column in 0..<reflection.columns {
                let published = reflection.grid.cells[row][column].brightness
                #expect(
                    reflection.adjustedL(row: row, column: column) == published,
                    "adjustedL disagreed with ASCIICell.brightness at (\(row), \(column))")
                distinct.insert(published)
            }
        }
        // A constant field would satisfy the equality above vacuously.
        #expect(distinct.count > 1, "the fixture produced a constant tone field")
    }

    /// Property 2, descriptor half — the decisive one. Feed the reported lanes
    /// and tone into the SAME public entry point the production kernel calls,
    /// with production's own pool width, and require it to reproduce the glyph
    /// the converter actually rendered, cell for cell.
    ///
    /// This is what makes arms K and T trustworthy: arm K is this call with a
    /// different `topK`, so if the call cannot reproduce production at
    /// `topK = 12`, nothing it reports at `topK = 95` means anything.
    @Test func reportedLanesReproduceTheProductionPickThroughFindBestScored() throws {
        let image = rampedStructureImage(side: 192)
        let characterSet = StandardCharacterSet.standard
        let converter = converter(characterSet)
        let reflection = try #require(converter.cellQueryDescriptors(image, columns: 24))
        try #require(reflection.supportsShapeDescriptor, "fixture produced degenerate cells")

        let glyphs = characterSet.characters
        var checked = 0
        for row in 0..<reflection.rows {
            for column in 0..<reflection.columns {
                let best = ShapeMatching.findBestScored(
                    queryLanes: reflection.lanes(row: row, column: column),
                    queryBrightness: reflection.adjustedL(row: row, column: column),
                    candidateBrightness: characterSet.brightnessValues,
                    candidateLanes: characterSet.shapeVectorLanes,
                    // Production's width at the default `density: 0`.
                    topK: 12
                )
                #expect(
                    glyphs[best.index] == reflection.grid.cells[row][column].character,
                    "cell (\(row), \(column)): re-running the matcher on the reported descriptor picked \(glyphs[best.index]) but the converter rendered \(reflection.grid.cells[row][column].character)"
                )
                checked += 1
            }
        }
        #expect(checked > 0, "no cells were checked")
    }

    /// The lane buffer is flattened, so a shape error here would slice a
    /// neighbouring cell's descriptor and still typecheck. Pin the layout.
    @Test func laneBufferIsFlattenedAtTheDeclaredStride() throws {
        let image = rampedStructureImage(side: 192)
        let reflection = try #require(converter().cellQueryDescriptors(image, columns: 24))

        let cells: Int = reflection.rows * reflection.columns
        let stride: Int = reflection.lanesPerCell
        #expect(stride == StandardCharacterSet.lanesPerCharacter)
        #expect(reflection.lanes.count == cells * stride)
        #expect(reflection.adjustedL.count == cells)
        // Second cell of row 0 must start exactly one stride in.
        let sliced = Array(reflection.lanes[stride..<(2 * stride)])
        #expect(sliced == reflection.lanes(row: 0, column: 1))
    }

    /// The descriptor is a log-polar concept. A non-logPolar converter has no
    /// query lanes to report, and must say so rather than hand back zeros that
    /// would read as a legitimate all-zero descriptor.
    @Test func nonLogPolarAlgorithmsReportNoDescriptors() {
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.blocks,
            palette: BuiltInPalette.monochrome,
            algorithm: .dotMatrix,
            colorSpace: .sRGB,
            oversample: 2
        )
        #expect(converter.cellQueryDescriptors(rampedStructureImage(side: 128), columns: 16) == nil)
    }
}
