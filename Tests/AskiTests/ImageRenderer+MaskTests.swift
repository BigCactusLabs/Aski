import CoreGraphics
import Testing
@testable import Aski

@Suite struct ImageRendererMaskTests {
    @Test func effectiveNoGroundIsByteIdenticalForEveryFallback() {
        let source = TestImages.horizontalGradient(width: 5, height: 3)
        let fallbacks: [MaskFallback] = [
            .transparent,
            .solid(CGColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 0.8)),
            .originalImage(source, sizing: .fill),
            .character("#", color: CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 0.7)),
        ]
        let ineffectiveGrounds: [CGColor] = [
            CGColor(red: 1, green: 0, blue: 1, alpha: 0),
            CGColor(red: 1, green: 0, blue: 1, alpha: .nan),
        ]
        let cells = [
            [
                ASCIICell(character: "A", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 1, coverage: 0.35),
                ASCIICell(character: "B", displayColor: SIMD3<Float>(0, 1, 1), alpha: 0.8, brightness: 0.7, coverage: 0.8),
            ]
        ]
        let background = CGColor(red: 0.02, green: 0.03, blue: 0.04, alpha: 1)

        for fallback in fallbacks {
            let legacy = ASCIIGrid(cells: cells, colorSpace: .sRGB, maskFallback: fallback)
                .renderImage(font: .system(size: 18), backgroundColor: background, scale: 2)
            let legacyBytes = TestImages.deviceRGBBytes(legacy)

            for ground in ineffectiveGrounds {
                let rendered = ASCIIGrid(
                    cells: cells,
                    colorSpace: .sRGB,
                    maskFallback: fallback,
                    maskGroundColor: ground
                ).renderImage(font: .system(size: 18), backgroundColor: background, scale: 2)
                #expect(TestImages.deviceRGBBytes(rendered) == legacyBytes)
            }
        }
    }

    @Test func allWhiteMaskPaintsOpaqueGroundBehindEmptyGlyph() {
        let grid = Self.groundGrid(character: " ", coverage: 1)
        let image = grid.renderImage(
            font: .system(size: 20),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )

        let sample = Self.rgbaPixels(image)[0]
        #expect(sample.r > 240)
        #expect(sample.r > sample.g * 4)
        #expect(sample.r > sample.b * 4)
    }

    @Test func fractionalCoverageInterpolatesCompletedBranchesOnce() {
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let render: (Float) -> CGImage = { coverage in
            Self.groundGrid(character: "█", coverage: coverage).renderImage(
                font: .system(size: 24),
                backgroundColor: background,
                scale: 1
            )
        }
        let inactive = Self.rgbaPixels(render(0))
        let half = Self.rgbaPixels(render(0.5))
        let active = Self.rgbaPixels(render(1))

        let strongestGlyphPixel = active.indices.max { active[$0].g < active[$1].g }!
        #expect(active[strongestGlyphPixel].g > 200)
        #expect(Self.isBetween(half[strongestGlyphPixel].r, inactive[strongestGlyphPixel].r, active[strongestGlyphPixel].r))
        #expect(Self.isBetween(half[strongestGlyphPixel].g, inactive[strongestGlyphPixel].g, active[strongestGlyphPixel].g))
        #expect(Self.isBetween(half[strongestGlyphPixel].b, inactive[strongestGlyphPixel].b, active[strongestGlyphPixel].b))
        #expect(half[strongestGlyphPixel].g > 80)
    }

    @Test func partialAlphaGroundCompositesOverCanvasAndPreservesSourceAspect() {
        let grid = ASCIIGrid(
            cells: [[ASCIICell(character: " ", displayColor: .zero, alpha: 1, brightness: 0, coverage: 1)]],
            colorSpace: .sRGB,
            maskFallback: .transparent,
            maskGroundColor: CGColor(red: 1, green: 0, blue: 0, alpha: 0.5)
        )
        let background = CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        let regular = grid.renderImage(font: .system(size: 20), backgroundColor: background, scale: 1)
        let preserved = grid.renderImage(
            font: .system(size: 20),
            backgroundColor: background,
            scale: 1,
            preserveSourceAspect: true
        )

        let sample = Self.rgbaPixels(regular)[0]
        #expect(sample.r > 100)
        #expect(sample.b > 100)
        #expect(preserved.width == regular.width)
        #expect(preserved.height > regular.height)
    }

    @Test func allWhiteCoverageIsByteIdenticalToUnmaskedRender() {
        let cell = ASCIICell(character: "█", displayColor: SIMD3<Float>(1, 0, 0), alpha: 1, brightness: 1)
        let unmasked = ASCIIGrid(cells: [[cell]], colorSpace: .sRGB)
        let masked = ASCIIGrid(
            cells: [[ASCIICell(character: "█", displayColor: SIMD3<Float>(1, 0, 0), alpha: 1, brightness: 1, coverage: 1)]],
            colorSpace: .sRGB,
            maskFallback: .solid(CGColor(red: 0, green: 0, blue: 1, alpha: 1)),
            maskUsesHardEdges: false
        )
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

        let a = unmasked.renderImage(font: .system(size: 20), backgroundColor: background, scale: 1)
        let b = masked.renderImage(font: .system(size: 20), backgroundColor: background, scale: 1)

        #expect(Self.bytes(a) == Self.bytes(b))
    }

    @Test func fallbackPaintsBehindHalfCoveredCells() {
        let grid = ASCIIGrid(
            cells: [
                [
                    ASCIICell(
                        character: "█",
                        displayColor: SIMD3<Float>(1, 0, 0),
                        alpha: 1,
                        brightness: 1,
                        coverage: 0.5
                    )
                ]
            ],
            colorSpace: .sRGB,
            maskFallback: .solid(CGColor(red: 0, green: 0, blue: 1, alpha: 1)),
            maskUsesHardEdges: false
        )

        let image = grid.renderImage(
            font: .system(size: 24),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )
        let pixels = Self.rgbaPixels(image)
        let sample = pixels.max { lhs, rhs in
            Int(lhs.r) + Int(lhs.b) < Int(rhs.r) + Int(rhs.b)
        }!

        #expect(sample.r > 80)
        #expect(sample.b > 40)
        #expect(sample.r > sample.b)
    }

    @Test func zeroCoverageWithSolidFallbackShowsFallbackNotCell() {
        let grid = ASCIIGrid(
            cells: [
                [
                    ASCIICell(
                        character: "█",
                        displayColor: SIMD3<Float>(1, 0, 0),
                        alpha: 1,
                        brightness: 1,
                        coverage: 0
                    )
                ]
            ],
            colorSpace: .sRGB,
            maskFallback: .solid(CGColor(red: 0, green: 0, blue: 1, alpha: 1)),
            maskUsesHardEdges: true
        )

        let image = grid.renderImage(
            font: .system(size: 24),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )
        let pixels = Self.rgbaPixels(image)
        #expect(pixels.contains { $0.b > 200 && $0.r < 50 })
    }

    private static func bytes(_ image: CGImage) -> [UInt8] {
        rgbaPixels(image).flatMap { [$0.r, $0.g, $0.b, $0.a] }
    }

    private static func groundGrid(character: Character, coverage: Float) -> ASCIIGrid {
        ASCIIGrid(
            cells: [
                [
                    ASCIICell(
                        character: character,
                        displayColor: SIMD3<Float>(0, 1, 0),
                        alpha: 1,
                        brightness: 1,
                        coverage: coverage
                    )
                ]
            ],
            colorSpace: .sRGB,
            maskFallback: .solid(CGColor(red: 0, green: 0, blue: 1, alpha: 1)),
            maskGroundColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        )
    }

    private static func isBetween(_ value: UInt8, _ lhs: UInt8, _ rhs: UInt8) -> Bool {
        let lower = min(lhs, rhs)
        let upper = max(lhs, rhs)
        return value >= lower && value <= upper
    }

    private static func rgbaPixels(_ image: CGImage) -> [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &bytes,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 0, to: bytes.count, by: 4).map { index in
            (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
        }
    }
}
