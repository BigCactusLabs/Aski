import CoreGraphics
import Testing
@testable import Aski

@Suite struct ConverterTests {
    @Test func convertHorizontalGradientProducesBrightnessRamp() {
        let image = TestImages.horizontalGradient(width: 400, height: 100)
        let converter = DefaultConverter()
        let grid = converter.convert(image, columns: 40)

        #expect(grid.columns == 40)
        #expect(grid.rows > 0)

        let firstColumnIndex = 0
        let lastColumnIndex = grid.columns - 1
        let firstColumnBrightness = grid.cells.map { $0[firstColumnIndex].brightness }
        let lastColumnBrightness = grid.cells.map { $0[lastColumnIndex].brightness }
        let firstColumnMean = firstColumnBrightness.reduce(0, +) / Float(grid.rows)
        let lastColumnMean = lastColumnBrightness.reduce(0, +) / Float(grid.rows)
        #expect(firstColumnMean < lastColumnMean)
    }

    @Test func defaultConverterInitializes() {
        let converter = DefaultConverter()
        #expect(converter.algorithm == .logPolar)
        #expect(converter.tileShape == .wide)
        #expect(converter.tileShape.sourceCellHeightOverWidth == 2.2)
        #expect(converter.colorSampling == .linearLightAverage)
        #expect(converter.paletteMatching == .oklabEuclidean)
        #expect(converter.gamutMapping == .rayTrace)
    }

