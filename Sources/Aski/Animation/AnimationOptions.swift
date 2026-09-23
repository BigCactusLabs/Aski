import Foundation

public struct AnimationOptions: Sendable, Equatable {
    public var duration: TimeInterval
    public var seed: UInt64
    public var cycling: CyclingOptions?
    public var entrance: EntrancePattern?
    public var ongoing: OngoingPattern?

    public init(
        duration: TimeInterval,
        seed: UInt64 = 0,
        cycling: CyclingOptions? = .default,
        entrance: EntrancePattern? = nil,
        ongoing: OngoingPattern? = nil
    ) {
        precondition(duration.isFinite && duration > 0, "AnimationOptions.duration must be finite and positive")
        ongoing?.validate()
        self.duration = duration
        self.seed = seed
        self.cycling = cycling
        self.entrance = entrance
        self.ongoing = ongoing
    }
}
