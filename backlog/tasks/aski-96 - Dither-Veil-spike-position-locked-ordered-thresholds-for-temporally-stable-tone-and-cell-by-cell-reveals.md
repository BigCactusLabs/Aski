---
id: ASKI-96
title: >-
  Dither Veil spike: position-locked ordered thresholds for temporally stable
  tone and cell-by-cell reveals
status: To Do
assignee: []
created_date: '2026-10-13 03:00'
labels:
  - research
  - animation
  - masking
  - dither
dependencies: []
references:
  - 'https://reactbits.dev/animations/dither-veil'
  - >-
    https://github.com/DavidHDev/react-bits/blob/1eeb6f105c68b964289d85dabbe84a1d551f3797/src/content/Animations/DitherVeil/DitherVeil.jsx
  - Sources/Aski/RenderingOptions.swift
  - Sources/Aski/GridRowWalk.swift
  - Sources/Aski/Animation/PatternEvaluator.swift
  - Sources/Aski/Masking/MaskOptions.swift
priority: low
type: spike
ordinal: 97000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
React Bits' Dither Veil (source read at react-bits 1eeb6f1, 2026-09-27) renders a photo as a 1-bit or N-level dither in ink/paper duotone; the pointer paints a decaying trail mask that reveals the full-colour photo, and each cell flips when the mask value passes that cell's own 8x8 Bayer rank, so the veil opens and closes cell by cell instead of along a smooth edge. Other parts: tone patterns Bayer 8x8, a 64x64 void-and-cluster blue-noise rank texture, an engraving diagonal-line threshold, and CPU serpentine Floyd-Steinberg or Atkinson diffusion; an optional rim-colour band between rank thresholds; click shockwave rings; a radial intro with Bayer jitter; and a border-variance check that keys out plain backgrounds.

Two ideas look transferable to Aski. They are hypotheses until Aski measures them:

1. Ordered thresholds for tone. dotMatrix diffuses Floyd-Steinberg error serially (GridRowWalk.swift), so a change in one cell moves picks downstream and the cells cannot be scored in parallel. An ordered threshold (Bayer or blue-noise rank) depends only on cell position. It should give lower frame-to-frame churn in motion and video, and a parallel walk, at some cost in static MAE. The ASTSK-41/45 hysteresis line failed on scene-dependent churn; a threshold fixed to cell position is a different mechanism from either.
2. Rank-ordered cell reveal. EntrancePattern.reveal and the mask/photo-dissolve path use a continuous distance or coverage front. Gating each cell on rank(cell) < progress produces the stippled reveal of Dither Veil from existing pieces, with no new compositing.

Out of scope until a concrete app use appears (No SDK ceremony): pointer-driven trails, shockwaves, the rim band, background keying. React Bits' licence reports as NOASSERTION on GitHub, so do not copy its code. Bayer matrices and void-and-cluster (Ulichney 1993) are public algorithms; implement them from the literature.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Read the Dither Veil mechanism against Aski's current dotMatrix dither, EntrancePattern.reveal, and mask/photo-dissolve, and record which parts are already covered, which are new, and which are out of scope, in a dated docs/Research note
- [ ] #2 Before measuring, pre-register a frozen control (current Floyd-Steinberg dotMatrix at the shipped strength), the arms (Bayer 8x8 and blue-noise rank thresholds, built lab-only or behind @_spi(AskiResearch)), the corpus (stills plus at least two motion clips through aski lab video), and a decision rule over static MAE/GMSD and frame-to-frame glyph churn
- [ ] #3 Measure static quality, temporal churn, and dotMatrix walk wall time for each arm against the control on the exact sampling lattice, commit the CSVs, and record a PASS/KILL/INCONCLUSIVE verdict under the pre-registered rule
- [ ] #4 Prototype a rank-ordered cell-reveal variant in the motion lab and render a side-by-side GIF against EntrancePattern.reveal; record a keep/drop call, plus the concrete app use if keeping, before any public API is proposed
- [ ] #5 Production sources and goldens stay unchanged. A PASS files a separate promotion task with its no-harm census; a KILL keeps only the note and artifacts
<!-- AC:END -->
