import CoreGraphics
import CoreVideo
import Foundation
import Testing
import VideoToolbox

@testable import Aski

/// ASKI-1. A decoded `CGImage` larger than the conversion budget is resampled
/// straight from its own pixels to the sampling lattice, with no PNG encode and
/// no `CGImageSource` round-trip. These tests pin the geometry of that
/// preparation, its alpha, orientation and color handling, and its fidelity
/// against the exact area average of each lattice pixel's source footprint, the
/// same reference the resampler choice was measured against
/// (`docs/Research/2026-11-10-aski-1-direct-cgimage-preparation.md`).
///
/// Raster tolerances are in 8-bit code values: mean absolute error (MAE) and
/// the 99th-percentile absolute error (p99) against that reference. On the
/// photo-like scene below, at four lattice geometries, this build measures MAE
/// 0.92–1.12 and p99 11–13; Lanczos rings by a few code values at hard edges,
/// which the exact area average does not. The old ImageIO-thumbnail path
/// measured MAE 0.94–1.42 and p99 15–25 on the same lattices. The bounds, MAE
/// below 1.5 and p99 at most 20, sit above both and well below what a wrong
/// path produces: a raster shifted down by one row measures MAE 3.6–4.6 and p99
/// near 90, Display P3 bytes read as sRGB measure MAE 5.6 and p99 63, and a
/// vertically flipped raster measures MAE 35.
@Suite struct TargetSizePreparationTests {

    // MARK: - Prepared size

    /// The longest side lands exactly on the budget and the short side is the
    /// proportional size rounded to the nearest pixel.
    @Test(arguments: [
        (4032, 3024, 152, 152, 114),  // 4:3 landscape photo
        (3024, 4032, 203, 152, 203),  // the same photo in portrait
        (1920, 1080, 160, 160, 90),  // video frame
        (1000, 1000, 160, 160, 160),  // square
        (1000, 333, 100, 100, 33),  // 33.3 rounds down
        (1000, 335, 100, 100, 34),  // 33.5 rounds up
        (10_000, 3, 100, 100, 1),  // short side would round to zero
    ])
    func preparedSizePutsTheLongestSideOnTheBudget(
        width: Int, height: Int, maxPixelSize: Int, expectedWidth: Int, expectedHeight: Int
    ) throws {
        let size = try #require(preparedSize(width: width, height: height, maxPixelSize: maxPixelSize))
        #expect(size.width == expectedWidth)
        #expect(size.height == expectedHeight)
    }

    @Test(arguments: [(100, 50, 160), (160, 80, 160), (1, 1, 1)])
    func preparedSizeNeverUpscales(width: Int, height: Int, maxPixelSize: Int) throws {
        let size = try #require(preparedSize(width: width, height: height, maxPixelSize: maxPixelSize))
        #expect(size.width == width)
        #expect(size.height == height)
    }

    @Test(arguments: [(0, 10, 10), (10, 0, 10), (10, 10, 0), (-1, 10, 10)])
    func preparedSizeRejectsDegenerateInput(width: Int, height: Int, maxPixelSize: Int) {
        #expect(preparedSize(width: width, height: height, maxPixelSize: maxPixelSize) == nil)
    }

