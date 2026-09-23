public enum EntrancePattern: Sendable, Equatable {
    case cascadeLR(easing: AnimationEasing = .linear)
    case cascadeRL(easing: AnimationEasing = .linear)
    case cascadeTB(easing: AnimationEasing = .linear)
    case reveal(origin: AnimationAnchor, easing: AnimationEasing = .linear)
}
