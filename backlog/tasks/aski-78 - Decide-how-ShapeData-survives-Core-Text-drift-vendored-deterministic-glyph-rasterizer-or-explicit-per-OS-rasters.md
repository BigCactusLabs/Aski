---
id: ASKI-78
title: >-
  Decide how ShapeData survives Core Text drift: vendored deterministic glyph
  rasterizer or explicit per-OS rasters
status: To Do
assignee: []
created_date: '2026-09-23T15:47:00Z'
updated_date: '2026-11-24T21:37:05Z'
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

### Groundwork — 2026-10-27 (base 4c675957; re-applied via CLI after merging main)

Factor font choice from rasterizer choice before costing the two routes. `Tools/BuildStandardVectors/BuildStandardVectors.swift` resolves system Courier at 32 pt, while the canonical Vesper renderer uses bundled Courier Prime at 14 pt. Swapping both font and rasterizer in one trial would obscure what changed.

Bounded experiment: retain committed ShapeData as the selection control; first compare Core Text/system Courier with Core Text using identical bundled Courier Prime bytes at the same descriptor-generation point size and geometry, then compare that same bundled font through a pinned alternate rasterizer. Record font hashes, library/build configuration, canvas, placement/baseline, glyph order, grayscale coverage and hint/bitmap policy. Run the exact-lattice MAE/GMSD census before interpreting regenerated descriptors. In parallel, cost explicit per-OS assets and their regeneration/selection rules. This is preparation for the required owner decision, not a choice to add FreeType or regenerate production bytes.

Apple's `CTFontCreatePathForGlyph` returns glyph outlines; rendering those paths with Core Graphics still does not establish OS-independent pixels. FreeType exposes `FT_LOAD_NO_HINTING`, `FT_LOAD_NO_BITMAP`, and `FT_RENDER_MODE_NORMAL` for controlled grayscale trials, but those switches alone do not prove cross-host byte stability. Demonstrate that with pinned inputs and multiple hosts before promising deterministic assets. Existing committed ShapeData and the recorded macOS-27 rendered-golden baseline remain the controls.

Primary sources inspected: https://developer.apple.com/documentation/coretext/ctfontcreatepathforglyph(_:_:_:) ; https://freetype.org/freetype2/docs/reference/ft2-glyph_retrieval.html .

Audit 2026-11-24: PR #30 removed the public preset. The canonical renderer referred to above is now the package-only Tools/AskiToolSupport/FrozenRenderReference.swift (`.courierPrime(size: 14)`), and "the frozen preset" in AC#1 means that reference. AC#3 is half done: docs/Research/2026-09-04-aski51-core-text-drift-policy.md already records the macOS 27 TRIGGERED result in its front matter and body; the decision part is still open. For AC#4, CONTRIBUTING.md (toolchain and snapshot baseline) documents the current host-bound golden constraint, but no multi-OS policy has been decided.

2026-11-24 research note: docs/Research/2026-11-24-aski78-rasterizer-options.md (decision inputs; status active).
The 0.0452 maximum is in the retired v3 structure block, which production discards; the largest loaded-channel delta is 0.0059 (brightness), still above the 0.001 tolerance (91 of 158 non-braille rows), and the standard sort change is brightness-driven.
On one macOS 27.2.1 host Core Text draws 24 block, box-drawing and geometric glyphs from Menlo, not Courier or Courier Prime (uncommitted probe).
Recommendation, medium-low confidence and pending the owner: run the staged hash experiment first; prior favours tool-only FreeType plus programmatic geometric glyphs. AC#4 recommendation (medium): split by path, several accepted digests for Core Image suites.
AC#1 selection-ceiling MAE/GMSD census (regenerated in-memory vs committed vectors) has not been run.

2026-11-24 owner decision (accepted the recommendations in docs/Research/2026-11-24-aski78-rasterizer-options.md, section Owner decision). (1) ShapeData: run the staged hash experiment before choosing a mechanism. Pre-register the rule, run Stage 0 on both macOS 27.0.1 hosts and Stage 1 on the four listed hosts, and Stage 2 only for a qualifying arm. If arms qualify, prefer Core Text outlines plus CG fill (no new dependency), then tool-only FreeType 2.15.0 plus programmatic geometric glyphs; adopt per-key audit digests if none qualifies. Regeneration stays blocked. (2) Rendered goldens: option D. CPU-only outputs stay exact; the Core Image suites accept several committed digests per snapshot, added only for host variants that reproduce across repeated captures; a per-channel tolerance only where ASKI-112 shows inherent nondeterminism; G0 placement waits on its host-stability check. AC#2, AC#3 and AC#4 stay unchecked until the mechanism and the digest helper are implemented. The AC#1 census has not run.
<!-- SECTION:NOTES:END -->
