---
id: ASKI-74
title: Validate Swift 6.4 fix for case-only product collisions
status: Done
assignee: []
created_date: 2026-09-04 08:24
updated_date: '2026-11-14T17:38:00Z'
labels:
  - toolchain
  - ci
  - build
dependencies: []
references:
  - Package.swift
  - docs/Research/2026-09-04-aski41-swift-build-migration-gate.md
  - >-
    https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/SwiftBuildPreview.md
  - https://github.com/swiftlang/swift-package-manager/issues/9184
  - https://github.com/swiftlang/swift-package-manager/pull/10067
priority: medium
type: spike
ordinal: 75000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ASKI-41 found deterministic full-graph failures under Apple Swift 6.3.2. A throwaway ASKI-74 feasibility worktree at d12f158 renamed the historical demo target and seven internal lab modules while preserving product names. Those changes removed the previously observed AskiDemo shadow and lab product/module diagnostics, but two clean Swift Build attempts then exposed the controlling blocker: the public Aski library product and required aski executable product share a case-insensitive Swift Build target namespace. The executable compile consumed the 107-file Sources/Aski Swift file list and failed because main.d was absent.

The official Swift Build preview guide documents this exact unsupported class and links swift-package-manager#9184. Upstream PR #10067 merged its regression coverage to release/6.4.x; the fixture pairs a MyProduct library with lower-case executable-product variants backed by differently named executable targets. No Swift 6.3 manifest setting can retain both Aski and aski while changing the product-derived Swift Build target name. Scratch-path only relocates the shared output root, moduleAliases do not rename this root package module, and a case-sensitive volume is not a portable project contract.

Do not implement a Swift 6.3 repo workaround. On a genuine side-by-side Xcode 27 / Swift 6.4 toolchain, validate the upstream fix against the unchanged one-package Aski graph. Preserve the public Aski module, aski, AskiDemo, all seven legacy lab product names, unified routing, and replay behavior. This task remains the prerequisite for ASKI-41 full requalification.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 From a fresh current-main checkout, swift build --build-tests --build-system swiftbuild succeeds with the unchanged one-package graph; neither the Aski/aski case-only corruption nor the earlier demo/lab collision diagnostics occur.
- [x] #2 Filtered and full Swift Build tests run from the built graph, and build-once then test/run --skip-build reuse succeeds with an explicit backend on every SwiftPM command.
- [x] #3 The aski command, AskiDemo, and all seven lab products preserve help, version, bare-exit, unified-routing, and generated-artifact behavior against the native backend.
- [x] #4 Resources remain byte-identical; research-index and repo-map checks detect reversible drift; DocC plus Markdown export and the benchmark plugin succeed under Swift Build.
- [x] #5 Sources, Package.swift, Package.resolved, public and executable product names, swift-tools-version, and the one-package architecture remain unchanged; a final native just check passes before any completion commit.
- [x] #6 The validation runs on the installed final Xcode 27 / Apple Swift 6.4 toolchain (now the selected default); record xcodebuild -version and xcrun swift --version with the results.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Wait for a genuine final Xcode 27 / Swift 6.4 installation. Do not install a toolchain or change the global Xcode selection as part of this task.
2. Create fresh native and Swift Build worktrees from the same current-main commit. Record exact Xcode, Swift, SwiftPM, SDK, OS, and filesystem context. Select the side-by-side toolchain with DEVELOPER_DIR and use an explicit backend on every SwiftPM command.
3. Run a clean Swift Build build-tests command first. Inspect the generated graph and logs for the prior AskiDemo shadow, seven lab basename collisions, and Aski/aski file-list corruption. If the upstream 6.4 fix does not hold, keep the task open and report the upstream failure; do not rename required names or add package/wrapper ceremony.
4. If the clean graph passes, run filtered and full skip-build tests, all package tools with drift falsification, resource parity, DocC plus Markdown, the benchmark plugin, and native-versus-Swift-Build command/replay parity. Keep runs serial.
5. Record the compatibility result in the ASKI-41 verdict note and generated research index. Mark ASKI-74 Done only when every acceptance criterion passes, then let ASKI-41 repeat its frozen performance and promotion lane.