    @Test func explicitDefaultPoliciesMatchDefaultConverterOutput() {
        let image = TestImages.horizontalGradient(width: 160, height: 80)
        let implicit = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.fullColor
        ).convert(image, columns: 24)
        let explicit = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.fullColor,
            colorSampling: .linearLightAverage,
            paletteMatching: .oklabEuclidean,
            gamutMapping: .rayTrace
        ).convert(image, columns: 24)

        #expect(explicit.cells == implicit.cells)
        #expect(explicit.colorSpace == implicit.colorSpace)
    }

    @Test func adaptiveL0LegacyPolicyStillConverts() {
        let image = TestImages.horizontalGradient(width: 120, height: 80)
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.fullColor,
            gamutMapping: .adaptiveL0
        )
        let grid = converter.convert(image, columns: 16)

        #expect(grid.columns == 16)
        #expect(grid.rows > 0)
        for cell in grid.cells.flatMap({ $0 }) {
            #expect(cell.displayColor.x >= 0 && cell.displayColor.x <= 1)
            #expect(cell.displayColor.y >= 0 && cell.displayColor.y <= 1)
            #expect(cell.displayColor.z >= 0 && cell.displayColor.z <= 1)
        }
    }

    @Test func convertTinyCellsDoesNotTrapInShapeDescriptor() {
        let image = TestImages.horizontalGradient(width: 20, height: 39)
        let grid = DefaultConverter().convert(image, columns: 20)

        #expect(grid.columns == 20)
        #expect(grid.rows > 0)
    }

    @Test func eachAlgorithmProducesValidOutput() {
        let image = TestImages.horizontalGradient(width: 200, height: 100)
        let allCharsets: [StandardCharacterSet] = [
            .standard, .minimal, .blocks,
            .dots, .lines, .diagonal, .cross, .diamond, .mixed, .braille,
        ]
        for algorithm in [ASCIIAlgorithm.logPolar, .dotMatrix] {
            for charset in allCharsets {
                for cs in [RenderColorSpace.sRGB, .displayP3] {
                    let converter = ASCIIConverter(
                        characterSet: charset,
                        palette: BuiltInPalette.fullColor,
                        algorithm: algorithm,
                        colorSpace: cs
                    )
                    let grid = converter.convert(image, columns: 16)
                    #expect(grid.columns == 16)
                    #expect(grid.rows > 0)
                    for cell in grid.cells.flatMap({ $0 }) {
                        #expect(charset.characters.contains(cell.character))
                        #expect((0...1).contains(cell.displayColor.x))
                        #expect((0...1).contains(cell.displayColor.y))
                        #expect((0...1).contains(cell.displayColor.z))
                        #expect((0...1).contains(cell.alpha))
                    }
                }
            }
        }
    }

    @Test func tileShapeChangesGridDimensions() {
        let image = TestImages.horizontalGradient(width: 200, height: 200)
        let columns = 40
        let rowsAt: (ASCIITileShape) -> Int = { shape in
            ASCIIConverter(
                characterSet: StandardCharacterSet.standard,
                palette: BuiltInPalette.fullColor,
                tileShape: shape
            )
            .convert(image, columns: columns)
            .rows
        }
        let wide = rowsAt(.wide)  // sourceCellHeightOverWidth = 2.2
        let square = rowsAt(.square)  // 1.0 → ~2.2× more rows
        let tall = rowsAt(.tall)  // 0.5 → ~4.4× more rows

        // ±1 row tolerance for integer-truncation drift.
        #expect(abs(square - Int(round(Double(wide) * 2.2))) <= 1, "square=\(square) wide=\(wide)")
        #expect(abs(tall - Int(round(Double(wide) * 4.4))) <= 1, "tall=\(tall) wide=\(wide)")
    }

    @Test func renderingOptionsClampInvalidValues() {
        let image = TestImages.horizontalGradient(width: 100, height: 100)
        let charset = StandardCharacterSet.minimal

        // -1 on a 0...1 knob clamps to 0.
        let belowMin = ASCIIConverter(
            characterSet: charset,
            palette: BuiltInPalette.fullColor,
            algorithm: .dotMatrix,
            options: RenderingOptions(coverage: -1)
        ).convert(image, columns: 16)
        let atZero = ASCIIConverter(
            characterSet: charset,
            palette: BuiltInPalette.fullColor,
            algorithm: .dotMatrix,
            options: RenderingOptions(coverage: 0)
        ).convert(image, columns: 16)
        #expect(
            belowMin.cells.flatMap { $0 }.map(\.character)
                == atZero.cells.flatMap { $0 }.map(\.character))

        // 5 on a 0...1 knob clamps to 1.
        let aboveMax = ASCIIConverter(
            characterSet: charset,
            palette: BuiltInPalette.fullColor,
            algorithm: .dotMatrix,
            options: RenderingOptions(coverage: 5)
        ).convert(image, columns: 16)
        let atOne = ASCIIConverter(
            characterSet: charset,
            palette: BuiltInPalette.fullColor,
            algorithm: .dotMatrix,
            options: RenderingOptions(coverage: 1)
        ).convert(image, columns: 16)
        #expect(
            aboveMax.cells.flatMap { $0 }.map(\.character)
                == atOne.cells.flatMap { $0 }.map(\.character))
    }

    @Test func mutableOversampleClampsToAtLeastOne() {
        var converter = ASCIIConverter(
            characterSet: StandardCharacterSet.minimal,
            palette: BuiltInPalette.fullColor
        )

        converter.oversample = 0
        #expect(converter.oversample == 1)
        converter.oversample = -10
        #expect(converter.oversample == 1)

        let image = TestImages.horizontalGradient(width: 80, height: 80)
        let grid = converter.convert(image, columns: 16)
        #expect(grid.columns == 16)
        #expect(grid.rows > 0)
    }

    @Test func extremeMutableOversampleReturnsEmptyGridInsteadOfTrapping() {
        var converter = ASCIIConverter(
            characterSet: StandardCharacterSet.minimal,
            palette: BuiltInPalette.fullColor
        )
        converter.oversample = Int.max

        let image = TestImages.horizontalGradient(width: 80, height: 80)
        let grid = converter.convert(image, columns: 16)

        #expect(grid.cells.isEmpty)
    }

    @Test func extremeColumnsReturnEmptyGridInsteadOfTrapping() {
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.minimal,
            palette: BuiltInPalette.fullColor
        )
        let image = TestImages.horizontalGradient(width: 1, height: 4)

        let grid = converter.convert(image, columns: Int.max)

        #expect(grid.cells.isEmpty)
    }

    // The next two tests are wiring sanity checks (necessary, not sufficient).
    // They prove `density` and `edgeEmphasis` reach the kernel — a no-op
    // plumbing produces identical grids and fails. Algorithmic correctness
    // for default options is verified by `CharacterizationTests`.
    @Test func renderingOptionsAffectOutput_densityWidensTopKForLogPolar() {
        let image = TestImages.horizontalGradient(width: 200, height: 60)
        let convert: (Float) -> [[Character]] = { density in
            ASCIIConverter(
                characterSet: StandardCharacterSet.standard,
                palette: BuiltInPalette.fullColor,
                algorithm: .logPolar,
                options: RenderingOptions(density: density)
            )
            .convert(image, columns: 40)
            .cells.map { $0.map(\.character) }
        }
        let zeroDensity = convert(0)
        let highDensity = convert(1)
        let differingCells = zip(zeroDensity.flatMap { $0 }, highDensity.flatMap { $0 })
            .filter { $0 != $1 }.count
        #expect(
            differingCells >= 5,
            """
            density=1 produced near-identical output to density=0 \
            (\(differingCells) cells changed) — top-K widening is likely \
            not wired through
            """)
    }

    // edgeEmphasis-effect wiring is verified in LogPolarKernelTests, where we
    // can control cell dimensions directly. Through the converter at default
    // oversample=2 the cell size is too small (cellWidth=2) for the kernel's
    // Sobel guard `w >= 3, h >= 3` to fire, so the option is wired but
    // structurally gated out — testing at this layer would be misleading.

    @Test func renderingOptionsAffectOutput_brightnessRaisesDisplayLuminance() {
        let image = TestImages.horizontalGradient(width: 100, height: 100)
        let lo = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.fullColor,
            algorithm: .logPolar,
            options: RenderingOptions(brightness: -0.5)
        ).convert(image, columns: 20)
        let hi = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.fullColor,
            algorithm: .logPolar,
            options: RenderingOptions(brightness: 0.5)
        ).convert(image, columns: 20)

        let meanL: ([[ASCIICell]]) -> Float = { rows in
            let bs = rows.flatMap { $0.map(\.brightness) }
            return bs.reduce(0, +) / Float(bs.count)
        }
        #expect(meanL(hi.cells) > meanL(lo.cells))
    }

    @Test func renderingOptionsWellFormed_cartesianSweep() {
        // Sweep each knob at min, mid, max of its valid range. Out-of-range
        // values are tested separately by `renderingOptionsClampInvalidValues`.
        let image = TestImages.horizontalGradient(width: 80, height: 80)
        let unitKnob: [Float] = [0, 0.5, 1]  // 0...1 knobs
        let bipolarKnob: [Float] = [-1, 0, 1]  // -1...1 knobs
        for c in unitKnob {
            for d in unitKnob {
                for e in unitKnob {
                    for br in bipolarKnob {
                        for ct in bipolarKnob {
                            for algo in [ASCIIAlgorithm.logPolar, .dotMatrix] {
                                let opts = RenderingOptions(
                                    coverage: c, density: d, edgeEmphasis: e,
                                    brightness: br, contrast: ct
                                )
                                let grid = ASCIIConverter(
                                    characterSet: StandardCharacterSet.minimal,
                                    palette: BuiltInPalette.fullColor,
                                    algorithm: algo,
                                    options: opts
                                ).convert(image, columns: 8)
                                for cell in grid.cells.flatMap({ $0 }) {
                                    #expect(cell.brightness.isFinite)
                                    #expect((0...1).contains(cell.alpha))
                                    #expect(cell.displayColor.x.isFinite)
                                    #expect(cell.displayColor.y.isFinite)
                                    #expect(cell.displayColor.z.isFinite)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func edgeEmphasisAffectsLogPolarOutputAtOversample4() {
        // At oversample=4, default thumbnail math produces cellWidth >= 3 and
        // LogPolarKernel.sobelMagnitude fires. The Sobel-blended shape vector
        // diverges from the (1 - luminance) shape vector, so picked glyphs
        // differ across multiple cells.
        let image = TestImages.horizontalGradient(width: 200, height: 60)
        let convert: (Float) -> [[Character]] = { e in
            ASCIIConverter(
                characterSet: StandardCharacterSet.standard,
                palette: BuiltInPalette.fullColor,
                algorithm: .logPolar,
                options: RenderingOptions(edgeEmphasis: e),
                oversample: 4
            )
            .convert(image, columns: 40)
            .cells.map { $0.map(\.character) }
        }
        let zero = convert(0)
        let high = convert(1)
        let differingCells = zip(zero.flatMap { $0 }, high.flatMap { $0 })
            .filter { $0 != $1 }.count
        #expect(
            differingCells >= 5,
            """
            edgeEmphasis=1 at oversample=4 produced near-identical output to \
            edgeEmphasis=0 (\(differingCells) cells changed) — Sobel weighting \
            should now fire because cellWidth >= 3.
            """)
    }

    @Test func displayP3ConversionPreservesWideGamutRed() {
        let image = TestImages.solidDisplayP3Red(width: 64, height: 32)
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.fullColor,
            colorSpace: .displayP3
        )
        // Use enough columns to keep this test on the direct CGImage path.
        // Thumbnail transcode can preserve appearance by converting the P3
        // primary into equivalent sRGB-red coordinates, which would test
        // ImageIO behavior instead of the converter's target-space mapping.
        let grid = converter.convert(image, columns: 32)
        let colors = grid.cells.flatMap { $0.map(\.displayColor) }
        let mean = colors.reduce(SIMD3<Float>(0, 0, 0), +) / Float(colors.count)

        #expect(grid.colorSpace == .displayP3)
        #expect(mean.x > 0.98)
        #expect(mean.y < 0.02)
        #expect(mean.z < 0.02)
    }
}