    /// A portrait source's `maxPixelSize` is set so its width lands on
    /// `columns * oversample`. Rounding the prepared width, rather than
    /// flooring it as ImageIO did, keeps every cell at least `oversample`
    /// pixels wide, so the log-polar descriptor always has support.
    @Test(arguments: [2, 4])
    func portraitCellsKeepTheOversampleWidth(oversample: Int) {
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.blocks,
            palette: BuiltInPalette.monochrome,
            tileShape: .wide,
            oversample: oversample
        )
        var failures: [String] = []
        for width in stride(from: 601, through: 1_400, by: 37) {
            for height in stride(from: 1_500, through: 4_200, by: 211) where height > width {
                for columns in [24, 40, 76, 97, 120] {
                    guard
                        let (cols, rows) = gridDimensions(
                            imageWidth: width, imageHeight: height, columns: columns, tileShape: .wide),
                        let budget = converter.thumbnailMaxPixelSize(
                            image: Self.blank(width: width, height: height), columns: cols, rows: rows),
                        let size = preparedSize(width: width, height: height, maxPixelSize: budget)
                    else {
                        failures.append("\(width)x\(height) c\(columns): no geometry")
                        continue
                    }
                    if size.width / cols < oversample {
                        failures.append("\(width)x\(height) c\(columns): cell width \(size.width / cols)")
                    }
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(10))")
    }

    // MARK: - Which path runs

    /// AC#1: an oversized source reaches the converter's raster through the
    /// direct resampler, at the lattice size, and nothing else.
    @Test func oversizedSourceIsResampledStraightToTheLattice() throws {
        let image = Self.photoLike(width: 2_400, height: 1_600)
        let converter = VesperPreset.canonical.makeConverter()
        let preparation = try #require(converter.prepareConversion(image, columns: 76, mask: nil))
        let context = preparation.context

        let direct = try #require(
            resampleRGBA8(
                image, width: context.pixelWidth, height: context.pixelHeight,
                targetColorSpace: converter.colorSpace))
        #expect(context.pixels == direct)
        #expect(context.pixelWidth == context.columns * context.cellWidth)
        #expect(context.pixelHeight == context.rows * context.cellHeight)
    }

