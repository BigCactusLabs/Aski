import CoreGraphics
import CoreImage
import os

internal struct BackgroundResolver: Sendable {
    private static let log = OSLog(subsystem: "com.bigcactuslabs.aski", category: "Effects")

    func resolve(_ background: Background, outputExtent: CGRect) -> CIImage? {
        guard outputExtent.width > 0, outputExtent.height > 0 else {
            os_log("BackgroundResolver: degenerate extent", log: Self.log, type: .info)
            return nil
        }

        switch background {
        case .transparent:
            return nil
        case .solid(let color):
            return CIImage(color: CIColor(cgColor: color)).cropped(to: outputExtent)
        case .original(let image, let sizing):
            return apply(sizing, to: CIImage(cgImage: image), outputExtent: outputExtent)
        case .blurred(let image, let radius, let opacity, let sizing):
            let sized = apply(sizing, to: CIImage(cgImage: image), outputExtent: outputExtent)
            let blurred = sized.flatMap { applyBlur($0, radius: radius, extent: outputExtent) }
            return blurred.flatMap { applyOpacity($0, opacity: opacity) }
        }
    }

    private func apply(_ sizing: BackgroundSizing, to image: CIImage, outputExtent: CGRect) -> CIImage? {
        let sourceExtent = image.extent
        guard sourceExtent.width > 0, sourceExtent.height > 0 else { return nil }

        switch sizing {
        case .fill:
            let scale = max(outputExtent.width / sourceExtent.width, outputExtent.height / sourceExtent.height)
            let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let dx = outputExtent.midX - scaled.extent.midX
            let dy = outputExtent.midY - scaled.extent.midY
            return
                scaled
                .transformed(by: CGAffineTransform(translationX: dx, y: dy))
                .cropped(to: outputExtent)

        case .fit:
            let scale = min(outputExtent.width / sourceExtent.width, outputExtent.height / sourceExtent.height)
            let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let dx = outputExtent.midX - scaled.extent.midX
            let dy = outputExtent.midY - scaled.extent.midY
            return
                scaled
                .transformed(by: CGAffineTransform(translationX: dx, y: dy))
                .composited(over: CIImage(color: .clear).cropped(to: outputExtent))
                .cropped(to: outputExtent)

        case .stretch:
            let sx = outputExtent.width / sourceExtent.width
            let sy = outputExtent.height / sourceExtent.height
            return
                image
                .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
                .transformed(by: CGAffineTransform(translationX: outputExtent.minX, y: outputExtent.minY))
                .cropped(to: outputExtent)
        }
    }

    private func applyBlur(_ image: CIImage, radius: Double, extent: CGRect) -> CIImage? {
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        filter?.setValue(radius, forKey: kCIInputRadiusKey)
        return filter?.outputImage?.cropped(to: extent)
    }

    private func applyOpacity(_ image: CIImage, opacity: Double) -> CIImage? {
        let filter = CIFilter(name: "CIColorMatrix")
        filter?.setValue(image, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)), forKey: "inputAVector")
        return filter?.outputImage
    }
}
