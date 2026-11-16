// Type-check this exact API against each compiler and deployment floor.
func scopedHistogramProbe() -> Float {
    withUnsafeTemporaryAllocation(of: Float.self, capacity: 60) { histogram in
        histogram.initialize(repeating: 0)
        histogram[59] += 1
        return histogram.reduce(Float.zero, +)
    }
}
