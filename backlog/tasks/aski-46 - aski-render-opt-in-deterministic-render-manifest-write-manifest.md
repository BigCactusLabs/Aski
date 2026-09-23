---
id: ASKI-46
title: 'aski render: opt-in deterministic render manifest (--write-manifest)'
status: Done
assignee: []
created_date: '2026-08-21 02:14'
updated_date: '2026-08-21 03:25'
labels: []
dependencies: []
references:
  - 'Source tracker issue #18 (not migrated)'
priority: medium
type: enhancement
ordinal: 48000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Migrated from GitHub issue #18 (full manifest v1 field list and provenance-boundary rules there). Add --write-manifest <path> to the new aski render command only: schemaVersion 1, tool SHA, command id, source path, normalized input dimensions, grid geometry, charset, render settings incl. canonical #RRGGBBAA background, text/PNG artifact records. Sorted keys, trailing newline, atomic write, Draft 2020-12 schema under the governed docs subtree, built from the same in-memory conversion (reuse ToolImageConversion from PR #20) — never reconvert or reopen artifacts. Explicitly an unsigned render record, not a C2PA claim. Blocked until PRs #19/#20 merge.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Manifest byte-deterministic for same checkout/invocation/input
- [ ] #2 Schema committed with a sync test against the report type (mirror the inspect schema drift guard)
- [ ] #3 Manifest write failure returns failure exit code with clear stderr
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-08-21 03:09
---
Implemented on branch aski-46-render-manifest; PR #25 open for owner review. Worker gate green; determinism and failure-exit verified empirically on the built binary.
---

created: 2026-08-21 03:25
---
Merged to main via PR #25 (a8b76b7). Codex review round: path-collision rejection added (bcfa5ad, usage error 64 + guard test); cwd-SHA finding declined as settled pre-existing behavior (SharedOptions.swift). Full just check green on the merged content.
---
<!-- COMMENTS:END -->
