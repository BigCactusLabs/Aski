internal struct CharacterSetSnapshot: Sendable, Equatable {
    let characters: ContiguousArray<Character>

    init<C: Collection>(characters: C) where C.Element == Character {
        self.characters = ContiguousArray(characters)
    }

    subscript(index: Int) -> Character {
        characters[index]
    }
}
