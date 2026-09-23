---
id: ASKI-36
title: Audit preconditions buried in internal helpers reachable only from public API
status: Done
assignee: []
created_date: '2026-08-20 03:15'
updated_date: '2026-08-24 03:45'
labels:
  - correctness
  - robustness
  - audit
dependencies: []
references:
  - Sources/Aski/ShapeMatching.swift
  - Sources/Aski/ASCIIConverter.swift
  - Sources/Aski/Animation/BitSet.swift
  - Sources/Aski/Algorithms/LumaResample.swift
  - Sources/Aski/CharacterSets/StandardCharacterSet.swift
priority: medium
type: spike
ordinal: 38000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Batch A batch (ASKI-6/17/18/19/23/24) fixed six instances of one defect shape: a public API accepts a value it never validates, and the process traps far from the call the caller wrote. A sweep for siblings found that the shape is systemic in the internal helpers, not limited to the six filed sites.

Buried precondition sites found, each reachable only indirectly from public API:
- ShapeMatching.swift:16-639 — dozens of preconditions inside internal matching-kernel functions, several calls deep from public ASCIIConverter API. A count or dimension mismatch traps deep in the stack, the same class as the EdgeMapKernel and DotMatrixKernel defects filed as ASKI-23
- ASCIIConverter.swift:171 — precondition(candidateStride > 0), on a value computed from RenderingOptions rather than passed directly
- Animation/BitSet.swift:11 and :22 — precondition(index >= 0 && index < count) in an internal bit-indexing helper on the animation hot path
- Algorithms/LumaResample.swift:9-10 — preconditions on src.count and dimensions computed upstream
- CharacterSets/StandardCharacterSet.swift:26 — fatalError in the static bundled-resource loader; crashes hard if a bundle resource fails to load

This is filed as a spike, not a fix: the useful output is a classification, not a mechanical conversion of every precondition into a thrown error. Many of these are correct internal invariants that should stay exactly as they are. The question worth answering is which of them can be driven out of domain by a public caller — those are latent versions of the bugs Batch A just fixed.

Deferred from the Batch A work to avoid widening that batch mid-flight.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every precondition and fatalError in Sources/Aski is classified as: enforced-at-a-public-boundary, an internal invariant no public caller can violate, or a latent public-input trap
- [x] #2 Each latent public-input trap is filed as its own task with the public call path that reaches it
- [x] #3 The classification records which public entry point guarantees each internal invariant, so a future entry point cannot silently bypass it
- [x] #4 No behaviour changes land under this task; it produces the audit and the follow-up tasks only
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Executed 2026-08-23 by a read-only audit worker, verified and landed by the orchestrator. Classification: 36 class-A (enforced at a public boundary), 56 class-B (internal invariants with their guaranteeing entry points recorded), 18 class-C (latent public-input traps). Full tables: docs/Research/2026-08-23-aski36-trap-audit.md. DELIBERATE DEVIATION from AC#2 as written: the 18 class-C sites were filed as ONE consolidated task (ASKI-53) rather than 18, because all share a single root cause — ASCIIConverter accepts ASCIICharacterSet conformances without validating the parallel-array invariant — and one boundary validation fixes every path; 18 tasks would have been 18 duplicates of that sentence. Each site and its trigger path is preserved verbatim in the note's class-C table. AC#4 held: no behaviour changed.
<!-- SECTION:NOTES:END -->
