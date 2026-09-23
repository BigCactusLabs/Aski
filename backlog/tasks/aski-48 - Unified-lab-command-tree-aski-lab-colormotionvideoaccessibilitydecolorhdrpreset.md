---
id: ASKI-48
title: >-
  Unified lab command tree: aski lab
  {color,motion,video,accessibility,decolor,hdr,preset}
status: Done
assignee:
  - '@codex'
created_date: '2026-08-21 02:15'
updated_date: '2026-09-04 07:35'
labels: []
dependencies:
  - ASKI-47
  - ASKI-70
references:
  - 'Source tracker issue #23 (not migrated)'
  - docs/Research/2026-09-03-future-direction-and-architecture.md
priority: medium
type: enhancement
ordinal: 50000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Migrated from GitHub issue #23 (harvested from closed PR #21; full requirements there). After PRs #19/#20 merge and the SAP upgrade (ASKI-47) lands: fold the seven lab executables into importable command modules under aski lab, keep Aski*Lab product names as genuinely thin replay shims for committed research provenance. Hard lessons from #21: root must be async-correct (its binary failed every invocation incl. --help — add at least one test that launches the built executable); namespace commands must not exit 0 where replay twins exit 64; extend the ASTSK-61 golden to the full canonical tree plus replay surfaces — never replace byte-diff fixtures with live spot-checks; include shell completion generation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 aski lab tree functional with replay shims byte-thin
- [x] #2 At least one test launches the built aski binary
- [x] #3 Golden covers full canonical tree and replay surfaces
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Convert the seven lab implementations to importable root-package modules and add explicit historical executable products backed by byte-thin replay targets.
2. Add an importable AskiCLI root with an async-correct `aski` command, a failing-on-bare `lab` namespace, and canonical color, motion, video, accessibility, decolor, hdr, and preset command roots that reuse the existing lab subcommands.
3. Make video execution conform to AsyncParsableCommand without changing its historical argument, help, usage, or exit behavior.
4. Add built-binary launch, replay exit-parity, replay-shim structure, full canonical/replay command golden, and Bash/Zsh/Fish completion-generation coverage.
5. Update Package.swift and the command inventory/architecture/agent references, regenerate guarded artifacts that actually change, and record task evidence only through backlog CLI.
6. Run targeted command tests first, request the shared full-gate window, run `just check`, then finalize and commit locally without pushing.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented the root-package command tree without changing the ASKI-70 package boundary. Historical Aski*Lab products now contain byte-thin replay entry points; canonical `aski lab` commands reuse the importable lab modules; the root and video paths use explicit async runners. Added built-binary launch, replay parity, canonical/replay golden, manifest-structure, and Bash/Zsh/Fish completion tests. Validation: focused ASKI-48 selection passed 15 tests in 4 suites; full `just check` passed format, one build, registry and repo-map drift checks, 1,562 core tests in 230 suites, 152 media tests in 36 suites, 2 deadlock sentinels in 2 suites, and DocC.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-09-04 03:46
---
2026-09-03 architecture ruling: ASKI-70 must measure and decide the lab/product package boundary before this command tree lands. A hard Research package split and importable aski lab modules are not automatically compatible. Preserve the replay contract, but do not force research modules into the product package without a measured decision.
---

author: @codex
created: 2026-09-04 06:09
---
ASKI-70 ruling (2026-09-04): keep the importable lab command modules and thin replay shims in the root Swift package. Do not narrow the aski lab tree to manufacture a package seam. The measured nested-package prototype duplicated Aski artifacts in direct use or pulled the child module back into the root graph, could not consume the unpublished mixed-use AskiToolSupport target, and required a second test-package invocation. Shipping generators and repository-governance tools also stay at root. Evidence: docs/Research/2026-09-04-aski70-package-boundary-measurement.md.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Unified all seven research labs under `aski lab` while preserving each historical Aski*Lab executable as a byte-thin replay surface. Verified exact help/version/error parity, built-binary startup, full command goldens, shell completions, package structure, and the complete local quality gate (1,716 tests in 268 suites plus DocC).
<!-- SECTION:FINAL_SUMMARY:END -->
