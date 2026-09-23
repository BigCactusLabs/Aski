import CoreGraphics
import Testing
@testable import Aski

@Suite("Aski.BrailleRasterizer")
struct BrailleRasterizerTests {
    @Test func zeroCodepointHasNoFilledPixels() {
        let raster = BrailleRasterizer.rasterize(codepoint: 0x2800, size: 32)
        #expect(raster.allSatisfy { $0 == 0 })
    }

    @Test func allDotsCodepointFillsExpectedDotCount() {
        let raster = BrailleRasterizer.rasterize(codepoint: 0x28FF, size: 64)
        let onPixels = raster.filter { $0 > 0.5 }.count
        #expect(onPixels > 64)
    }

    /// `rasterize` returns a `size × size` `[Float]` in TOP-LEFT origin order:
    /// `raster[0..size]` is the visual top row, `raster[(size-1)*size...]` is
    /// the visual bottom row. The expected dot positions below use the same
    /// (column, row) → (x, y) mapping where row 0 is at the top.
    struct ExpectedDot: Sendable {
        let bitIndex: Int
        let visualColumn: Int  // 0 = left,  1 = right
        let visualRow: Int  // 0 = top,   3 = bottom
    }

    /// Per the Unicode Braille standard (see BrailleRasterizer.swift dotPositions):
    static let allBitDots: [ExpectedDot] = [
        ExpectedDot(bitIndex: 0, visualColumn: 0, visualRow: 0),
        ExpectedDot(bitIndex: 1, visualColumn: 0, visualRow: 1),
        ExpectedDot(bitIndex: 2, visualColumn: 0, visualRow: 2),
        ExpectedDot(bitIndex: 3, visualColumn: 1, visualRow: 0),
        ExpectedDot(bitIndex: 4, visualColumn: 1, visualRow: 1),
        ExpectedDot(bitIndex: 5, visualColumn: 1, visualRow: 2),
        ExpectedDot(bitIndex: 6, visualColumn: 0, visualRow: 3),
        ExpectedDot(bitIndex: 7, visualColumn: 1, visualRow: 3),
    ]

    @Test(arguments: BrailleRasterizerTests.allBitDots)
    func eachSingleBitCodepointPlacesDotInExpectedRegion(dot: ExpectedDot) {
        let size = 64
        let codepoint = UInt32(0x2800 | (1 << dot.bitIndex))
        let raster = BrailleRasterizer.rasterize(codepoint: codepoint, size: size)

        var sumX: Double = 0
        var sumY: Double = 0
        var n: Double = 0
        for y in 0..<size {
            for x in 0..<size {
                if raster[y * size + x] > 0.5 {
                    sumX += Double(x)
                    sumY += Double(y)
                    n += 1
                }
            }
        }
        #expect(n > 10, "bit \(dot.bitIndex): too few ON pixels (\(n)) to compute centroid")
        let cx = sumX / n
        let cy = sumY / n

        let cellWidth = Double(size) / 2
        let cellHeight = Double(size) / 4
        let expectedX = cellWidth * (Double(dot.visualColumn) + 0.5)
        let expectedY = cellHeight * (Double(dot.visualRow) + 0.5)

        let tolX = cellWidth * 0.5
        let tolY = cellHeight * 0.5
        #expect(
            abs(cx - expectedX) <= tolX,
            "bit \(dot.bitIndex): centroid x=\(cx), expected ≈\(expectedX)±\(tolX)")
        #expect(
            abs(cy - expectedY) <= tolY,
            "bit \(dot.bitIndex): centroid y=\(cy), expected ≈\(expectedY)±\(tolY)")
    }

    @Test func rasterizeAndDrawAgreeOnSingleBitGlyphs() {
        let size = 64
        let codepoint: UInt32 = 0x28FF
        let viaRasterize = BrailleRasterizer.rasterize(codepoint: codepoint, size: size)

        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size,
            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        BrailleRasterizer.draw(
            codepoint: codepoint,
            foregroundColor: CGColor(gray: 1, alpha: 1),
            in: ctx, rect: CGRect(x: 0, y: 0, width: size, height: size)
        )
        var viaDraw = [Float](repeating: 0, count: size * size)
        let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(size * size) {
            viaDraw[i] = Float(bytes[i]) / 255
        }

        var disagreements = 0
        for i in 0..<(size * size) {
            let a = viaRasterize[i] > 0.5
            let b = viaDraw[i] > 0.5
            if a != b { disagreements += 1 }
        }
        let pixelTotal = size * size
        #expect(
            Double(disagreements) / Double(pixelTotal) < 0.05,
            "rasterize and draw disagree on \(disagreements)/\(pixelTotal) pixels")
    }

    @Test(arguments: Array(0x2800...0x28FF))
    func parameterizedRasterizesEveryCodepointWithoutTrap(codepoint: Int) {
        let raster = BrailleRasterizer.rasterize(codepoint: UInt32(codepoint), size: 32)
        #expect(raster.count == 32 * 32)
        #expect(raster.allSatisfy { (0...1).contains($0) })
    }
}
