import CoreGraphics

public enum BackgroundSizing: Sendable, Hashable {
    /// Aspect-fill: scale the source to fill the output extent; overflow is cropped.
    case fill
    /// Aspect-fit: scale the source to fit within the output extent; surround is transparent.
    case fit
    /// Stretch the source to match the output extent exactly. Distorts.
    case stretch
}

public enum Background: Sendable {
    case transparent
    case solid(CGColor)
    case original(CGImage, sizing: BackgroundSizing)
    case blurred(CGImage, radius: Double, opacity: Double, sizing: BackgroundSizing)
}

public struct CompositionOptions: Sendable {
    public var background: Background
    public var characterBlendMode: CGBlendMode
    public var colorOverlay: ColorOverlay?
    public var perCharacter: PerCharacterEffects

    public init(
        background: Background = .transparent,
        characterBlendMode: CGBlendMode = .normal,
        colorOverlay: ColorOverlay? = nil,
        perCharacter: PerCharacterEffects = .init()
    ) {
        self.background = background
        self.characterBlendMode = characterBlendMode
        self.colorOverlay = colorOverlay
        self.perCharacter = perCharacter
    }
}
