import Foundation

public enum AnimationEasing: Sendable, Equatable {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    internal func apply(_ value: Double) -> Double {
        let t = value.isFinite ? min(1, max(0, value)) : 0
        switch self {
        case .linear:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            return 1 - (1 - t) * (1 - t)
        case .easeInOut:
            if t < 0.5 {
                return 2 * t * t
            }
            return 1 - pow(-2 * t + 2, 2) / 2
        }
    }
}
