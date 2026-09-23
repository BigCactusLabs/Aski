internal struct CellMatchResult: Sendable {
    let winnerCharacter: Character
    let winnerIndex: Int
    let rankedIndices: ContiguousArray<Int>
}
