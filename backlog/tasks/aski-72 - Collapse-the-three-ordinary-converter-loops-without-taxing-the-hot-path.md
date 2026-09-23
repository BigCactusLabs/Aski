---
id: ASKI-72
title: Collapse the three ordinary converter loops without taxing the hot path
status: Done
assignee: []
created_date: '2026-09-04 03:45'
updated_date: '2026-09-04 10:43'
labels:
  - architecture
  - performance
dependencies:
  - ASKI-16
  - ASKI-68
  - ASKI-69
references:
  - docs/Research/2026-09-03-future-direction-and-architecture.md
  - docs/Research/2026-09-04-aski72-converter-engine-consolidation.md
priority: medium
type: chore
ordinal: 73000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ASCIIConverter currently repeats preparation, kernel construction, row walking, ink handling, and cell construction across ordinary, ranked-candidate, and residual conversion. Consolidate those paths after the surviving production algorithms and matcher are known. The shared engine must specialize result capture: ordinary conversion must not allocate or sort ranked candidates, and residual conversion must not manufacture data its contract does not use.

Stateful temporal conversion is out of scope because it owns cross-frame history. dotMatrix also remains a specialized serial conversion kernel while it is retained; its Floyd-Steinberg error changes selection and cannot be moved to a renderer or post-process.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Extract one shared preparation and row-walk skeleton used by ordinary, ranked, and residual conversion, with statically specialized or equivalently zero-overhead capture policies.
- [x] #2 The ordinary path calls only the minimum score interface and does not construct ranked arrays, residual payloads, or per-cell dynamic dispatch.
- [x] #3 dotMatrix capabilities are explicit: serial traversal, one meaningful winner, and no meaningful residual; no fabricated generic results are required.
- [x] #4 Temporal conversion remains separate and its state and concurrency invariants do not enter the ordinary engine.
- [x] #5 Default and diagnostic outputs are byte-identical, allocation and conversion benchmarks are neutral or better, production duplication and line count decrease, and just check passes.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Freeze plain, ranked, and residual conversion fingerprints across logPolar/dotMatrix, masks, invalid/empty inputs, rank strides 1/6, NaN residuals, serial/parallel execution, and repeat determinism on untouched production. 2. Record baseline wall, CPU, and malloc distributions for representative plain/ranked/residual/dotMatrix conversions. 3. Introduce one internal statically specialized conversion preparation and row-walk engine over GlyphBank, preserving dotMatrix serial/stateful semantics and keeping temporal separate. 4. Prove byte parity, no new plain-path storage/allocation, neutral-or-better performance, and at least 60 net production lines removed. 5. Update architecture documentation and the generated repo map, obtain independent architecture/concurrency and test/performance reviews, then run focused checks and the full local gate before completion.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented one generic ConversionEngine row walk with concrete plain, ranked, and residual captures. Dispatch occurs once per conversion; dotMatrix remains forced serial; temporal conversion is byte-unchanged. Replaced the fabricated AlgorithmKernel surface with the real CharacterScoring capability and surface-specific dot-matrix semantics. Frozen 16 named fingerprints repeat the full matrix twice. Focused validation passed 51 tests in 15 suites. Independent architecture/concurrency and test/performance reviews are clean after fixing final-binary provenance, dot ranked/residual forced-parallel parity, and exact mask metadata coverage. Final performance uses release binary SHA-256 e93516a93a82e1e1846d2f31519ba2da695e212727737a8ae33b3469b1ce6dda: allocation counts are exactly unchanged in all four cases; wall p50/p90 stays within 2.5 percent; no benchmark threshold changed. Fixed production scope fell from 1,024 to 962 lines (-62). Format, research registry (54 notes), repo map (108 source files), and full just check passed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Consolidated ordinary, ranked, and residual conversion into one statically specialized row-walk engine without changing output bytes or dot-matrix/temporal semantics. Verified with 16 frozen fingerprints, a 51-test focused suite, two independent reviews, exact allocation parity, neutral-or-better release timings, a 62-line production reduction, and the complete local just check gate.
<!-- SECTION:FINAL_SUMMARY:END -->
