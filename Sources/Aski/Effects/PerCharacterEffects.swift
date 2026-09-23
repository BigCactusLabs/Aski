public struct BloomOptions: Sendable, Hashable {
    public var intensity: Double
    public var radius: Double

    public init(intensity: Double, radius: Double) {
        self.intensity = intensity
        self.radius = radius
    }
}

public struct AberrationOptions: Sendable, Hashable {
    public var intensity: Double

    public init(intensity: Double) {
        self.intensity = intensity
    }
}

public struct PerCharacterEffects: Sendable, Hashable {
    public var bloom: BloomOptions?
    public var chromaticAberration: AberrationOptions?

    public init(bloom: BloomOptions? = nil, chromaticAberration: AberrationOptions? = nil) {
        self.bloom = bloom
        self.chromaticAberration = chromaticAberration
    }
}
