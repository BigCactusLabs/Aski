---
id: ASKI-33
title: >-
  Algorithm kernel scalars from public options are unvalidated and trap in Int
  conversion
status: Done
assignee: []
created_date: '2026-08-20 03:14'
updated_date: '2026-08-24 15:36'
labels:
  - correctness
  - algorithms
  - robustness
dependencies: []
references:
  - Sources/Aski/Algorithms/LogPolarKernel.swift
  - Sources/Aski/Algorithms/SteerableEnergy.swift
  - Sources/Aski/Algorithms/EdgeMap.swift
  - Sources/Aski/RenderingOptions.swift
priority: high
type: bug
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Same defect class as the ASKI-6/17/18/19/23/24 batch, in the matching kernels: a public scalar is accepted with no validation, then converted to Int deep inside an algorithm where the caller cannot see the failure.

`RenderingOptions.density` is a public field with no clamp at any boundary. It reaches six unguarded conversions:
- LogPolarKernel.swift:69, :86, :105, :148, :257 — `Int((context.options.density * 24).rounded())`
- LogPolarKernel.swift:422 — `Int((context.options.occupancyMatching * Float(...)).rounded())`, same pattern on a second public knob

A non-finite or extreme `density` therefore traps in the matcher rather than at the `convert` call.

Caller-supplied `sigma` has the same shape in two more kernels:
- SteerableEnergy.swift:56 — `Int(Foundation.ceil(3 * sigma))`, no isFinite check
- EdgeMap.swift:78 — `max(1, Int((3 * sigma).rounded(.up)))`, no isFinite check

Found by a variant sweep during the Batch A validation work (ASKI-6/17/18/19/23/24); deliberately deferred to avoid widening that batch mid-flight. Not covered by any filed task.

Note the batch settled a per-subsystem convention that this task should follow rather than relitigate: structural parameters are rejected at the public boundary by precondition, aesthetic ones are clamped via sanitizedClamped, and derived arithmetic that can overflow from in-domain input must degrade rather than trap.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every conversion listed above is either bounded before the Int conversion or fed by a value validated at the public boundary, following the convention already established in the Batch A work
- [x] #2 density and occupancyMatching have a documented valid domain, and an out-of-domain value is rejected or clamped by one stated rule rather than trapping in LogPolarKernel
- [x] #3 sigma is validated or bounded at both SteerableEnergy and EdgeMap call sites under the same rule
- [x] #4 Regression covers non-finite and extreme-but-finite density, occupancyMatching and sigma through the public convert path
- [x] #5 Output for all currently-valid parameter values is byte-identical, and just check passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board audit 2026-08-24: implemented and merged to main in PR #28 (batch-validation wave, merge b835160); all ACs were already checked — status flip only.
<!-- SECTION:NOTES:END -->
