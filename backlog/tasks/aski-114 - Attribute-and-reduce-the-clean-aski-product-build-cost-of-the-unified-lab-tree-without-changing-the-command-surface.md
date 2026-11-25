---
id: ASKI-114
title: >-
  Attribute and reduce the clean aski product-build cost of the unified lab tree
  without changing the command surface
status: To Do
assignee: []
created_date: '2026-11-25T18:57:02Z'
updated_date: '2026-11-25T19:10:46Z'
labels:
  - cli
  - build
  - performance
dependencies:
  - ASKI-75
priority: low
ordinal: 115000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ASKI-75 (docs/Research/2026-11-25-aski75-cli-build-tax.md) returned INVESTIGATE under its frozen AC#5 rule: at 99fc4c7, with Swift 6.4.2 and Swift Build, a clean debug `swift build --product aski` takes 9.95 s versus 7.84 s for a lab-free control of the same commit (+2.11 s, +26.9%). The largest single build process peaks at 2.17 GiB versus 0.73 GiB, and the executable roughly doubles (release 8.7 MB vs 4.0 MB; AskiColorLab is 2.4 MB of linked symbols and brings in CryptoKit). The reading that decided the verdict (either the 20% or the 15 s limit fires) was fixed before measurement; under the other reading (both limits) the result would have been ACCEPT, and the 15 s limit was not approached. AC#5 requires this narrow follow-up whenever INVESTIGATE fires.

Attribute the cost first, then test at most two link-topology or module-layout options that keep `aski lab ...` identical. This task does not reopen ASKI-70's package-split decision and does not authorize renaming, hiding or removing commands.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Attribute the clean-build excess and the 2.17 GiB peak build process to modules on a named host with the build backend pinned (for example with --experimental-trace-events-file and per-process memory sampling), before any option is built
- [ ] #2 Prototype at most two options that keep the aski lab tree, replay shims, help/version/error parity, metadata and shell completions identical (the command-surface golden unchanged), and measure each with Scripts/research/aski75-2026-11-25/sample.sh against the same frozen 20%-or-15-second rule and reading
- [ ] #3 Record KEEP or ADOPT in a research note; an adopted change must remove complexity or be justified by the measured saving, and just check passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-25: the owner left the AC#5 reading of "20% or 15 seconds" to the lead. The lead kept reading (a), "either limit fires", which matches ASKI-70's use of the same wording, so this task stays open.
<!-- SECTION:NOTES:END -->
