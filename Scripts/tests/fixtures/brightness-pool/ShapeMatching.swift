import simd

public enum ShapeMatching {
    /// Returns the brightness pre-filter pool used by log-polar shape matching.
    ///
    /// This is SPI for research harnesses that need to characterize the
    /// candidate pool without changing matcher behavior. Ordering is brightness
    /// delta ascending, then candidate index ascending.
    @_spi(AskiResearch)
    public static func poolIndices(
        queryBrightness: Float,
        candidateBrightness: [Float],
        topK: Int
    ) -> [Int] {
        let count = candidateBrightness.count
        precondition(count > 0, "candidate set must not be empty")
        precondition(topK > 0, "topK must be positive")

        var pairs: [(index: Int, brightnessDelta: Float)] = []
        pairs.reserveCapacity(count)
        for index in 0..<count {
            pairs.append((index, abs(candidateBrightness[index] - queryBrightness)))
        }
        pairs.sort {
            if $0.brightnessDelta == $1.brightnessDelta {
                return $0.index < $1.index
            }
            return $0.brightnessDelta < $1.brightnessDelta
        }
        return pairs.prefix(min(topK, count)).map(\.index)
    }

    /// Finds ranked character indices.
    ///
    /// Ordering is shape distance ascending, then brightness delta ascending,
    /// then candidate index ascending. With `resultLimit == 1` and the same
    /// brightness limit as `findBest(topK:)`, the first result preserves the
    /// existing winner semantics.
    public static func findRanked(
        queryLanes: [SIMD4<Float>],
        queryBrightness: Float,
        candidateBrightness: [Float],
        candidateLanes: [SIMD4<Float>],
        brightnessLimit: Int,
        resultLimit: Int
    ) -> [Int] {
        let lanesPerCharacter = StandardCharacterSet.lanesPerCharacter
        let shapeVectorDimension = lanesPerCharacter * 4
        precondition(
            queryLanes.count == lanesPerCharacter,
            "query must be \(lanesPerCharacter) SIMD4 lanes (\(shapeVectorDimension)D)"
        )
        let count = candidateBrightness.count
        precondition(count > 0, "candidate set must not be empty")
        precondition(brightnessLimit > 0, "brightnessLimit must be positive")
        precondition(resultLimit > 0, "resultLimit must be positive")
        precondition(
            candidateLanes.count == count * lanesPerCharacter,
            "candidate lanes must be count * \(lanesPerCharacter)"
        )

        var brightnessPairs: [(index: Int, brightnessDelta: Float)] = []
        brightnessPairs.reserveCapacity(count)
        for index in 0..<count {
            brightnessPairs.append((index, abs(candidateBrightness[index] - queryBrightness)))
        }
        brightnessPairs.sort {
            if $0.brightnessDelta == $1.brightnessDelta {
                return $0.index < $1.index
            }
            return $0.brightnessDelta < $1.brightnessDelta
        }

        var scored: [(index: Int, distance: Float, brightnessDelta: Float)] = []
        scored.reserveCapacity(min(brightnessLimit, count))
        for pair in brightnessPairs.prefix(min(brightnessLimit, count)) {
            let laneOffset = pair.index * lanesPerCharacter
            var distance: Float = 0
            for laneIndex in 0..<lanesPerCharacter {
                let delta = queryLanes[laneIndex] - candidateLanes[laneOffset + laneIndex]
                distance += simd_dot(delta, delta)
            }
            scored.append((pair.index, distance, pair.brightnessDelta))
        }

        scored.sort {
            if $0.distance == $1.distance {
                if $0.brightnessDelta == $1.brightnessDelta {
                    return $0.index < $1.index
                }
                return $0.brightnessDelta < $1.brightnessDelta
            }
            return $0.distance < $1.distance
        }

        return scored.prefix(min(resultLimit, scored.count)).map(\.index)
    }

