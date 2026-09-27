import CoreGraphics
import Foundation
import ImageIO
import Testing
import simd

@_spi(AskiResearch) @testable import Aski

/// Pins the cause of ASKI-79 (logPolar renders an all-blank grid on five
/// built-in sets) and ASKI-80 (logPolar on `standard` reduces to a fixed glyph
/// per tone band).
///
/// At the shipping footprint every cell query can occupy only the few
/// descriptor bins the 2x4 cell reaches (the ASKI-55 support collapse). A
/// non-blank glyph with no mass in those bins has `q·g == 0` against every
/// query, so the distance cannot prefer it over a lighter glyph; when no
/// non-blank glyph in a set reaches them, the zero-norm blank wins every cell.
///
/// The reachable set is derived here from real query descriptors, not written
/// down: a saturated cell (every pixel ink under the shipped inverted query)
/// occupies every bin the footprint can reach, and a real fixture's queries
/// must stay inside that set.
@Suite struct LogPolarReachableSupportTests {

    private static let shippingColumns = 80

    private static let builtIns: [(name: String, set: StandardCharacterSet)] = [
        ("standard", .standard), ("minimal", .minimal), ("blocks", .blocks),
        ("dots", .dots), ("lines", .lines), ("diagonal", .diagonal), ("cross", .cross),
        ("diamond", .diamond), ("mixed", .mixed), ("braille", .braille),
    ]

    /// The five sets ASKI-79 measured as all-blank under logPolar.
    private static let blankCollapsed: Set<String> = [
        "minimal", "dots", "diagonal", "cross", "diamond",
    ]

