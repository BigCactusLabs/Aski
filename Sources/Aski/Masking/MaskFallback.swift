import CoreGraphics

public enum MaskFallback: Sendable {
    case transparent
    case solid(CGColor)
    case originalImage(CGImage, sizing: BackgroundSizing)
    case character(Character, color: CGColor?)
}

internal extension MaskFallback {
    var isTransparentFallback: Bool {
        if case .transparent = self {
            return true
        }
        return false
    }

    var textReplacementCharacter: Character? {
        if case .character(let character, _) = self {
            return character
        }
        return nil
    }
}
