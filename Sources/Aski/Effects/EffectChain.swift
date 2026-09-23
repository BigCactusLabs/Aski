public enum Effect: Sendable, Hashable {
    case vignette(intensity: Double)
    case scanLines(intensity: Double, frequency: Double)
    case crtCurvature(intensity: Double)
    case chromaticAberration(intensity: Double)
    case bloom(intensity: Double, radius: Double)
    case filmGrain(intensity: Double, seed: UInt64)
    case glitch(intensity: Double, seed: UInt64)
    case rgbSplit(intensity: Double)
    case blur(radius: Double)
    case pixelate(scale: Double)
    case halftone(scale: Double)
    case filmDust(intensity: Double, seed: UInt64)
}

public struct EffectChain: Sendable {
    public var effects: [Effect]

    public init(_ effects: [Effect] = []) {
        self.effects = effects
    }
}
