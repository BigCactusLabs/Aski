---
id: ASKI-107
title: >-
  fullColor renders do not preserve the source's tone or colour: glyph coverage
  is not compensated and there is no per-cell ground
status: To Do
assignee: []
created_date: '2026-11-12T21:48:00Z'
updated_date: '2026-11-13T05:21:00Z'
labels:
  - correctness
  - rendering
  - color
dependencies: []
priority: medium
ordinal: 108000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A fullColor render gives each glyph its cell's source colour and draws it on one flat ground. Strokes cover only a fraction of a cell, so the rendered cell's average is mostly the ground, not the source. Measured at 3f6da15 (v0.8.0-55) with 'aski render <photo> --columns 132 --palette fullColor --background #000000 --render-png out.png --width 1760', comparing linear-light cell averages of the PNG against the source on the same grid: a high-key outdoor photo (pale sky, tan rock, dark foreground) keeps 17 percent of the source's light with a mean per-channel cell error of 75 of 255 (sRGB); a landscape canyon photo keeps 13 percent with error 52. A light --background does not help, because glyph density follows source brightness, so a light ground overshoots (256 and 577 percent). The same gap was measured on a downstream site in 2026-09 (glyph-mask slices kept 53 to 58 percent of the photo's light). A downstream consumer worked around it outside Aski: render --palette monochrome as a mask, then compute two flat colours per cell (glyph and ground) by solving, per channel, for the ground value at which strokes plus ground average in linear light to the source cell. That reached a mean error of 0.4 of 255 on the same photo, but the glyph colours are an arbitrary darkened copy of the cell colour and were judged to look wrong, and dark-on-dark cells lose their glyphs, so the choice of glyph/ground pair needs design in Aski rather than a fixed factor. Related, both Done: ASKI-15 (full-colour desaturation), ASKI-3 (grid colour-space semantics). Tone loss in sparse charsets at selection time is ASKI-30; this task is about colour at render time for any charset.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A reproducible measurement (script or test) reports light kept and mean cell error against the source for a fullColor render, on at least one high-key and one low-key corpus image
- [ ] #2 Decide and record the approach: coverage-compensated glyph colour on a flat ground, an optional per-cell ground colour (two colours per cell, as terminals do with foreground and background), or both
- [ ] #3 With the chosen option enabled, rendered cell averages match the source within a tolerance frozen before the decisive measurement, without glyphs vanishing into their ground
- [ ] #4 The per-cell colours are available to consumers that draw the grid themselves (grid output or manifest), not only in the PNG renderer
- [ ] #5 Default output is unchanged unless the decision record says otherwise
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-13: audit metadata: labels and priority added to match the other rendering bug tasks. Where the description points at ASKI-30 for the tone question, the open follow-up is ASKI-57 (ASKI-30 is Done/INCONCLUSIVE). Related: ASKI-103, whose composition policy (encoded vs linear-light mixing) affects measured per-cell averages, so AC#1 should fix the composition policy it measures under.
<!-- SECTION:NOTES:END -->
