---
id: ASKI-41
title: >-
  Swift 6.4 / Swift Build compatibility and performance lane (do not promote
  yet)
status: In Progress
assignee: []
created_date: '2026-08-20 20:08'
updated_date: '2026-09-10 04:38'
labels:
  - ci
  - benchmarks
  - toolchain
  - performance
dependencies:
  - ASKI-74
references:
  - justfile
  - Scripts/repo-doctor.sh
  - Scripts/validate-docc.sh
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - Package.swift
  - docs/Research/2026-09-03-future-direction-and-architecture.md
  - 'https://www.swift.org/install/macos/'
  - >-
    https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/SwiftBuildPreview.md
  - docs/Research/2026-09-04-aski41-swift-build-migration-gate.md
  - 'https://github.com/swiftlang/swift-package-manager/issues/9184'
  - 'https://github.com/swiftlang/swift-package-manager/pull/10067'
documentation:
  - 'https://developer.apple.com/xcode/system-requirements'
  - >-
    https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes
  - >-
    https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/Documentation.md
  - 'https://www.swift.org/blog/swift-package-manager-manifest-api-redesign/'
modified_files:
  - >-
    backlog/tasks/aski-41 -
    Swift-6.4-Swift-Build-compatibility-and-performance-lane-do-not-promote-yet.md
  - >-
    backlog/tasks/aski-74 -
    Remove-Swift-Build-module-and-product-basename-collisions.md
  - docs/Research/2026-09-04-aski41-swift-build-migration-gate.md
  - docs/Research/2026-09-03-future-direction-and-architecture.md
  - docs/Research/README.md
  - docs/Research/index.json
priority: medium
type: spike
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Do not make Swift 6.4 the required toolchain yet. Stand up a non-blocking compatibility and performance lane instead, and promote only after the final toolchain survives Aski's Metal, media, DocC, plugin, snapshot, and build-reuse contracts.

## Status as of 2026-08-20

Swift 6.4 is not a final release. Apple's current stable Xcode (26.6) still ships Swift 6.3; Swift 6.4 arrives via Xcode 27 beta 5, which needs macOS Tahoe 26.4+. Promoting today would put a beta Xcode, beta SDK, new compiler, new SwiftPM build backend, new Metal toolchain, new DocC, and new Swift Testing into the authoritative local gate simultaneously — no regression or speedup would be attributable to anything.

## Why this matters to Aski

The consequential change is the build system, not the language. Swift Build shipped as a preview in Swift 6.3 and becomes SwiftPM's default in 6.4. Aski's package graph is exactly the shape that exposes backend parity problems: one library, many executable lab targets, resource-heavy targets, build tools, a benchmark command plugin, and one large test target depending on nearly every tool and lab.

Xcode 27's dependency-scanner work (avoiding redundant setup and Clang-header searches) could help a package importing this much Apple framework surface, but the same change tightens duplicate Clang-module-name handling. That is a reason to benchmark, not to assume a win.

## Correction to the original phasing

The recommendation's Phase 1 ("land and measure the Swift 6.3 gate optimizations first") is DONE as of 2026-08-20 — PRs #11, #12, #13 are merged to main. The measured baseline does not support the perf framing those PRs were argued on, and this task inherits the real numbers rather than the claimed ones:

- Full `just check`, same tree, single samples on M3 Max: 179s before #11 -> 205s after #11 -> 196s after #13.
- `Scripts/validate-docc.sh` warm: 6s validation-only vs 5s with --emit-markdown. The second DocC conversion is nearly free warm, so #12's local saving did not materialize.
- Test accounting after #13 is exact: 1260 core + 149 media + 2 sentinels = 1411.

So #13 was retained for stability (ASKI-39 contention), not wall time, and the honest control for any Swift Build or Swift 6.4 comparison is "roughly flat vs the pre-#11 gate". Phase 1's first job here is to re-measure these as repeated samples rather than single ones, because single samples are what produced the misleading framing in the first place.

## Phase 2 - Swift Build under the CURRENT compiler (highest-value experiment)

Isolate the backend change while holding compiler, SDK, Metal toolchain, and test frameworks fixed. Under Xcode 26.5/26.6 and Swift 6.3, in a separate worktree:

    xcrun swift build --build-system swiftbuild
    xcrun swift test  --build-system swiftbuild
    xcrun swift run   --build-system swiftbuild BuildResearchIndex --check
    xcrun swift run   --build-system swiftbuild BuildRepoMap --check

