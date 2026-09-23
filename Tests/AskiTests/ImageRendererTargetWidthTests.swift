import CoreGraphics
import Testing
@_spi(AskiResearch) @testable import Aski

@Suite(.serialized) struct ImageRendererTargetWidthTests {
    @Test func everyRequestedWidthIsExactForBothArmsAndGridFixtures() {
        let font = ASCIIFont.courierPrime(size: 10)
        let grids = [Self.makeGrid(), Self.make80ColumnGrid()]

        for grid in grids {
            for targetPixelWidth in Self.targetPixelWidths {
                do {
                    let direct = grid.renderImage(
                        font: font,
                        backgroundColor: Self.background,
                        targetPixelWidth: targetPixelWidth
                    )
                    let supersampled = grid.renderImage(
                        font: font,
                        backgroundColor: Self.background,
                        targetPixelWidth: targetPixelWidth,
                        resample: .supersample(factor: 2)
                    )

                    #expect(direct.width == targetPixelWidth)
                    #expect(supersampled.width == targetPixelWidth)
                    #expect(direct.height > 0)
                    #expect(supersampled.height == direct.height)
                }
            }
        }
    }

    @Test func publicTargetWidthRouteMatchesSupersampleFourAndDiffersFromDirect() {
        let grid = Self.make80ColumnGrid()
        let font = ASCIIFont.courierPrime(size: 10)
        let publicImage = grid.renderImage(
            font: font,
            backgroundColor: Self.background,
            targetPixelWidth: 243
        )
        let supersampled = grid.renderImage(
            font: font,
            backgroundColor: Self.background,
            targetPixelWidth: 243,
            resample: .supersample(factor: 4)
        )
        let direct = grid.renderImage(
            font: font,
            backgroundColor: Self.background,
            targetPixelWidth: 243,
            resample: .direct
        )

        #expect(publicImage.width == supersampled.width)
        #expect(publicImage.height == supersampled.height)
        #expect(publicImage.width == direct.width)
        #expect(publicImage.height == direct.height)
        #expect(TestImages.deviceRGBBytes(publicImage) == TestImages.deviceRGBBytes(supersampled))
        #expect(TestImages.deviceRGBBytes(publicImage) != TestImages.deviceRGBBytes(direct))
    }

    @Test func nonMultipleWidthsUseTheIndependentlyDerivedGridHeight() {
        let grid = Self.makeGrid()
        let font = ASCIIFont.courierPrime(size: 10)

        for targetPixelWidth in Self.nonMultipleTargetPixelWidths {
            let image = grid.renderImage(
                font: font,
                backgroundColor: Self.background,
                targetPixelWidth: targetPixelWidth
            )
            let expectedHeight = Self.expectedPixelHeight(
                rows: grid.rows,
                columns: grid.columns,
                font: font,
                targetPixelWidth: targetPixelWidth
            )

            #expect(image.width == targetPixelWidth)
            #expect(image.height == expectedHeight)
        }
    }

    @Test func directArmWithoutSubpixelPositioningMatchesExactScaleGeometry() {
        // pointSize 10 × glyph-width ratio 0.6 gives a 6-point cell; 6 columns
        // at scale 2 therefore land at exactly 72 pixels with no ceil slack.
        let grid = Self.makeGrid()
        let font = ASCIIFont.courierPrime(size: 10)
        let scaleImage = grid.renderImage(font: font, backgroundColor: Self.background, scale: 2)
        let withoutSubpixelPositioning = grid.renderTargetWidthImage(
            font: font,
            backgroundColor: Self.background,
            targetPixelWidth: 72,
            preserveSourceAspect: false,
            resample: .direct,
            subpixelPositioning: false
        )
        let withSubpixelPositioning = grid.renderTargetWidthImage(
            font: font,
            backgroundColor: Self.background,
            targetPixelWidth: 72,
            preserveSourceAspect: false,
            resample: .direct,
            subpixelPositioning: true
        )

        #expect(TestImages.deviceRGBBytes(withoutSubpixelPositioning) == TestImages.deviceRGBBytes(scaleImage))
        #expect(withSubpixelPositioning.width == scaleImage.width)
        #expect(withSubpixelPositioning.height == scaleImage.height)
    }