2026-11-13 execution: validate the unchanged current-main graph on selected final Xcode 27 / Swift 6.4 with an explicit swiftbuild backend; capture the first clean build and stop the dependent validation matrix if it fails. Current upstream sources were checked again; preserve the package and product names.

2026-11-13 continuation: prepare an opt-in exact pre-encoder input comparison for all 36 HDR fixture/k cases, using the existing renderer, encoder and frozen HDR gates. Commit the rule before native captures. Compare two independent invocations per backend with repeated encodes of identical inputs; retain any unresolved cross-backend-only effect. Finish an explicitly native full gate without changing product/source/manifest names or the canonical gate ordering.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-09-04 feasibility result under Xcode 26.5 / Apple Swift 6.3.2: an uncommitted throwaway tree removed the initially observed demo and seven lab diagnostics. Native targeted tests passed (35 tests in four suites) and just check-fast passed (823 tests in 155 suites). Clean Swift Build build-tests then failed twice at 98% after 35.82s and 34.79s because AskiCLIRunner was invoked with an aski.SwiftFileList containing 107 Sources/Aski files. The partial implementation was deliberately not committed. Official evidence identifies this as the documented case-insensitive executable/library product-name limitation fixed for release/6.4.x, so the task is retargeted to validate that upstream fix.

### Implementer context — 2026-09-10 (base 952529a)

**Current state:** ASKI-74 is To Do and is the prerequisite for ASKI-41. The checked-in feasibility record describes a failed Swift Build run under a Swift 6.3.2 environment: an earlier throwaway target/module rename removed AskiDemo and seven lab diagnostics, then the unchanged required public `Aski` library and lowercase `aski` executable product collided case-insensitively in Swift Build output; the executable consumed the library file list and failed with missing `main.d`. This is recorded evidence, not a reason to alter the package.

**Start here:** Read the ASKI-74 task and `docs/Research/2026-09-04-aski41-swift-build-migration-gate.md` sections on the feasibility correction and promotion gates. Inspect `Package.swift` product declarations and target paths. The validation must preserve public `Aski`, executable `aski`, `AskiDemo`, `AskiTileMatrix`, and all seven legacy lab products (`AskiColorLab`, `AskiMotionLab`, `AskiVideoLab`, `AskiAccessLab`, `AskiDecolorLab`, `AskiHDRLab`, `AskiPresetLab`). `UnifiedLabCommandTests`, `CommandSurfaceGoldenTests`, and `ResearchManifestTests` encode help/version/bare-exit, replay, golden, and runner-discovery contracts.

**Constraints and dependencies:** Wait for a genuine final side-by-side Xcode 27/Swift 6.4 toolchain and select it per command; do not install, change global Xcode selection, or treat the dated note’s toolchain/install inventory as current. Do not rename required products/modules, split SwiftPM, add wrappers/symlinks, rely on a case-sensitive volume, or invent a Swift 6.3 manifest workaround. Keep `swift-tools-version: 6.3`, one package, `Sources/`, `Package.resolved`, unified routing, replay behavior, and generated artifact inputs unchanged. The task specifically validates the upstream case-only product fix attributed in the note to SwiftPM PR #10067.

**Validation to run:** From fresh current main, run every SwiftPM command with `--build-system swiftbuild`: clean `swift build --build-tests`, filtered and full tests, build-once then `test/run --skip-build`, all product help/version/bare and canonical routing checks, resource byte parity, reversible ResearchIndex/RepoMap drift checks, whole-package symbol graph, DocC validation plus `--emit-markdown`, and the benchmark plugin. Compare native and Swift Build command/replay behavior. Re-run native `just check` before completion; do not mark Done unless every acceptance criterion passes.

**First step:** Perform live toolchain discovery, then run the clean unchanged-graph Swift Build build. If the upstream fix does not hold, record the failure and keep ASKI-74 open for the next upstream/toolchain validation.

Source map: `Tests/AskiTests/UnifiedLabCommandTests.swift`, `Tests/AskiTests/CommandSurfaceGoldenTests.swift`, `Tests/AskiTests/ResearchManifestTests.swift`, `Scripts/validate-docc.sh`.