The gate must be adapted temporarily so every related command selects the same backend; mixing backends across commands invalidates the reuse contract under test.

Measure: clean test-graph build, one-file incremental rebuild, branch-switch rebuild, warm `just check`, warm `just check-fast`, peak memory and machine responsiveness, benchmark-plugin operation, --skip-build reuse, resource copying, test filtering, tool execution, DocC symbol-graph generation.

## Phase 3 - Swift 6.4 as a non-required toolchain

Install Xcode 27 beta side-by-side and select it per command; do not replace the system Xcode:

    DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift --version

Keep `swift-tools-version: 6.3`. Tools-version is the minimum required to CONSUME the package, not the newest compiler it may be tested on; raising it to 6.4 excludes Xcode 26.5/26.6 users and buys nothing unless Aski adopts a 6.4-only PackageDescription API. Aski already sets Swift 6 language mode explicitly on its targets, so a 6.4 compiler builds the package as-is.

Qualify with `just check-fast`, `just check`, `just bench`, `just release-preflight`, inspecting: compiler errors and new warnings, throwing-Task and concurrency diagnostics, exact snapshot and golden output, metallib regeneration, GIF/MP4 frame counts, the two deadlock sentinels, Core Image effects, DocC symbol links and Markdown export, command-plugin behavior, clean/incremental build times, and cross-command --skip-build behavior.

Xcode 27 still supports deployment targets below Aski's iOS 18 / macOS 15 / visionOS 2 floors, so this does not force a platform-floor change.

## Phase 4 - promotion gates (ALL must hold)

1. Swift 6.4 and its Xcode are final, not beta.
2. That Xcode is available in every dev/CI environment Aski actually uses.
3. `just check` passes repeatedly from both clean and warm states.
4. Metallib output is byte-identical, or any change is independently explained and reviewed.
5. Snapshots and numerical goldens do not churn unexpectedly.
6. The benchmark plugin and all package tools work under Swift Build.
7. The build-once / --skip-build strategy from #11 works under the new backend.
8. Clean, incremental, and warm-gate performance is no worse than Swift 6.3, or the trade-off is justified.
9. Media-test stability is unchanged or improved.
10. Dependencies compile without unreviewed upgrades.

