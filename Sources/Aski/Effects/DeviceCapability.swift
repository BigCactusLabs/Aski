public enum DeviceCapability: Sendable, Hashable {
    case full
    case reducedQuality(ReducedReason)
}

public enum ReducedReason: Sendable, Hashable {
    case metallibUnsupported
}
