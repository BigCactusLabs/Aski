/// Lab-only ASKI-88 arms. This file is NOT a member of any repository target.
/// The probe copies it into a disposable module beside the extracted control.
public enum PoolSelectionArms {
    private struct Entry {
        let index: Int
        let distance: Float
    }

    private static func precedes(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.distance == rhs.distance { return lhs.index < rhs.index }
        return lhs.distance < rhs.distance
    }

    private static func useControl(query: Float, values: [Float], limit: Int) -> Bool {
        precondition(!values.isEmpty && limit > 0)
        // Keep the old sort for a full pool or unordered input. This does not
        // make NaN ordering well-defined; it avoids inventing new behavior.
        // The O(N) finite scan is part of the measured cost, not hidden setup.
        return limit >= values.count || !query.isFinite || values.contains { !$0.isFinite }
    }

    public static func insertion(query: Float, values: [Float], limit: Int) -> [Int] {
        if useControl(query: query, values: values, limit: limit) {
            return ShapeMatching.poolIndices(queryBrightness: query, candidateBrightness: values, topK: limit)
        }
        var selected: [Entry] = []
        selected.reserveCapacity(limit)
        for index in values.indices {
            let entry = Entry(index: index, distance: abs(values[index] - query))
            if selected.count == limit && !precedes(entry, selected[limit - 1]) { continue }
            var low = 0
            var high = selected.count
            while low < high {
                let middle = low + (high - low) / 2
                if precedes(selected[middle], entry) { low = middle + 1 } else { high = middle }
            }
            if selected.count == limit { selected.removeLast() }
            selected.insert(entry, at: low)
        }
        return selected.map(\.index)
    }

    public static func heap(query: Float, values: [Float], limit: Int) -> [Int] {
        if useControl(query: query, values: values, limit: limit) {
            return ShapeMatching.poolIndices(queryBrightness: query, candidateBrightness: values, topK: limit)
        }
        var selected: [Entry] = []
        selected.reserveCapacity(limit)
        for index in values.indices {
            let entry = Entry(index: index, distance: abs(values[index] - query))
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
                    if child + 1 < selected.count && precedes(selected[child], selected[child + 1]) { child += 1 }
                    guard precedes(selected[parent], selected[child]) else { break }
                    selected.swapAt(parent, child)
                    parent = child
                }
            }
        }
        selected.sort(by: precedes)
        return selected.map(\.index)
    }
}