    private static var packageRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// The selection-ceiling census's default corpus fixture ASKI-79 names.
    private static func vavilovCrater() throws -> CGImage {
        let url = packageRootURL.appending(
            path: "docs/Research/Corpus/nasa-steerable-v1/assets/vavilov-crater.png")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// A uniform square image of one gray level.
    private static func flat(gray: UInt8, side: Int) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue))
        let value = CGFloat(gray) / 255
        context.setFillColor(CGColor(gray: value, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return try #require(context.makeImage())
    }

    /// The shipping converter: default options (inverted query, density 0) and
    /// default oversample.
    private static func converter(_ set: StandardCharacterSet)
        -> ASCIIConverter<StandardCharacterSet, BuiltInPalette>
    {
        ASCIIConverter(characterSet: set, palette: BuiltInPalette.monochrome)
    }

    /// Union of the bins any cell query occupies.
    private static func occupiedBins(_ queries: CellQueryDescriptors) -> Set<Int> {
        var bins = Set<Int>()
        for row in 0..<queries.rows {
            for column in 0..<queries.columns {
                let lanes = queries.lanes(row: row, column: column)
                for lane in lanes.indices {
                    for component in 0..<4 where lanes[lane][component] > 0 {
                        bins.insert(lane * 4 + component)
                    }
                }
            }
        }
        return bins
    }

    /// The bins reachable at the shipping footprint: the support of a fully
    /// inked cell. A black source is all ink under the inverted query.
    private static func reachableBins() throws -> Set<Int> {
        let queries = try #require(
            converter(.standard).cellQueryDescriptors(
                try flat(gray: 0, side: 1024), columns: shippingColumns))
        try #require(queries.supportsShapeDescriptor)
        return occupiedBins(queries)
    }

    private static func zeroNormGlyphs(_ set: StandardCharacterSet) -> Set<Int> {
        let lanesPerCharacter = StandardCharacterSet.lanesPerCharacter
        let lanes = set.shapeVectorLanes
        return Set(
            set.characters.indices.filter { index in
                (0..<lanesPerCharacter).allSatisfy {
                    lanes[index * lanesPerCharacter + $0] == .zero
                }
            })
    }

    /// Non-blank glyphs with any mass in `bins`.
    private static func glyphsReaching(_ bins: Set<Int>, in set: StandardCharacterSet)
        -> [Character]
    {
        let lanesPerCharacter = StandardCharacterSet.lanesPerCharacter
        let lanes = set.shapeVectorLanes
        let blank = zeroNormGlyphs(set)
        return set.characters.indices.filter { index in
            !blank.contains(index)
                && bins.contains { lanes[index * lanesPerCharacter + $0 / 4][$0 % 4] > 0 }
        }.map { set.characters[$0] }
    }

    /// The derivation is sound: the shipping footprint is a real 2-pixel-wide
    /// cell (the tone-only fallback does not fire), a fully inked cell reaches
    /// only a handful of the 60 bins, and every query on a real fixture stays
    /// inside that set.
    @Test func realQueriesStayInsideTheSaturatedCellSupport() throws {
        let reachable = try Self.reachableBins()
        #expect(!reachable.isEmpty)
        #expect(reachable.count <= 3, "support collapse lifted: \(reachable.sorted())")

        let queries = try #require(
            Self.converter(.standard).cellQueryDescriptors(
                try Self.vavilovCrater(), columns: Self.shippingColumns))
        #expect(queries.supportsShapeDescriptor)
        let observed = Self.occupiedBins(queries)
        #expect(!observed.isEmpty)
        #expect(
            observed.isSubset(of: reachable),
            "real queries reached \(observed.sorted()) outside \(reachable.sorted())")
    }

    /// ASKI-79 AC#1, cause half: for each built-in set, whether any non-blank
    /// glyph has mass in the reachable bins. The five sets without one are the
    /// five ASKI-79 measured as all-blank; every other set has at least one.
    ///
    /// `standard` is pinned to its three reaching glyphs (ASKI-80): the other 92
    /// are orthogonal to every shipping query.
    @Test func onlyTheBlankCollapsedSetsHaveNoGlyphInTheReachableBins() throws {
        let reachable = try Self.reachableBins()
        for (name, set) in Self.builtIns {
            let reaching = Self.glyphsReaching(reachable, in: set)
            #expect(
                reaching.isEmpty == Self.blankCollapsed.contains(name),
                "\(name): \(reaching.count) non-blank glyphs reach \(reachable.sorted())")
            #expect(Self.zeroNormGlyphs(set).count == 1, "\(name) should hold exactly one blank")
        }
        #expect(Set(Self.glyphsReaching(reachable, in: .standard)) == ["|", "}", "j"])
    }

    /// ASKI-79 KNOWN DEFECT — this test asserts the CURRENT, WRONG behaviour.
    ///
    /// Under logPolar at the shipping footprint, the five blank-collapsed sets
    /// render every cell of a real fixture as their blank glyph. When ASKI-79 is
    /// fixed, flip this expectation to "not every cell is blank" (AC#1: no
    /// recommended pairing yields an all-blank grid on a real fixture) and
    /// rename the test.
    @Test func knownDefectASKI79BlankCollapsedSetsRenderAllBlank() throws {
        let image = try Self.vavilovCrater()
        for (name, set) in Self.builtIns where Self.blankCollapsed.contains(name) {
            let blank = Self.zeroNormGlyphs(set).map { set.characters[$0] }
            let grid = Self.converter(set).convert(image, columns: Self.shippingColumns)
            let cells = grid.cells.flatMap { $0 }
            #expect(!cells.isEmpty)
            #expect(
                cells.allSatisfy { blank.contains($0.character) },
                "\(name) rendered a non-blank cell; ASKI-79 may be fixed — flip this test")
        }
    }

    /// The recommended logPolar pairings that do render today stay non-blank.
    /// `minimal` and `dots` are also recommended (Algorithms.md) and are the
    /// known defect above.
    @Test func recommendedPairingsOutsideTheDefectAreNotAllBlank() throws {
        let image = try Self.vavilovCrater()
        for set in [StandardCharacterSet.standard, .mixed, .braille] {
            let blank = Self.zeroNormGlyphs(set).map { set.characters[$0] }
            let grid = Self.converter(set).convert(image, columns: Self.shippingColumns)
            #expect(grid.cells.flatMap { $0 }.contains { !blank.contains($0.character) })
        }
    }
}
