import CoreGraphics

/// A radial light for ``LightingOptions``.
///
/// Over a white image with no ambient light, a light of ``intensity`` 1 renders
/// exactly ``color`` at ``position`` and fades to no light at ``radius``.
public struct PointLight: Sendable {
    /// The light's center as fractions of the output width and height, with (0, 0)
    /// at the bottom-left corner.
    public var position: CGPoint
    /// The distance at which the light reaches zero, as a fraction of the output's
    /// longer side.
    public var radius: Double
    /// A scale for the light's encoded sRGB components. Each scaled component stops
    /// at 1, or at the color's own value when a wide-gamut component exceeds 1, so
    /// values above 1 saturate the light instead of overdriving it.
    public var intensity: Double
    /// The light's color, interpreted in the color space the `CGColor` declares.
    public var color: CGColor

    public init(position: CGPoint, radius: Double, intensity: Double, color: CGColor) {
        self.position = position
        self.radius = radius
        self.intensity = intensity
        self.color = color
    }
}

/// Point lights and an ambient level that multiply the rendered image.
///
/// The light field is the ambient gray plus every light, added in linear light. It
/// multiplies the image after mask composition and before the effect chain, and the
/// image keeps its alpha. Only the first four lights are used.
public struct LightingOptions: Sendable {
    public var lights: [PointLight]
    /// The gray level present everywhere, as an encoded sRGB value; negative values
    /// count as 0. With no lights, white renders as this gray, so 1 leaves the image
    /// unchanged.
    public var ambient: Double

    public init(lights: [PointLight], ambient: Double = 0.5) {
        self.lights = lights
        self.ambient = ambient
    }
}
