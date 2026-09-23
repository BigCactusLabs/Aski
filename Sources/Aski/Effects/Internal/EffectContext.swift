import CoreGraphics
import CoreImage

internal struct EffectContext: Sendable {
    let workingColorSpace: CGColorSpace
    let outputExtent: CGRect
    let renderColorSpace: RenderColorSpace
    let deviceCapability: DeviceCapability
}
