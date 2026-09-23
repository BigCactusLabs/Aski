import CoreGraphics
import Testing
@testable import Aski

@Suite struct MaskSamplerTests {
    @Test func allWhiteMaskSamplesAsFullCoverage() {
        let image = Self.grayImage(width: 3, height: 2) { _, _ in 1 }
        let coverage = MaskSampler.sample(
            MaskOptions(image: image),
            columns: 3,
            rows: 2
        )

        #expect(coverage == Array(repeating: Float(1), count: 6))
    }

    @Test func allBlackMaskSamplesAsZeroCoverage() {
        let image = Self.grayImage(width: 2, height: 2) { _, _ in 0 }
        let coverage = MaskSampler.sample(
            MaskOptions(image: image),
            columns: 2,
            rows: 2
        )

        #expect(coverage == Array(repeating: Float(0), count: 4))
    }

    @Test func hardEdgesThresholdBeforeInvert() {
        let image = Self.grayImage(width: 4, height: 1) { x, _ in
            [CGFloat(0.0), CGFloat(0.49), CGFloat(0.5), CGFloat(1.0)][x]
        }

        let hard = MaskSampler.sample(
            MaskOptions(image: image, softEdges: false, invert: false),
            columns: 4,
            rows: 1
        )
        let inverted = MaskSampler.sample(
            MaskOptions(image: image, softEdges: false, invert: true),
            columns: 4,
            rows: 1
        )

        #expect(hard == [0, 0, 1, 1])
        #expect(inverted == [1, 1, 0, 0])
    }

    @Test func softEdgesPreserveIntermediateLuminance() {
        let image = Self.grayImage(width: 3, height: 1) { x, _ in
            [CGFloat(0.0), CGFloat(0.5), CGFloat(1.0)][x]
        }
        let coverage =
            MaskSampler.sample(
                MaskOptions(image: image, softEdges: true),
                columns: 3,
                rows: 1
            ) ?? []

        #expect(coverage.count == 3)
        #expect(coverage[0] < 0.05)
        #expect(abs(coverage[1] - 0.5) < 0.02)
        #expect(coverage[2] > 0.95)
    }

    @Test func everySoftEdgeAndInvertCombinationPreservesExpectedCoverage() throws {
        let image = Self.grayImage(width: 4, height: 1) { x, _ in
            [CGFloat(0), CGFloat(0.25), CGFloat(0.5), CGFloat(1)][x]
        }

        for softEdges in [false, true] {
            for invert in [false, true] {
                let coverage = try #require(
                    MaskSampler.sample(
                        MaskOptions(image: image, softEdges: softEdges, invert: invert),
                        columns: 4,
                        rows: 1
                    )
                )
                let expected: [Float]
                switch (softEdges, invert) {
                case (false, false): expected = [0, 0, 1, 1]
                case (false, true): expected = [1, 1, 0, 0]
                case (true, false): expected = [0, 0.25, 0.5, 1]
                case (true, true): expected = [1, 0.75, 0.5, 0]
                }

                #expect(coverage.count == expected.count)
                for (actual, expectedValue) in zip(coverage, expected) {
                    #expect(abs(actual - expectedValue) < 0.02)
                }
            }
        }
    }

    @Test func invalidDimensionsReturnNil() {
        let image = Self.grayImage(width: 1, height: 1) { _, _ in 1 }
        #expect(MaskSampler.sample(MaskOptions(image: image), columns: 0, rows: 1) == nil)
        #expect(MaskSampler.sample(MaskOptions(image: image), columns: 1, rows: 0) == nil)
    }

    private static func grayImage(
        width: Int,
        height: Int,
        valueAt: (Int, Int) -> CGFloat
    ) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        for y in 0..<height {
            for x in 0..<width {
                context.setFillColor(gray: valueAt(x, y), alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return context.makeImage()!
    }
}
