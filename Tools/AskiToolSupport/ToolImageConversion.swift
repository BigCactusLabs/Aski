import Aski
import CoreGraphics

/// One resolved file conversion shared by product commands. Keeping the decoded
/// thumbnail, grid, and text together prevents inspection and artifact metadata
/// from drifting away from the render path they describe.
struct ToolImageConversion {
    let normalizedImage: CGImage
    let grid: ASCIIGrid
    let text: String

    static func load(
        inputPath: String,
        columns: Int,
        charset: Charset,
        mask: DemoMaskArguments? = nil
    ) throws -> ToolImageConversion {
        let converter = ASCIIConverter(characterSet: charset.characterSet, palette: BuiltInPalette.fullColor)
        let image = try DemoImageIO.loadThumbnailForConversion(
            at: inputPath,
            columns: columns,
            tileShape: converter.tileShape,
            oversample: converter.oversample
        )
        let maskOptions: MaskOptions?
        if let mask, let maskImage = try mask.loadMaskImage(sourceImage: image) {
            maskOptions = mask.makeMaskOptions(maskImage: maskImage, sourceImage: image)
        } else {
            maskOptions = nil
        }
        let grid = converter.convert(image, columns: columns, mask: maskOptions)
        return ToolImageConversion(normalizedImage: image, grid: grid, text: grid.renderPlainText())
    }
}
