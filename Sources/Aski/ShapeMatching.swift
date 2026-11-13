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

        let pairs = brightnessPool(queryBrightness: queryBrightness, candidateBrightness: candidateBrightness, limit: topK)
        return pairs.prefix(min(topK, count)).map(\.index)
    }

    /// Retain the K best brightness pairs, with the worst retained pair at
    /// the heap root. Callers consume the selected prefix in the old order.
    @usableFromInline
    internal static func brightnessPool(
        queryBrightness: Float,
        candidateBrightness: [Float],
        limit: Int
    ) -> [(index: Int, brightnessDelta: Float)] {
        func precedes(_ lhs: (index: Int, brightnessDelta: Float), _ rhs: (index: Int, brightnessDelta: Float)) -> Bool {
            if lhs.brightnessDelta == rhs.brightnessDelta {
                return lhs.index < rhs.index
            }
            return lhs.brightnessDelta < rhs.brightnessDelta
        }

        let count = candidateBrightness.count
        // Preserve the existing sort for full pools and unordered inputs.
        if limit >= count || !queryBrightness.isFinite
            || candidateBrightness.contains(where: { !$0.isFinite })
        {
            var pairs: [(index: Int, brightnessDelta: Float)] = []
            pairs.reserveCapacity(count)
            for index in 0..<count {
                pairs.append((index, abs(candidateBrightness[index] - queryBrightness)))
            }
            pairs.sort(by: precedes)
            return pairs
        }

        var selected: [(index: Int, brightnessDelta: Float)] = []
        selected.reserveCapacity(limit)
        for index in candidateBrightness.indices {
            let entry = (index: index, brightnessDelta: abs(candidateBrightness[index] - queryBrightness))
            if selected.count < limit {
                selected.append(entry)
                var child = selected.count - 1
                while child > 0 {
                    let parent = (child - 1) / 2
                    guard precedes(selected[parent], selected[child]) else { break }
                    selected.swapAt(parent, child)
                    child = parent
                }
            } else if precedes(entry, selected[0]) {
                selected[0] = entry
                var parent = 0
                while parent * 2 + 1 < selected.count {
                    var child = parent * 2 + 1
                    if child + 1 < selected.count && precedes(selected[child], selected[child + 1]) {
                        child += 1
                    }
                    guard precedes(selected[parent], selected[child]) else { break }
                    selected.swapAt(parent, child)
                    parent = child
                }
            }
        }
        selected.sort(by: precedes)
        return selected
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

        let brightnessPairs = brightnessPool(
            queryBrightness: queryBrightness, candidateBrightness: candidateBrightness, limit: brightnessLimit)

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

        let pairs = brightnessPool(queryBrightness: queryBrightness, candidateBrightness: candidateBrightness, limit: topK)

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

        let brightnessPairs = brightnessPool(
            queryBrightness: queryBrightness, candidateBrightness: candidateBrightness, limit: brightnessLimit)

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
