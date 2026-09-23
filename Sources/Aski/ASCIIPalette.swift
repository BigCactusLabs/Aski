import simd

/// Palette contract for ASCII conversion.
///
/// Use `PaletteContent.passThrough` to keep adjusted source color, or
/// `PaletteContent.fixed(_:)` to quantize output to declared palette colors.
public protocol ASCIIPalette: Sendable {
    var content: PaletteContent { get }
}

/// Explicit palette payload for ASCII conversion.
public struct PaletteContent: Sendable, Hashable {
    private enum Storage: Sendable, Hashable {
        case passThrough
        case fixed([PaletteColor])
    }

    private let storage: Storage

    /// Keep adjusted source color without palette quantization.
    public static let passThrough = PaletteContent(storage: .passThrough)

    /// Quantize output to the supplied declared colors.
    ///
    /// - Precondition: `colors` must not be empty. Empty arrays are not a
    ///   pass-through sentinel; use `passThrough` explicitly.
    public static func fixed(_ colors: [PaletteColor]) -> PaletteContent {
        precondition(!colors.isEmpty, "PaletteContent.fixed requires at least one color")
        return PaletteContent(storage: .fixed(colors))
    }

    public var isPassThrough: Bool {
        if case .passThrough = storage { return true }
        return false
    }

    public var colors: [PaletteColor]? {
        if case .fixed(let colors) = storage { return colors }
        return nil
    }
}

/// A palette color declared in a supported source color space.
public struct PaletteColor: Sendable, Hashable {
    public var components: SIMD3<Float>
    public var colorSpace: PaletteColorSpace

    /// Create a palette color from transfer-encoded RGB components in `0...1`.
    public init(_ components: SIMD3<Float>, colorSpace: PaletteColorSpace = .sRGB) {
        self.components = components
        self.colorSpace = colorSpace
    }
}

/// Supported declared color spaces for palette input.
public struct PaletteColorSpace: Sendable, Hashable {
    internal let rawValue: String

    /// Transfer-encoded sRGB components.
    public static let sRGB = PaletteColorSpace(rawValue: "srgb")

    /// Transfer-encoded Display P3 components.
    public static let displayP3 = PaletteColorSpace(rawValue: "display-p3")
}

/// Built-in ASCII palette presets.
public struct BuiltInPalette: ASCIIPalette {
    public let content: PaletteContent

    /// Source-color pass-through with no palette quantization.
    public static let fullColor = BuiltInPalette(content: .passThrough)

    /// Single white ink; luminance is encoded entirely by character density downstream.
    public static let monochrome = BuiltInPalette(
        content: .fixed([PaletteColor(SIMD3<Float>(1, 1, 1), colorSpace: .sRGB)])
    )

    public static let ansi16: BuiltInPalette = {
        // Classic 16-color ANSI palette (xterm-compatible approximations).
        let srgb: [SIMD3<Float>] = [
            SIMD3(0.00, 0.00, 0.00),  // black
            SIMD3(0.50, 0.00, 0.00),  // red
            SIMD3(0.00, 0.50, 0.00),  // green
            SIMD3(0.50, 0.50, 0.00),  // yellow
            SIMD3(0.00, 0.00, 0.50),  // blue
            SIMD3(0.50, 0.00, 0.50),  // magenta
            SIMD3(0.00, 0.50, 0.50),  // cyan
            SIMD3(0.75, 0.75, 0.75),  // white
            SIMD3(0.50, 0.50, 0.50),  // bright black (gray)
            SIMD3(1.00, 0.00, 0.00),  // bright red
            SIMD3(0.00, 1.00, 0.00),  // bright green
            SIMD3(1.00, 1.00, 0.00),  // bright yellow
            SIMD3(0.00, 0.00, 1.00),  // bright blue
            SIMD3(1.00, 0.00, 1.00),  // bright magenta
            SIMD3(0.00, 1.00, 1.00),  // bright cyan
            SIMD3(1.00, 1.00, 1.00),  // bright white
        ]
        return BuiltInPalette(
            content: .fixed(srgb.map { PaletteColor($0, colorSpace: .sRGB) })
        )
    }()
}
