import Foundation

internal enum ScheduleBuilder {
    // Fraction of the base period the per-cell jitter may add or remove.
    // `CyclingOptions.minSpeed`/`maxSpeed` budget for this margin.
    internal static let periodJitterFraction = 0.25

    static func build(
        baseGrid: ASCIIGrid,
        candidates: ContiguousArray<UInt16>,
        candidateStride: Int,
        candidateCounts: ContiguousArray<UInt16>,
        characterSet: CharacterSetSnapshot,
        options: AnimationOptions
    ) -> AnimationSchedule {
        let characterCount = characterSet.characters.count
        precondition(characterCount >= 1 && characterCount <= Int(UInt16.max), "Aski animation requires 1...65,535 characters in the character set")
        precondition(candidateStride > 0, "candidateStride must be positive")
        options.ongoing?.validate()
        if let cycling = options.cycling {
            precondition(cycling.k > 0, "CyclingOptions.k must be positive")
            cycling.validateSpeed()
        }

        let cellCount = baseGrid.rows * baseGrid.columns
        precondition(candidates.count == cellCount * candidateStride, "candidates must be cellCount * candidateStride")
        precondition(candidateCounts.count == cellCount, "candidateCounts must match cell count")
        let resolvedCycling = normalizedCycling(options.cycling)
        var phases = ContiguousArray<Float>(repeating: 0, count: cellCount)
        var periods = ContiguousArray<Float>(repeating: 1, count: cellCount)
        var participates = BitSet(count: cellCount)

        for row in 0..<baseGrid.rows {
            for column in 0..<baseGrid.columns {
                let cellIndex = row * baseGrid.columns + column
                let distinctCount = Int(candidateCounts[cellIndex])

                guard let cycling = resolvedCycling else {
                    continue
                }

                let basePeriod = 1.0 / cycling.speed
                periods[cellIndex] = Float(
                    jitteredPeriod(
                        basePeriod: basePeriod,
                        randomness: cycling.randomness,
                        seed: options.seed,
                        row: row,
                        column: column
                    ))
                phases[cellIndex] = Float(
                    phase(
                        basePeriod: basePeriod,
                        randomness: cycling.randomness,
                        seed: options.seed,
                        row: row,
                        column: column
                    ))

                let coverage = baseGrid.cells[row][column].coverage
                let intensityRoll = SplitMix64.unitDouble(seed: options.seed, row: row, column: column, salt: .intensity)
                participates.set(
                    cellIndex,
                    to: coverage > 0 && intensityRoll < cycling.intensity && distinctCount >= 2
                )
            }
        }

        return AnimationSchedule(
            candidates: candidates,
            candidateStride: candidateStride,
            phases: phases,
            periods: periods,
            participates: participates,
            entrance: options.entrance,
            ongoing: options.ongoing,
            cycling: resolvedCycling,
            duration: options.duration,
            seed: options.seed,
            columns: baseGrid.columns,
            rows: baseGrid.rows
        )
    }

    private static func normalizedCycling(_ cycling: CyclingOptions?) -> CyclingOptions? {
        guard var cycling else { return nil }
        cycling.intensity = PatternEvaluator.sanitizedClamped(cycling.intensity, min: 0, max: 1, defaultValue: 0.6)
        cycling.randomness = PatternEvaluator.sanitizedClamped(cycling.randomness, min: 0, max: 1, defaultValue: 0.5)
        return cycling
    }

    private static func jitteredPeriod(
        basePeriod: Double,
        randomness: Double,
        seed: UInt64,
        row: Int,
        column: Int
    ) -> Double {
        let jitter = (SplitMix64.unitDouble(seed: seed, row: row, column: column, salt: .period) - 0.5) * 2
        return basePeriod * (1 + randomness * periodJitterFraction * jitter)
    }

    private static func phase(
        basePeriod: Double,
        randomness: Double,
        seed: UInt64,
        row: Int,
        column: Int
    ) -> Double {
        let positional = (Double(row + column) * 0.05).truncatingRemainder(dividingBy: 1)
        let random = SplitMix64.unitDouble(seed: seed, row: row, column: column, salt: .phase)
        return ((1 - randomness) * positional + randomness * random) * basePeriod
    }
}
