---
id: ASKI-14
title: Characterize advisory smoke-CI wall time on hosted macOS runners
status: To Do
assignee: []
created_date: '2026-08-18 18:02'
updated_date: '2026-08-24 15:47'
labels:
  - ci
  - enhancement
dependencies: []
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The authoritative quality gate for this package is the full local 'just check' run on developer hardware; hosted CI is an advisory fast-subset smoke only (see AGENTS.md). First public runs (2026-08-18, macos-26 runner) showed the smoke shape completing in ~8 minutes, while accelerator-dependent suites (Metal, snapshot, video) were pathologically slow on the runner VM. Leading hypothesis: the wall-time gap vs local is virtualization, not CPU — the runner VM has no GPU passthrough (Metal tests lose the GPU) and no media-engine access (VideoToolbox falls back to software encode). Investigate within the advisory-smoke frame: profile per-suite timings from smoke logs to rank the remaining cost, evaluate SwiftPM build caching (actions/cache on .build keyed on Package.resolved + Swift version — every job currently cold-builds), and record a characterization of the virtualization penalty. CI must never become a merge gate; do not propose required status checks or full-suite CI runs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Documented per-step and per-suite baseline timing for the advisory smoke run
- [ ] #2 The virtualization hypothesis is confirmed or refuted with per-suite evidence (accelerator-dependent vs CPU-bound suite timings)
- [ ] #3 At least one implemented improvement (e.g. build caching) or a written verdict that current smoke time is acceptable
- [ ] #4 The smoke run stays advisory: no required status checks, no full-suite trigger added
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-22: Context change — hosted CI is now manual-only (workflow_dispatch) and the hosted benchmarks job was removed (ci.yml, commit e0401a9; docs f6ef334). Reason: the repo is private, macOS runners bill at 10x, and always-on CI consumed ~2,800 of ~3,000 included Actions minutes in one billing cycle. Effect on this task: smoke-timing data now accumulates only from hand-fired runs (gh workflow run ci.yml), so characterization is slower and this task is deprioritized. Its premises become attractive again if the repo goes public (standard-runner minutes free) or CI moves to a self-hosted runner. AC #4 (stays advisory, no required checks) is now enforced by the trigger itself.

Board audit 2026-08-24 (deep pass): OBSOLETE-CANDIDATE: ci.yml is workflow_dispatch-only, benchmarks job removed, repo private with Actions off; ACs can only be fed by hand-fired runs nobody produces. Recommend closing as wont-do or parking blocked-on-context; premises revive only if repo goes public or CI moves self-hosted. Owner decision.

Closed 2026-08-24 as wont-do by owner decision after the board audit: CI is workflow_dispatch-only on a private repo with Actions off, the hosted benchmarks job is removed, and the ACs can only be fed by hand-fired runs nobody produces. Premises revive only if the repo goes public or CI moves to a self-hosted runner — refile then.
Historical context (2026-09-23): this describes the pre-publication private repository's CI; re-evaluate before applying it to the public tree.
<!-- SECTION:NOTES:END -->
