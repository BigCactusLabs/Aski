import CoreImage

internal enum CellMaskExtractor {
    static func mask(from cellRaster: CIImage) -> CIImage {
        let filter = CIFilter(name: "CIColorMatrix")!
        filter.setValue(cellRaster, forKey: kCIInputImageKey)
        let alphaProjection = CIVector(x: 0, y: 0, z: 0, w: 1)
        filter.setValue(alphaProjection, forKey: "inputRVector")
        filter.setValue(alphaProjection, forKey: "inputGVector")
        filter.setValue(alphaProjection, forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputAVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputBiasVector")
        return filter.outputImage?.cropped(to: cellRaster.extent) ?? cellRaster
    }
}
