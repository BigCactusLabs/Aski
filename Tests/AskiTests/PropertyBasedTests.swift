import CoreGraphics
import PropertyBased
import simd
import Testing
@testable import Aski

@Suite struct PropertyBasedTests {

    @Test(arguments: [Float(0.1), Float(0.3), Float(0.5), Float(0.7), Float(0.9)])
    func uniformGrayscaleCalibration(gv: Float) {
        let image = Self.solidColor(SIMD3(gv, gv, gv), width: 200, height: 200)
        let grid = DefaultConverter().convert(image, columns: 40)
        let brightnesses = grid.cells.flatMap { $0.map(\.brightness) }
        let mean = brightnesses.reduce(0, +) / Float(brightnesses.count)
        let sourceOKLABL = ColorConversion.linearSRGBToOKLAB(
            SIMD3(
                ColorConversion.sRGBDecode(gv),
                ColorConversion.sRGBDecode(gv),
                ColorConversion.sRGBDecode(gv)
            )
        ).x

        #expect(abs(mean - sourceOKLABL) < 0.15, "gv=\(gv), mean=\(mean), expected~\(sourceOKLABL)")
    }

    @Test func oklabRoundTripInGamut() {
        let step: Float = 0.05
        var violations = 0
        var total = 0
        var r: Float = 0
        while r <= 1.0 {
            var g: Float = 0
            while g <= 1.0 {
                var b: Float = 0
                while b <= 1.0 {
                    total += 1
                    let rgb = SIMD3(r, g, b)
                    let back = ColorConversion.oklabToLinearSRGB(
                        ColorConversion.linearSRGBToOKLAB(rgb)
                    )
                    if simd_length(back - rgb) > 1.0 / 255.0 { violations += 1 }
                    b += step
                }
                g += step
            }
            r += step
        }

        #expect(violations == 0, "\(violations) of \(total) round-trip violations")
    }

    @Test func gamutMapIsStableOnInGamutInputs() {
        for r in stride(from: 0.1, through: 0.9, by: 0.1) {
            for g in stride(from: 0.1, through: 0.9, by: 0.1) {
                for b in stride(from: 0.1, through: 0.9, by: 0.1) {
                    let rgb = SIMD3(Float(r), Float(g), Float(b))
                    let oklab = ColorConversion.linearSRGBToOKLAB(rgb)
                    let mapped = GamutMapping.adaptiveL0ToSRGB(oklab)
                    #expect(simd_length(mapped - rgb) < 0.01, "rgb=\(rgb) mapped=\(mapped)")
                }
            }
        }
    }

    @Test func gridDimensionsAreDeterministic() {
        let image = TestImages.horizontalGradient(width: 1000, height: 500)
        let converter = DefaultConverter()
        let a = converter.convert(image, columns: 80)
        let b = converter.convert(image, columns: 80)

        #expect(a.columns == b.columns)
        #expect(a.rows == b.rows)
    }

    @Test func invalidColumnCountsReturnEmptyGrid() {
        let image = TestImages.horizontalGradient(width: 100, height: 50)
        let converter = DefaultConverter()

        #expect(converter.convert(image, columns: 0).cells.isEmpty)
        #expect(converter.convert(image, columns: -1).cells.isEmpty)
    }

    @Test func srgbTransferRoundTripsRandomLinearValues() async {
        await propertyCheck(count: 250, input: Gen.float(in: 0...1)) { value in
            let encoded = ColorConversion.sRGBEncode(value)
            let decoded = ColorConversion.sRGBDecode(encoded)
            #expect(abs(decoded - value) < 1.0 / 255.0)
        }
    }

    @Test func oklabRoundTripsRandomInGamutRGB() async {
        await propertyCheck(
            count: 250,
            input: Gen.float(in: 0...1), Gen.float(in: 0...1), Gen.float(in: 0...1)
        ) { r, g, b in
            let rgb = SIMD3(r, g, b)
            let back = ColorConversion.oklabToLinearSRGB(
                ColorConversion.linearSRGBToOKLAB(rgb)
            )
            #expect(simd_length(back - rgb) < 1.0 / 255.0)
        }
    }

