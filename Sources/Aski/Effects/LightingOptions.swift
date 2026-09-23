import CoreGraphics

public struct PointLight: Sendable {
    public var position: CGPoint
    public var radius: Double
    public var intensity: Double
    public var color: CGColor

    public init(position: CGPoint, radius: Double, intensity: Double, color: CGColor) {
        self.position = position
        self.radius = radius
        self.intensity = intensity
        self.color = color
    }
}

public struct LightingOptions: Sendable {
    public var lights: [PointLight]
    public var ambient: Double

    public init(lights: [PointLight], ambient: Double = 0.5) {
        self.lights = lights
        self.ambient = ambient
    }
}
