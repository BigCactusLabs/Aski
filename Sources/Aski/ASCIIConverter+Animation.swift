import CoreGraphics

public extension ASCIIConverter {
    func animate(
        _ image: CGImage,
        columns: Int,
        options: AnimationOptions,
        mask: MaskOptions? = nil
    ) -> AnimatedASCIIGrid {
        let characterCount = glyphBank.characters.count
        precondition(characterCount >= 1 && characterCount <= Int(UInt16.max), "Aski animation requires 1...65,535 characters in the character set")

        // `AnimationOptions.ongoing` and `.cycling` are public `var`s, so a
        // valid options value can be mutated out of domain after construction.
        // Re-check both here, at the entry point, rather than trusting the
        // initializer (ASKI-18).
        options.ongoing?.validate()

        let snapshot = CharacterSetSnapshot(characters: glyphBank.characters)
        let candidateStride: Int
        if let cycling = options.cycling {
            precondition(cycling.k > 0, "CyclingOptions.k must be positive")
            cycling.validateSpeed()
            candidateStride = max(1, min(cycling.k, characterCount))
        } else {
            candidateStride = 1
        }

        let ranked = convertWithRankedCandidates(
            image,
            columns: columns,
            candidateStride: candidateStride,
            mask: mask
        )
        let schedule = ScheduleBuilder.build(
            baseGrid: ranked.grid,
            candidates: ranked.candidates,
            candidateStride: ranked.candidateStride,
            candidateCounts: ranked.candidateCounts,
            characterSet: snapshot,
            options: options
        )

        return AnimatedASCIIGrid(
            baseGrid: ranked.grid,
            duration: options.duration,
            seed: options.seed,
            schedule: schedule,
            characterSet: snapshot
        )
    }
}
