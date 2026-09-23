---
id: ASKI-59
title: 'Explore ASCII-grid photo animation: fixed glyph grid, moving sample field'
status: To Do
assignee: []
created_date: '2026-08-27 05:15'
updated_date: '2026-09-16 18:16'
labels: []
dependencies: []
references:
  - docs/Research/2026-09-03-future-direction-and-architecture.md
ordinal: 60000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Animate a still photo behind a fixed ASCII glyph grid. Explore this as an Aski capability — it is adjacent to ASKI-9's photo → render → animated reveal.

The technique (all in the fragment shader; the cell grid never moves, only what each cell samples):
- Ken Burns drift: slow breathe-zoom (zoom = 1.06 + 0.025*sin(t*0.11)) plus wandering pan (0.010 amplitude, incommensurate sin/cos frequencies 0.07/0.053)
- Heat shimmer: center.x += sin(t*0.9 + y*16.0) * 0.0012
- Sparse cell flicker: per-cell hash (fract(sin(dot(cellId, vec2(12.9898,78.233)))*43758.5453)); cells where fract(n + t*0.05) > 0.96 dip one ramp step; only mid-tone cells (idx >= 2)

Questions to explore:
- Can Aski's CPU renderer produce the same effect as frame sequences (GIF/APNG export) for no-JS contexts?
- Better flicker statistics from Aski's measured glyph metrics (dip toward nearest-coverage neighbor glyph instead of ramp index -1)?
- Reveal choreography: combine with ASKI-9's animated reveal — drift begins after the reveal completes.
- Amplitude/frequency guidance: current values were tuned by eye at 12px cells; do they hold at other cell sizes?

Reference implementation: bcl-web orbs/ascii-photo.html, related task ASKI-58 (atlas/settings investigation).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)
Current state: public animation already supports AnimatedASCIIGrid, time-based reveal/cycling/ongoing effects, materialize(frameRate:), image rendering, GIF export, and MP4 export. AskiMotionLab materializes text/image frames and writes GIFs. The current animation still uses a fixed ASCIIGrid geometry and existing candidate schedules; no moving sample field, Ken Burns source resampling, heat shimmer, sparse source-driven flicker, or APNG writer exists. GIF is a batch ImageIO path and its research note records color-quantization limits. The temporal SPI path is a separate research control and does not provide a product motion field. ASCIIAlgorithm has only logPolar and dotMatrix now; edgeMap was removed and must stay removed.

Start here: Sources/Aski/ASCIIConverter+Animation.swift, Sources/Aski/Animation/AnimatedASCIIGrid.swift, Sources/Aski/Animation/AnimationOptions.swift, Sources/Aski/Video/ASCIIGIFEncoder.swift, Tools/AskiMotionLab/MotionLabCLI.swift, the frozen-preset reveal integration test under Tests/AskiTests/, and the 2026-09-04 ASKI-73 product-probe rule note under docs/Research/. The ASKI-73 rule is the product boundary: probe one tests the existing frozen-preset center reveal, and the moving-sample-field treatment is eligible only as one changed variable in probe two if motion is selected. Compare the same source still with the Aski-specific motion grammar.

Constraints and dependencies: ASKI-59 is one motion candidate for ASKI-73, not evidence that motion is the product wedge. Use the ASKI-73 gates before promotion: identity PASS is at least 6/8, preference plus export is at least 5/8, repeat distinct-source export is at least 3/8 after 48 hours to 14 days, motion keep is at least 5/8, and the paid gate is at least 2 real non-zero payments. Synthetic or repository-only smoke is not product evidence. Keep fixed geometry and provenance while a candidate is lab-only. Do not restore edgeMap or promote EMA/tau/source-tether treatments killed by the temporal research, and do not invent amplitudes, frequencies, selector thresholds, or a public API. APNG is absent, so the existing GIF path cannot be described as APNG support.

Validation to run: after ASKI-73 authorizes the motion arm, compare still, center reveal, and the single candidate treatment on the same real sources; run the existing GIF and frozen-preset reveal integration tests, then the product probe and applicable repository gates. No tests, builds, exports, or experiments were run in this inspection.

First step: wait for the ASKI-73 motion decision, then register a bounded same-source frame-sequence experiment around the existing AnimatedASCIIGrid/GIF path without changing the public surface.

Source map: `Sources/Aski/ASCIIAlgorithm.swift`.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-09-04 03:46
---
Product routing 2026-09-03: this is one motion candidate for ASKI-73, not evidence that motion is the product wedge. Compare the same source as still versus this Aski-specific motion grammar and keep it only if it improves the pre-registered creator outcome.
---
<!-- COMMENTS:END -->