    @Test(.shrinking) func gamutMappingReturnsFiniteUnitRGB() async {
        await propertyCheck(
            count: 250,
            input: Gen.float(in: -0.5...1.5), Gen.float(in: -1...1), Gen.float(in: -1...1)
        ) { l, a, b in
            let rgb = GamutMapping.adaptiveL0ToSRGB(SIMD3(l, a, b))
            #expect(rgb.x.isFinite && rgb.y.isFinite && rgb.z.isFinite)
            #expect((0...1).contains(rgb.x))
            #expect((0...1).contains(rgb.y))
            #expect((0...1).contains(rgb.z))
        }
    }

    @Test func convertingRandomSolidColorsKeepsCellFieldsBounded() async {
        await propertyCheck(
            count: 50,
            input: Gen.float(in: 0...1), Gen.float(in: 0...1), Gen.float(in: 0...1)
        ) { r, g, b in
            let image = Self.solidColor(SIMD3(r, g, b), width: 120, height: 80)
            let grid = DefaultConverter().convert(image, columns: 24)
            for cell in grid.cells.flatMap({ $0 }) {
                #expect(cell.brightness.isFinite)
                #expect((0...1).contains(cell.alpha))
                #expect(cell.displayColor.x.isFinite && (0...1).contains(cell.displayColor.x))
                #expect(cell.displayColor.y.isFinite && (0...1).contains(cell.displayColor.y))
                #expect(cell.displayColor.z.isFinite && (0...1).contains(cell.displayColor.z))
            }
        }
    }

    @Test func dotMatrixIsDeterministicAcrossRepeatedConversions() {
        let image = TestImages.horizontalGradient(width: 120, height: 60)
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.minimal,
            palette: BuiltInPalette.fullColor,
            algorithm: .dotMatrix,
            options: RenderingOptions(coverage: 0.7)
        )
        let a = converter.convert(image, columns: 24)
        let b = converter.convert(image, columns: 24)

        let aChars = a.cells.flatMap { $0.map(\.character) }
        let bChars = b.cells.flatMap { $0.map(\.character) }
        #expect(
            aChars == bChars,
            """
            DotMatrixKernel produced different output on two identical \
            convert() calls; check that errorBuffer is reset (kernels \
            are re-instantiated per convert()).
            """)
    }

    @Test func randomMaskCoverageValuesStayBounded() async {
        await propertyCheck(
            count: 50,
            input: Gen.int(in: 1...12), Gen.int(in: 1...12), Gen.float(in: 0...1)
        ) { width, height, gray in
            let image = Self.solidGrayMask(value: CGFloat(gray), width: width, height: height)
            let coverage =
                MaskSampler.sample(
                    MaskOptions(image: image),
                    columns: max(1, width / 2),
                    rows: max(1, height / 2)
                ) ?? []
            for value in coverage {
                #expect(value.isFinite)
                #expect((0...1).contains(value))
            }
        }
    }

    @Test func hardMasksOnlyProduceBinaryCoverage() async {
        await propertyCheck(
            count: 50,
            input: Gen.int(in: 1...12), Gen.int(in: 1...12), Gen.float(in: 0...1)
        ) { width, height, gray in
            let image = Self.solidGrayMask(value: CGFloat(gray), width: width, height: height)
            let coverage =
                MaskSampler.sample(
                    MaskOptions(image: image, softEdges: false),
                    columns: width,
                    rows: height
                ) ?? []
            for value in coverage {
                #expect(value == 0 || value == 1)
            }
        }
    }

    @Test func doubleInvertRestoresHardMaskCoverage() async {
        await propertyCheck(
            count: 50,
            input: Gen.int(in: 1...12), Gen.int(in: 1...12), Gen.float(in: 0...1)
        ) { width, height, gray in
            let image = Self.solidGrayMask(value: CGFloat(gray), width: width, height: height)
            let normal =
                MaskSampler.sample(
                    MaskOptions(image: image, softEdges: false, invert: false),
                    columns: width,
                    rows: height
                ) ?? []
            let inverted =
                MaskSampler.sample(
                    MaskOptions(image: image, softEdges: false, invert: true),
                    columns: width,
                    rows: height
                ) ?? []
            let doubleInverted = inverted.map { 1 - $0 }
            #expect(normal == doubleInverted)
        }
    }

    private static func solidGrayMask(value: CGFloat, width: Int, height: Int) -> CGImage {
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
        context.setFillColor(gray: value, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private static func solidColor(_ rgb: SIMD3<Float>, width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        context.setFillColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
