import CoreGraphics
import CoreImage
import os

private let stockCIEffectsLog = OSLog(subsystem: "com.bigcactuslabs.aski", category: "Effects")

internal struct StockCIEffectKernel: EffectKernel {
    let kind: Kind

    enum Kind: Sendable {
        case vignette(intensity: Double)
        case bloom(intensity: Double, radius: Double)
        case chromaticAberration(intensity: Double)
        case blur(radius: Double)
        case pixelate(scale: Double)
        case colorOverlay(color: CGColor, blendMode: CGBlendMode, opacity: Double)
        case scanLinesApprox(intensity: Double, frequency: Double)
        case crtCurvatureApprox
        case halftoneApprox(scale: Double)
        case filmDustApprox(intensity: Double, seed: UInt64)
        case glitchApprox(intensity: Double, seed: UInt64)
        case rgbSplitApprox(intensity: Double)
        case filmGrainApprox(intensity: Double, seed: UInt64)
    }

    func apply(to image: CIImage, in context: EffectContext) throws -> CIImage {
        // ASKI-34. Several kinds below size a raster from
        // `context.outputExtent` (`seededNoise` converts it with
        // `Int(ceil(...))`), and CoreImage reports `CGRectInfinite` for
        // generator and tiled filters, so an unbounded extent reaching here
        // would trap. The rule (see `RenderPixelBounds.finiteExtent`) is to
        // CLAMP it to the finite reference rect this call site already knows,
        // which here is the pre-effect input image's own extent: the image
        // genuinely exists and is merely unbounded, so the effect still has a
        // real region to work on. The input is cropped to that rect before it
        // is measured, so the whole chain below sees one bounded geometry.
        // Only when the input image is unbounded too is there no reference
        // left, and only then does the effect degrade to the ASKI-17-style
        // empty image.
        guard
            let extent = RenderPixelBounds.finiteExtent(
                context.outputExtent,
                clampedTo: image.extent
            )
        else {
            return EffectsRenderEngine.emptyCIImage()
        }
        guard extent != context.outputExtent else {
            return applyKind(to: image, in: context)
        }
        let bounded = EffectContext(
            workingColorSpace: context.workingColorSpace,
            outputExtent: extent,
            renderColorSpace: context.renderColorSpace,
            deviceCapability: context.deviceCapability
        )
        return applyKind(to: image.cropped(to: extent), in: bounded)
    }

    private func applyKind(to image: CIImage, in context: EffectContext) -> CIImage {
        switch kind {
        case .vignette(let intensity):
            return applyVignette(to: image, intensity: intensity, in: context)
        case .bloom(let intensity, let radius):
            return applyBloom(to: image, intensity: intensity, radius: radius, in: context)
        case .chromaticAberration(let intensity):
            return applyChromaticAberration(to: image, intensity: intensity, in: context)
        case .blur(let radius):
            return applyBlur(to: image, radius: radius, in: context)
        case .pixelate(let scale):
            return applyPixelate(to: image, scale: scale, in: context)
        case .colorOverlay(let color, let blendMode, let opacity):
            return applyColorOverlay(to: image, color: color, blendMode: blendMode, opacity: opacity, in: context)
        case .scanLinesApprox(let intensity, let frequency):
            return applyScanLinesApprox(to: image, intensity: intensity, frequency: frequency, in: context)
        case .crtCurvatureApprox:
            os_log(
                "crtCurvature requested on reduced-capability device; rendering as no-op",
                log: stockCIEffectsLog,
                type: .info
            )
            return image
        case .halftoneApprox(let scale):
            return applyHalftoneApprox(to: image, scale: scale, in: context)
        case .filmDustApprox(let intensity, let seed):
            return applyFilmDustApprox(to: image, intensity: intensity, seed: seed, in: context)
        case .glitchApprox(let intensity, let seed):
            return applyGlitchApprox(to: image, intensity: intensity, seed: seed, in: context)
        case .rgbSplitApprox(let intensity):
            return applyRGBSplitApprox(to: image, intensity: intensity, in: context)
        case .filmGrainApprox(let intensity, let seed):
            return applyFilmGrainApprox(to: image, intensity: intensity, seed: seed, in: context)
        }
    }

