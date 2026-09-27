---
id: ASKI-83
title: aski render --output rejects device paths such as /dev/null and /dev/stdout
status: To Do
assignee: []
created_date: '2026-09-27 17:36'
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
- [ ] #1 Destinations that are not regular files (character devices, FIFOs) are written directly without staging or backup, or rejected up front with a message that names the reason
- [ ] #2 A test covers --output /dev/null alongside --render-png
<!-- AC:END -->
