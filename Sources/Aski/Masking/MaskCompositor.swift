import CoreGraphics
import CoreImage

internal enum MaskCompositor {
    static func sourceOver(
        _ source: CIImage,
        background: CIImage,
        extent: CGRect
    ) -> CIImage {
        let filter = CIFilter(name: "CISourceOverCompositing")!
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(background, forKey: kCIInputBackgroundImageKey)
        return (filter.outputImage ?? source).cropped(to: extent)
    }

    static func blendWithMask(
        source: CIImage,
        background: CIImage,
        mask: CIImage,
        extent: CGRect
    ) -> CIImage {
        let filter = CIFilter(name: "CIBlendWithMask")!
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(background, forKey: kCIInputBackgroundImageKey)
        filter.setValue(mask, forKey: kCIInputMaskImageKey)
        return (filter.outputImage ?? source).cropped(to: extent)
    }
}
