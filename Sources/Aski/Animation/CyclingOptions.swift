public struct CyclingOptions: Sendable, Equatable {
    public var k: Int
    public var speed: Double
    public var intensity: Double
    public var randomness: Double

    /// Smallest cycling speed whose base period `1 / speed` still stores as a
    /// finite `Float` in `AnimationSchedule.periods`.
    ///
    /// See ``maxSpeed`` for why the range is enforced rather than sanitized.
    public static let minSpeed = (1 + ScheduleBuilder.periodJitterFraction) / Double(Float.greatestFiniteMagnitude)

    /// Largest cycling speed whose base period `1 / speed` still stores as a
    /// normal (non-subnormal, non-zero) `Float` in `AnimationSchedule.periods`.
    ///
    /// Both bounds leave room for the ±`ScheduleBuilder.periodJitterFraction`
    /// per-cell jitter applied on top of the base period. Outside the range the
    /// stored period collapses to zero or to infinity, which leaves the cycling
    /// schedule with no representable cadence. `speed` is a structural
    /// parameter — it defines the schedule — so an out-of-range value is
    /// rejected at the public boundary rather than clamped (ASKI-6 AC#2),
    /// matching how `AnimationOptions.duration` is handled.
    public static let maxSpeed = (1 - ScheduleBuilder.periodJitterFraction) / Double(Float.leastNormalMagnitude)

    /// - Precondition: `speed` is finite and within ``minSpeed``...``maxSpeed``.
    ///   `intensity` and `randomness` are aesthetic and are clamped to `0...1`
    ///   at schedule-build time instead.
    public init(
        k: Int = 6,
        speed: Double = 1.0,
        intensity: Double = 0.6,
        randomness: Double = 0.5
    ) {
        self.k = k
        self.speed = speed
        self.intensity = intensity
        self.randomness = randomness
        validateSpeed()
    }

    /// `speed` is a `var`, so it can be mutated out of domain after
    /// construction. The animation entry points re-check it before building a
    /// schedule.
    internal func validateSpeed() {
        precondition(speed.isFinite && speed > 0, "CyclingOptions.speed must be finite and positive")
        precondition(
            speed >= Self.minSpeed && speed <= Self.maxSpeed,
            "CyclingOptions.speed must be within \(Self.minSpeed)...\(Self.maxSpeed) so 1 / speed is a representable Float period"
        )
    }

    public static let `default` = CyclingOptions()
}