Audit 2026-11-12: Swift 6.4 / Xcode 27 is now the installed default, so the wait condition is met; the side-by-side premise of AC#1 no longer applies. The title and filename differ.

2026-11-13: owner ruling: AC#1 re-scoped. The original criterion (a final toolchain side-by-side via DEVELOPER_DIR without a global Xcode change) no longer applies because Xcode 27 / Swift 6.4 is the installed default. The replacement criterion is now the last in the list. The task is unblocked.

2026-11-13 explicit-backend replay: unchanged clean Swift Build graph passed; filtered 30 tests and full 1537 core / 177 media / 2 sentinels passed with skip-build. Native control build, 112 command-surface comparisons, 15 resource-copy byte checks, reversible index drift rejection/restoration, explicit Swift Build symbol graph, DocC/Markdown, six-workload benchmark exports and final unmodified just check passed. Final canonical gate used default Swift Build (206.05s), not explicit native. All 28 seven-lab artifact commands succeeded; HDR metadata and existing gates agree, but some decoded cross-backend measures exceed the one same-native repeat envelope. Keep task open pending owner review. Extra generator checks show identical kernel regeneration and vector-audit drift on both backends; source/resources preserved. Research note records exact bounds and limitations.

Lead review: AC1, AC2, AC4 and AC6 are established by the unchanged-graph explicit-backend captures. AC3 stays open for HDR artifact parity; a single same-backend repeat is not a noise bound. AC5 stays open because the unmodified canonical just check passed using the installed Swift Build default, not an explicit legacy-native backend. Compact evidence is in Scripts/research/aski74-2026-11-13/readout.json. The vector drift repeats the existing ASKI-78 finding. No production bytes or acceptance thresholds changed.

2026-11-13 pause checkpoint: the explicit legacy-native full just check passed on original product base e9ac79bd48ab0d387d85cedf15f5bab244fc0aad plus five reviewed test/lab diagnostic files. Core 1538, media 177, two deadlock sentinels and DocC passed. The seven logged SwiftPM calls all selected native; exactly one initial build was followed by skip-build drift/test phases. All 1194 source hashes remained unchanged, including production Sources, Tools, Package.swift and Package.resolved. AC5 is established for this frozen snapshot. The HDR boundary diagnostic compiled and was explicitly skipped; no new HDR capture ran. AC3 remains open. Owner requested a pause; all native processes exited and the worktrees, reports and resume instructions were saved locally. Any later source change requires validation appropriate to that change before completion.

2026-11-14: The committed HDR boundary diagnostic at 026a448 passed its unchanged comparator after four independent explicit-backend captures (432 records). All 36 input pairs and interpretation metadata match exactly; all 12 G1-G4 gate sets pass; no field varies only across backends under the frozen predicate. All 66 differing case/fields also vary within an unchanged binary;45 have no shared observed value between backends. This establishes the scoped registered boundary condition, not general or statistical backend equivalence, byte-identical HEIC, a future variability bound or exclusion of concurrent backend effects. All1194 source hashes and per-backend binaries remained unchanged. Earlier native full gate carries for those exact bytes. Combined latest-main gate is pending before final integration. Public rule, comparator, negative controls and compact hashed receipts are in Scripts/research/aski74-hdr-boundary-2026-11-13.

Final combined integration gate on 2026-11-14 passed after merging main b2297d9:1549 core tests,178 media,two deadlock sentinels and DocC; opt-in HDR capture remained disabled. All1316 tested file hashes and the dependency lock were unchanged through the gate. The final bookkeeping change only marks this already qualified scoped task Done; native measurement evidence stays bound to026a448. ASKI-41 historical performance criterion remains superseded, not passed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Qualified the unchanged case-only Aski/aski product graph on installed Xcode27/Swift6.4. Full graph, reuse, commands, resources, tools and explicit native gate pass. The registered four-capture HDR comparison preserves exact inputs and existing gate outcomes; compressed output variability remains scoped and does not establish general backend equivalence. Final latest-main combined gate passes.
<!-- SECTION:FINAL_SUMMARY:END -->
