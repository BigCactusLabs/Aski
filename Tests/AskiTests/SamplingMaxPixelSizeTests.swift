import CoreGraphics
import Testing

@testable import Aski

/// ASKI-105. `ASCIIConverter` and `TileGridConverter` size their sampling
/// lattice with one rule, `samplingMaxPixelSize`. `TileGridConverter` used to
/// cap the longest side at `max(columns, rows) * oversample`, which in a
/// portrait is the height, so the width came out under `columns * oversample`.
/// The ASKI-104 portrait, 975×1280 at 60 columns, prepared 119 px wide at
/// oversample 2 (one source pixel per cell) and 59 px wide at oversample 1,
/// which is an empty grid.
///
/// The library prepares a direct `CGImage` without ImageIO (ASKI-1):
/// `preparedSize` rounds the short side, so the one-pixel ImageIO
/// subsample-floor undershoot that the command-line loader has to retry around
/// (ASKI-104) cannot take a library portrait below the width budget. The
/// sweeps below check that through the real lattice.
@Suite struct SamplingMaxPixelSizeTests {

    // MARK: - Tile portraits

    @Test(arguments: [1, 2, 3, 4])
    func portraitTileCellsAreOversamplePixelsWide(oversample: Int) throws {
        let image = TestImages.horizontalGradient(width: 975, height: 1_280)
        let converter = TileGridConverter(oversample: oversample)
        let prepared = try #require(converter.prepareLattice(image, columns: 60))

        #expect(prepared.cols == 60)
        #expect(prepared.rows == 78)
        #expect(prepared.lattice.cellWidth == oversample)
        #expect(prepared.lattice.cellHeight == oversample)

        // The geometry reproduces the bug: the old cap gives narrower cells.
        let oldCap = max(prepared.cols, prepared.rows) * oversample
        let oldSize = try #require(preparedSize(width: 975, height: 1_280, maxPixelSize: oldCap))
        #expect(oldSize.width / prepared.cols < oversample)
    }

    /// At oversample 1 the old cap prepared the portrait 59 px wide for 60
    /// columns, so the cell width floored to zero and the grid came back empty.
    @Test func portraitTileConversionAtOversampleOneIsNotEmpty() {
        let image = TestImages.horizontalGradient(width: 975, height: 1_280)
        let grid = TileGridConverter(oversample: 1).convert(image, columns: 60)
        #expect(grid.columns == 60)
        #expect(grid.rows == 78)
    }

