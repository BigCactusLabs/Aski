import Foundation

public struct AnimatedASCIIGrid: Sendable {
    public let baseGrid: ASCIIGrid
    public let duration: TimeInterval
    public let seed: UInt64

    internal let schedule: AnimationSchedule
    internal let characterSet: CharacterSetSnapshot

    internal init(
        baseGrid: ASCIIGrid,
        duration: TimeInterval,
        seed: UInt64,
        schedule: AnimationSchedule,
        characterSet: CharacterSetSnapshot
    ) {
        self.baseGrid = baseGrid
        self.duration = duration
        self.seed = seed
        self.schedule = schedule
        self.characterSet = characterSet
    }

    public func grid(at time: TimeInterval) -> ASCIIGrid {
        guard baseGrid.rows > 0, baseGrid.columns > 0 else {
            return baseGrid
        }
        let resolvedTime = time.isFinite ? max(0, time) : 0
        var rows: [[ASCIICell]] = []
        rows.reserveCapacity(baseGrid.rows)

        for row in 0..<baseGrid.rows {
            var line: [ASCIICell] = []
            line.reserveCapacity(baseGrid.columns)
            for column in 0..<baseGrid.columns {
                let cellIndex = row * baseGrid.columns + column
                let baseCell = baseGrid.cells[row][column]
                let candidateSlot = selectedCandidateSlot(cellIndex: cellIndex, time: resolvedTime)
                // Construction-time guarantee: the only production construction
                // path, `ASCIIConverter.animate`, passes the same grid to
                // `ScheduleBuilder.build` and this initializer. The builder
                // preconditions candidate storage against that grid's cell count.
                let characterIndex = Int(schedule.candidates[cellIndex * schedule.candidateStride + candidateSlot])
                let coord = AnimationCellCoordinate(
                    column: column,
                    row: row,
                    columns: baseGrid.columns,
                    rows: baseGrid.rows
                )
                let entranceAlpha =
                    schedule.entrance.map {
                        PatternEvaluator.entranceAlpha($0, coord: coord, time: resolvedTime, duration: duration)
                    } ?? 1
                let ongoingAlpha =
                    schedule.ongoing.map {
                        PatternEvaluator.ongoingAlpha($0, coord: coord, time: resolvedTime)
                    } ?? 1
                let alpha = baseCell.alpha * Float(PatternEvaluator.clampUnit(entranceAlpha * ongoingAlpha, fallback: 1))
                line.append(
                    ASCIICell(
                        character: characterSet[characterIndex],
                        displayColor: baseCell.displayColor,
                        alpha: alpha,
                        brightness: baseCell.brightness,
                        coverage: baseCell.coverage
                    ))
            }
            rows.append(line)
        }

        return ASCIIGrid(
            cells: rows,
            colorSpace: baseGrid.colorSpace,
            composition: baseGrid.composition,
            maskFallback: baseGrid.maskFallback,
            maskGroundColor: baseGrid.maskGroundColor,
            maskUsesHardEdges: baseGrid.maskUsesHardEdges
        )
    }

    /// Upper bound on the number of grids a single `materialize(frameRate:)`
    /// call will allocate.
    ///
    /// One full `ASCIIGrid` is built per frame, so an unbounded
    /// `duration * frameRate` exhausts memory long before the frame index
    /// overflows `Int`. `Tools/AskiToolSupport` reuses this value so the labs
    /// pre-check and the library contract cannot drift apart.
    public static let maxMaterializedFrameCount = 10_000

    /// Renders the animation as one grid per cadence step, plus the endpoint.
    ///
    /// - Precondition: `frameRate > 0`, and `duration * frameRate` yields at
    ///   most ``maxMaterializedFrameCount`` frames. An oversized request is
    ///   rejected, never truncated — silently returning a shorter animation
    ///   than the caller asked for would be a worse failure than a visible one.
    ///
    ///   This agrees with the ASKI-6 rule for ``grid(at:)`` rather than
    ///   contradicting it. `grid(at:)` stays total for every finite time, and
    ///   no `duration` that `AnimationOptions` accepts is unsupported here
    ///   either: what is bounded is the *frame count* of one call, not the
    ///   duration. Any accepted duration remains fully reachable through
    ///   `grid(at:)`, or through `materialize(frameRate:)` at a `frameRate`
    ///   low enough to fit the bound.
    public func materialize(frameRate: Int) -> [ASCIIGrid] {
        precondition(frameRate > 0, "frameRate must be positive")
        let scaledDuration = duration * Double(frameRate)
        // Decide the cadence in `Double` first, then bound the *exact* count it
        // implies. A looser bound (`ceil(scaledDuration) + 1`) rejects a request
        // that lands on the cap: an endpoint a few ULPs above a whole frame is
        // snapped back onto that frame below, so it costs one frame, not two.
        let nearestWholeFrame = scaledDuration.rounded(.toNearestOrAwayFromZero)
        let tolerance = max(scaledDuration.ulp * 8, Double.ulpOfOne)
        let endpointFallsOnFrame = nearestWholeFrame > 0 && abs(scaledDuration - nearestWholeFrame) <= tolerance
        let lastCadenceStep = max(0, endpointFallsOnFrame ? nearestWholeFrame : floor(scaledDuration))
        // One grid per cadence step from zero, plus the endpoint when it does
        // not already coincide with the last step. `.infinity` for a
        // non-finite product, which the cap then rejects.
        let frameCount = scaledDuration.isFinite ? lastCadenceStep + (endpointFallsOnFrame ? 1 : 2) : .infinity
        precondition(
            frameCount <= Double(Self.maxMaterializedFrameCount),
            "AnimatedASCIIGrid.materialize(frameRate:) would produce more than \(Self.maxMaterializedFrameCount) frames for duration \(duration) at \(frameRate) fps"
        )
        // Safe now: the cap has bounded `lastCadenceStep` above, and `max(0:)`
        // bounded it below, so the conversion cannot trap.
        let lastCadenceIndex = Int(lastCadenceStep)
        var frames = (0...lastCadenceIndex).map { index in
            grid(at: Double(index) / Double(frameRate))
        }
        if !endpointFallsOnFrame {
            frames.append(grid(at: duration))
        }
        return frames
    }

    private func selectedCandidateSlot(cellIndex: Int, time: TimeInterval) -> Int {
        guard schedule.participates.contains(cellIndex), schedule.candidateStride > 1 else {
            return 0
        }
        let period = max(Double(schedule.periods[cellIndex]), Double.leastNonzeroMagnitude)
        let phase = Double(schedule.phases[cellIndex])
        let progress = ((time + phase) / period).truncatingRemainder(dividingBy: 1)
        // ASKI-6: `time` is only guaranteed finite, so `time + phase` can
        // overflow to infinity and the remainder can then be NaN. The slot is
        // derived arithmetic rather than a caller-supplied knob, so it
        // saturates to the first slot instead of trapping in `Int(_:)`.
        guard progress.isFinite else { return 0 }
        let slot = Int(floor(progress * Double(schedule.candidateStride)))
        return min(max(slot, 0), schedule.candidateStride - 1)
    }
}
