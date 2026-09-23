internal struct BitSet: Sendable, Equatable {
    let count: Int
    private var words: [UInt64]

    init(count: Int) {
        self.count = max(0, count)
        self.words = Array(repeating: 0, count: (max(0, count) + 63) / 64)
    }

    mutating func set(_ index: Int, to value: Bool) {
        precondition(index >= 0 && index < count, "BitSet index out of bounds")
        let wordIndex = index / 64
        let bit = UInt64(1) << UInt64(index % 64)
        if value {
            words[wordIndex] |= bit
        } else {
            words[wordIndex] &= ~bit
        }
    }

    func contains(_ index: Int) -> Bool {
        precondition(index >= 0 && index < count, "BitSet index out of bounds")
        let wordIndex = index / 64
        let bit = UInt64(1) << UInt64(index % 64)
        return (words[wordIndex] & bit) != 0
    }
}