    /// Real lattices, so the prepared width comes from the resampling path
    /// itself and not from the arithmetic alone.
    @Test(arguments: [ASCIITileShape.square, .wide, .tall])
    func portraitTileLatticesKeepTheOversampleOnBothAxes(shape: ASCIITileShape) {
        var failures: [String] = []
        for (width, height) in [(601, 1_500), (975, 1_280), (1_203, 1_999), (733, 3_001)] {
            let image = TestImages.horizontalGradient(width: width, height: height)
            for columns in [24, 60, 97] {
                for oversample in [1, 2, 3] {
                    let converter = TileGridConverter(samplingShape: shape, oversample: oversample)
                    guard let prepared = converter.prepareLattice(image, columns: columns) else {
                        failures.append("\(width)x\(height) c\(columns) o\(oversample): no lattice")
                        continue
                    }
                    let cell = (prepared.lattice.cellWidth, prepared.lattice.cellHeight)
                    if cell.0 < oversample || cell.1 < oversample {
                        failures.append("\(width)x\(height) c\(columns) o\(oversample): cell \(cell)")
                    }
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(10))")
    }

    // MARK: - The shared rule

    /// A portrait large enough to be downscaled is prepared with every cell at
    /// least `oversample` pixels on both axes, for every sampling shape. A
    /// source at or under the cap is read at its own size; preparation never
    /// upscales, so those cases are skipped.
    @Test(arguments: [ASCIITileShape.square, .wide, .tall], [1, 2, 4])
    func portraitCellsKeepTheOversampleOnBothAxes(shape: ASCIITileShape, oversample: Int) {
        var failures: [String] = []
        var checked = 0
        for width in stride(from: 601, through: 1_400, by: 37) {
            for height in stride(from: 1_500, through: 4_200, by: 211) {
                for columns in [24, 40, 76, 97, 120] {
                    guard
                        let (cols, rows) = gridDimensions(
                            imageWidth: width, imageHeight: height, columns: columns, tileShape: shape),
                        let cap = samplingMaxPixelSize(
                            width: width, height: height, columns: cols, rows: rows, oversample: oversample, tileShape: shape),
                        let size = preparedSize(width: width, height: height, maxPixelSize: cap)
                    else {
                        failures.append("\(width)x\(height) c\(columns): no geometry")
                        continue
                    }
                    guard height > cap else { continue }
                    checked += 1
                    if size.width / cols < oversample || size.height / rows < oversample {
                        failures.append(
                            "\(width)x\(height) c\(columns): cell \(size.width / cols)x\(size.height / rows)")
                    }
                }
            }
        }
        #expect(checked > 500)
        #expect(failures.isEmpty, "\(failures.prefix(10))")
    }

    /// Square images and landscape images sampled with `.square` or `.wide`
    /// keep their previous cap, including panoramas whose row count clamps to 1.
    @Test(arguments: [ASCIITileShape.square, .wide, .tall], [1, 2, 4])
    func squareAndLandscapeKeepTheBaseCap(shape: ASCIITileShape, oversample: Int) {
        var failures: [String] = []
        for width in stride(from: 600, through: 4_200, by: 211) {
            let heights = shape == .tall ? [width] : Array(stride(from: 1, to: width, by: 157)) + [width]
            for height in heights {
                for columns in [24, 40, 76, 97, 120] {
                    guard
                        let (cols, rows) = gridDimensions(
                            imageWidth: width, imageHeight: height, columns: columns, tileShape: shape)
                    else {
                        failures.append("\(width)x\(height) c\(columns): no grid")
                        continue
                    }
                    let cap = samplingMaxPixelSize(
                        width: width, height: height, columns: cols, rows: rows, oversample: oversample, tileShape: shape)
                    if cap != max(cols, rows) * oversample {
                        failures.append("\(width)x\(height) c\(columns): cap \(String(describing: cap))")
                    }
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(10))")
    }

    @Test(arguments: [1, 2, 4])
    func tallLandscapeCellsKeepTheOversampleOnBothAxes(oversample: Int) {
        var failures: [String] = []
        var checked = 0
        for width in stride(from: 600, through: 4_200, by: 149) {
            for height in Array(stride(from: 1, through: 32, by: 3))
                + Array(stride(from: 33, to: width, by: 113)) + [width - 1]
            {
                for columns in [24, 40, 76, 97, 120] {
                    guard
                        let (cols, rows) = gridDimensions(
                            imageWidth: width, imageHeight: height, columns: columns, tileShape: .tall),
                        let cap = samplingMaxPixelSize(
                            width: width, height: height, columns: cols, rows: rows, oversample: oversample, tileShape: .tall),
                        let size = preparedSize(width: width, height: height, maxPixelSize: cap)
                    else {
                        failures.append("\(width)x\(height) c\(columns): no geometry")
                        continue
                    }
                    guard width > cap else { continue }
                    checked += 1
                    if size.width / cols < oversample || size.height / rows < oversample {
                        failures.append(
                            "\(width)x\(height) c\(columns): cell \(size.width / cols)x\(size.height / rows)")
                    }
                }
            }
        }
        #expect(checked > 3_000)
        #expect(failures.isEmpty, "\(failures.prefix(10))")
    }

    @Test func overflowingCapsAreNil() {
        #expect(samplingMaxPixelSize(width: 10, height: 10, columns: Int.max, rows: 1, oversample: 2, tileShape: .square) == nil)
        #expect(samplingMaxPixelSize(width: 1, height: 10, columns: Int.max / 2, rows: 1, oversample: 2, tileShape: .square) == nil)
        #expect(samplingMaxPixelSize(width: 10, height: 1, columns: 1, rows: Int.max / 2, oversample: 2, tileShape: .tall) == nil)
        #expect(samplingMaxPixelSize(width: 10, height: 10, columns: 4, rows: 4, oversample: 0, tileShape: .square) == nil)
    }

    /// Both converters, and the budget each gives the command-line loader
    /// (`preparationMaxPixelSize`), take their cap from the shared rule. The
    /// tile converter clamps an oversample below 1 to 1; `ASCIIConverter`
    /// clamps when it is set.
    @Test(arguments: [(975, 1_280), (1_280, 975), (1_000, 1_000), (300, 2_400)])
    func bothConvertersUseTheSharedRule(width: Int, height: Int) throws {
        let image = TestImages.horizontalGradient(width: width, height: height)
        for shape in [ASCIITileShape.square, .wide, .tall] {
            let (cols, rows) = try #require(
                gridDimensions(imageWidth: width, imageHeight: height, columns: 60, tileShape: shape))
            let shared = samplingMaxPixelSize(width: width, height: height, columns: cols, rows: rows, oversample: 3, tileShape: shape)
            let ascii = ASCIIConverter(
                characterSet: StandardCharacterSet.blocks,
                palette: BuiltInPalette.monochrome,
                tileShape: shape,
                oversample: 3
            )
            let tile = TileGridConverter(samplingShape: shape, oversample: 3)
            #expect(ascii.thumbnailMaxPixelSize(image: image, columns: cols, rows: rows) == shared)
            #expect(ascii.preparationMaxPixelSize(sourceWidth: width, sourceHeight: height, columns: 60) == shared)
            #expect(tile.thumbnailMaxPixelSize(width: width, height: height, columns: cols, rows: rows) == shared)
            #expect(tile.preparationMaxPixelSize(sourceWidth: width, sourceHeight: height, columns: 60) == shared)
            #expect(
                TileGridConverter(samplingShape: shape, oversample: 0)
                    .preparationMaxPixelSize(sourceWidth: width, sourceHeight: height, columns: 60)
                    == samplingMaxPixelSize(width: width, height: height, columns: cols, rows: rows, oversample: 1, tileShape: shape))
        }
    }

    // MARK: - ASCII tall portraits

    /// Before the rule was shared, the ASCII portrait branch replaced the base
    /// cap outright. With the `.tall` sampling shape a portrait has about twice
    /// as many rows as columns × height/width, so that halved the cell height,
    /// and at oversample 1 it floored to zero and the grid came back empty. The
    /// shared rule keeps the larger base cap.
    @Test(arguments: [1, 2, 3])
    func tallPortraitASCIICellsKeepTheOversampleHeight(oversample: Int) throws {
        let image = TestImages.horizontalGradient(width: 975, height: 1_280)
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.blocks,
            palette: BuiltInPalette.monochrome,
            tileShape: .tall,
            oversample: oversample
        )
        let context = try #require(converter.prepareConversion(image, columns: 60, mask: nil)).context
        #expect(context.rows == 157)
        #expect(context.cellHeight == oversample)
        #expect(context.cellWidth >= oversample)
        #expect(converter.convert(image, columns: 60).rows == 157)
    }

    // MARK: - Tall landscapes

    @Test(arguments: [(1_280, 960), (1_601, 16), (1_203, 1_199)], [1, 2, 3])
    func tallLandscapeLatticesKeepTheOversampleOnBothAxes(
        dimensions: (width: Int, height: Int), oversample: Int
    ) throws {
        let image = TestImages.horizontalGradient(width: dimensions.width, height: dimensions.height)
        let ascii = ASCIIConverter(characterSet: StandardCharacterSet.blocks, palette: BuiltInPalette.monochrome, tileShape: .tall, oversample: oversample)
        let tile = TileGridConverter(samplingShape: .tall, oversample: oversample)
        for columns in [24, 60, 97] {
            let cap = try #require(
                ascii.preparationMaxPixelSize(sourceWidth: image.width, sourceHeight: image.height, columns: columns))
            #expect(cap < image.width)
            let context = try #require(ascii.prepareConversion(image, columns: columns, mask: nil)).context
            let prepared = try #require(tile.prepareLattice(image, columns: columns))
            #expect(context.cellWidth >= oversample)
            #expect(context.cellHeight >= oversample)
            #expect(prepared.lattice.cellWidth == context.cellWidth)
            #expect(prepared.lattice.cellHeight == context.cellHeight)
        }
    }