    private func applyVignette(to image: CIImage, intensity: Double, in context: EffectContext) -> CIImage {
        guard intensity > 0 else { return image }
        let extent = context.outputExtent
        let radius = max(extent.width, extent.height) * 0.5
        let filter = CIFilter(name: "CIVignette")!
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(intensity, forKey: kCIInputIntensityKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        return (filter.outputImage ?? image).cropped(to: extent)
    }

    private func applyBloom(
        to image: CIImage,
        intensity: Double,
        radius: Double,
        in context: EffectContext
    ) -> CIImage {
        guard intensity > 0, radius > 0 else { return image }
        let filter = CIFilter(name: "CIBloom")!
        filter.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(intensity, forKey: kCIInputIntensityKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        return (filter.outputImage ?? image).cropped(to: context.outputExtent)
    }

    private func applyChromaticAberration(to image: CIImage, intensity: Double, in context: EffectContext) -> CIImage {
        guard intensity > 0 else { return image }
        let extent = context.outputExtent
        let shift = CGFloat(intensity) * 4

        let red = redOnly(image)
            .transformed(by: .init(translationX: -shift, y: 0))
        let green = greenOnly(image)
        let blue = blueOnly(image)
            .transformed(by: .init(translationX: shift, y: 0))

        let redGreen = additive(red, with: green, extent: extent)
        return additive(redGreen, with: blue, extent: extent)
    }

    private func applyBlur(to image: CIImage, radius: Double, in context: EffectContext) -> CIImage {
        guard radius > 0 else { return image }
        let filter = CIFilter(name: "CIGaussianBlur")!
        filter.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        return (filter.outputImage ?? image).cropped(to: context.outputExtent)
    }

    private func applyPixelate(to image: CIImage, scale: Double, in context: EffectContext) -> CIImage {
        guard scale > 1 else { return image }
        let filter = CIFilter(name: "CIPixellate")!
        filter.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(
            CIVector(x: context.outputExtent.midX, y: context.outputExtent.midY),
            forKey: kCIInputCenterKey
        )
        return (filter.outputImage ?? image).cropped(to: context.outputExtent)
    }

    private func applyColorOverlay(
        to image: CIImage,
        color: CGColor,
        blendMode: CGBlendMode,
        opacity: Double,
        in context: EffectContext
    ) -> CIImage {
        let extent = context.outputExtent
        let ciColor = CIColor(cgColor: color)
        let scaledColor = CIColor(
            red: ciColor.red,
            green: ciColor.green,
            blue: ciColor.blue,
            alpha: CGFloat(max(0, min(1, opacity)))
        )
        let overlay = CIImage(color: scaledColor).cropped(to: extent)

        guard let kernel = BlendModeMapping.kernel(for: blendMode) else {
            return image
        }
        let blended =
            kernel.apply(
                foreground: overlay,
                background: image,
                colorSpace: context.workingColorSpace
            ) ?? image
        return blended.cropped(to: extent)
    }

    private func applyScanLinesApprox(
        to image: CIImage,
        intensity: Double,
        frequency: Double,
        in context: EffectContext
    ) -> CIImage {
        let extent = context.outputExtent
        let stripe =
            CIFilter(
                name: "CIStripesGenerator",
                parameters: [
                    "inputCenter": CIVector(x: extent.midX, y: extent.midY),
                    "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: 1),
                    "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
                    "inputWidth": max(1.0, frequency),
                    "inputSharpness": 0.5,
                ])?.outputImage?.cropped(to: extent) ?? image
        let modulation = CIFilter(name: "CIColorMatrix")
        modulation?.setValue(stripe, forKey: kCIInputImageKey)
        let scale = CGFloat(1.0 - max(0, min(1, intensity)) * 0.5)
        modulation?.setValue(CIVector(x: scale, y: 0, z: 0, w: 0), forKey: "inputRVector")
        modulation?.setValue(CIVector(x: 0, y: scale, z: 0, w: 0), forKey: "inputGVector")
        modulation?.setValue(CIVector(x: 0, y: 0, z: scale, w: 0), forKey: "inputBVector")
        let mask = modulation?.outputImage ?? stripe
        let blend = CIFilter(name: "CIMultiplyCompositing")!
        blend.setValue(image, forKey: kCIInputImageKey)
        blend.setValue(mask, forKey: kCIInputBackgroundImageKey)
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    private func applyHalftoneApprox(to image: CIImage, scale: Double, in context: EffectContext) -> CIImage {
        let filter = CIFilter(name: "CICMYKHalftone")!
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputWidthKey)
        filter.setValue(CIVector(x: context.outputExtent.midX, y: context.outputExtent.midY), forKey: "inputCenter")
        return (filter.outputImage ?? image).cropped(to: context.outputExtent)
    }

    private func applyFilmDustApprox(to image: CIImage, intensity: Double, seed: UInt64, in context: EffectContext) -> CIImage {
        let extent = context.outputExtent
        let noise = seededNoise(extent: extent, seed: seed)
        let opacity = CGFloat(max(0, min(1, intensity)) * 0.2)
        let mask = CIFilter(name: "CIColorMatrix")
        mask?.setValue(noise, forKey: kCIInputImageKey)
        mask?.setValue(CIVector(x: 0, y: 0, z: 0, w: opacity), forKey: "inputAVector")
        let dust = (mask?.outputImage ?? noise).cropped(to: extent)
        let blend = CIFilter(name: "CISourceOverCompositing")!
        blend.setValue(dust, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    private func applyGlitchApprox(to image: CIImage, intensity: Double, seed: UInt64, in context: EffectContext) -> CIImage {
        let dx = CGFloat((Double(seed % 17) / 17.0 - 0.5) * intensity * 0.05 * Double(context.outputExtent.width))
        let shifted = image.transformed(by: .init(translationX: dx, y: 0))
        return shifted.cropped(to: context.outputExtent)
    }

    private func applyRGBSplitApprox(to image: CIImage, intensity: Double, in context: EffectContext) -> CIImage {
        let shift = CGFloat(intensity) * 4.0
        let extent = context.outputExtent
        let red = channelMatrix(image, r: CIVector(x: 1, y: 0, z: 0, w: 0), g: .zero4, b: .zero4)
            .transformed(by: .init(translationX: -shift, y: 0))
        let green = channelMatrix(image, r: .zero4, g: CIVector(x: 0, y: 1, z: 0, w: 0), b: .zero4)
        let blue = channelMatrix(image, r: .zero4, g: .zero4, b: CIVector(x: 0, y: 0, z: 1, w: 0))
            .transformed(by: .init(translationX: shift, y: 0))
        let redGreen = additive(red, with: green, extent: extent)
        return additive(redGreen, with: blue, extent: extent)
    }

    private func applyFilmGrainApprox(to image: CIImage, intensity: Double, seed: UInt64, in context: EffectContext) -> CIImage {
        let extent = context.outputExtent
        let noise = seededNoise(extent: extent, seed: seed)
        let opacity = CGFloat(max(0, min(1, intensity)) * 0.15)
        let scaled = CIFilter(name: "CIColorMatrix")
        scaled?.setValue(noise, forKey: kCIInputImageKey)
        scaled?.setValue(CIVector(x: 0, y: 0, z: 0, w: opacity), forKey: "inputAVector")
        let grain = (scaled?.outputImage ?? noise).cropped(to: extent)
        let blend = CIFilter(name: "CIScreenBlendMode")!
        blend.setValue(grain, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    private func seededNoise(extent: CGRect, seed: UInt64) -> CIImage {
        let width = max(1, Int(ceil(extent.width)))
        let height = max(1, Int(ceil(extent.height)))
        var state = seed
        let byteCount = width * height * 4
        guard let data = CFDataCreateMutable(nil, byteCount) else {
            return CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)).cropped(to: extent)
        }
        CFDataSetLength(data, byteCount)
        guard let bytes = CFDataGetMutableBytePtr(data) else {
            return CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)).cropped(to: extent)
        }
        for offset in stride(from: 0, to: byteCount, by: 4) {
            let value = nextSeededByte(&state)
            bytes[offset] = value
            bytes[offset + 1] = value
            bytes[offset + 2] = value
            bytes[offset + 3] = 255
        }

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard
            let provider = CGDataProvider(data: data),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            return CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)).cropped(to: extent)
        }