Only then update `Scripts/repo-doctor.sh`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`, and `AGENTS.md`. Leave `swift-tools-version: 6.3` regardless, unless a manifest feature genuinely requires 6.4.

## Explicit non-goals

Changing `swift-tools-version` to 6.4 now. Requiring contributors to install Xcode 27 beta. Touching `Sources/` — this lane is CI, tooling, and measurement only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A repeated-sample (not single-sample) Swift 6.3 baseline is recorded at a named commit on main: clean test-graph build, one-file incremental rebuild, branch-switch rebuild, warm just check, warm just check-fast, and peak memory — superseding the single-sample 179s/205s/196s figures in the description.
- [x] #2 Swift Build is measured under Swift 6.3 via --build-system swiftbuild in a separate worktree across build/test/run, with every gate command on the same backend, and compared against that baseline on the full Phase 2 measurement list.
- [x] #3 The cross-command artifact-reuse contract that just check depends on (swift build --build-tests, then swift run --skip-build and swift test --skip-build) is explicitly validated under Swift Build, including a falsification check that the drift tools still FAIL on perturbed generated artifacts.
- [ ] #4 Swift 6.4 / Xcode 27 beta is qualified side-by-side via DEVELOPER_DIR without replacing the system Xcode and without changing swift-tools-version, recording results for just check, just bench, and just release-preflight — including metallib byte-equality, snapshot and golden churn, GIF/MP4 frame counts, the two deadlock sentinels, DocC symbol links and Markdown export, and benchmark-plugin behavior.
- [x] #5 A verdict note lands under docs/Research/ with an explicit PROMOTE / HOLD / KILL call and the evidence behind it, stating which of the ten Phase 4 gates passed, failed, or could not be evaluated.
- [x] #6 No required-toolchain change is merged unless all ten Phase 4 gates hold and Swift 6.4 plus its Xcode are final; swift-tools-version stays 6.3 unless a manifest feature genuinely requires 6.4.
- [x] #7 Sources/ is untouched by this task — changes are limited to CI, scripts, tooling, docs, and measurement artifacts.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Freeze commit d7b2a52ac22b9fe1e073bed2e661b3f2c125f612 and its parent baca440fa30a1cbaef77636ace411cb39fea4cd0. Use the installed Xcode 26.5 / Apple Swift 6.3.2 toolchain only. Keep Package.swift, Package.resolved, Sources/, and global toolchain selection unchanged in the final tree.
2. Use two fresh worktrees on the same volume: /private/tmp/aski-41-native for --build-system native and /private/tmp/aski-41-swiftbuild for --build-system swiftbuild. A temporary xcrun shim outside the repository injects the selected backend into every swift build, test, run, and package command while passing non-Swift xcrun calls through. Logs must show no unqualified SwiftPM command.
3. Use three samples per timing class and compare medians. Run samples serially. For each backend record /usr/bin/time -lp wall time and maximum resident set size plus memory_pressure and load-average observations. Measure clean swift build --build-tests, then touch only the mtime of Sources/Aski/ASCIIAlgorithm.swift and measure a one-file incremental rebuild. For branch-switch samples, build baca440 unmeasured, switch to d7b2a52, and time the rebuild; restore the native worktree to cdx/aski-41-final and the Swift Build worktree to detached d7b2a52.
4. With a warm graph, run three measured just check-fast and three measured just check samples per backend, alternating backend order between samples. Keep all runs serial and uncontended. A sample is retained and labeled if external contention occurs; no after-the-fact discard.
5. Under Swift Build, explicitly validate build --build-tests followed by test/run --skip-build, filtered test selection, BuildResearchIndex and BuildRepoMap execution, resource-bundle presence and source-byte parity, DocC symbol-graph plus catalog and Markdown output, and the benchmark command plugin. Falsify both drift checks by making one reversible byte-only perturbation to each generated artifact, requiring a nonzero check result, then restore and verify the original SHA-256.
6. Compare Swift Build to native. Correctness, artifact reuse, resources, filtering, tools, DocC, and plugin checks are hard requirements. Performance is PASS when the Swift Build median is no more than both 10% and 10 seconds worse for each measured class; a larger regression requires a concrete benefit to justify it. Peak RSS is PASS when no measured class regresses by more than both 10% and 100 MiB. Report limitations; /usr/bin/time does not aggregate every descendant process.
7. Run the Swift 6.4/Xcode 27 lane only if a genuine installed side-by-side toolchain exists. Discovery found none, so do not install one or weaken the gate. Mark Phase 4 gates unavailable as applicable and issue HOLD. Never PROMOTE unless all ten Phase 4 gates pass on a final toolchain available in every real environment. KILL applies only to a proven hard incompatibility or unjustified repeated regression; missing 6.4/Xcode 27 remains HOLD.
8. Write a docs/Research verdict note and generated registry update, record the acceptance and HOLD state through backlog CLI, verify Package.swift, Package.resolved, and Sources/ are byte-clean, then run one full native just check on the final tree before the sole local commit. Do not push.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Baseline d7b2a52, Xcode 26.5, Apple Swift 6.3.2. Native medians: clean build-tests 64.03s / 663404544B RSS; one-file incremental 4.09s / 220823552B; parent-to-baseline rebuild 31.78s / 624033792B; warm check-fast 106.13s / 705724416B; warm check 182.40s / 1754218496B. All 15 native samples passed.

Swift Build full graph failed three of three attempts at d7b2a52. Parent baca440 has an Aski/AskiDemo module-shadow cycle; d7b2a52 also duplicates eight intermediate artifact classes for each of seven lab product/module basenames. Target-scoped Aski/resource parity, both drift tools with skip-build and falsification, and the benchmark plugin pass. Filtered tests, the complete build-once/skip-build contract, and whole-package DocC fail or are blocked.

A later uncommitted ASKI-74 feasibility tree at d12f158 removed the earlier demo and lab diagnostics but exposed Swift 6.3 Swift Build case-insensitive output corruption between the required Aski library and aski executable product. Two clean attempts failed at 98% after 35.82s and 34.79s when AskiCLIRunner consumed the 107-file Sources/Aski file list. The official Swift Build preview documents this class in swift-package-manager#9184, and PR #10067 merged an exact case-variant product regression fixture to release/6.4.x. No permissible Swift 6.3 manifest-only fix preserves the names and one-package architecture. There is no installed Xcode 27 or Swift 6.4 toolchain. Verdict HOLD; ASKI-74 now validates the upstream 6.4 fix before requalification.

The prior final native just check passed on the finished ASKI-41 documentation and Backlog tree: 1562 core tests, 152 media tests, 2 deadlock sentinels, and DocC. ASKI-41 remains In Progress because the final Swift 6.4/Xcode 27 lane is unevaluable and ASKI-74 is open.

Modified files: backlog/tasks/aski-41 - Swift-6.4-Swift-Build-compatibility-and-performance-lane-do-not-promote-yet.md, backlog/tasks/aski-74 - Remove-Swift-Build-module-and-product-basename-collisions.md, docs/Research/2026-09-04-aski41-swift-build-migration-gate.md, docs/Research/2026-09-03-future-direction-and-architecture.md, docs/Research/README.md, docs/Research/index.json

### Implementer context — 2026-09-10 (base 952529a)

**Current state:** ASKI-41 is In Progress with a recorded HOLD verdict. The checked-in migration note says the native Swift 6.3.2 baseline passed its repeated timing classes, while Swift Build could not construct the complete package/test graph. Treat those measurements as historical evidence from the named run. ASKI-74 is the direct prerequisite for any new qualification.

**Start here:** Read `docs/Research/2026-09-04-aski41-swift-build-migration-gate.md` for the frozen rule, failure evidence, target-scoped probes, and ten promotion gates. Read `Package.swift` and `justfile` together: the package is still tools-version 6.3, and `just check` is format → one `swift build --build-tests` → drift tools → core/media/deadlock phases → DocC. `Tests/AskiTests/UnifiedLabCommandTests.swift` records the canonical root command that ASKI-74 must preserve.

**Constraints and dependencies:** Finish ASKI-74 first on a genuine final side-by-side Swift 6.4/Xcode toolchain selected per command. Do not infer present toolchain availability from the dated note, install anything, select a global Xcode, change `swift-tools-version`, rename `Aski`/`aski`, split the package, or touch `Sources/`. Every SwiftPM probe must use the same explicit backend; preserve build-once followed by `--skip-build`. Existing recorded Swift Build failures include seven lab basename artifact collisions and the case-insensitive `Aski` library/`aski` executable product collision.

**Validation to run:** In ASKI-74, run fresh-main `swift build --build-tests --build-system swiftbuild`, filtered/full tests, build-once and `--skip-build` tests/runs, command/replay help/version/bare behavior, resources and reversible drift falsification, DocC plus Markdown export, and the benchmark plugin. Then repeat ASKI-41's clean, incremental, branch-switch, warm `just check-fast`, and warm `just check` samples, with snapshots/goldens, metallib, GIF/MP4 counts, media serial phase, deadlock sentinels, and dependency compilation covered. Native `just check` remains the final gate.

**First step:** Re-discover the installed side-by-side toolchain at execution time, then run ASKI-74 against the unchanged one-package graph. Promotion remains unresolved until all ten gates pass.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-09-04 03:46
---
2026-09-03 frontier refresh corroborates HOLD: Swift 6.3.3 is the stable release; 6.4 is a development snapshot, UniqueArray and Span temporary allocation carry no Aski speedup evidence, and Swift Build remains preview/opt-in under Swift 6.3. Run this qualification only after ASKI-70 and any promoted package-graph change so the baseline is not immediately invalidated. Compilation caching was still an active proposal, not an available optimization.
---

created: 2026-09-04 08:24
---
Swift Build qualification at d7b2a52 is blocked under Apple Swift 6.3.2. The parent baca440 already fails with an Aski/AskiDemo module-shadow cycle. The current graph also fails deterministically with duplicate output artifacts for all seven lab product/module basenames. ASKI-74 owns the smallest collision-free manifest/module fix and blocks any future Swift Build promotion; ASKI-41 remains HOLD.
---

created: 2026-09-04 09:05
---
2026-09-04 ASKI-74 feasibility correction: a throwaway d12f158 worktree removed the previously observed AskiDemo and seven lab diagnostics, then clean Swift Build failed twice because the required public Aski library and aski executable product collide case-insensitively in Swift 6.3 output paths. SwiftPM documents this exact unsupported class in the Swift Build preview under issue #9184. PR #10067 merged an exact case-variant product regression fixture to release/6.4.x. No permissible Swift 6.3 manifest-only fix preserves both names and the one-package architecture. ASKI-74 now validates the upstream fix on a genuine side-by-side final Xcode 27 / Swift 6.4 toolchain; ASKI-41 remains HOLD and In Progress.
---
<!-- COMMENTS:END -->
