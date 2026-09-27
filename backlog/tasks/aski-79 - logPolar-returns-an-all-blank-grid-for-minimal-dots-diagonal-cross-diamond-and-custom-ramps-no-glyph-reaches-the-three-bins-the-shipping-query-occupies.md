---
id: ASKI-79
title: >-
  logPolar returns an all-blank grid for minimal, dots, diagonal, cross, diamond
  and custom ramps: no glyph reaches the three bins the shipping query occupies
status: In Progress
assignee: []
created_date: '2026-09-27 17:35'
updated_date: '2026-09-27 20:42'
labels:
  - correctness
  - algorithms
  - matcher
  - glyphs
  - docs
dependencies: []
references:
  - docs/Research/2026-08-19-sampling-lattice-support-collapse.md
  - Sources/Aski/Algorithms/LogPolarKernel.swift
  - Sources/Aski/Algorithms/ShapeContext.swift
  - Sources/Aski/Aski.docc/Algorithms.md
priority: high
type: bug
ordinal: 80000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MEASURE-FIRST. Found 2026-09-27 while choosing glyphs for the bcl-web canyon strip (Aski HEAD 6b6d251).

SYMPTOM
`aski render <image> --columns 80 --charset minimal` (also dots, diagonal, cross, diamond) prints only spaces. Measured: 100% blank cells for those five built-ins and for a RasterizedCharacterSet ramp " .·:;-=+*xX#" rasterized from IBM Plex Mono, on AskiBench/corpus/nasa/nasa-nasa-steerable-v1-vavilov-crater.png, AskiBench/corpus/nasa/nasa-nasa-occupancy-v1-cernan-portrait.jpg and a bcl-web photo (img/ashim-d-silva-WeYamle9fDM-unsplash.jpg), at 80 and 288 columns, under both `shapeQueryPolarity` values. blocks, lines, mixed, braille and standard are not blank.

MECHANISM (verified with the `@_spi(AskiResearch)` `cellQueryDescriptors` and each set's `shapeVectorLanes`)
- At the shipping footprint every query descriptor occupies only bins 51, 54 and 56 (radial ring 4, angular bins 3, 6, 8): the ASKI-55 2-3/60 support collapse. Median 3 occupied bins per cell, max 3, at both 80 and 288 columns.
- No non-blank glyph in minimal, dots, diagonal, cross, diamond or the custom ramp has any mass in those three bins. So q·g = 0 and d(q,g) = |q|² + |g|² > |q|² = d(q, blank) for every glyph.
- The blank therefore wins every cell by exactly min|g|² over the set (0.052 minimal, 0.044 dots, 0.066 diagonal, 0.055 cross, 0.041 diamond, 0.051 custom ramp). The margin is a constant of the charset and never depends on the image.
- The tone pre-filter cannot rescue it: these sets hold at most 12 glyphs, so the topK=12 pool always admits the blank (ASKI-28).
- Direct polarity does not change it: the query still reaches only those bins, and dark cells additionally go to the all-zero descriptor (2% of cells on the bcl-web photo, 14-17% on the NASA fixtures).

This is very likely the "undiagnosed degeneracy" recorded on ASKI-61 (minimal/dots/cross/diamond/diagonal all at an identical 0.24754 MAE under both polarities): an all-blank grid scores the same whatever the charset.

PUBLIC DOCS ARE WRONG TODAY
Algorithms.md "Recommended pairings" and the `ASCIIAlgorithm.logPolar` doc comment recommend logPolar with minimal and dots. Both produce blank output.

REPRO (in-repo)
for c in minimal dots diagonal cross diamond blocks; do .build/release/aski render AskiBench/corpus/nasa/nasa-nasa-steerable-v1-vavilov-crater.png --columns 80 --charset $c | tr -d ' \n' | wc -c; done
(prints 0 for the first five). Library level: `ASCIIConverter(characterSet: .minimal, palette: BuiltInPalette.monochrome).cellQueryDescriptors(image, columns: 80)`, then take each cell's lanes against `characterSet.shapeVectorLanes`: every non-blank dot product is 0.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A test pins the cause: for each built-in charset, whether any non-blank glyph has mass in the descriptor bins reachable at the shipping footprint, and that no recommended pairing yields an all-blank grid on a real fixture
- [x] #2 The fix is chosen under a rule pre-registered before the decisive run (candidates: restore descriptor support per ASKI-55; fall back to tone ranking when the query is orthogonal to every pooled candidate, as degenerateToneRanking already does for 1-pixel footprints; keep the blank out of shape argmin unless tone selects it; stop recommending the pairing); any golden move carries the no-harm selection-ceiling census
- [x] #3 Algorithms.md pairing table and the ASCIIAlgorithm.logPolar doc comment match measured behavior
- [x] #4 A custom RasterizedCharacterSet whose glyphs miss the reachable bins gets non-blank output or a documented diagnostic, not a silent all-blank grid
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Batch 79-82. Phase 1 (50d619f) pinned the cause: LogPolarReachableSupportTests shows no non-blank glyph in minimal, dots, diagonal, cross or diamond has mass in the reachable bins (51, 54, 56), so the blank wins every cell. Fix chosen under the rule frozen at 40bafb0: arm 1 (orthogonal cell falls back to the tone-nearest pooled glyph) was KILLed. It removed the all-blank grid on every fixture but raised standard MAE x1.0301-1.0423 on both PNG corpora (KILL bar 1.0300); GMSD x1.15-1.43. Production unchanged, no golden moved. Closed by documentation per rule section 6: logPolar recommended with standard and braille only; Algorithms.md, CharacterSets.md, GettingStarted.md, CommandLine.md, the ASCIIAlgorithm.logPolar and RasterizedCharacterSet doc comments updated; custom-set examples pass .dotMatrix. AC#4: documented diagnostic plus a test for a custom RasterizedCharacterSet missing the reachable bins. Evidence: docs/Research/2026-09-27-aski-79-80-orthogonality-fallback.md.
<!-- SECTION:NOTES:END -->