    /// A source already within the budget keeps the CoreGraphics draw it had
    /// before ASKI-1, byte for byte, so CLI and app inputs that arrive as an
    /// ImageIO thumbnail render exactly as they did.
    @Test(arguments: [(152, 101), (120, 152), (152, 152)])
    func withinBudgetSourceKeepsTheExistingDraw(width: Int, height: Int) throws {
        let image = Self.photoLike(width: width, height: height)
        let converter = VesperPreset.canonical.makeConverter()
        let preparation = try #require(converter.prepareConversion(image, columns: 76, mask: nil))
        let context = preparation.context

        let drawn = try #require(
            readRGBA8(
                image, width: context.pixelWidth, height: context.pixelHeight,
                targetColorSpace: converter.colorSpace))
        #expect(context.pixels == drawn)
    }

    // MARK: - Alpha

    /// Straight (unpremultiplied) alpha is converted to the premultiplied
    /// layout the samplers expect, and the resampled values track the area
    /// average.
    @Test func straightAlphaSourceArrivesPremultiplied() throws {
        let image = Self.straightAlphaRamp(width: 1_600, height: 900)
        let (pixels, width, height) = try Self.lattice(image, maxPixelSize: 160, columns: 40, rows: 12)
        let reference = try Self.areaReference(image, width: width, height: height, colorSpace: .sRGB)

        #expect(Self.premultiplicationViolations(pixels) == 0)
        let error = Self.error(pixels, reference)
        #expect(error.mae < 0.5, "MAE \(error.mae)")
        #expect(error.p99 <= 2, "p99 \(error.p99)")
    }

    /// Lanczos overshoots at a hard alpha edge. Clipping to alpha keeps every
    /// pixel validly premultiplied, and fully transparent regions stay zero.
    @Test func ringingAtAHardAlphaEdgeIsClippedToAlpha() throws {
        let image = Self.opaqueDiscOnClear(width: 2_000, height: 2_000)
        let (pixels, width, height) = try Self.lattice(image, maxPixelSize: 160, columns: 40, rows: 20)

        #expect(Self.premultiplicationViolations(pixels) == 0)
        // The corners are far outside the disc and must be exactly clear.
        for (x, y) in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)] {
            let offset = (y * width + x) * 4
            #expect(Array(pixels[offset..<offset + 4]) == [0, 0, 0, 0], "corner (\(x), \(y))")
        }
        let reference = try Self.areaReference(image, width: width, height: height, colorSpace: .sRGB)
        let error = Self.error(pixels, reference)
        #expect(error.mae < 1.5, "MAE \(error.mae)")
    }

    // MARK: - Orientation

    /// A decoded `CGImage` carries no orientation metadata: its first row is
    /// the top of the picture. Each quadrant must land in the same quadrant of
    /// the lattice on both preparation paths.
    @Test(arguments: [400, 4_000])
    func quadrantsKeepTheirPlace(sourceSide: Int) throws {
        let image = Self.quadrants(side: sourceSide)
        let (pixels, width, height) = try Self.lattice(image, maxPixelSize: 160, columns: 40, rows: 20)

        func color(atX x: Int, y: Int) -> [UInt8] {
            let offset = (y * width + x) * 4
            return Array(pixels[offset..<offset + 3])
        }
        let quarterX = width / 4
        let quarterY = height / 4
        #expect(color(atX: quarterX, y: quarterY) == Self.topLeft)
        #expect(color(atX: width - 1 - quarterX, y: quarterY) == Self.topRight)
        #expect(color(atX: quarterX, y: height - 1 - quarterY) == Self.bottomLeft)
        #expect(color(atX: width - 1 - quarterX, y: height - 1 - quarterY) == Self.bottomRight)
    }

    // MARK: - Tagged and wide-gamut color

    enum TaggedSource: String, CaseIterable, Sendable {
        case sRGBOpaque
        case sRGBNoAlpha
        case displayP3Saturated
        case displayP3Sixteen
        case extendedLinearHalfFloat
        case grayGamma22
        case videoFrameBGRA
    }

    /// Every tagged source is converted to the target color space before it is
    /// resampled, so the result tracks the area average of a CoreGraphics
    /// conversion of the full-size source, including out-of-sRGB Display P3
    /// colors and 16-bit and half-float storage.
    @Test(arguments: TaggedSource.allCases, [RenderColorSpace.sRGB, .displayP3])
    func taggedSourceTracksTheAreaAverage(source: TaggedSource, target: RenderColorSpace) throws {
        let image = try Self.tagged(source, width: 1_920, height: 1_080)
        let (pixels, width, height) = try Self.lattice(
            image, maxPixelSize: 160, columns: 80, rows: 20, colorSpace: target)
        let reference = try Self.areaReference(image, width: width, height: height, colorSpace: target)

        let error = Self.error(pixels, reference)
        #expect(error.mae < 1.5, "\(source) → \(target): MAE \(error.mae)")
        #expect(error.p99 <= 20, "\(source) → \(target): p99 \(error.p99)")
        if source == .grayGamma22 {
            var spread = 0
            for offset in stride(from: 0, to: pixels.count, by: 4) {
                let channels = pixels[offset..<offset + 3].map(Int.init)
                spread = max(spread, channels.max()! - channels.min()!)
            }
            #expect(spread <= 1, "gray source picked up a tint: channel spread \(spread)")
        }
    }

    // MARK: - Conversion output

    enum ConversionCase: String, CaseIterable, Sendable {
        case vesperLandscape
        case vesperPortrait
        case fullColorLandscape
        case fullColorDisplayP3
    }

    /// AC#3: the grid the converter produces from the direct preparation
    /// matches the grid the same converter produces from the exact
    /// area-averaged lattice. The first two cases run the frozen preset.
    ///
    /// This build measures glyph agreement 0.950–0.978, brightness MAE
    /// 0.0024–0.0051 and display-color MAE 0.0020–0.0034 (on a 0–1 scale).
    /// For comparison, a thumbnail from the old ImageIO path converted in the
    /// same way measured agreement 0.956–0.984 and brightness MAE 0.0016–0.0031.
    /// A lattice shifted down by one raster row measured agreement 0.893–0.974
    /// and brightness MAE 0.0060–0.0140. Glyph agreement alone is therefore a
    /// weak check; the raster tests above are what catch a misplaced row. These
    /// bounds cap how far the resampler may move what the user sees.
    @Test(arguments: ConversionCase.allCases)
    func conversionMatchesTheAreaAveragedReference(testCase: ConversionCase) throws {
        let image: CGImage
        let converter: DefaultConverter
        let columns: Int
        switch testCase {
        case .vesperLandscape:
            image = Self.photoLike(width: 2_400, height: 1_600)
            converter = VesperPreset.canonical.makeConverter()
            columns = VesperPreset.canonical.columns
        case .vesperPortrait:
            image = Self.photoLike(width: 1_500, height: 2_250)
            converter = VesperPreset.canonical.makeConverter()
            columns = VesperPreset.canonical.columns
        case .fullColorLandscape:
            image = Self.photoLike(width: 2_400, height: 1_600)
            converter = ASCIIConverter(
                characterSet: .standard, palette: .fullColor, colorSpace: .sRGB, oversample: 4)
            columns = 80
        case .fullColorDisplayP3:
            image = try Self.tagged(.displayP3Saturated, width: 2_400, height: 1_600)
            converter = ASCIIConverter(
                characterSet: .standard, palette: .fullColor, colorSpace: .displayP3, oversample: 4)
            columns = 80
        }

        let preparation = try #require(converter.prepareConversion(image, columns: columns, mask: nil))
        let context = preparation.context
        let reference = try Self.areaReference(
            image, width: context.pixelWidth, height: context.pixelHeight, colorSpace: context.colorSpace)
        let referenceContext = ConversionContext(
            pixels: reference.map { UInt8(max(0, min(255, $0.rounded()))) },
            pixelWidth: context.pixelWidth,
            pixelHeight: context.pixelHeight,
            cellWidth: context.cellWidth,
            cellHeight: context.cellHeight,
            columns: context.columns,
            rows: context.rows,
            palette: context.palette,
            options: context.options,
            colorSpace: context.colorSpace,
            colorSampling: context.colorSampling,
            paletteMatching: context.paletteMatching,
            gamutMapping: context.gamutMapping,
            composition: context.composition
        )
        let referenceRows = ConversionEngine.renderRows(
            preparation: PreparedConversion(
                context: referenceContext,
                sampledCoverage: nil,
                maskFallback: nil,
                maskGroundColor: nil,
                maskUsesHardEdges: false
            ),
            mode: .forcedSerial,
            capture: PlainCellCapture(kernel: LogPolarKernel(glyphBank: converter.glyphBank))
        )
        let produced = converter.convert(image, columns: columns).cells

        try #require(produced.count == referenceRows.count)
        var cells = 0
        var agreeing = 0
        var brightnessError: Float = 0
        var colorError: Float = 0
        for (producedRow, referenceRow) in zip(produced, referenceRows) {
            try #require(producedRow.count == referenceRow.count)
            for (cell, expected) in zip(producedRow, referenceRow) {
                cells += 1
                if cell.character == expected.character { agreeing += 1 }
                brightnessError += abs(cell.brightness - expected.brightness)
                let delta = cell.displayColor - expected.displayColor
                colorError += (abs(delta.x) + abs(delta.y) + abs(delta.z)) / 3
            }
        }
        let agreement = Double(agreeing) / Double(cells)
        let meanBrightnessError = brightnessError / Float(cells)
        let meanColorError = colorError / Float(cells)
        #expect(agreement >= 0.93, "\(testCase): glyph agreement \(agreement)")
        #expect(meanBrightnessError < 0.0075, "\(testCase): brightness MAE \(meanBrightnessError)")
        #expect(meanColorError < 0.0075, "\(testCase): display-color MAE \(meanColorError)")
    }

    // MARK: - Measurement helpers

    /// Runs `samplingLattice` for an explicit grid and returns its raster.
    private static func lattice(
        _ image: CGImage,
        maxPixelSize: Int,
        columns: Int,
        rows: Int,
        colorSpace: RenderColorSpace = .sRGB
    ) throws -> (pixels: [UInt8], width: Int, height: Int) {
        let lattice = try #require(
            samplingLattice(
                image: image, maxPixelSize: maxPixelSize, columns: columns, rows: rows,
                colorSpace: colorSpace))
        return (lattice.pixels, lattice.pixelWidth, lattice.pixelHeight)
    }

    /// The exact area average of each `width × height` output pixel's footprint
    /// in a full-size CoreGraphics conversion of `image` to `colorSpace`, in the
    /// same premultiplied 8-bit encoding the samplers read.
    private static func areaReference(
        _ image: CGImage, width: Int, height: Int, colorSpace: RenderColorSpace
    ) throws -> [Double] {
        let native = try #require(readRGBA8(image, targetColorSpace: colorSpace))
        let sourceWidth = image.width
        let sourceHeight = image.height

        func footprints(source: Int, output: Int) -> [[(index: Int, weight: Double)]] {
            let scale = Double(source) / Double(output)
            return (0..<output).map { index in
                let start = Double(index) * scale
                let end = Double(index + 1) * scale
                var taps: [(index: Int, weight: Double)] = []
                var pixel = Int(start)
                while Double(pixel) < end, pixel < source {
                    let overlap = min(Double(pixel + 1), end) - max(Double(pixel), start)
                    if overlap > 0 { taps.append((pixel, overlap / scale)) }
                    pixel += 1
                }
                return taps
            }
        }
        let columnTaps = footprints(source: sourceWidth, output: width)
        let rowTaps = footprints(source: sourceHeight, output: height)

        var horizontal = [Double](repeating: 0, count: width * sourceHeight * 4)
        native.withUnsafeBufferPointer { input in
            horizontal.withUnsafeMutableBufferPointer { output in
                for y in 0..<sourceHeight {
                    for x in 0..<width {
                        var sum = SIMD4<Double>.zero
                        for tap in columnTaps[x] {
                            let offset = (y * sourceWidth + tap.index) * 4
                            sum +=
                                tap.weight
                                * SIMD4(
                                    Double(input[offset]), Double(input[offset + 1]),
                                    Double(input[offset + 2]), Double(input[offset + 3]))
                        }
                        let offset = (y * width + x) * 4
                        output[offset] = sum.x
                        output[offset + 1] = sum.y
                        output[offset + 2] = sum.z
                        output[offset + 3] = sum.w
                    }
                }
            }
        }

        var result = [Double](repeating: 0, count: width * height * 4)
        horizontal.withUnsafeBufferPointer { input in
            result.withUnsafeMutableBufferPointer { output in
                for y in 0..<height {
                    for x in 0..<width {
                        var sum = SIMD4<Double>.zero
                        for tap in rowTaps[y] {
                            let offset = (tap.index * width + x) * 4
                            sum +=
                                tap.weight
                                * SIMD4(
                                    input[offset], input[offset + 1], input[offset + 2], input[offset + 3])
                        }
                        let offset = (y * width + x) * 4
                        output[offset] = sum.x
                        output[offset + 1] = sum.y
                        output[offset + 2] = sum.z
                        output[offset + 3] = sum.w
                    }
                }
            }
        }
        return result
    }

    private static func error(_ pixels: [UInt8], _ reference: [Double]) -> (mae: Double, p99: Double) {
        precondition(pixels.count == reference.count)
        var deltas = [Double](repeating: 0, count: pixels.count)
        var sum = 0.0
        for index in pixels.indices {
            let delta = abs(Double(pixels[index]) - reference[index])
            deltas[index] = delta
            sum += delta
        }
        deltas.sort()
        let p99 = deltas[min(deltas.count - 1, Int(Double(deltas.count) * 0.99))]
        return (sum / Double(pixels.count), p99)
    }

    /// Pixels whose color exceeds their alpha, which a premultiplied raster
    /// cannot hold.
    private static func premultiplicationViolations(_ pixels: [UInt8]) -> Int {
        var count = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[offset + 3]
            if pixels[offset] > alpha || pixels[offset + 1] > alpha || pixels[offset + 2] > alpha {
                count += 1
            }
        }
        return count
    }

    // MARK: - Sources

    private static let topLeft: [UInt8] = [255, 0, 0]
    private static let topRight: [UInt8] = [0, 255, 0]
    private static let bottomLeft: [UInt8] = [0, 0, 255]
    private static let bottomRight: [UInt8] = [255, 255, 255]

    private static func blank(width: Int, height: Int) -> CGImage {
        context(width: width, height: height, space: CGColorSpace(name: CGColorSpace.sRGB)!).makeImage()!
    }

    private static func context(
        width: Int,
        height: Int,
        space: CGColorSpace,
        bitsPerComponent: Int = 8,
        bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue
    ) -> CGContext {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo)!
    }

    /// Four flat sRGB quadrants, laid out in memory with the first row at the
    /// top of the picture.
    private static func quadrants(side: Int) -> CGImage {
        let half = side / 2
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let color: [UInt8]
                switch (x < half, y < half) {
                case (true, true): color = topLeft
                case (false, true): color = topRight
                case (true, false): color = bottomLeft
                case (false, false): color = bottomRight
                }
                let offset = (y * side + x) * 4
                bytes[offset] = color[0]
                bytes[offset + 1] = color[1]
                bytes[offset + 2] = color[2]
            }
        }
        return CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// Draws the photo-like scene in `context`: a smooth two-axis color field,
    /// soft and hard-edged discs, and bars a few lattice cells wide. Feature
    /// sizes scale with the canvas so they survive the downscale to a 76- to
    /// 80-column lattice as multi-cell structure.
    private static func drawScene(in context: CGContext, width: Int, height: Int, saturated: Bool) {
        let space = context.colorSpace!
        let w = CGFloat(width)
        let h = CGFloat(height)
        let low: CGFloat = saturated ? 0 : 0.15
        let high: CGFloat = saturated ? 1 : 0.85
        let gradient = CGGradient(
            colorsSpace: space,
            colors: [
                CGColor(colorSpace: space, components: [high, low, low, 1])!,
                CGColor(colorSpace: space, components: [low, high * 0.8, low, 1])!,
                CGColor(colorSpace: space, components: [low, low, high, 1])!,
            ] as CFArray,
            locations: [0, 0.5, 1])!
        context.drawLinearGradient(
            gradient, start: .zero, end: CGPoint(x: w, y: h * 0.6), options: [])

        context.setFillColor(CGColor(colorSpace: space, components: [0.05, 0.05, 0.08, 1])!)
        context.fillEllipse(in: CGRect(x: w * 0.12, y: h * 0.18, width: w * 0.3, height: h * 0.45))
        context.setFillColor(CGColor(colorSpace: space, components: [high, high, low, 1])!)
        context.fillEllipse(in: CGRect(x: w * 0.58, y: h * 0.52, width: w * 0.22, height: w * 0.22))

        context.setFillColor(CGColor(colorSpace: space, components: [0.95, 0.95, 0.92, 1])!)
        let bar = w / 38
        for index in 0..<6 {
            let x = w * 0.5 + CGFloat(index) * bar * 2
            context.fill(CGRect(x: x, y: h * 0.08, width: bar, height: h * 0.32))
        }
        context.setStrokeColor(CGColor(colorSpace: space, components: [0.02, 0.02, 0.02, 1])!)
        context.setLineWidth(w / 90)
        context.move(to: CGPoint(x: w * 0.05, y: h * 0.95))
        context.addLine(to: CGPoint(x: w * 0.95, y: h * 0.7))
        context.strokePath()
    }

    static func photoLike(width: Int, height: Int) -> CGImage {
        let context = context(width: width, height: height, space: CGColorSpace(name: CGColorSpace.sRGB)!)
        drawScene(in: context, width: width, height: height, saturated: false)
        return context.makeImage()!
    }

    private static func tagged(_ source: TaggedSource, width: Int, height: Int) throws -> CGImage {
        switch source {
        case .sRGBOpaque:
            return photoLike(width: width, height: height)
        case .sRGBNoAlpha:
            let context = context(
                width: width, height: height, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            drawScene(in: context, width: width, height: height, saturated: false)
            return context.makeImage()!
        case .displayP3Saturated:
            let context = context(
                width: width, height: height, space: CGColorSpace(name: CGColorSpace.displayP3)!)
            drawScene(in: context, width: width, height: height, saturated: true)
            return context.makeImage()!
        case .displayP3Sixteen:
            let context = context(
                width: width, height: height, space: CGColorSpace(name: CGColorSpace.displayP3)!,
                bitsPerComponent: 16,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder16Little.rawValue)
            drawScene(in: context, width: width, height: height, saturated: true)
            return context.makeImage()!
        case .extendedLinearHalfFloat:
            let context = context(
                width: width, height: height,
                space: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                bitsPerComponent: 16,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder16Little.rawValue
                    | CGBitmapInfo.floatComponents.rawValue)
            drawScene(in: context, width: width, height: height, saturated: false)
            return context.makeImage()!
        case .grayGamma22:
            let gray = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!
            let context = context(
                width: width, height: height, space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue)
            let gradient = CGGradient(
                colorsSpace: gray,
                colors: [
                    CGColor(colorSpace: gray, components: [0.05, 1])!,
                    CGColor(colorSpace: gray, components: [0.95, 1])!,
                ] as CFArray,
                locations: [0, 1])!
            context.drawLinearGradient(
                gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
            context.setFillColor(CGColor(colorSpace: gray, components: [0.1, 1])!)
            context.fillEllipse(
                in: CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
            return context.makeImage()!
        case .videoFrameBGRA:
            return try videoFrame(photoLike(width: width, height: height))
        }
    }

    /// Wraps `image` in a 32BGRA `CVPixelBuffer` and hands it back through
    /// `VTCreateCGImageFromCVPixelBuffer`, the way the video decoder produces
    /// its frames.
    private static func videoFrame(_ image: CGImage) throws -> CGImage {
        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferCGImageCompatibilityKey: true]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA,
            attributes as CFDictionary, &buffer)
        let pixelBuffer = try #require(status == kCVReturnSuccess ? buffer : nil)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let drawn = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
        drawn?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        try #require(drawn != nil)

        var frame: CGImage?
        let created = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &frame)
        return try #require(created == noErr ? frame : nil)
    }

    /// A horizontal color ramp whose alpha ramps vertically, stored with
    /// straight (unpremultiplied) alpha.
    private static func straightAlphaRamp(width: Int, height: Int) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let alpha = UInt8((Double(y) / Double(height - 1) * 255).rounded())
            for x in 0..<width {
                let t = Double(x) / Double(width - 1)
                let offset = (y * width + x) * 4
                bytes[offset] = UInt8((t * 255).rounded())
                bytes[offset + 1] = UInt8(((1 - t) * 200).rounded())
                bytes[offset + 2] = 90
                bytes[offset + 3] = alpha
            }
        }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)!
    }

    private static func opaqueDiscOnClear(width: Int, height: Int) -> CGImage {
        let context = context(width: width, height: height, space: CGColorSpace(name: CGColorSpace.sRGB)!)
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setShouldAntialias(false)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fillEllipse(
            in: CGRect(
                x: CGFloat(width) * 0.2, y: CGFloat(height) * 0.2,
                width: CGFloat(width) * 0.6, height: CGFloat(height) * 0.6))
        return context.makeImage()!
    }
}
