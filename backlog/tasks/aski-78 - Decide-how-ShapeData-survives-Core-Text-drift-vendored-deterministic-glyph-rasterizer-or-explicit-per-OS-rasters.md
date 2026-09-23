---
id: ASKI-78
title: >-
  Decide how ShapeData survives Core Text drift: vendored deterministic glyph
  rasterizer or explicit per-OS rasters
status: To Do
assignee: []
created_date: '2026-09-23 15:47'
labels:
  - spike
  - gate
dependencies: []
priority: medium
ordinal: 79000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The ASKI-51 audit TRIGGERED on macOS 27.0 (26A428) / Xcode 27.0 (27A266a) / Swift 6.4 during ASKI-77: 9 of 10 ShapeData v3 sets drift (max component delta 0.0452 in blocks, tolerance 0.001), and the standard set's brightness-sorted order changed; braille is byte-identical. The committed .bin files were NOT regenerated, as the policy requires when a trigger fires, so current selection output is unchanged (all text and selection goldens pass on macOS 27). The policy's required follow-up is this task: choose between vendoring a deterministic text glyph rasterizer and defining explicit per-OS golden rasters, then validate the choice. Until it lands, any change that needs ShapeData regeneration (schema, raster construction, glyph inventory, accepted matching change) is blocked. Render snapshots are separate: ASKI-77 re-recorded them on macOS 27, and they now fail on macOS 26.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Both options are costed against Aski evidence: selection effect of the macOS 27 drift on the frozen preset (selection-ceiling MAE and GMSD with in-memory regenerated vectors versus committed), and the maintenance cost of per-OS rasters
- [ ] #2 The owner records the decision; the chosen mechanism is implemented and the ASKI-51 audit either no longer depends on the OS rasterizer or is keyed per OS
- [ ] #3 docs/Research/2026-09-04-aski51-core-text-drift-policy.md is updated with the macOS 27 TRIGGERED result and the decision
<!-- AC:END -->
