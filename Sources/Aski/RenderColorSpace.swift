import CoreGraphics

public enum RenderColorSpace: Sendable, Hashable {
    case sRGB
    case displayP3
}

internal extension RenderColorSpace {
    // Cell components are transfer-encoded, even when the destination context
    // uses a linear-light composition policy.
    var encodedCGColorSpace: CGColorSpace {
        switch self {
        case .sRGB: Self.encodedSRGB
        case .displayP3: Self.encodedDisplayP3
        }
    }

    func encodedColor(_ rgb: SIMD3<Float>, alpha: Float) -> CGColor {
        guard
            let color = CGColor(
                colorSpace: encodedCGColorSpace,
                components: [CGFloat(rgb.x), CGFloat(rgb.y), CGFloat(rgb.z), CGFloat(alpha)]
            )
        else {
            preconditionFailure("Known RGB color spaces must accept RGBA components")
        }
        return color
    }

    private static let encodedSRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let encodedDisplayP3 = CGColorSpace(name: CGColorSpace.displayP3)!
}
