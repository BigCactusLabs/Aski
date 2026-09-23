import CoreGraphics

public struct ColorOverlay: Sendable {
    public var color: CGColor
    public var blendMode: CGBlendMode
    public var opacity: Double

    public init(color: CGColor, blendMode: CGBlendMode = .multiply, opacity: Double = 1) {
        self.color = color
        self.blendMode = blendMode
        self.opacity = opacity
    }
}
