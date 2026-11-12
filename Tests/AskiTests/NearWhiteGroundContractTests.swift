import CoreGraphics
import Foundation
import Testing
import simd

@_spi(AskiResearch) @testable import Aski

/// ASKI-84: the owner retained the canonical preset's near-white ground.
/// These contracts pin that decision without changing matcher or snapshot bytes.
@Suite struct NearWhiteGroundContractTests {
    @Test(arguments: [UInt8(243), UInt8(255)])
    func opaqueNearWhiteSourceExposesCanonicalGround(gray: UInt8) throws {
        let preset = VesperPreset.canonical
        let source = try Self.opaqueImage { _ in gray }
        let queries = try #require(
            preset.makeConverter().cellQueryDescriptors(source, columns: preset.columns))

        // A real two-dimensional footprint must reach the matcher. This must
        // not pass by taking the separate one-pixel-axis tone fallback.
        #expect(queries.supportsShapeDescriptor)
        #expect(queries.columns == preset.columns)
        try #require(queries.rows > 0)
        #expect(queries.lanes.allSatisfy { $0 == .zero })
        let cells = queries.grid.cells.flatMap { $0 }
        #expect(cells.count == queries.rows * preset.columns)
        #expect(cells.allSatisfy { $0.character == " " && $0.alpha == 1 && $0.coverage == 1 })

        // Compare to an independent solid fill in the renderer's own color
        // space. This checks visible ground without adding an OS byte golden.
        let rendered = preset.render(source)
        try #require(rendered.width > 1 && rendered.height > 1)
        let colorSpace = try #require(rendered.colorSpace)
        let ground = try #require(
            CGContext(
                data: nil, width: rendered.width, height: rendered.height,
                bitsPerComponent: 8, bytesPerRow: rendered.width * 4,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ground.setFillColor(preset.backgroundColor)
        ground.fill(CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
        let reference = try #require(ground.makeImage())
        #expect(TestImages.deviceRGBBytes(rendered) == TestImages.deviceRGBBytes(reference))
    }

    /// The 242/243 boundary is for opaque, already-sampled equal RGB bytes.
    /// It is not a threshold on arbitrary source pixels: resizing, color
    /// conversion, and premultiplied alpha happen before the shape query.
    @Test(arguments: [(UInt8(242), false), (UInt8(243), true), (UInt8(255), true)])
    func neighboringOpaqueSamplesSeparateInkFromGround(gray: UInt8, isGround: Bool) {
        let converter = VesperPreset.canonical.makeConverter()
        let pixels = Array(repeating: [gray, gray, gray, UInt8(255)], count: 8).flatMap { $0 }
        let context = ConversionContext(
            pixels: pixels, pixelWidth: 2, pixelHeight: 4,
            cellWidth: 2, cellHeight: 4, columns: 1, rows: 1,
            palette: ResolvedPalette(
                content: converter.palette.content, needsHelmlab: converter.paletteMatching.needsHelmlab),
            options: ResolvedRenderingOptions(converter.options),
            colorSpace: converter.colorSpace,
            colorSampling: converter.colorSampling,
            paletteMatching: converter.paletteMatching,
            gamutMapping: converter.gamutMapping,
            composition: converter.composition
        )
        let kernel = LogPolarKernel(glyphBank: converter.glyphBank)
        let cell = CellCoord(column: 0, row: 0)
        let lanes = kernel.researchQueryShapeVector(cell: cell, in: context)
        let stats = context.cellStats(at: cell)
        let character = kernel.score(cell: cell, stats: stats, in: context)

        #expect(context.cellSupportsShapeDescriptor)
        #expect(stats.alpha == 1)
        #expect(lanes.allSatisfy({ $0 == .zero }) == isGround)
        #expect((character == " ") == isGround)
    }

    /// A diagnostic ramp through the near-white transition, sampled through
    /// the real converter. The exact source-column boundary is deliberately
    /// not pinned to a pre-resize luma value. Visual cliff assessment on the
    /// occupancy fixtures remains a separate native research check.
    @Test func gradientIntoWhiteContainsBothInkAndContiguousGround() throws {
        let preset = VesperPreset.canonical
        let source = try Self.opaqueImage { x in UInt8(224 + 31 * x / 151) }
        let queries = try #require(
            preset.makeConverter().cellQueryDescriptors(source, columns: preset.columns))
        try #require(queries.supportsShapeDescriptor && queries.rows > 0)
        let row = queries.rows / 2
        var groundColumns: [Int] = []
        var inkColumns: [Int] = []

        for column in 0..<queries.columns {
            let character = queries.grid.cells[row][column].character
            if queries.lanes(row: row, column: column).allSatisfy({ $0 == .zero }) {
                #expect(character == " ")
                groundColumns.append(column)
            } else if character != " " {
                inkColumns.append(column)
            }
        }

        let firstGround = try #require(groundColumns.first)
        let lastInk = try #require(inkColumns.last)
        #expect(lastInk < firstGround)
        #expect(groundColumns == Array(firstGround..<queries.columns))
    }

    /// Named Display P3 matches the canonical conversion space. All pixels are
    /// opaque, so the shape-query test never confuses premultiplication with
    /// near-white source color. The fixed 152-pixel width fits the 76-column
    /// preset's thumbnail budget without a source-image downscale.
    private static func opaqueImage(sample: (Int) -> UInt8) throws -> CGImage {
        let width = 152
        let height = 152
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * height * 4)
        for _ in 0..<height {
            for x in 0..<width {
                let value = sample(x)
                pixels.append(contentsOf: [value, value, value, 255])
            }
        }
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        return try #require(
            CGImage(
                width: width, height: height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent))
    }
}
