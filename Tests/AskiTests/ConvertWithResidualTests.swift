@_spi(AskiResearch) import Aski
import Testing

/// B3: `convertWithResidual` surfaces a per-cell shape-residual field while
/// producing a grid that is identical to `convert(_:columns:)`.
struct ConvertWithResidualTests {
    @Test func convertWithResidualMatchesConvertAndSizesResidual() {
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.monochrome,
            colorSpace: .sRGB
        )
        // Non-trivial image so cells are not all identical.
        let image = TestImages.horizontalGradient(width: 256, height: 128)

        let plain = converter.convert(image, columns: 16)
        let (grid, residual) = converter.convertWithResidual(image, columns: 16)

        // Same dimensions as `convert`.
        #expect(grid.rows == plain.rows)
        #expect(grid.columns == plain.columns)

        // Residual is row-major, length rows * columns.
        #expect(residual.count == grid.rows * grid.columns)

        // Whole-cell identity with `convert`: character, displayColor, alpha,
        // brightness, and coverage in one comparison (ASCIICell is Equatable) —
        // strictly stronger than checking characters + colors separately.
        // (ASCIIGrid itself is not Equatable, so compare at the .cells level.)
        #expect(grid.cells == plain.cells)
    }

    @Test func residualValuesAreFiniteForLogPolar() {
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.monochrome,
            colorSpace: .sRGB
        )
        let image = TestImages.horizontalGradient(width: 256, height: 128)
        let (_, residual) = converter.convertWithResidual(image, columns: 16)

        // logPolar always yields a real, finite 60D squared-L2 distance per
        // cell — no NaN sentinel (that is dotMatrix only). A leaked inf or NaN
        // would fail this.
        #expect(residual.allSatisfy { $0.isFinite })
    }
}