    @Test func supersampleArmsPreserveAnOpaqueUniformBackground() {
        let background = CGColor(red: 0.12, green: 0.34, blue: 0.56, alpha: 1)
        let expectedBackground = Self.sRGBBytes(for: background)
        let space = ASCIICell(character: " ", displayColor: .zero, alpha: 1, brightness: 0)
        let grid = ASCIIGrid(cells: Array(repeating: Array(repeating: space, count: 6), count: 3), colorSpace: .sRGB)

        for factor in [2, 4] {
            let image = grid.renderImage(
                font: .courierPrime(size: 10),
                backgroundColor: background,
                targetPixelWidth: 97,
                resample: .supersample(factor: factor)
            )

            #expect(image.width == 97)
            #expect(image.height > 0)
            let imageIsBackground = Self.isUniformBackground(
                TestImages.deviceRGBBytes(image),
                expected: expectedBackground
            )
            #expect(imageIsBackground)
        }
    }

    @Test func supersampledTargetWidthPreservesTheGridColorSpace() {
        let cell = ASCIICell(
            character: "#",
            displayColor: SIMD3(0.9, 0.2, 0.1),
            alpha: 1,
            brightness: 0.5
        )
        let grid = ASCIIGrid(
            cells: Array(repeating: Array(repeating: cell, count: 6), count: 3),
            colorSpace: .displayP3
        )
        let direct = grid.renderImage(
            font: .courierPrime(size: 10),
            backgroundColor: Self.background,
            targetPixelWidth: 97
        )
        let supersampled = grid.renderImage(
            font: .courierPrime(size: 10),
            backgroundColor: Self.background,
            targetPixelWidth: 97,
            resample: .supersample(factor: 4)
        )

        #expect(direct.colorSpace?.name == CGColorSpace.displayP3)
        #expect(supersampled.colorSpace?.name == direct.colorSpace?.name)
    }

    @Test func invalidTargetWidthInputsProduceTheExistingOnePixelFallback() {
        let grid = Self.makeGrid()
        let font = ASCIIFont.courierPrime(size: 10)

        for targetPixelWidth in [0, -5, RenderPixelBounds.maxPixelExtent + 1] {
            let image = grid.renderImage(
                font: font,
                backgroundColor: Self.background,
                targetPixelWidth: targetPixelWidth
            )
            #expect(image.width == 1)
            #expect(image.height == 1)
        }

        let invalidFactor = grid.renderImage(
            font: font,
            backgroundColor: Self.background,
            targetPixelWidth: 97,
            resample: .supersample(factor: 1)
        )
        #expect(invalidFactor.width == 1)
        #expect(invalidFactor.height == 1)

        let oversizedSupersample = grid.renderImage(
            font: font,
            backgroundColor: Self.background,
            targetPixelWidth: RenderPixelBounds.maxPixelExtent,
            resample: .supersample(factor: 2)
        )
        #expect(oversizedSupersample.width == 1)
        #expect(oversizedSupersample.height == 1)

        let emptyGrid = ASCIIGrid(cells: [], colorSpace: .sRGB)
        let emptyImage = emptyGrid.renderImage(
            font: font,
            backgroundColor: Self.background,
            targetPixelWidth: 97
        )
        #expect(emptyImage.width == 1)
        #expect(emptyImage.height == 1)
    }

