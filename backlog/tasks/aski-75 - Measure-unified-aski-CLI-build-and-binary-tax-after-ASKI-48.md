---
id: ASKI-75
title: Measure unified aski CLI build and binary tax after ASKI-48
status: To Do
assignee: []
created_date: '2026-09-04 12:59'
updated_date: '2026-09-04 12:59'
labels:
  - cli
  - build
  - performance
  - architecture
dependencies:
  - ASKI-48
  - ASKI-70
references:
  - Package.swift
  - Tools/AskiCLI/AskiCommand.swift
  - docs/Research/2026-09-04-aski70-package-boundary-measurement.md
priority: medium
type: spike
ordinal: 76000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ASKI-70 correctly killed a nested Research package split, but its product-build measurements predate ASKI-48. ASKI-48 deliberately changed the canonical `aski` executable from the old demo path to `AskiCLIRunner -> AskiCLI`, and `AskiCLI` statically imports all seven lab modules so the new `aski lab ...` tree is discoverable from one command. That is a strong UX simplification, but it may widen the canonical executable's build/link and distribution frontier even though the `Aski` library target itself remains clean.

Measure the cost rather than inferring it from the manifest. Isolate the exact ASKI-48 delta using parent `baca440fa30a1cbaef77636ace411cb39fea4cd0` versus ASKI-48 commit `d7b2a52ac22b9fe1e073bed2e661b3f2c125f612`, then record current-main numbers on the same host/toolchain as a drift check. This task is not permission to reopen ASKI-70 or split the package. Keep the unified CLI unless a measured regression is large enough to justify a narrower implementation strategy that preserves the same command surface and replay behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 On one named host/toolchain, measure at least three clean and three warm `swift build --product aski` samples for the ASKI-48 parent, ASKI-48 commit, and current main; record median wall time and peak RSS with identical cache/setup rules.
- [ ] #2 Measure the resulting `aski` executable's on-disk size and Mach-O/linkage footprint for the same three refs; record link-step timing when it can be isolated reproducibly without changing optimization settings.
- [ ] #3 Measure `swift build --target Aski` on the same refs and confirm ASKI-48 did not widen the downstream library target's dependency frontier; any library-target regression is investigated separately from CLI cost.
- [ ] #4 Preserve the current one-package architecture, `aski lab` command tree, historical replay shims, help/version/error parity, and shell-completion surface during measurement. Do not rename or hide commands to make the numbers pass.
- [ ] #5 Record ACCEPT or INVESTIGATE. ACCEPT when the exact ASKI-48 clean/warm product-build medians do not regress by more than 20% or 15 seconds and no distribution constraint is exposed. INVESTIGATE creates a narrow CLI-linkage optimization task only if that threshold fires; it does not automatically revive a package split.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Create disposable worktrees for `baca440f`, `d7b2a52`, and current main. Record exact macOS, Xcode, Swift, SwiftPM, architecture, and package-cache state.
2. For each ref, run matched clean and warm `swift build --product aski` measurements three times, capture `/usr/bin/time -lp`, and retain complete build logs so link activity can be compared rather than guessed.
3. Record the final executable's byte size and Mach-O load-command/dependency summary, then run matched `swift build --target Aski` measurements to separate canonical-CLI coupling from downstream-library cost.
4. Compare the exact ASKI-48 delta first; use current main only to detect subsequent drift. Apply the frozen 20%-or-15-second investigation threshold without revising it after seeing results.
5. Write a short result note. If ACCEPT, close the task and leave ASKI-48/70 architecture unchanged. If INVESTIGATE, create one narrowly scoped implementation task that preserves the unified command UX and first tests dead stripping/link topology before considering any package-boundary change.
<!-- SECTION:PLAN:END -->
