---
id: ASKI-23
title: >-
  StandardCharacterSet.parse can desynchronize characters from its matching
  arrays
status: Done
assignee: []
created_date: '2026-08-19 05:24'
updated_date: '2026-08-20 04:14'
labels:
  - correctness
  - character-sets
  - input-validation
dependencies: []
references:
  - Sources/Aski/CharacterSets/StandardCharacterSet.swift
  - Sources/Aski/Algorithms/EdgeMapKernel.swift
  - Sources/Aski/Algorithms/DotMatrixKernel.swift
  - Sources/Aski/ASCIICharacterSet.swift
priority: low
type: bug
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`StandardCharacterSet.parse` reads `charCount` scalars but only appends the ones that survive `Unicode.Scalar(scalar)`:

    for _ in 0..<charCount {
        let scalar = try readU32()
        if let s = Unicode.Scalar(scalar) { characters.append(Character(s)) }
    }

It then reads the brightness, lane, raw-density and structure-channel blocks at the FULL `charCount`. A .bin carrying a surrogate or out-of-range scalar therefore yields `characters.count < brightnessValues.count`, silently violating the `ASCIICharacterSet` contract that all per-glyph arrays are parallel.

Downstream, matcher indices are derived from `candidateBrightness.count`, so they can exceed `characters.count`. `LogPolarKernel.character(at:)` bounds-checks and falls back to space, but `EdgeMapKernel.pickScored` and `DotMatrixKernel.pick` index `characterSet.characters[bestIndex]` directly — an out-of-bounds trap. `resolveBlankGlyphIndex` searches `brightnessValues.indices` and can likewise return an index past the end.

Not reachable through the shipped resources: the checked-in .bin files are well-formed, and `parse(data:setName:)` is internal (only in-module callers and @testable tests reach it with arbitrary bytes). Filing it because it is a parser silently producing a value that breaks a documented invariant rather than throwing, and because the guarded and unguarded index sites disagree about whether that invariant can be trusted.

The same file already throws `LoadError.truncated`, `.badMagic`, `.badDimension` and `.unknownVersion` for other malformed input, so the missing case fits an existing pattern.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 parse throws a LoadError for a .bin whose scalar block contains a value that is not a valid Unicode scalar, rather than returning a set with mismatched array lengths
- [x] #2 Any StandardCharacterSet parse returns with characters.count == brightnessValues.count == rawDensityValues.count and shapeVectorLanes.count == characters.count * lanesPerCharacter, and the structure-channel and steerable arrays match when present
- [x] #3 EdgeMapKernel and DotMatrixKernel either bounds-check their characters[index] reads the way LogPolarKernel.character(at:) does, or the invariant is documented as a parser-enforced precondition they may rely on
- [x] #4 Regression feeds a hand-built .bin containing a surrogate scalar and asserts the thrown error; the shipped built-in sets load byte-identically
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Landed in merge commit da78b1a (Batch A).

StandardCharacterSet.parse silently skipped scalars that failed Unicode.Scalar(_:) while reading every other per-glyph block at full charCount, leaving characters shorter than its parallel arrays. It now throws LoadError.invalidScalar (a new case). This was a live out-of-bounds trap, not a theoretical one: the matcher kernels derive an index from brightnessValues and use it to subscript characters unchecked.

AC#3 offered two routes — bounds-check the kernels, or document the invariant as a parser-enforced precondition they may rely on. This takes the DOCUMENTED route: the parallel-array rule is now stated on the public ASCIICharacterSet protocol and repeated at each unchecked read (AlgorithmKernel.swift:57, DotMatrixKernel.swift:68, EdgeMapKernel.swift:99). The bounds-check route adds a branch to the hottest loop in the library to defend against a conformance nobody has written.

Reviewer-visible consequence: ASCIICharacterSet is public, so an EXTERNAL conformance that breaks the invariant traps by design. Both in-repo conformances hold it — RasterizedCharacterSet builds every array in one loop over characters, verified rather than assumed.

loadOrFatal wraps load, so a caller-supplied set surfaces LoadError.invalidScalar as a thrown error while the bundled-resource path keeps its fatalError. That bundled fatalError is in scope for ASKI-36, not here.

Coverage: StandardCharacterSetScalarValidationTests feeds a hand-built .bin containing a surrogate scalar and asserts the thrown error; a companion test anchors the shipped built-in sets to their exact loaded bytes, so 'the built-ins still load' is proven positively rather than inferred.
<!-- SECTION:NOTES:END -->
