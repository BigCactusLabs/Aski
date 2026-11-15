---
id: ASKI-103
title: >-
  Soft mask edges mix opaque branches in encoded values on Core Graphics paths
  and in linear light on Core Image paths
status: Done
assignee:
  - '@codex'
created_date: '2026-11-10T19:09:00Z'
updated_date: '2026-11-15T19:54:00Z'
labels:
  - correctness
  - rendering
  - masking
dependencies: []
priority: low
type: bug
ordinal: 104000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while fixing ASKI-101. After ASKI-101 every render path applies the same coverage weight, but the colors that weight mixes are combined in each path's compositing space. Under the default RenderCompositionPolicy.encodedDisplay8Bit, the Core Graphics overlay paths (direct ASCII, target width, direct tile pixelArt/brick fallback) mix encoded values, while the Core Image mask compositor (effects, async, renderCIImage, AskiRenderEngine, any render with a ground, rerouted tile mosaic) mixes in the shared context's extended linear sRGB working space. Measured on a one-cell sRGB grid with a zero-alpha glyph, an opaque white solid fallback and an opaque black background: direct ASCII gives 191/128/64 at coverage 0.25/0.5/0.75, the effects path gives 225/187/138. Under the opt-in extendedLinearPerGamut policy the direct path already mixes in linear light and agrees with the effects path. Over transparent content the alpha is identical on every path, which MaskColorContractTests.softCoverageIsALinearWeightOnEveryPath pins. The same encoded-versus-linear split likely applies to glyph antialiasing edges on the effects path versus direct rendering; confirm before scoping.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Measure the split on every MaskColorContractTests path under both composition policies, for soft mask edges and for glyph antialiasing edges
- [x] #2 Decide whether Core Image paths should follow the grid's RenderCompositionPolicy, with a pre-registered rule and the frozen-preset no-harm census if any frozen-preset golden would move
- [x] #3 Document the outcome in the Masking and Rendering guides
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Freeze and commit a measurement protocol and opt-in instrument for all existing render paths, both composition policies and gamuts. 2. Independently review the instrument before reading decisive measurements. 3. Measure soft opaque mask blends and glyph AA separately, including deferred CI consumers and ground routing. 4. Decide and document the per-stage compatibility contract under the frozen rule; unexplained results remain open. 5. Run the full local gate with unchanged production output and goldens.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-13: related: ASKI-107 measures linear-light cell averages, which this task's composition policy affects.

2026-11-15: Protocol and instrument frozen at e609764 before first capture. Independent source review required a real reducer control and narrowed target glyph claims before capture; thresholds stayed unchanged. Native matrix passed all 496 applicable rows, with 24 tile glyph N/A rows: 18 paths, both ASCII policies and grid gamuts, both CI consumers, 432 soft-mask rows, 48 glyph rows and 16 controls. TileGrid has no policy knob, so tile policy is explicitly N/A. KEEP current per-stage behavior; the policy controls ASCII Core Graphics rasterization, not every later CI operation or caller context. Masking/Rendering guides and API comments now state this scope. Production output and goldens unchanged, so no no-harm census is required. Full native gate passed before capture; final documentation/evidence gate runs before PR.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Measured and documented mask and glyph composition across all existing color-contract paths. All registered applicable measurements pass. Kept current stage-specific blending, with explicit policy and CI-consumer limits. Committed CSV, controls, source hashes, replay protocol and native capture evidence; no production render behavior or golden changes.
<!-- SECTION:FINAL_SUMMARY:END -->
