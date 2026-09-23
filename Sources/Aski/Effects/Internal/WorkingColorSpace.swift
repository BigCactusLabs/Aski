import CoreGraphics

internal enum WorkingColorSpace {
    /// Core Image's canonical high-color working space for effects.
    static let extendedLinearSRGB: CGColorSpace = {
        CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
            ?? CGColorSpaceCreateDeviceRGB()
    }()
}