    /// Returns the index and squared-L2 shape distance of the best-matching
    /// character. Mirrors `findBest` exactly — same selection logic, same
    /// brightness pre-filter — but surfaces the discarded distance so research
    /// harnesses can map per-cell shape residual without touching the hot path.
    @inlinable
    public static func findBestScored(
        queryLanes: [SIMD4<Float>],
        queryBrightness: Float,
        candidateBrightness: [Float],
        candidateLanes: [SIMD4<Float>],
        topK: Int
    ) -> (index: Int, distance: Float) {
        let lanesPerCharacter = StandardCharacterSet.lanesPerCharacter
        let shapeVectorDimension = lanesPerCharacter * 4
        precondition(
            queryLanes.count == lanesPerCharacter,
            "query must be \(lanesPerCharacter) SIMD4 lanes (\(shapeVectorDimension)D)"
        )
        let count = candidateBrightness.count
        precondition(count > 0, "candidate set must not be empty")
        precondition(topK > 0, "topK must be positive")
        precondition(
            candidateLanes.count == count * lanesPerCharacter,
            "candidate lanes must be count * \(lanesPerCharacter)"
        )

        var pairs: [(index: Int, brightnessDelta: Float)] = []
        pairs.reserveCapacity(count)
        for index in 0..<count {
            pairs.append((index, abs(candidateBrightness[index] - queryBrightness)))
        }
        pairs.sort {
            if $0.brightnessDelta == $1.brightnessDelta {
                return $0.index < $1.index
            }
            return $0.brightnessDelta < $1.brightnessDelta
        }

        var bestIndex = pairs[0].index
        var bestDistance = Float.infinity
        for pair in pairs.prefix(min(topK, count)) {
            let laneOffset = pair.index * lanesPerCharacter
            var distance: Float = 0
            for laneIndex in 0..<lanesPerCharacter {
                let delta = queryLanes[laneIndex] - candidateLanes[laneOffset + laneIndex]
                distance += simd_dot(delta, delta)
            }
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = pair.index
            }
        }
        return (bestIndex, bestDistance)
    }

    /// Returns each ranked candidate paired with its squared-L2 shape distance.
    /// Mirrors `findRanked` exactly — same ordering (shape distance ascending,
    /// then brightness delta ascending, then candidate index ascending) — but
    /// surfaces the distances so research harnesses can inspect per-cell
    /// residuals without touching the production path.
    public static func findRankedScored(
        queryLanes: [SIMD4<Float>],
        queryBrightness: Float,
        candidateBrightness: [Float],
        candidateLanes: [SIMD4<Float>],
        brightnessLimit: Int,
        resultLimit: Int
    ) -> [(index: Int, distance: Float)] {
        let lanesPerCharacter = StandardCharacterSet.lanesPerCharacter
        let shapeVectorDimension = lanesPerCharacter * 4
        precondition(
            queryLanes.count == lanesPerCharacter,
            "query must be \(lanesPerCharacter) SIMD4 lanes (\(shapeVectorDimension)D)"
        )
        let count = candidateBrightness.count
        precondition(count > 0, "candidate set must not be empty")
        precondition(brightnessLimit > 0, "brightnessLimit must be positive")
        precondition(resultLimit > 0, "resultLimit must be positive")
        precondition(
            candidateLanes.count == count * lanesPerCharacter,
            "candidate lanes must be count * \(lanesPerCharacter)"
        )

        var brightnessPairs: [(index: Int, brightnessDelta: Float)] = []
        brightnessPairs.reserveCapacity(count)
        for index in 0..<count {
            brightnessPairs.append((index, abs(candidateBrightness[index] - queryBrightness)))
        }
        brightnessPairs.sort {
            if $0.brightnessDelta == $1.brightnessDelta {
                return $0.index < $1.index
            }
            return $0.brightnessDelta < $1.brightnessDelta
        }

        var scored: [(index: Int, distance: Float, brightnessDelta: Float)] = []
        scored.reserveCapacity(min(brightnessLimit, count))
        for pair in brightnessPairs.prefix(min(brightnessLimit, count)) {
            let laneOffset = pair.index * lanesPerCharacter
            var distance: Float = 0
            for laneIndex in 0..<lanesPerCharacter {
                let delta = queryLanes[laneIndex] - candidateLanes[laneOffset + laneIndex]
                distance += simd_dot(delta, delta)
            }
            scored.append((pair.index, distance, pair.brightnessDelta))
        }

        scored.sort {
            if $0.distance == $1.distance {
                if $0.brightnessDelta == $1.brightnessDelta {
                    return $0.index < $1.index
                }
                return $0.brightnessDelta < $1.brightnessDelta
            }
            return $0.distance < $1.distance
        }

        return scored.prefix(min(resultLimit, scored.count)).map { ($0.index, $0.distance) }
    }

    /// Finds the index of the best-matching character.
    @inlinable
    public static func findBest(
        queryLanes: [SIMD4<Float>],
        queryBrightness: Float,
        candidateBrightness: [Float],
        candidateLanes: [SIMD4<Float>],
        topK: Int
    ) -> Int {
        findBestScored(
            queryLanes: queryLanes,
            queryBrightness: queryBrightness,
            candidateBrightness: candidateBrightness,
            candidateLanes: candidateLanes,
            topK: topK
        ).index
    }

}
