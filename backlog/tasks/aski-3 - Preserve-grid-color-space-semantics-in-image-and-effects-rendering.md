---
id: ASKI-3
title: Preserve grid color-space semantics in image and effects rendering
status: Done
assignee:
  - '@codex'
created_date: 2026-08-18 18:01
updated_date: '2026-11-13T04:21:00Z'
labels:
  - correctness
  - rendering
  - color
dependencies: []
priority: high
type: bug
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ASCIICell.displayColor and TileCell.displayColor are encoded in the grid RenderColorSpace, but the direct ASCII, tile, and effects raster paths construct Generic RGB CGColors. This materially changes non-neutral sRGB and Display P3 values. AskiRenderEngine also changes the grid color-space tag without converting cell components. Correct the complete defect family so image output matches the documented cell-color contract and the already color-space-aware attributed-string path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Direct ASCIIGrid and TileGrid encoded 8-bit rendering interprets each displayColor in the grid declared sRGB or Display P3 space and preserves non-neutral components within one 8-bit quantization step.
- [x] #2 Effects rasterization uses the same color-space-correct interpretation as direct rendering for ASCIIGrid and TileGrid.
- [x] #3 Rendering through AskiRenderEngine with an engine color space that differs from the grid preserves colorimetry and emits the intended output color-space tag without retagging unchanged components.
- [x] #4 Regression coverage includes the non-neutral discriminator (0.8, 0.2, 0.1) in sRGB and Display P3 and detects Generic RGB reinterpretation in direct, effects, and engine-adapted paths.
- [x] #5 Alpha, mask fallback, composition-policy, braille, tile-shape, and attributed-string behavior remain correct, and focused tests plus just check pass.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Preserve control and record failing native color checks. 2. Correct source colors and engine conversion. 3. Commit the no-harm rule before measuring; retain paired corpus CSVs. 4. Attribute integration changes, inspect and update goldens, complete independent review and full local gate. 5. Record progress, commit and push the completed branch, then pause as requested.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Implementer context — 2026-09-10 (base 952529a)

Current state: `ASCIICell.displayColor` is documented as already display-ready in the grid `RenderColorSpace`. The encoded 8-bit composition policy selects an sRGB or Display P3 drawing space, but the direct image renderer builds foregrounds with `CGColor(red:green:blue:alpha:)`; the effects ASCII raster builder does the same. Tile direct and effects rendering share `RasterColorCache.color` and `renderCellsForRaster` in `Sources/Aski/Tiles/TileGrid+Rendering.swift`, where the same generic RGB constructor is used. Include `CellRasterBuilder.makeTileRaster` and both engine adaptation overloads in the defect family. Both draw actual cell components into a tagged context without an explicit component conversion at those call sites. The engine adaptation path reconstructs a grid with `colorSpace: colorSpace` while passing through the original cells, masks, and fallback metadata. That can change the interpretation of unchanged components. The attributed-string path is a useful contrast because it selects sRGB or Display P3 platform color constructors.

Start here: trace one non-neutral encoded cell through `ImageRenderer`, `CellRasterBuilder`, and `AskiRenderEngine` for both direct and non-default composition paths. Keep the `RenderCompositionPolicy.cgColorSpace(for:)` mapping in the trace; output tags alone do not prove component colorimetry. The HDR extended-range helper also has a separate decode path, so its inclusion in this scope needs an explicit decision.

Constraints and dependencies: preserve alpha, mask fallback, active mask ground, braille, tile-shape, and attributed behavior. Existing focused tests mostly check tags, primaries, or byte identity for sRGB cells; they do not provide the required non-neutral `(0.8, 0.2, 0.1)` sRGB/P3 discriminator across direct, effects, and engine-adapted output. The engine adaptation must also retain all mask fields when its color-space behavior is corrected.

Validation to run: add focused tests for the non-neutral discriminator and the existing fallback/composition cases, then run `just check-fast` and the full `just check` gate. Compare decoded pixel values and output tags, not only `CGColorSpace.name`; keep rectangular and no-effects compatibility assertions.

First step: capture the current direct, effects, and engine-adapted pixel/tag behavior with the same encoded cell and record the expected color-space interpretation before choosing the conversion boundary.

Source map: `Sources/Aski/ASCIICell.swift`, `Sources/Aski/Renderers/ImageRenderer.swift`, `Sources/Aski/Effects/Internal/CellRasterBuilder.swift`, `Sources/Aski/Effects/AskiRenderEngine.swift`, `Sources/Aski/ColorPipelinePolicies.swift`, `Tests/AskiTests/AskiRenderEngineTests.swift`, `Tests/AskiTests/RenderCompositionPropagationTests.swift`.

Pause handoff, 2026-11-05: fix/aski-3-render-color-space builds on batch/aski-current-2026-11-05 (draft PR15, head14c8697; completed ASKI-8/83/97). Protocol commit6b47141 precedes every census measurement. Public methods, evidence, SSIM contract rationale, golden review, validation, limits and next actions are in docs/Research/2026-11-05-aski3-color-semantics.md and its linked Results directory. Full gate completed before final status text; production/test hashes remain unchanged. Control checkout and local logs retained. User requested commit, push, then pause; no new task started. On resume, review this layer against the PR15 branch; ASKI-15 and ASKI-98 are follow-up options.

Review repairs and re-record, 2026-11-06: CLI --background/--mask-fallback-color/--mask-ground and HDR lab --background-hex colors now built in sRGB (#808080 no longer renders #929292); engine and attributed-string gamut conversion use relative colorimetric intent (output unchanged on this host); Generic RGB mask-paint check reads the name from CGColor(red:green:blue:alpha:) once instead of a string literal; DocC/README examples tag colors as sRGB; regression tests added for the CLI colors and out-of-gamut Display P3 to sRGB engine output. Merged base 89fd227, which withdraws the ASKI-97 27.0.1 re-baseline (ASKI-97 reopened); the 27.0.1 re-baseline is not current. Re-recorded 11 composition snapshot references and the 2 DocC mask-ground test references plus their catalog assets on macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Swift 6.4, Apple M3 Max; snapshot suites passed twice without recording; full just check passed at cc98d95 (1451 core, 156 media, 2 sentinel tests). Selection census unaffected (no selection-path change); research note and result package updated.

Audit 2026-11-12: merged as public PR #18 (4855f5a) on 2026-11-07. The follow-ups named above are resolved: ASKI-98 and ASKI-15 are Done.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Corrected encoded sRGB/Display P3 source colors in direct ASCII, tile, and effects rendering and added true engine gamut conversion. Eight native regression tests cover both gamuts, direct/async/engine, linear composition, alpha/coverage, and explicit/inherited character fallback. Paired pre-registered selection census: all six production MAE/GMSD ratios exactly 1.0 across 75,468 cells. Reviewed 61 changed PNGs and G0; retained tone/alpha attribution and source/asset hashes. Full just check passed: 1,449 core + 156 media + 2 deadlock tests, plus structural gates and DocC. No benchmark or snapshot tolerance change. ASKI-98 tracks the preexisting literal mask-paint path split; engine conversion cost remains unmeasured.
<!-- SECTION:FINAL_SUMMARY:END -->
