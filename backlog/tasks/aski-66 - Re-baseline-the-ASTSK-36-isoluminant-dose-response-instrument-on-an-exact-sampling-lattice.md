---
id: ASKI-66
title: >-
  Re-baseline the ASTSK-36 isoluminant dose-response instrument on an exact
  sampling lattice
status: Done
assignee:
  - '@codex'
created_date: '2026-09-02 07:11'
updated_date: '2026-09-16 17:37'
labels: []
dependencies: []
references:
  - 27e249254a931850627c79b8b079470b7a79f82b
documentation:
  - docs/Research/2026-09-04-aski66-exact-lattice-dose-redesign.md
modified_files:
  - Tests/AskiTests/AskiColorLabIsoluminantRescueTests.swift
  - Tools/AskiColorLab/IsoluminantRescue/IsoluminantDoseCalibration.swift
  - docs/Research/2026-06-11-isoluminant-dose-response.md
  - docs/Research/2026-09-04-aski66-exact-lattice-dose-redesign.md
  - >-
    docs/Research/Results/2026-09-04-aski66-dose-calibration/dose-calibration.csv
priority: medium
ordinal: 67000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up to ASKI-65 (GH #36). The 2026-06-11 ASTSK-36 dose-response PASS (redGreen 0/0/0/0.39/0.56, blueYellow 0/0/0/0.50/0.58 over lambda in {0,.25,.5,.75,1}) was measured on the truncated sampling lattice: the 512-square battery at 64 columns resolved 29 rows, so the converter read an 8x17 cell (aspect 2.125, below the 2.2 wide-tile ratio) and dropped the bottom 19 rows. ASKI-65 draws every thumbnail into an exact columns*cellWidth x rows*cellHeight lattice; the isoluminant lab now refuses non-exact fixtures (latticeWouldResample) and its battery is authored at the exact-lattice height for its column count (512x522 at 64 columns, 8x18 cell, 29 rows; ToolArgumentBounds.exactLatticeHeight). The shape-residual and decolor labs were left mapping native oracle blocks through the lattice instead of refusing, because their square batteries at many column counts are never exact and re-siting them is its own re-tune. Re-measured on exact lattices the competition-ramp instrument no longer grades: 8x18 cells (512x522, 256x270, 640x648) and 16x36 (1024x1044) are inert at every lambda (0/0/0/0/0); an odd 8x19 cell (512x209, 11 rows) is binary (0/.562/.562/.562/.562, onset below 0.25); 8x20 (512x140) is inert. Cell-height parity moves the response (consistent with ASKI-25's disjoint-bin finding for 2x4 vs 2x5), and the graded curve existed only on the defective 2.125-aspect cell. The >=3 bar in competitionRampsYieldGradedDoseResponse is UNCHANGED and the failing assertions are pinned with withKnownIssue so the gate reports the instrument state honestly and flips loud if it recovers. chromaShapeAssist default stays 0 (ASTSK-37 corpus gate already failed), so no shipped behavior depends on this verdict.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 docs/Research/2026-06-11-isoluminant-dose-response.md carries the new verdict with the exact-lattice measurements; the addendum ASKI-65 added is superseded or confirmed
- [x] #2 The withKnownIssue pins in AskiColorLabIsoluminantRescueTests are removed and the test asserts the settled verdict directly
- [x] #3 Decide whether the competition-ramp instrument can be redesigned to grade on an exact lattice (e.g. luma-split range or chroma scale re-tuned for the 8x18 cell, or a lambda sweep finer than 0.25 around the onset). The June ASTSK-36 PASS is ALREADY RETRACTED (2026-09-02, invalid run: instrument artifact); the open question is only whether a redesigned instrument reinstates a graded verdict or the dose-response question closes as INCONCLUSIVE
- [x] #4 Lattice audit of archived verdicts: one line per pre-ASKI-65 lab verdict (shape-residual ASTSK-27/31, occupancy ASTSK-7, decolor, ASTSK-35/42) recording its battery size, column counts, and whether the battery was an exact lattice or read through the truncating path; flag any KILL whose battery was non-exact as a candidate false negative (same asymmetry as this PASS's false positive)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Commit a bounded exact-lattice calibration and holdout rule before reading any new measurements.
2. Add a research-only parameterized competition-ramp calibration seam without changing production defaults.
3. Run the frozen calibration grid and evaluate at two frozen exact-lattice holdouts; stop after this one search.
4. Replace the known-issue pins with the settled outcome and update the retraction note.
5. Audit each named pre-ASKI-65 verdict for exact-lattice and descriptor-support validity, then update related task records.
6. Regenerate research and repository indexes, run focused validation and the full local gate, and finalize through the Backlog CLI.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-09-02 review ruling (owner accepted): the June AC #1 PASS is re-recorded now as RETRACTED (invalid run, instrument artifact) rather than deferred to this task; the merits question is INCONCLUSIVE pending this task. Rationale: run-level validity is settled (no response window on any exact lattice), only the redesign question is open. Docs updated on main: research doc title/summary/Decision strike-note, docs/Research index, decolor-oracle pointer; the two unpinned assertions (monotone, off-band) are commented as vacuous while the instrument is inert. Bar and withKnownIssue pins unchanged (no isIntermittent, so knownIssueNotRecorded trips if the instrument recovers).

Docs audit 2026-09-02: when building the AC#4 table, keep two lattice defects distinct or the audit will conflate them. (a) The non-exact-fixture truncation this task is about — battery not a whole number of cells, converter drops the remainder — fixed by ASKI-65 and refused by the isoluminant lab. (b) The oversample-2 descriptor support collapse in docs/Research/2026-08-19-sampling-lattice-support-collapse.md — 2-3 of 60 reachable bins, a different mechanism tracked by ASKI-25/26/29 and NOT addressed by ASKI-65. A verdict can be suspect under either, both, or neither, and the remedies differ. Also: ASKI-31 (remove the bottom-remainder truncation) now reads as satisfied by ASKI-65 — droppedX/droppedY are asserted zero in SamplingLatticeContractTests and AskiColorLabSamplingLatticeTests, and the AskiColorLabSamplingLatticeTests.swift:96 'asserts droppedY > 0' gotcha in ASKI-31's own notes is stale. Worth closing ASKI-31 on the merits before this audit runs.

CORRECTION to the docs-audit note above (same session, 2026-09-02): the claim that ASKI-31 'reads as satisfied by ASKI-65' was WRONG on AC#3 and loose on AC#1. Re-checked against the four ASKI-65 commits (4940464, 4db60d6, ba85b62, d4348f3): AC#2 is genuinely satisfied — uniform pitch is structural (SamplingGeometry carries scalar cellWidth/cellHeight) and tested by latticeIsAnExactMultipleOfTheGrid. AC#3 is HALF done: golden regeneration was deliberate and enumerated (4db60d6 lists all six), but the selection-ceiling before/after under BOTH MAE and GMSD was never run — no AskiColorLab selection-ceiling invocation, no CSV, no research note for ASKI-65 at all. That missing half is the substantive one: ASKI-31 framed the change as 'a product decision about the frozen preset's output, not a bug fix' and required exactly that no-harm evidence. ASKI-65 moved every golden of vertically-varying content INCLUDING the frozen preset's canonical render and re-recorded them; re-recording a golden is not a quality measurement. AC#1 is satisfied in substance (no row goes unread) but ASKI-65 took a THIRD approach — resample the thumbnail into a lattice-sized raster — rather than (a) exact-multiple thumbnail or (b) centred lattice, so the required 'choice between (a) and (b) recorded and justified' never happened. That third approach also carries a cost neither (a) nor (b) had: it rescales the source by up to one cell pitch per axis. Whether that rescale harms pick quality is precisely what the unrun MAE/GMSD selection-ceiling would answer. Do NOT close ASKI-31 as satisfied; the open work is the no-harm measurement.

Follow-up 2026-09-02 (PR #38 review): the correction note above overstated one point. It said the lattice-raster approach 'carries a cost neither (a) nor (b) had: it rescales the source by up to one cell pitch per axis.' Approach (a) - make the thumbnail an exact multiple of the grid - would also have shifted the source-to-thumbnail scale by up to one cell pitch per axis, so rescale magnitude is not the distinguishing cost. The real one is the SECOND resampling stage: CellSampling.swift:207 samplingLattice re-reads the already-resampled thumbnail into a pixelWidth x pixelHeight raster at interpolationQuality .high, so the pipeline now interpolates twice where (a) would have interpolated once. That is a stronger argument for the unrun no-harm measurement, not a weaker one. The load-bearing conclusion is unchanged: ASKI-31 AC #3's selection-ceiling before/after under MAE and GMSD was never run, and ASKI-31 stays open.

2026-09-04 final result: preregistration committed at 51de4e6 and the audited runner at 27e2492 before measurement. The one permitted release run evaluated 64 valid candidates x 2 axes x 21 lambda arms (2,688 rows); every axis had one invariant response and no lambda-50, so no candidate qualified and the frozen stop rule skipped both holdouts. Verdict INCONCLUSIVE; no second tuning round and no production default change. The historical audit separately identifies non-exact lattice exposure and descriptor-support regime for ASTSK-27/31, ASTSK-7, decolor, ASTSK-35, and ASTSK-42. Focused research, manifest, registry, and rescue validation passed: 76 tests in 4 suites.

Cross-task correction 2026-09-16 (backlog architecture audit). The 2026-09-02 follow-up note above ends 'ASKI-31 AC #3's selection-ceiling before/after under MAE and GMSD was never run, and ASKI-31 stays open.' That was true when written and is now wrong: ASKI-31's close-out ran the missing half the same day. Frozen-preset production-arm MAE ratio after/before was 1.0016 and 1.0085, both inside the 1.01 no-harm guard, with GMSD agreeing in direction; verdict NO HARM, recorded in docs/Research/2026-09-02-aski-31-lattice-no-harm.md. ASKI-31 is Done with AC#3 checked. Nothing in this task depends on ASKI-31 remaining open.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Closed the invalid June dose-response claim with one preregistered exact-lattice calibration. All 64 candidates were valid but inert, so the synthetic dose question is INCONCLUSIVE and chromaShapeAssist stays default-off. Committed the 2,688-row result artifact, replaced the known-issue pins with the settled inert contract, and audited six archived verdict families for lattice and support validity.
<!-- SECTION:FINAL_SUMMARY:END -->
