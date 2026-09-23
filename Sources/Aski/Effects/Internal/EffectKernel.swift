import CoreImage

internal protocol EffectKernel: Sendable {
    func apply(to image: CIImage, in context: EffectContext) throws -> CIImage
}
