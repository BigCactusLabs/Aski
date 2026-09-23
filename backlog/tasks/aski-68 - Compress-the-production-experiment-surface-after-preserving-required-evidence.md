---
id: ASKI-68
title: Compress the production experiment surface after preserving required evidence
status: Done
assignee: []
created_date: '2026-09-04 03:44'
updated_date: '2026-09-04 13:01'
labels:
  - architecture
  - research-debt
dependencies:
  - ASKI-29
  - ASKI-50
  - ASKI-66
references:
  - docs/Research/2026-09-03-future-direction-and-architecture.md
documentation:
  - docs/Research/2026-09-04-aski68-production-experiment-cleanup.md
modified_files:
  - Sources/Aski/RenderingOptions.swift
  - Sources/Aski/Algorithms/LogPolarKernel.swift
  - Sources/Aski/ShapeMatching.swift
  - Sources/Aski/ASCIICharacterSet.swift
  - Sources/Aski/CharacterSets/StandardCharacterSet.swift
  - Sources/Aski/CharacterSets/RasterizedCharacterSet.swift
  - Tools/AskiColorLab/AskiColorLabCommand.swift
  - Tools/BuildStandardVectors/LegacyShapeChannels.swift
  - Tests/AskiTests/Goldens/command-surface.json
  - docs/Research/2026-09-04-aski68-production-experiment-cleanup.md
  - docs/repo-map.generated.md
  - docs/architecture.md
priority: high
type: chore
ordinal: 69000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Four settled KILL treatments still enlarge the public RenderingOptions surface and hot matcher path: occupancyMatching, shapeStructureAssist, steerableShapeAssist, and inkPreCompensation. chromaShapeAssist is also public, but its former PASS was retracted after ASKI-65 exposed an invalid sampling lattice; its merits remain INCONCLUSIVE under ASKI-66. Historical notes and artifacts are the durable record. Default-off production branches are not.

Do not delete evidence that ASKI-29, ASKI-50, or ASKI-66 still needs. First inventory the exact replay surface. Remove settled controls from the normal public API immediately where replay can remain behind @_spi(AskiResearch); delete their implementation only when the dependent run can be reproduced from the research harness or preserved artifacts. rawDensityValues is not one of the failed treatments and remains available to tone and oracle work. Apply the same inventory to failed temporal research paths, but do not fold stateful temporal conversion into the ordinary converter.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Inventory each public or SPI experiment, every current consumer, the verdict and sampling regime, and the minimum code or artifact required to reproduce open ASKI-29, ASKI-50, and ASKI-66 work.
- [x] #2 Remove occupancyMatching, shapeStructureAssist, steerableShapeAssist, and inkPreCompensation from the normal public product surface; keep only the minimum temporary research SPI required by an explicit open task.
- [x] #3 Demote chromaShapeAssist to research SPI until ASKI-66 settles it; then promote it only on a valid PASS or delete it on KILL or INCONCLUSIVE.
- [x] #4 Delete settled implementation branches after the reproduction dependencies close, while preserving research notes, result artifacts, and Git history.
- [x] #5 Default output is byte-identical, the public option count and production branch count decrease, and just check passes.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Reconciled cleanly to main 8fbb9bb before validation. Re-recorded the command surface, indexed 53 research notes and 106 source files, and corrected one historical local link to identify the retired arm as Git-history-only. Vector audit: 10/10 byte-identical, maximum delta 0, no sort permutation; just regen-vectors produced no ShapeData diff. Focused production/API/temporal/CLI validation passed 215 tests in 36 suites; artifact contracts passed 43 tests in eight suites. Authoritative just check passed 1,394 core tests, 152 serial media tests, two isolated deadlock sentinels, and DocC. No frozen research result artifacts were changed.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architectural review
created: 2026-09-04 13:01
---
Post-refactor review at `952529aa6fdf3f0df6c448c402451e0718f190ab`: ASKI-68, ASKI-71, and ASKI-72 achieved the intended simplification. The default posture after these tasks is architecture stability, not another broad cleanup campaign. New production abstractions or matcher branches should require a concrete product/research need plus measured replacement value; default-off experimentation should remain in labs rather than accumulate in `Sources/`.

The remaining review follow-ups are intentionally narrow: ASKI-75 measures the canonical unified CLI build/link tax without reopening the one-package ruling; ASKI-76 decides the pre-1.0 public charset/research API boundary without changing the validated internal `GlyphBank`; ASKI-73 closes the final response-evidence provenance seam before human scoring. None is a mandate to redesign the converter or package graph.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Removed the five settled default-off experiment families from the public and production surface after their dependencies closed. RenderingOptions fell from 12 public controls to five; LogPolarKernel lost 11 public-option decision branches plus the SPI bottleneck branch, and four converter/temporal ink post-pick hooks were removed. Six dedicated commands and one decisive-production mode, obsolete glyph arrays, implementation code, benchmarks, and dedicated tests were deleted. Historical notes/results, rawDensityValues, v3 binary reproducibility, base residual-map, selection-ceiling, the arbiter, ASKI-69 matcher challenger, and isolated temporal replay paths remain. The full local gate passed 1,548 tests plus DocC, and all 10 vector sets were byte-identical.
<!-- SECTION:FINAL_SUMMARY:END -->
