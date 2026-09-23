import Testing
import simd
@testable import Aski

@Suite struct CoreTypesTests {
    @Test func renderColorSpaceValues() {
        let sRGB = RenderColorSpace.sRGB
        let p3 = RenderColorSpace.displayP3
        #expect(sRGB != p3)
    }

    @Test func asciiCellConstruction() {
        let cell = ASCIICell(
            character: "A",
            displayColor: SIMD3(1.0, 0.5, 0.2),
            alpha: 0.8,
            brightness: 0.6
        )
        #expect(cell.character == "A")
        #expect(cell.displayColor == SIMD3<Float>(1.0, 0.5, 0.2))
        #expect(cell.alpha == 0.8)
        #expect(cell.brightness == 0.6)
    }
}
