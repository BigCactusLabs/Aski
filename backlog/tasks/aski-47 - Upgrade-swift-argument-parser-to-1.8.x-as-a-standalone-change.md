---
id: ASKI-47
title: Upgrade swift-argument-parser to 1.8.x as a standalone change
status: Done
assignee: []
created_date: '2026-08-21 02:15'
updated_date: '2026-08-21 23:15'
labels: []
dependencies: []
references:
  - 'Source tracker issue #22 (not migrated)'
priority: medium
type: enhancement
ordinal: 49000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Migrated from GitHub issue #22 (harvested from closed PR #21). Standalone PR, green local gate required. Known landmines from PR #21's failure: (1) changing the SAP requirement invalidates Package.resolved originHash and forces a full re-resolve, which floats package-benchmark to 1.36.2 where the Jemalloc trait no longer exists — hold package-benchmark below 1.36 or adopt the new trait names deliberately (with the hold, the full gate passed on the #21 branch); (2) regenerate Package.resolved on the actual macOS toolchain; (3) verify the ASTSK-61 command-surface golden against 1.8.x _dumpHelp serialization.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Own PR; full just check green; no feature changes riding along
- [x] #2 package-benchmark resolution pinned or migrated deliberately
- [x] #3 Command-surface golden verified or regenerated against 1.8.x serialization
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented on branch aski-47-sap-upgrade; PR #26 open for review 2026-08-21. SAP resolves 1.8.2; package-benchmark held at 1.35.0; ASTSK-61 golden regenerated (serialization-only diff, command set identical); just check green 182.8s.

Merged to main via PR #26 (8d422fa) 2026-08-21; CHANGELOG Unreleased entry added; worktree and branch removed.
<!-- SECTION:NOTES:END -->
