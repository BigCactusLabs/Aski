---
id: ASKI-83
title: aski render --output rejects device paths such as /dev/null and /dev/stdout
status: Done
assignee:
  - '@codex'
created_date: 2026-09-27 17:36
updated_date: '2026-11-06T17:30:00Z'
labels:
  - cli
  - correctness
dependencies: []
references:
  - Tools/AskiToolSupport/DemoOutputTransaction.swift
priority: low
type: bug
ordinal: 84000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found 2026-09-27 (Aski HEAD 6b6d251).

REPRO
.build/release/aski render AskiBench/corpus/nasa/nasa-nasa-steerable-v1-vavilov-crater.png --columns 20 --output /dev/null
prints "error: could not stage output '/dev/null'" and exits 70. `--output /dev/stdout` fails the same way.

CAUSE
`DemoOutputTransaction.stage` (Tools/AskiToolSupport/DemoOutputTransaction.swift:75-97) writes each artifact to a sibling staging file next to its destination and then swaps it in. A sibling file cannot be created in /dev, so any device destination fails. The replace step also moves an existing destination aside to a backup sibling; what that would do to a device node where staging did succeed was not tested.

WHY IT MATTERS
Discarding the text grid while keeping `--render-png` is an ordinary scripting need; bcl-web hit it rendering all ten charsets to PNG.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Destinations that are not regular files (character devices, FIFOs) are written directly without staging or backup, or rejected up front with a message that names the reason
- [x] #2 A test covers --output /dev/null alongside --render-png
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Inspect output transaction and classify special destinations before staging. 2. Support ordinary text output to /dev/null and /dev/stdout without replacing device nodes; reject unsupported special targets with explicit diagnostics. 3. Cover /dev/null together with PNG output and preserve regular-file rollback. 4. Run focused regressions, independent review, and the full just check gate.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented direct text streams for /dev/null and /dev/stdout, special-file rejection before staging, and regular-file rollback. Focused batch passed 60 tests across six suites. Native CLI probes passed null+PNG, pipe and regular-file stdout redirection, append, aliases, FIFO rejection and closed-fd rollback. Independent review prompted a confirmed broken-pipe probe: SIGPIPE terminates before cleanup. Descriptor-scoped suppression and an isolated regression are in progress before full acceptance.

Closed-pipe handling is now descriptor-scoped with restoration; four isolated cases prove successful writes, typed failures, rollback, no leftovers and restored flags. All ten CLI subprocess probes pass. Full just check is blocked by existing composition/effect/mask snapshots, reproduced unchanged on clean origin/main 06adfdb. Task remains In Progress pending the repository-wide gate; no golden files or thresholds changed.

Full just check passed on macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Swift 6.4: core 1441 tests, serial media 156, two deadlock sentinels, format/build/drift checks and DocC. An additional parallel-core run passed all 1441 tests. ASKI-97 resolved the independent baseline blocker without changing production rendering, ShapeData, frozen Vesper output or exact-comparison thresholds.

2026-11-06 correction: the ASKI-97 re-baseline cited above was withdrawn (host-dependent drift; original goldens restored in 25460c3). This task's closure does not depend on it: with the original goldens, full just check passed on an Apple M3 Max host with macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Swift 6.4 (1441 core, 156 media, 2 sentinels, DocC). The snapshot mismatches seen earlier were host-dependent raster drift unrelated to this change; ASKI-78 owns that policy.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Text output to /dev/null and /dev/stdout writes directly, including supported aliases; unsupported special targets fail before staging. Companion regular files retain transactional rollback. Descriptor-scoped SIGPIPE handling reports closed-pipe errors and restores flags without changing process-wide signals. Focused tests, ten native CLI scenarios and the full local gate pass with the original render goldens on an M3 Max macOS 27.0.1 host; the ASKI-97 re-baseline was withdrawn.
<!-- SECTION:FINAL_SUMMARY:END -->