    @Test func targetWidthUsesTheMaskGroundBranchAtDerivedScale() {
        let grid = ASCIIGrid(
            cells: [[ASCIICell(character: "█", displayColor: SIMD3(0, 1, 0), alpha: 1, brightness: 1, coverage: 0.5)]],
            colorSpace: .sRGB,
            maskFallback: .solid(CGColor(red: 0, green: 0, blue: 1, alpha: 1)),
            maskGroundColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        )
        let font = ASCIIFont.courierPrime(size: 10)
        let scaleImage = grid.renderImage(font: font, backgroundColor: Self.background, scale: 2)
        let targetImage = grid.renderTargetWidthImage(
            font: font,
            backgroundColor: Self.background,
            targetPixelWidth: 12,
            preserveSourceAspect: false,
            resample: .direct,
            subpixelPositioning: false
        )

        #expect(targetImage.width == scaleImage.width)
        #expect(targetImage.height == scaleImage.height)
        #expect(TestImages.deviceRGBBytes(targetImage) == TestImages.deviceRGBBytes(scaleImage))
    }

    @Test func publicTargetWidthBoundIsAQuarterOfTheRawExtentOnBothAxes() {
        #expect(ASCIIGrid.maxTargetPixelWidth == RenderPixelBounds.maxPixelExtent / 4)
        #expect(TargetWidthResample.supersample(factor: 4).maxPixelExtent == ASCIIGrid.maxTargetPixelWidth)
        #expect(TargetWidthResample.direct.maxPixelExtent == RenderPixelBounds.maxPixelExtent)
        #expect(TargetWidthResample.supersample(factor: 1).maxPixelExtent == nil)

        let font = ASCIIFont.courierPrime(size: 10)
        let width = ASCIIGrid.maxTargetPixelWidth + 1

        // One past the public bound is still a legal direct-arm geometry...
        #expect(
            ASCIIGrid.renderGeometry(
                columns: 6, rows: 1, font: font, targetPixelWidth: width, preserveSourceAspect: false
            ) != nil
        )
        // ...but not under the 4× ceiling, so the public path never reaches the
        // supersample allocation guard: it fails at geometry, like the scale path.
        #expect(
            ASCIIGrid.renderGeometry(
                columns: 6, rows: 1, font: font, targetPixelWidth: width, preserveSourceAspect: false,
                maxPixelExtent: ASCIIGrid.maxTargetPixelWidth
            ) == nil
        )
        // The derived height is bound the same way as the width.
        #expect(
            ASCIIGrid.renderGeometry(
                columns: 6, rows: 40, font: font, targetPixelWidth: 60, preserveSourceAspect: false,
                maxPixelExtent: 100
            ) == nil
        )
        #expect(
            ASCIIGrid.renderGeometry(
                columns: 6, rows: 4, font: font, targetPixelWidth: 60, preserveSourceAspect: false,
                maxPixelExtent: 100
            ) != nil
        )

        let image = Self.makeGrid().renderImage(font: font, backgroundColor: Self.background, targetPixelWidth: width)
        #expect(image.width == 1)
        #expect(image.height == 1)
    }

    @Test func linearCompositionSupersampleAveragesWithoutTheSRGBTransfer() throws {
        // A 2×2 block of two black and two white opaque pixels. Averaged as
        // linear light the mean is 0.5 → byte 128. Decoding the bytes as sRGB
        // first and re-encoding the mean gives sRGBEncode(0.5) → byte 188.
        let bytes: [UInt8] = [0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 0, 255]
        func makeSource(_ space: CGColorSpace) throws -> CGImage {
            var pixels = bytes
            let context = try #require(
                pixels.withUnsafeMutableBytes { buffer in
                    CGContext(
                        data: buffer.baseAddress,
                        width: 2,
                        height: 2,
                        bitsPerComponent: 8,
                        bytesPerRow: 8,
                        space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    )
                }
            )
            return try #require(context.makeImage())
        }
        func reducedByte(_ image: CGImage, space: CGColorSpace, sourceIsLinear: Bool) throws -> UInt8 {
            let reduced = try #require(
                ASCIIGrid.downsampleTargetWidthImage(
                    image, factor: 2, outputWidth: 1, outputHeight: 1, colorSpace: space,
                    sourceIsLinear: sourceIsLinear
                )
            )
            let data = try #require(reduced.dataProvider?.data)
            let pointer = try #require(CFDataGetBytePtr(data))
            #expect(pointer[3] == 255)
            #expect(pointer[0] == pointer[1] && pointer[1] == pointer[2])
            return pointer[0]
        }

        let srgb = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let linear = try #require(CGColorSpace(name: CGColorSpace.linearSRGB))
        let encodedMean = UInt8((ColorConversion.sRGBEncode(0.5) * 255).rounded())
        #expect(encodedMean == 188)

        #expect(try reducedByte(makeSource(srgb), space: srgb, sourceIsLinear: false) == encodedMean)
        #expect(try reducedByte(makeSource(linear), space: linear, sourceIsLinear: true) == 128)

        // A linear-composition grid keeps its linear tag through the public path.
        let cell = ASCIICell(character: "#", displayColor: SIMD3(0.5, 0.5, 0.5), alpha: 1, brightness: 0.5)
        let grid = ASCIIGrid(
            cells: Array(repeating: Array(repeating: cell, count: 6), count: 2),
            colorSpace: .sRGB,
            composition: .extendedLinearPerGamut
        )
        let publicImage = grid.renderImage(
            font: .courierPrime(size: 10), backgroundColor: Self.background, targetPixelWidth: 97
        )
        #expect(publicImage.width == 97)
        #expect(publicImage.colorSpace?.name == CGColorSpace.linearSRGB)
    }

    private static let background = CGColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
    private static let targetPixelWidths = [1, 7, 97, 243, 600, 960, 1166, 2332]
    private static let nonMultipleTargetPixelWidths = [1, 7, 97, 243, 1166, 2332]

    private static func expectedPixelHeight(
        rows: Int,
        columns: Int,
        font: ASCIIFont,
        targetPixelWidth: Int
    ) -> Int {
        let glyphWidth = font.pointSize * 0.6
        let glyphHeight = font.pointSize * 1.2
        let scale = CGFloat(targetPixelWidth) / (CGFloat(columns) * glyphWidth)
        return Int(ceil(CGFloat(rows) * glyphHeight * scale))
    }

    private static func sRGBBytes(for color: CGColor) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return bytes
    }

    private static func isUniformBackground(_ bytes: [UInt8], expected: [UInt8]) -> Bool {
        guard expected.count == 4 else { return false }
        guard bytes.count.isMultiple(of: expected.count) else { return false }

        for offset in stride(from: 0, to: bytes.count, by: expected.count) {
            for channel in expected.indices where abs(Int(bytes[offset + channel]) - Int(expected[channel])) > 1 {
                return false
            }
        }
        return true
    }

    private static func makeGrid() -> ASCIIGrid {
        let glyphs: [[Character]] = [
            ["#", "@", "A", ".", "/", "M"],
            ["\u{283F}", "\u{28FF}", "\u{2801}", "W", "i", "="],
            ["g", "0", "x", "|", "%", "\u{28A5}"],
        ]
        var cells: [[ASCIICell]] = []
        for (rowIndex, row) in glyphs.enumerated() {
            var cellRow: [ASCIICell] = []
            for (columnIndex, character) in row.enumerated() {
                let t = Float(rowIndex * row.count + columnIndex) / Float(glyphs.count * row.count)
                cellRow.append(
                    ASCIICell(
                        character: character,
                        displayColor: SIMD3(t, 1 - t, Float(columnIndex % 3) / 2),
                        alpha: (rowIndex + columnIndex).isMultiple(of: 2) ? 1 : 0.6,
                        brightness: t
                    )
                )
            }
            cells.append(cellRow)
        }
        return ASCIIGrid(cells: cells, colorSpace: .sRGB)
    }

    private static func make80ColumnGrid() -> ASCIIGrid {
        let rows = (0..<3).map { rowIndex in
            (0..<80).map { columnIndex in
                let t = Float(rowIndex * 80 + columnIndex) / Float(3 * 80)
                return ASCIICell(
                    character: columnIndex.isMultiple(of: 3) ? "#" : "W",
                    displayColor: SIMD3(t, 1 - t, 0.5),
                    alpha: 1,
                    brightness: t
                )
            }
        }
        return ASCIIGrid(cells: rows, colorSpace: .sRGB)
    }
}
