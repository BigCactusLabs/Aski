---
id: ASKI-77
title: Re-baseline golden drift on Xcode 27 / Swift 6.4 / macOS 27
status: Done
assignee: []
created_date: '2026-09-23 15:10'
updated_date: '2026-09-23 15:56'
labels:
  - gate
dependencies: []
ordinal: 78000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
14 tests (ImageRendererGoldenTests, SnapshotTests, BuiltInPaletteSnapshotTests, MaskSnapshotTests, CompositionSnapshotTests, EffectKernelSnapshotTests) fail byte/pixel golden comparison on unchanged main under Swift 6.4 / macOS 27.0 (blotter bl_ce5b1362428c996b9f0f). Blocks the v0.7.0 release gate. Follow the ASKI-51 regen policy (docs/Research/2026-09-04-aski51-core-text-drift-policy.md).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each failing test's drift is measured (max channel delta, changed-pixel fraction) and attributed (Core Text raster, Core Graphics/Metal, ShapeData bins) with the ASKI-51 vector audit run on this host
- [x] #2 Goldens re-recorded on Xcode 27 / Swift 6.4 / macOS 27 only where the policy allows, with toolchain provenance recorded
- [x] #3 No-harm census (selection-ceiling MAE and GMSD before/after) committed as CSV if any frozen-preset golden moves
- [x] #4 just check passes on this host apart from documented environment items
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-09-23 result on macOS 27.0 (26A428), Xcode 27.0 (27A266a), Apple Swift 6.4 (swiftlang-6.4.0.34.1), from source a6cb011.

Measured: 64 golden comparisons failed in 14 tests: G0 byte golden (86 of 1,936 pixels, max channel delta 11), 7 SnapshotTests images, 3 palette, 8 mask, 21 of 22 composition and all 24 effect-kernel images. Max channel delta was 1 to 38 except isolated pixels (181 on halftone-default, 255 in two composition cases); changed-pixel fractions were 0.004 to 0.72. Likely sources: Core Text glyph rasterization (renderer, palette, mask, charset images), Core Graphics compositing (composition), Metal kernels and stock Core Image filters (effects). These are likely-source classifications, not a controlled old-versus-new toolchain experiment. The four .lines text snapshots, the VesperPreset golden and the TileGridRendering snapshots all passed, so glyph selection did not change.

ASKI-51 audit (just audit-vectors): TRIGGERED. 9 of 10 sets drift, max component delta 0.0452 (blocks), standard brightness order changed, braille byte-identical. Per the policy, ShapeData .bin files were not regenerated; ASKI-78 is the required follow-up.

Re-recorded: default.metallib regenerated with just regen-kernels under Metal toolchain 27A266a (two regenerations byte-identical), then the 63 PNG snapshots (SNAPSHOT_TESTING_RECORD=failed) and the G0 golden (RECORD_G0=1) on that library. The new G0 bytes match an independent reproduction made during measurement. The six suites passed twice in a row without record mode. The goldens now fail on macOS 26.

No frozen-preset golden moved, so no no-harm census is required (AC #3 not applicable).

just check passed on this host (1416 + 152 + 2 tests, DocC validated). A comment-only edit to ImageRendererGoldenTests.swift landed during the run; it cannot change results.

Merged in PR #2 (12c8488) on 2026-09-23.
<!-- SECTION:NOTES:END -->
