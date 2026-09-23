---
id: ASKI-74
title: Validate Swift 6.4 fix for case-only product collisions
status: To Do
assignee: []
created_date: '2026-09-04 08:24'
updated_date: '2026-09-10 04:38'
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
  - 'https://github.com/swiftlang/swift-package-manager/issues/9184'
  - 'https://github.com/swiftlang/swift-package-manager/pull/10067'
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
- [ ] #1 A genuine final Xcode 27 / Swift 6.4 toolchain is available side-by-side and selected per command without installation or a global Xcode change.
- [ ] #2 From a fresh current-main checkout, swift build --build-tests --build-system swiftbuild succeeds with the unchanged one-package graph; neither the Aski/aski case-only corruption nor the earlier demo/lab collision diagnostics occur.
- [ ] #3 Filtered and full Swift Build tests run from the built graph, and build-once then test/run --skip-build reuse succeeds with an explicit backend on every SwiftPM command.
- [ ] #4 The aski command, AskiDemo, and all seven lab products preserve help, version, bare-exit, unified-routing, and generated-artifact behavior against the native backend.
- [ ] #5 Resources remain byte-identical; research-index and repo-map checks detect reversible drift; DocC plus Markdown export and the benchmark plugin succeed under Swift Build.
- [ ] #6 Sources, Package.swift, Package.resolved, public and executable product names, swift-tools-version, and the one-package architecture remain unchanged; a final native just check passes before any completion commit.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Wait for a genuine final Xcode 27 / Swift 6.4 installation. Do not install a toolchain or change the global Xcode selection as part of this task.
2. Create fresh native and Swift Build worktrees from the same current-main commit. Record exact Xcode, Swift, SwiftPM, SDK, OS, and filesystem context. Select the side-by-side toolchain with DEVELOPER_DIR and use an explicit backend on every SwiftPM command.
3. Run a clean Swift Build build-tests command first. Inspect the generated graph and logs for the prior AskiDemo shadow, seven lab basename collisions, and Aski/aski file-list corruption. If the upstream 6.4 fix does not hold, keep the task open and report the upstream failure; do not rename required names or add package/wrapper ceremony.
4. If the clean graph passes, run filtered and full skip-build tests, all package tools with drift falsification, resource parity, DocC plus Markdown, the benchmark plugin, and native-versus-Swift-Build command/replay parity. Keep runs serial.
5. Record the compatibility result in the ASKI-41 verdict note and generated research index. Mark ASKI-74 Done only when every acceptance criterion passes, then let ASKI-41 repeat its frozen performance and promotion lane.
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
<!-- SECTION:NOTES:END -->