        return CIImage(cgImage: image)
            .transformed(by: .init(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
    }

    private func nextSeededByte(_ state: inout UInt64) -> UInt8 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return UInt8(truncatingIfNeeded: value >> 56)
    }

    private func redOnly(_ image: CIImage) -> CIImage {
        channelMatrix(image, r: CIVector(x: 1, y: 0, z: 0, w: 0), g: .zero4, b: .zero4)
    }

    private func greenOnly(_ image: CIImage) -> CIImage {
        channelMatrix(image, r: .zero4, g: CIVector(x: 0, y: 1, z: 0, w: 0), b: .zero4)
    }

    private func blueOnly(_ image: CIImage) -> CIImage {
        channelMatrix(image, r: .zero4, g: .zero4, b: CIVector(x: 0, y: 0, z: 1, w: 0))
    }

    private func channelMatrix(_ image: CIImage, r: CIVector, g: CIVector, b: CIVector) -> CIImage {
        let filter = CIFilter(name: "CIColorMatrix")!
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(r, forKey: "inputRVector")
        filter.setValue(g, forKey: "inputGVector")
        filter.setValue(b, forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        return filter.outputImage ?? image
    }

    private func additive(_ first: CIImage, with second: CIImage, extent: CGRect) -> CIImage {
        let filter = CIFilter(name: "CIAdditionCompositing")!
        filter.setValue(first, forKey: kCIInputImageKey)
        filter.setValue(second, forKey: kCIInputBackgroundImageKey)
        return (filter.outputImage ?? first).cropped(to: extent)
    }
}

private extension CIVector {
    static let zero4 = CIVector(x: 0, y: 0, z: 0, w: 0)
}
