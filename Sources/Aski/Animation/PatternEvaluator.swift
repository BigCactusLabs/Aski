import Foundation

internal struct AnimationCellCoordinate: Sendable, Equatable {
    let column: Int
    let row: Int
    let columns: Int
    let rows: Int
}

internal enum PatternEvaluator {
    // Fixed at 20% of the animation duration for v1 so entrance cases stay
    // simple. Expose this later only if app-side tuning proves it is needed.
    private static let revealWindow = 0.2

    static func entranceAlpha(
        _ pattern: EntrancePattern,
        coord: AnimationCellCoordinate,
        time: TimeInterval,
        duration: TimeInterval
    ) -> Double {
        let normalizedTime = duration > 0 ? max(0, time) / duration : 1
        let start: Double
        let easing: AnimationEasing
        switch pattern {
        case .cascadeLR(let e):
            start = position(Double(coord.column), count: coord.columns) * (1 - revealWindow)
            easing = e
        case .cascadeRL(let e):
            start = (1 - position(Double(coord.column), count: coord.columns)) * (1 - revealWindow)
            easing = e
        case .cascadeTB(let e):
            start = position(Double(coord.row), count: coord.rows) * (1 - revealWindow)
            easing = e
        case .reveal(let origin, let e):
            start = radialDistance(from: origin, coord: coord) * (1 - revealWindow)
            easing = e
        }

        if normalizedTime >= 1 {
            return 1
        }
        let progress = (normalizedTime - start) / revealWindow
        return easing.apply(progress)
    }

    /// Evaluates `pattern` for one cell.
    ///
    /// - Precondition: wave `frequency` and pulse `period` are finite and
    ///   positive. This is an internal invariant, not the enforcement point:
    ///   every public entry point that accepts an `OngoingPattern` calls
    ///   `OngoingPattern.validate()` first, so these two checks are unreachable
    ///   from public API (ASKI-18). They stay as a loud backstop — if a new
    ///   entry point is added and forgets the guard, this must fail rather than
    ///   quietly compute garbage. Kept deliberately; do not delete as dead code.
    ///   The accepting boundaries are `AnimationOptions.init`,
    ///   `ASCIIConverter.animate`, `ScheduleBuilder.build`,
    ///   `ASCIIGrid.applyingOngoingPattern`,
    ///   `ASCIIVideoFrame.applyingOngoingPattern` and `convertVideo`.
    static func ongoingAlpha(
        _ pattern: OngoingPattern,
        coord: AnimationCellCoordinate,
        time: TimeInterval
    ) -> Double {
        switch pattern {
        case .wave(let amplitude, let frequency, let direction):
            precondition(frequency.isFinite && frequency > 0, "wave frequency must be finite and positive")
            let resolvedAmplitude = sanitizedClamped(amplitude, min: 0, max: 0.5, defaultValue: 0.5)
            guard resolvedAmplitude > 0 else { return 1 }
            let spatial: Double
            switch direction {
            case .horizontal:
                spatial = loopPosition(Double(coord.column), count: coord.columns)
            case .vertical:
                spatial = loopPosition(Double(coord.row), count: coord.rows)
            case .diagonal:
                spatial = Double(coord.row + coord.column) / Double(max(coord.rows + coord.columns, 1))
            }
            let value = 0.5 + resolvedAmplitude * sin(2 * Double.pi * frequency * time - 2 * Double.pi * spatial)
            return clampUnit(value, fallback: 1)

        case .pulse(let period, let depth):
            precondition(period.isFinite && period > 0, "pulse period must be finite and positive")
            let resolvedDepth = sanitizedClamped(depth, min: 0, max: 1, defaultValue: 1)
            guard resolvedDepth > 0 else { return 1 }
            let value = 1 - resolvedDepth / 2 + (resolvedDepth / 2) * sin(2 * Double.pi * time / period + Double.pi / 2)
            return clampUnit(value, fallback: 1)
        }
    }

    static func clampUnit(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return min(1, max(0, fallback)) }
        return min(1, max(0, value))
    }

    static func sanitizedClamped(_ value: Double, min minimum: Double, max maximum: Double, defaultValue: Double) -> Double {
        guard value.isFinite else { return defaultValue }
        return Swift.min(maximum, Swift.max(minimum, value))
    }

    private static func position(_ value: Double, count: Int) -> Double {
        value / Double(max(count - 1, 1))
    }

    // For periodic patterns; avoids endpoint aliasing at value == count - 1.
    private static func loopPosition(_ value: Double, count: Int) -> Double {
        value / Double(max(count, 1))
    }

    /// The single consumption point of `AnimationAnchor` (ASKI-35).
    ///
    /// Coordinates outside `0...1` are **supported**, not clamped: the distance
    /// field is normalized against the largest anchor-to-corner distance, so an
    /// off-grid origin still yields a well-defined `0...1` wavefront — just a
    /// flatter one, sweeping in from outside the grid. Clamping would delete
    /// that effect. A NON-FINITE coordinate has no geometry at all (it produced
    /// a flat field: `NaN` revealed everything at once, `inf` revealed nothing
    /// until the end), so it resolves to the centre here — one rule, one place.
    /// A finite coordinate above ~`greatestFiniteMagnitude / 4` makes the
    /// corner `hypot` overflow to infinity and the normalized ratio NaN — its
    /// geometry cannot remain finite either, so it takes the same fallback.
    private static func radialDistance(from origin: AnimationAnchor, coord: AnimationCellCoordinate) -> Double {
        let safeMagnitude = Double.greatestFiniteMagnitude / 4
        let originX = abs(origin.x) <= safeMagnitude ? origin.x : 0.5
        let originY = abs(origin.y) <= safeMagnitude ? origin.y : 0.5
        let x = position(Double(coord.column), count: coord.columns)
        let y = position(Double(coord.row), count: coord.rows)
        let dx = x - originX
        let dy = y - originY
        let maxDistance = max(
            hypot(0 - originX, 0 - originY),
            hypot(1 - originX, 0 - originY),
            hypot(0 - originX, 1 - originY),
            hypot(1 - originX, 1 - originY)
        )
        guard maxDistance > 0 else { return 0 }
        return min(1, hypot(dx, dy) / maxDistance)
    }
}
