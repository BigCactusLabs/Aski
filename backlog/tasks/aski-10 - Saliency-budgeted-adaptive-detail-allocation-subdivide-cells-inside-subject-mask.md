---
id: ASKI-10
title: >-
  Saliency-budgeted adaptive detail allocation: subdivide cells inside subject
  mask
status: To Do
assignee: []
created_date: '2026-08-18 18:02'
updated_date: '2026-09-10 04:38'
labels:
  - research
  - algorithms
dependencies: []
priority: medium
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Frontier research (2026-07-29 sweep) surfaced saliency-budgeted abstraction as current CGF work (saliency-weighted region merging, CGF 2025 cgf.70259) and cheap on-device segmentation (distilled-SAM/Vision person masks, ~ms-scale). Direction: segment the subject (Vision person/subject mask; a host app can later feed tap-to-segment), then subdivide grid cells 2x2 only inside salient regions for image/video output (plain-text export stays uniform). Orthogonal to the killed shape-basis lines: it changes WHERE resolution goes, not the descriptor or glyph choice, so it is untouched by the documented log-polar descriptor degeneracy (see docs/Research/). Builds on the existing Masking/ subsystem.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Pre-registered A/B on real portraits at a FIXED total cell budget: adaptive vs uniform grid
- [ ] #2 KILL if face-region GMSD and HaarPSI (agreeing oracles, per the shape-residual instrument lesson in docs/Research/) fail to beat the uniform-grid baseline
- [ ] #3 KILL if non-salient-region degradation is subjectively fatal on an AskiPresetLab-style contact sheet
- [ ] #4 Lab-only first (Tools/), Sources/ untouched until the decisive run passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board audit 2026-08-24 (deep pass): AC#2 still names GMSD+HaarPSI as agreeing oracles; both were disqualified from defining optima by the ASKI-27 MAE ruling. Re-word AC#2 to the house oracle before the decisive run.

### Implementer context — 2026-09-10 (base 952529a)
Current state: ASKI-10 remains a research task. The shipped Masking path accepts a raster mask, stretches it to the resolved output grid, and samples one coverage value per uniform cell. ASCIIConverter passes that flat coverage array into ConversionEngine, and converter-produced ASCIIGrid values use a uniform rectangular matrix. The public grid can accept ragged rows (ASKI-7), but that is not adaptive per-cell geometry. Image rendering also computes one glyph rectangle from a single cell width and height. There is no current Vision/person segmentation, saliency scorer, nested 2x2 subdivision, per-cell geometry, or adaptive-grid output path in Sources, Tools, or Tests. Existing mask coverage, fallback, hard-edge, soft-edge, ground-color, snapshot, and animation-propagation tests protect the uniform path. AskiPresetLab can make labeled PNG candidates and a contact sheet, but it does not run this experiment.

Start here: trace MaskOptions.swift, MaskSampler.swift, ASCIIConverter.swift, ConversionEngine.swift, ASCIIGrid.swift, ImageRenderer.swift, and Tools/AskiPresetLab/PresetLabCLI.swift. Use the existing mask as the host-supplied region input and keep the experiment in Tools until the task gate is met. The plain-text renderer is a uniform row walk, so the task’s plain-text exception must remain explicit.

Constraints and dependencies: AC #1 requires an A/B comparison on real portraits with a fixed total cell budget. AC #2 in the task and its dated audit still names GMSD plus HaarPSI, while the standing methodology says MAE is the house oracle and GMSD is the guard. Resolve that conflict before any decisive run; do not silently rewrite the acceptance criterion. AC #3 requires a human check for fatal non-salient degradation on an AskiPresetLab-style contact sheet. Keep Sources untouched until a decisive lab result passes. Do not invent segmentation behavior, grid geometry, selector thresholds, or a new verdict. Any moved frozen goldens need the required no-harm census.

Validation to run: after the lab is implemented and the oracle is resolved, run the focused mask/grid and contact-sheet checks, then the current research and artifact gates from justfile and the appropriate full check. No tests or builds were run in this inspection.

First step: record the oracle decision and fixed-budget corpus, then design the lab artifact around the existing uniform MaskOptions/MaskSampler input and the current contact-sheet writer.

Source map: `Sources/Aski/Masking/MaskOptions.swift`, `Sources/Aski/Masking/MaskSampler.swift`, `Sources/Aski/ASCIIConverter.swift`, `Sources/Aski/ASCIIGrid.swift`, `Sources/Aski/Renderers/ImageRenderer.swift`, `Tests/AskiTests/MaskSamplerTests.swift`, `docs/agents/research-methodology.md`.
<!-- SECTION:NOTES:END -->
