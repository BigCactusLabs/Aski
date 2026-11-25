---
id: ASKI-75
title: Measure unified aski CLI build and binary tax after ASKI-48
status: To Do
assignee: []
created_date: '2026-09-04T12:59:00Z'
updated_date: '2026-11-25T18:53:56Z'
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
ASKI-70 correctly killed a nested Research package split, but its product-build measurements predate ASKI-48. ASKI-48 deliberately changed the canonical `aski` executable from the old demo path to `AskiCLIRunner -> AskiCLI`, and `AskiCLI` statically imports the lab modules (six since PR #30 removed the preset lab: AskiAccessLab, AskiColorLab, AskiDecolorLab, AskiHDRLab, AskiMotionLab, AskiVideoLab) so the `aski lab ...` tree is discoverable from one command. That is a strong UX simplification, but it may widen the canonical executable's build/link and distribution frontier even though the `Aski` library target itself remains clean.

Measure the current cost rather than inferring it from the manifest. Compare current main against a lab-free control of the same commit: a disposable, never-committed patch that removes the lab imports and the `lab` command group from `AskiCLI`. Run both on one named host with the toolchain and build backend pinned. This task is not permission to reopen ASKI-70 or split the package. Keep the unified CLI unless a measured cost is large enough to justify a narrower implementation strategy that preserves the same command surface and replay behavior.

Rescoped 2026-11-24 by owner decision: the original exact-delta arm (ASKI-48 parent baca440 versus ASKI-48 commit d7b2a52) is dropped. Both are private-history commits absent from the public repository, and numbers measured on them with Swift 6.3.2 and the native backend would not be comparable with the current Swift 6.4 / swiftbuild default.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 On one named host, with the macOS, Xcode and Swift versions and the build backend recorded and pinned, measure at least three clean and three warm `swift build --product aski` samples for current main and for the lab-free control of the same commit; record median wall time and peak RSS with identical cache/setup rules.
- [x] #2 Measure the resulting `aski` executable's on-disk size and Mach-O/linkage footprint for both builds; record link-step timing when it can be isolated reproducibly without changing optimization settings.
- [x] #3 Measure `swift build --target Aski` at current main and confirm the library target's dependency frontier contains no lab or CLI module; any library-target regression is investigated separately from CLI cost.
- [x] #4 Preserve the current one-package architecture, `aski lab` command tree, historical replay shims, help/version/error parity, and shell-completion surface. The lab-free control exists only in a disposable worktree; do not rename or hide commands to make the numbers pass.
- [ ] #5 Record ACCEPT or INVESTIGATE. ACCEPT when current main's clean and warm product-build medians do not exceed the lab-free control's by more than 20% or 15 seconds and no distribution constraint is exposed. INVESTIGATE creates a narrow CLI-linkage optimization task only if that threshold fires; it does not automatically revive a package split.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Create two disposable worktrees at the same current-main commit; in one, apply a measurement-only patch that removes the lab imports and the `lab` command group from AskiCLI. Record exact macOS, Xcode, Swift, SwiftPM, build backend, architecture, and package-cache state.
2. For each build, run matched clean and warm `swift build --product aski` measurements three times with the build backend pinned, capture `/usr/bin/time -lp`, and retain complete build logs so link activity can be compared rather than guessed.
3. Record each executable's byte size and Mach-O load-command/dependency summary, then run matched `swift build --target Aski` at current main to separate canonical-CLI coupling from downstream-library cost.
4. Apply the frozen 20%-or-15-second threshold without revising it after seeing results.
5. Write a short result note. If ACCEPT, close the task and leave the ASKI-48/70 architecture unchanged. If INVESTIGATE, create one narrowly scoped implementation task that preserves the unified command UX and first tests dead stripping and link topology before considering any package-boundary change.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Audit 2026-11-12: baca440 and d7b2a52 are private-history commits, absent from this checkout; the measurement needs the private archive or a re-based public commit pair.

Audit 2026-11-24: rescoped by owner decision before any measurement, so the threshold is not chosen after seeing results. Description, AC#1-5 and plan rewritten: the private-history before/after pair is dropped; the 20%-or-15-second threshold is kept and now applies to current main versus the lab-free control. ASKI-70's control numbers were taken with native Swift 6.3.2 and are not comparable with a Swift 6.4 / swiftbuild run.

Run 2026-11-25 (ASKI-75 r1, measured revision 99fc4c7): main vs lab-free control of the same commit on Apple M5 Max, macOS 27.2.1, Xcode 27.2, Swift 6.4.2, --build-system swiftbuild pinned. Clean product-build median 9.95 s vs 7.84 s (+2.11 s, +26.9%); warm no-op 1.29 s vs 1.14 s (+13.2%); link-only +0.20 s. Pre-registered reading (either the 20% or the 15 s limit fires) gives INVESTIGATE; the both-limits reading would give ACCEPT. Max single-process build RSS 2.17 GiB vs 0.73 GiB. Executable debug 13.3 MB vs 6.4 MB, release 8.7 MB vs 4.0 MB; adds CryptoKit and libswift_errno; no distribution constraint found. Aski target frontier is {Aski}; swift build --target Aski compiles no lab or CLI module. Note: docs/Research/2026-11-25-aski75-cli-build-tax.md; packet: Scripts/research/aski75-2026-11-25/. AC#5 stays unchecked until the narrow CLI-linkage follow-up drafted in the note is filed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
INVESTIGATE under the frozen AC#5 rule: the unified aski lab tree costs +2.11 s (+26.9%) on a clean debug product build and +0.15 s (+13.2%) on a warm no-op build against a lab-free control of 99fc4c7, roughly doubles the executable, and triples the peak single-process build RSS. No distribution constraint; the Aski library target is unaffected. Architecture, the aski lab tree and replay surface are unchanged. Evidence: docs/Research/2026-11-25-aski75-cli-build-tax.md.
<!-- SECTION:FINAL_SUMMARY:END -->
