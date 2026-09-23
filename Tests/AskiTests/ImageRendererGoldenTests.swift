import Testing
import CoreGraphics
import Foundation
@testable import Aski

/// G0 (ASTSK-10, HDR/EDR spike): the no-effects `renderImage` output must stay
/// **bit-identical** across the HDR-path refactor that extracts the shared draw
/// helper, and across machines. This is a raw-byte golden (distinct from the
/// perceptual PNG snapshot suite): a refactor that perturbs even one pixel fails
/// here. The HDR-path refactor's byte-identity was first verified via the
/// `courierPrime` PNG snapshot suite (byte-identical); this golden uses the same
/// bundled font so the bytes are reproducible across Apple OS/platform versions
/// (the resolved system face and CoreText rasterization are not), then guards
/// future regressions.
///
/// The fixture exercises both render branches — Core Text glyphs and the
/// programmatic braille raster — plus alpha/colour variation, so a regression in
/// either path is caught. Regenerate the golden with `RECORD_G0=1` **only** when
/// an intentional, reviewed output change is being baselined.
@Suite struct ImageRendererGoldenTests {
    static let font = ASCIIFont.courierPrime(size: 12)
    static let background = CGColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)

    /// Deterministic 6×3 grid mixing Core Text glyphs and braille codepoints.
    static func makeGrid() -> ASCIIGrid {
        let glyphs: [[Character]] = [
            ["#", "@", "A", ".", "/", "M"],
            ["\u{283F}", "\u{28FF}", "\u{2801}", "W", "i", "="],
            ["g", "0", "x", "|", "%", "\u{28A5}"],
        ]
        var cells: [[ASCIICell]] = []
        for (r, row) in glyphs.enumerated() {
            var cellRow: [ASCIICell] = []
            for (c, ch) in row.enumerated() {
                let t = Float(r * row.count + c) / Float(glyphs.count * row.count)
                let color = SIMD3<Float>(t, 1 - t, Float(c % 3) / 2)
                let alpha: Float = (r + c) % 2 == 0 ? 1.0 : 0.6
                cellRow.append(ASCIICell(character: ch, displayColor: color, alpha: alpha, brightness: t))
            }
            cells.append(cellRow)
        }
        return ASCIIGrid(cells: cells, colorSpace: .sRGB)
    }

    static var goldenURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Goldens/imagerenderer-g0-srgb.bin")
    }

    @Test func renderImageMatchesPreRefactorGolden() throws {
        let grid = Self.makeGrid()
        let image = grid.renderImage(font: Self.font, backgroundColor: Self.background, scale: 1)
        let bytes = Data(TestImages.deviceRGBBytes(image))
        let url = Self.goldenURL

        if ProcessInfo.processInfo.environment["RECORD_G0"] == "1" {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try bytes.write(to: url)
            return
        }

        let golden = try Data(contentsOf: url)
        #expect(bytes == golden, "renderImage output diverged from the pre-refactor G0 golden")
    }
}
