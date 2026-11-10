---
id: ASKI-97
title: Restore exact render snapshot baselines on macOS 27.0.1
status: To Do
assignee:
  - '@codex'
created_date: '2026-11-05T18:37:00Z'
updated_date: '2026-11-06T17:30:00Z'
labels:
  - gate
dependencies: []
references:
  - docs/Research/2026-09-04-aski51-core-text-drift-policy.md
  - docs/Research/Results/2026-11-05-aski97-render-drift/README.md
priority: high
type: bug
ordinal: 98000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Untouched origin/main 06adfdb reproduces 16 exact image mismatches against the macOS 27.0 goldens on macOS 27.0.1 with the same Xcode 27.0 / Swift 6.4 compiler. These block completion of ASKI-8 and ASKI-83. Preserved captures differ by at most one 8-bit channel step, with identical dimensions, alpha and color metadata; repeated isolated renders are byte-identical. Establish the narrow permissible baseline correction without hiding a rendering regression.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Per-image drift measurements, repeatability and rendering/comparison attribution limits are recorded with toolchain provenance.
- [x] #2 The vector audit and frozen-preset checks are applied without regenerating ShapeData; any frozen-preset golden movement carries the required MAE/GMSD census.
- [ ] #3 Only supported deterministic baseline changes are adopted; exact comparison and existing thresholds remain unchanged.
- [x] #4 The relevant snapshots and full just check pass on the final tree.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Preserve baseline and changed-tree failures and compare decoded images and comparator behavior. 2. Apply the existing ASKI-51/77 policy, audit vectors, verify frozen preset and independently review the evidence. 3. Update only justified render goldens and provenance. 4. Run targeted and full gates, then close the blocked task records.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Full just check passed on macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Swift 6.4: core 1441 tests, serial media 156, two deadlock sentinels, format/build/drift checks and DocC. An additional parallel-core run passed all 1441 tests. ASKI-97 resolved the independent baseline blocker without changing production rendering, ShapeData, frozen Vesper output or exact-comparison thresholds. The unchanged origin control reproduced all 16 candidates byte-for-byte in a parallel 1434-test run. Candidate selected snapshots plus VesperPresetTests passed 10 tests. Independent evidence review accepted the narrow rebaseline conditionally on the full gate and extra parallel-core pass; both conditions are now met. Exact old-OS causality remains unproved, and the earlier single mask-before pass did not reproduce. The triggered vector audit remains owned by ASKI-78; no ShapeData regeneration. Two tooling footguns encountered in evidence preparation were recorded in blotter.

2026-11-06: re-baseline WITHDRAWN (owner ruling). An Apple M3 Max host with the same macOS 27.0.1 (26A434), Xcode 27.0 (27A266a) and Swift 6.4 did not reproduce the drift: in detached checkouts the composition, effect-kernel and mask snapshot suites pass 11/11 at 06adfdb and fail exactly the 16 replaced PNGs (one 8-bit step each) at 14c8697. Identical OS and Xcode builds disagree, so the drift is host-dependent (hardware, GPU or other host state), not an OS patch-version change. Commit 25460c3 restores the 16 PNGs to their 06adfdb bytes, rewrites the CONTRIBUTING paragraph, and marks the drift result withdrawn while keeping its measurements. On the M3 Max host the restored goldens pass the three snapshot suites (11 tests) and full just check (1441 core, 156 media, 2 sentinels, DocC). AC3 is unchecked because the replacement was not a supported baseline change. Host-dependent exact rasters remain unresolved and belong with ASKI-78's platform raster policy.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Re-baseline withdrawn. The 16 PNG replacements reproduced only on the recording host; an M3 Max host with the same macOS 27.0.1 and Xcode 27.0 builds passes the original goldens and fails the replacements. Original goldens restored in 25460c3; drift measurements kept as history in docs/Research/Results/2026-11-05-aski97-render-drift/. Open until ASKI-78 sets a policy for host-dependent exact rasters.
<!-- SECTION:FINAL_SUMMARY:END -->
