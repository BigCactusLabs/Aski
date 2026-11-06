---
id: ASKI-78
title: >-
  Decide how ShapeData survives Core Text drift: vendored deterministic glyph
  rasterizer or explicit per-OS rasters
status: To Do
assignee: []
created_date: 2026-09-23 15:47
updated_date: '2026-11-06T17:30:00Z'
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
- [ ] #4 Decide how rendered goldens (PNG snapshots and the G0 byte golden) handle more than one OS: separate rasters per OS, a perceptual comparison, or macOS-27-only as accepted in ASKI-77 (PR #2 review). If they stay macOS-27-only, document it where the gate is described
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ASKI-97 repeated the read-only audit on macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Swift 6.4. Nine of ten sets drift; max component delta 0.0451757461, standard brightness sort changes, braille byte-identical. ShapeData remains untouched. Retained CSVs: docs/Research/Results/2026-11-05-aski97-render-drift/. Summary matches the known macOS 27 trigger; no earlier per-glyph CSV comparison was possible. ASKI-97 separately advances exact render goldens to 27.0.1 and records the cross-OS limitation in CONTRIBUTING. This task still owns the durable raster/platform policy decision.

2026-11-06 correction: the ASKI-97 move of exact render goldens to 27.0.1 was withdrawn and the original goldens restored (25460c3). An M3 Max host with the same macOS 27.0.1 (26A434) and Xcode 27.0 (27A266a) builds passes them, while the recording host saw 16 one-step differences, so exact raster output is host-dependent. AC4's golden policy must cover hosts, not only OS versions.
<!-- SECTION:NOTES:END -->
