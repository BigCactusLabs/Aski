import CoreImage

internal struct MetallibEffectKernel: EffectKernel {
    let kind: Kind
    let fallback: StockCIEffectKernel?

    enum Kind: Sendable, Hashable {
        case scanLines(intensity: Double, frequency: Double)
        case crtCurvature(intensity: Double)
        case halftone(scale: Double)
        case filmDust(intensity: Double, seed: UInt64)
        case glitch(intensity: Double, seed: UInt64)
        case rgbSplit(intensity: Double)
        case filmGrain(intensity: Double, seed: UInt64)
    }

    func apply(to image: CIImage, in context: EffectContext) throws -> CIImage {
        if case .reducedQuality = context.deviceCapability {
            return try applyFallbackOrThrow(to: image, in: context)
        }

        guard let kernel = lookupKernel() else {
            return try applyFallbackOrThrow(to: image, in: context)
        }
        return apply(kernel, to: image, in: context)
    }

    private func applyFallbackOrThrow(to image: CIImage, in context: EffectContext) throws -> CIImage {
        if let fallback {
            return try fallback.apply(to: image, in: context)
        }
        throw EffectError.unsupportedOnDevice(toEffect())
    }

    private func lookupKernel() -> CIKernel? {
        switch kind {
        case .scanLines: return CIKernelLibrary.scanLines
        case .crtCurvature: return CIKernelLibrary.crtCurvature
        case .halftone: return CIKernelLibrary.halftone
        case .filmDust: return CIKernelLibrary.filmDust
        case .glitch: return CIKernelLibrary.glitch
        case .rgbSplit: return CIKernelLibrary.rgbSplit
        case .filmGrain: return CIKernelLibrary.filmGrain
        }
    }

    private func apply(_ kernel: CIKernel, to image: CIImage, in context: EffectContext) -> CIImage {
        let extent = context.outputExtent
        let args = arguments(image: image)
        let out = kernel.apply(extent: extent, roiCallback: { _, rect in rect }, arguments: args)
        return (out ?? image).cropped(to: extent)
    }

    private func arguments(image: CIImage) -> [Any] {
        switch kind {
        case .scanLines(let intensity, let frequency):
            return [image, intensity, frequency]
        case .crtCurvature(let intensity):
            return [image, intensity]
        case .halftone(let scale):
            return [image, scale]
        case .filmDust(let intensity, let seed):
            return [image, intensity, Self.seedParts(seed)]
        case .glitch(let intensity, let seed):
            return [image, intensity, Self.seedParts(seed)]
        case .rgbSplit(let intensity):
            return [image, intensity]
        case .filmGrain(let intensity, let seed):
            return [image, intensity, Self.seedParts(seed)]
        }
    }

    private static func seedParts(_ seed: UInt64) -> CIVector {
        CIVector(
            x: CGFloat(seed & 0xFFFF),
            y: CGFloat((seed >> 16) & 0xFFFF),
            z: CGFloat((seed >> 32) & 0xFFFF),
            w: CGFloat((seed >> 48) & 0xFFFF)
        )
    }

    private func toEffect() -> Effect {
        switch kind {
        case .scanLines(let intensity, let frequency):
            return .scanLines(intensity: intensity, frequency: frequency)
        case .crtCurvature(let intensity):
            return .crtCurvature(intensity: intensity)
        case .halftone(let scale):
            return .halftone(scale: scale)
        case .filmDust(let intensity, let seed):
            return .filmDust(intensity: intensity, seed: seed)
        case .glitch(let intensity, let seed):
            return .glitch(intensity: intensity, seed: seed)
        case .rgbSplit(let intensity):
            return .rgbSplit(intensity: intensity)
        case .filmGrain(let intensity, let seed):
            return .filmGrain(intensity: intensity, seed: seed)
        }
    }
}
