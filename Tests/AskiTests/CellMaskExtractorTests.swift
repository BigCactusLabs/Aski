import Testing
import CoreImage
import CoreGraphics
@testable import Aski

@Suite struct CellMaskExtractorTests {
    @Test func opaqueAreaProducesOpaqueMask() {
        let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
        let opaqueWhite = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: extent)
        let mask = CellMaskExtractor.mask(from: opaqueWhite)

        let ctx = CIContext(options: nil)
        var pixel = [UInt8](repeating: 0, count: 4)
        ctx.render(
            mask,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 4, y: 4, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        #expect(pixel[0] > 200 && pixel[1] > 200 && pixel[2] > 200)
    }

    @Test func transparentAreaProducesTransparentMask() {
        let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
        let transparent = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
        let mask = CellMaskExtractor.mask(from: transparent)

        let ctx = CIContext(options: nil)
        var pixel = [UInt8](repeating: 255, count: 4)
        ctx.render(
            mask,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 4, y: 4, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        #expect(pixel[0] < 16 && pixel[1] < 16 && pixel[2] < 16)
    }

    @Test func maskExtentMatchesInput() {
        let extent = CGRect(x: 0, y: 0, width: 32, height: 16)
        let raster = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)).cropped(to: extent)
        let mask = CellMaskExtractor.mask(from: raster)
        #expect(mask.extent == extent)
    }
}
