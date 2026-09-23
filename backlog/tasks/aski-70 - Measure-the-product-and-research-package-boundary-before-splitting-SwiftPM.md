---
id: ASKI-70
title: Measure the product and research package boundary before splitting SwiftPM
status: Done
assignee: []
created_date: '2026-09-04 03:45'
updated_date: '2026-09-04 13:04'
labels:
  - architecture
  - build
  - research
dependencies: []
references:
  - docs/Research/2026-09-03-future-direction-and-architecture.md
  - >-
    https://raw.githubusercontent.com/apple/swift-collections/main/Benchmarks/Package.swift
documentation:
  - docs/Research/2026-09-04-aski70-package-boundary-measurement.md
  - docs/Research/2026-09-03-future-direction-and-architecture.md
modified_files:
  - docs/Research/2026-09-04-aski70-package-boundary-measurement.md
  - docs/Research/2026-09-03-future-direction-and-architecture.md
  - docs/Research/README.md
  - docs/Research/index.json
  - >-
    backlog/tasks/aski-48 -
    Unified-lab-command-tree-aski-lab-colormotionvideoaccessibilitydecolorhdrpreset.md
priority: medium
type: spike
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The root package publishes only Aski and aski, and the Aski library target has no third-party target dependency. The main coupling is repository-side: one AskiTests target depends on most research labs and generators, while just check intentionally builds the full test graph once and reuses it with --skip-build. A nested Research/Package.swift could make the product graph and command boundary clearer, but it does not automatically make downstream Aski consumers compile less.

Measure before moving targets. ASKI-48 also proposes one aski lab command tree with thin replay shims, which conflicts with hard package isolation and must be decided here. Shipping generators, repo-map governance, kernel regeneration, AskiToolSupport, the product CLI, and the authoritative full-repository gate stay supported. A sibling repository is out of scope; only a nested package in this repository is eligible.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Record the current product-only dependency graph, full test graph, clean and warm product build, warm just check/check-fast, peak memory, and the build-once artifact-reuse contract at a named commit with repeated samples.
- [x] #2 Prototype or model at least: current manifest with separated test targets, a nested Research package that depends on the root, and no split. State the package-access or SPI cost of every research touchpoint.
- [x] #3 Resolve ASKI-48 explicitly: either keep importable lab modules and replay shims in the root product boundary, or narrow aski lab before any package move. Shipping generators and repository-governance tools remain at root.
- [x] #4 Verify release preflight, generated-resource drift checks, DocC, shell discovery, research-index generation, and full-repository testing remain one authoritative workflow.
- [x] #5 Record PROMOTE, HOLD, or KILL with measured net benefit. A package move is a separate implementation task; this spike does not change Package.swift.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Freeze commit 8bb6859 and record the machine, toolchain, target graph, import graph, existing gate contract, and no-split control. 2. Run repeated clean and warm product builds plus repeated warm check-fast and check measurements, recording wall time, peak RSS, build output, and build-once --skip-build reuse. 3. Prototype separated test targets and a nested Research package only in disposable copies, record which target edges compile, and enumerate every SPI, testable-import, shared-support, path, command-surface, and package-access cost. 4. Compare no split, separated tests, and nested Research against pre-registered performance, correctness, operability, and reversibility fitness functions; explicitly resolve ASKI-48. 5. Write the evidence-backed verdict note, regenerate the research registry, verify docs and registry, update every ASKI-70 acceptance criterion and final summary through backlog CLI, and commit without changing Package.swift.

Pre-registered decision rule (recorded before timing output was inspected): use three measured samples per timing class and compare medians. PROMOTE only if a boundary prototype preserves every authoritative gate, introduces no root-to-Research cycle or product-only public support API, avoids compiling Aski twice in the authoritative workflow, improves a normal product or fast-loop path by at least 20% or 15 seconds, keeps product build regression at or below 5%, and keeps full-gate wall time and peak RSS regression at or below 10%. HOLD only if a plausible boundary benefit is measurable but a named acceptance dependency (especially ASKI-48) must change first. KILL if the benefit is below the threshold, the package duplicates Aski compilation, it weakens the one-gate build-once contract, or it requires product API solely for research access. No-split is the default counterfactual.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Measured commit 8bb6859e5063599f7b98ccae526a13aea0ee09af on an M3 Max with Swift 6.3.2, three samples per timing class. Median wall time and RSS: clean Aski target 28.79 s and 545849344 B; warm Aski target 10.31 s and 108658688 B; clean aski product 28.00 s and 545374208 B; warm aski product 8.43 s and 121208832 B; clean full test build 113.00 s and 602308608 B; warm check-fast 145.04 s and 698925056 B; warm full check 207.42 s and 1579253760 B. The third check-fast sample overlapped three other checks and is retained with the limitation. The current graph has 17 targets, 15 products, a dependency-free Aski target, one broad AskiTests target, 36 research SPI importers, 110 Aski testable importers, 69 test files importing labs or generators, and 92 AskiToolSupport importers. A separated-test model still compiled ResearchTests for a filtered ProductTests run. The nested model could consume public research SPI, but AskiToolSupport was not a product; direct root and child runs created separate Aski.build trees. A root CLI can depend on a child lab target without a target cycle, but this pulls the child back into the root graph and does not build child tests with the root test graph. ASKI-48 is resolved to the root package. Three frozen-control just check runs passed, release-preflight passed all nine doctor checks, and post-document format, research-registry, repo-map, diff, and no-Package.swift checks passed. No additional full suite was started after the parent reported cross-worktree timing-test contention.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architectural review
created: 2026-09-04 13:04
---
Post-ASKI-48 review does not change the package ruling. The one-package KILL remains the architectural default. It does identify one measurement that ASKI-70 could not contain because its timing control predates the unified command tree: `AskiCLI` now statically depends on all seven lab modules, so the canonical `aski` executable may have a wider build/link and binary frontier while the `Aski` library target remains clean.

ASKI-75 owns that exact before/after measurement using the ASKI-48 parent and implementation commits plus current main. A poor ASKI-75 result may justify a narrow CLI-linkage optimization, but must not be treated as evidence for reviving the nested Research package unless ASKI-70's original falsifiers are independently re-measured and overturned.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
KILL the nested Research package split. Measurements and disposable prototypes show no threshold benefit and show either duplicate Aski artifacts or weaker multi-package gate orchestration. Keep ASKI-48 lab modules and replay shims, AskiToolSupport, shipping generators, governance tools, labs, and tests in the root package. Recorded the evidence and falsifiers in docs/Research/2026-09-04-aski70-package-boundary-measurement.md; updated the earlier architecture decision and research registry; Package.swift is unchanged.
<!-- SECTION:FINAL_SUMMARY:END -->