    @Test func tallLandscapeConversionsAtOversampleOneAreNotEmpty() {
        let image = TestImages.horizontalGradient(width: 1_280, height: 960)
        let ascii = ASCIIConverter(characterSet: StandardCharacterSet.blocks, palette: BuiltInPalette.monochrome, tileShape: .tall, oversample: 1)
        let tile = TileGridConverter(samplingShape: .tall, oversample: 1)
        let asciiGrid = ascii.convert(image, columns: 60)
        let tileGrid = tile.convert(image, columns: 60)
        #expect(asciiGrid.columns == 60)
        #expect(asciiGrid.rows == 90)
        #expect(tileGrid.columns == 60)
        #expect(tileGrid.rows == 90)
    }

    @Test func tallLandscapeLatticesDoNotUpscaleSmallSources() throws {
        let image = TestImages.horizontalGradient(width: 8, height: 4)
        let ascii = ASCIIConverter(characterSet: StandardCharacterSet.blocks, palette: BuiltInPalette.monochrome, tileShape: .tall, oversample: 3)
        let tile = TileGridConverter(samplingShape: .tall, oversample: 3)
        let context = try #require(ascii.prepareConversion(image, columns: 4, mask: nil)).context
        let prepared = try #require(tile.prepareLattice(image, columns: 4))
        #expect(context.pixelWidth == image.width)
        #expect(context.pixelHeight == image.height)
        #expect(prepared.lattice.pixelWidth == image.width)
        #expect(prepared.lattice.pixelHeight == image.height)
    }
}
