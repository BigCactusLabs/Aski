---
id: ASKI-29
title: >-
  Descriptor kill record was measured at 48 of 60 reachable bins; the shipping
  preset runs at 2 to 3
status: Done
assignee:
  - '@codex'
created_date: '2026-08-19 05:58'
updated_date: '2026-09-04 07:01'
labels: []
dependencies: []
references:
  - docs/Research/2026-09-04-aski29-50-steerable-metric-replay.md
  - >-
    docs/Research/Results/2026-09-04-aski29-50-steerable-metric-replay/result.yaml
documentation:
  - docs/Research/2026-09-04-aski29-50-steerable-metric-replay.md
modified_files:
  - Tools/AskiColorLab/ShapeResidual/SteerableMetricReplay.swift
  - Tests/AskiTests/AskiColorLabSteerableMetricReplayTests.swift
  - docs/Research/2026-09-04-aski29-50-steerable-metric-replay.md
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The ShapeResidual lab raises oversample until the converter stops thumbnailing (noDownscaleOversample) so the oracle stays pixel-aligned with native source blocks. That is a correct instrument choice, but it puts the descriptor in a different regime from the product. Measured reachable support of the 60D log-polar histogram: shipping default oversample 2 at columns 80 gives a 2x4 cell, 3 admitted pixels of 8, 3 of 60 bins, a single radial ring; the ASTSK-31 lab regime (2048px source, oversample 26) gives 25x56, 48 of 60 bins; the ASTSK-42 lab regime (3072px, oversample 39) gives 38x85, 48 of 60 bins. Because the thumbnail longest side is capped at columns*oversample and the cell pitch is integer, cellWidth equals oversample exactly for landscape and square sources - so at the shipped default every cell is 2 source pixels wide on every image at every column count, and cell-height parity flips which bins are reachable (even heights land in radial bin 4, odd heights in radial bin 0). The kill verdicts stand on their own terms - a fully supported baseline is the harder test for a proposed channel - but the record contains no measurement of the descriptor in the configuration users actually get. This task closes that gap rather than reversing anything. Evidence: docs/Research/2026-08-19-sampling-lattice-support-collapse.md section 4.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 At least one archived decisive descriptor run is re-executed at the shipping sampling regime and the verdict is reported as held or flipped
- [x] #2 Future research notes state which sampling regime they measured, and the ShapeResidual harness records the resolved cell footprint and reachable-bin count alongside every verdict
- [x] #3 The column-count discontinuity from cell-height parity is characterized, since output quality is currently a discontinuous function of requested columns
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Freeze and commit one shared current-path replay contract before measurement.
2. Add a lab-only exact-lattice ASTSK-42 replay with shipping and historical-support regimes, five independent pixel oracles, and a parity census.
3. Score MILO with the pinned official model outside SwiftPM, finalize the fixed rule once, and commit the artifacts.
4. Update research records, cross-references, generated indexes, task evidence, and repo map.
5. Run focused tests and the full local gate; commit locally without changing Sources or defaults.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC#2 half-landed by ASKI-27 (branch `aski-27-house-oracle`, 2026-08-19): `ShapeResidualCommand.FixtureAnalysis` now carries `cellWidth`, `cellHeight` and `reachableBins`, read from the converter's own `samplingGeometry` and censused by `LatticeSupport.census`, and `spearmanTable` prints `footprint` and `bins/60` next to every rho. Guarded by `analysisRecordsTheResolvedFootprintAndReachableBins`, which pins the recorded bin count to the census of the recorded footprint so the two cannot drift. The synthetic battery reads 25x64 at 48/60 bins — the archived kill regime, next to every number it produced.

The other half of AC#2 — "future research notes state which sampling regime they measured" — is a documentation habit, not code; the 2026-08-19 house-oracle note states its regime and corpus throughout, and rule 4/5 of that note's §7 makes it standing.

AC#1 and AC#3 are untouched and this task stays open for them. Note for AC#1: ASKI-27 settled the oracle first, so a re-run at the shipping regime should now be scored under MAE (house oracle), NOT GMSD, and must name its corpus — the ranking-headroom margin straddles the +3.0% bar between nasa-steerable-v1 and nasa-structure-v1.

Board audit 2026-08-24 (deep pass): AC#2 done (ef825f2); AC#1 and AC#3 untouched. OVERLAP: ASKI-50 must regenerate the ASTSK-42 arms anyway — one regeneration can serve both AC#1 here and ASKI-50. AC#3 (cell-height parity split) is effectively a prerequisite for reopening the approach ASKI-31 rules out.

ASKI-66 lattice audit (2026-09-04): ASTSK-31 and ASTSK-35 used the non-exact 2048-square five-column grids but a full 48/60-bin descriptor regime; ASTSK-42 used non-exact 3072-square grids and 48/60 bins at C80. Their KILLs are candidate false negatives under the old truncating lattice, not reversed verdicts. The audit makes an exact-lattice, explicitly supported regeneration mandatory for AC1 and confirms that this remains separate from the shipping 2-3/60 support question.

Executed 2026-09-04 from pre-registered rule commit bcc67b2 and clean runner commit 7f2f73c. The current exact C80 shipping arm resolved to 2x4 cells, 3/60 bins, and zero dropped pixels; the separate historical-support comparator resolved to 38x85, 48/60, and zero dropped pixels. The archived KILL HELD under every registered loss in both regimes. Shipping aggregate deltas: MAE -0.1783%, GMSD -0.3805%, 1-HaarPSI -0.1116%, CSSIM -0.1709%, MILO -1.2606%. The 3072-square C4...80 census found parity transitions at 5, 6, 8, 9, 10, 12, 13, 14, 15, and 16, with none above 16. Full evidence: docs/Research/2026-09-04-aski29-50-steerable-metric-replay.md and docs/Research/Results/2026-09-04-aski29-50-steerable-metric-replay/.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DONE. A valid current-path ASTSK-42-style comparison closed the shipping-regime evidence gap. The KILL held at shipping 3/60 support and at a separate 48/60 comparator under all five registered metrics. The full exact-lattice column-parity census is committed. No Sources or default changed.
<!-- SECTION:FINAL_SUMMARY:END -->
