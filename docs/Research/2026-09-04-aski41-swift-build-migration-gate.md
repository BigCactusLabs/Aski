---
title: "ASKI-41 Swift Build migration gate - HOLD"
slug: 2026-09-04-aski41-swift-build-migration-gate
date: 2026-09-04
status: complete
subsystem: [meta]
summary: "Historical Swift 6.3 qualification held because the full package graph could not build. Xcode 27 / Swift 6.4 is now the installed default, and ASKI-41 closed by owner decision without its old side-by-side performance lane. ASKI-74 now passes the unchanged graph, tests, reuse, resources, commands, DocC and plugin checks. Its committed HDR boundary diagnostic passed on 2026-11-14: 36 exact encoder input pairs, all 12 unchanged gate sets and same-binary variation for every differing output field. This is scoped qualification, not byte-identical HEIC output or general backend equivalence; 45 varying fields have no shared observed value between backends. The matching fresh kernel/vector baseline drift remains separate, with checked-in resources preserved."
related_specs: [docs/architecture.md, docs/Research/2026-09-03-future-direction-and-architecture.md, justfile, Package.swift]
next_action: "Preserve the scoped qualification and historical HOLD evidence. ASKI-78 owns vector drift; no general HEIC equivalence or old side-by-side performance result is implied."
---

# ASKI-41 Swift Build migration gate

**Historical verdict (2026-09-04): HOLD.** See the dated qualification updates below.

At that sitting, the backend had useful target-scoped capability but could not build Aski's complete
package graph, and final Swift 6.4/Xcode 27 was unavailable. The original HOLD evidence remains intact.

## Status update — 2026-11-13

The HOLD verdict below is the 2026-09-04 result and stays as recorded. Its premise has since
changed: Xcode 27 (27A266a) with Apple Swift 6.4 is now the installed, selected toolchain, and
SwiftPM's default backend on it is Swift Build (`.build/.buildSystem_debug` reads `swiftbuild`;
`d75b83f` moved `package-cli` to the default build system because Swift 6.4 deprecates
`--build-system native`). Every local `just check` since has built the full test graph on that
backend, so adoption happened through the toolchain default rather than through this gate. The
owner closed ASKI-41 on 2026-11-13 with its side-by-side qualification criterion superseded, not
met. ASKI-74 carries the remaining validation of the collision fix on the installed toolchain.

## Frozen rule and baseline

The protocol was recorded in ASKI-41 before measurement results were inspected.

- Baseline: `d7b2a52ac22b9fe1e073bed2e661b3f2c125f612`, the stable package graph after
  ASKI-48.
- Branch-switch parent: `baca440fa30a1cbaef77636ace411cb39fea4cd0`.
- Host: Apple M3 Max, 14 cores (10 performance and 4 efficiency), 36 GB memory; macOS 26.6.2
  (25G83).
- Selected toolchain: Xcode 26.5 (17F42), macOS SDK 26.5, Apple Swift 6.3.2
  (`swiftlang-6.3.2.1.108 clang-2100.1.1.101`), swift-driver 1.148.6.
- Backends: separate fresh worktrees for `--build-system native` and
  `--build-system swiftbuild`. A temporary wrapper outside the repository added the selected backend to
  every `swift build`, `swift test`, `swift run`, and `swift package` command. The command logs confirm the
  qualifier on every measured SwiftPM invocation.
- Samples: three serial samples for each valid timing class. The table reports medians. Clean samples ran
  `swift package clean` or the first-worktree reset before `swift build --build-tests`. Incremental samples
  changed only the modification time of `Sources/Aski/ASCIIAlgorithm.swift`. Branch-switch samples built
  the parent unmeasured, switched to the baseline, and timed the rebuild.
- Timing: `/usr/bin/time -lp`. Wall time is `real`; RSS is its top-level maximum resident-set value. This
  value does not aggregate every descendant process. The workstation was not thermally isolated. Samples
  were retained as recorded.

The frozen performance rule required Swift Build to be no more than both 10% and 10 seconds slower for
each class. The RSS rule allowed no regression greater than both 10% and 100 MiB. Correctness, artifacts,
filtering, tools, DocC, and plugin behavior were hard requirements. No performance comparison is valid
when the candidate does not complete the measured graph.

## Installed-toolchain discovery

Only the selected Xcode 26.5 application is installed. The only additional Swift toolchain is the official
Swift 6.3.1 release toolchain. There is no Xcode 27 application and no Swift 6.4 toolchain. No toolchain was
installed and the global Xcode selection was not changed.

The external state agrees with that constraint. Swift.org's
[macOS install page](https://www.swift.org/install/macos/) lists Swift 6.3.3 as the stable release, while
Apple's [Xcode system requirements](https://developer.apple.com/xcode/system-requirements/) list the
available Xcode 27 beta with Swift 6.4. SwiftPM still documents Swift Build as a
[preview backend](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/SwiftBuildPreview.md)
for explicit opt-in, and the [swift-build repository](https://github.com/swiftlang/swift-build) describes
Swift 6.2 and 6.3 support as opt-in. The pending change to make Swift Build the default does not remove the
need to qualify Aski's actual graph.

That preview guide also lists a directly applicable known issue: Swift Build does not support overlapping
executable and library product names when compared case-insensitively. It links
[swift-package-manager#9184](https://github.com/swiftlang/swift-package-manager/issues/9184). The issue was
closed by [PR #10067](https://github.com/swiftlang/swift-package-manager/pull/10067), which merged to
`release/6.4.x`. Its regression fixture deliberately combines a library product `MyProduct` with executable
products such as `myproduct`, backed by separately named executable targets. That is the same required-name
shape as Aski's public `Aski` library and first-class `aski` executable.

## Native Swift 6.3.2 baseline

All 15 timed native runs succeeded.

| Class | Wall samples (s) | Median (s) | Maximum RSS samples (bytes) | Median RSS (bytes) |
| --- | --- | ---: | --- | ---: |
| clean `swift build --build-tests` | 77.01, 64.03, 63.06 | 64.03 | 632340480, 663404544, 683343872 | 663404544 |
| one-file incremental build | 4.09, 5.57, 4.01 | 4.09 | 221249536, 220561408, 220823552 | 220823552 |
| parent-to-baseline branch rebuild | 34.80, 31.60, 31.78 | 31.78 | 624033792, 621101056, 625311744 | 624033792 |
| warm `just --quiet check-fast` | 106.36, 106.13, 103.92 | 106.13 | 702119936, 705724416, 734642176 | 705724416 |
| warm `just --quiet check` | 227.21, 182.40, 162.24 | 182.40 | 1820295168, 1579515904, 1754218496 | 1754218496 |

The first clean sample includes creation of dependency working copies in the fresh worktree. It is retained
under the pre-registered no-discard rule. The full-gate spread confirms why the task required medians
instead of another single timing. Native runs produced the existing redundant-`#require` warning in
`AskiColorLabConventionAblationTests`; the measurement made no source change.

## Swift Build results under the same compiler

### Full graph: deterministic failure

Three clean `swift build --build-tests --build-system swiftbuild` attempts failed. Their wall times were
27.87, 9.52, and 9.46 seconds, with top-level RSS values of 310624256, 308396032, and 308543488 bytes.
These are failure latencies, not candidate performance samples. There is no valid clean, incremental,
branch-switch, check-fast, full-check, or RSS median to compare with native.

The current graph reports `Multiple commands produce` for each of these seven lab module/product names:

- `AskiColorLab`
- `AskiMotionLab`
- `AskiVideoLab`
- `AskiAccessLab`
- `AskiDecolorLab`
- `AskiHDRLab`
- `AskiPresetLab`

Every lab collides in all eight observed intermediate artifact classes:

| Artifact class | Repeated path suffix |
| --- | --- |
| linker file list | `<Lab>.LinkFileList` |
| LTO object | `<Lab>_lto.o` |
| dependency data | `<Lab>_dependency_info.dat` |
| compilation-requirements marker | `<Lab> Swift Compilation Requirements Finished` |
| Swift file list | `<Lab>.SwiftFileList` |
| output-file map | `<Lab>-OutputFileMap.json` |
| constant-extraction protocol list | `<Lab>_const_extract_protocols.json` |
| compilation-finished marker | `<Lab> Swift Compilation Finished` |

This is not solely an ASKI-48 regression. A separate build of the parent `baca440` also fails under Swift
Build, before it can establish a branch-switch control. That graph reports:

```text
module dependency cycle: 'Aski (Source Target) -> AskiToolSupport.swiftmodule -> Aski (Source Target)'
source target 'Aski' shadowing a Swift module with the same name at: 'Tools/AskiDemo'
```

ASKI-48's importable lab modules and thin executable runners add the seven product/module output
collisions, but the old graph already had an independent `Aski`/`AskiDemo` shadowing failure. ASKI-74 must
not assume those are the only blockers while preserving all executable product names and replay behavior.

### ASKI-74 feasibility result: Swift 6.3 workaround rejected

A later throwaway worktree at `d12f158` tested the smallest proposed manifest correction: rename the
historical demo target and the seven internal importable lab modules while preserving every product name,
path, command, source file, golden, and generated repo map. Native targeted tests (35 tests in four suites)
and `just check-fast` (823 tests in 155 suites) passed. The change removed the earlier demo-shadow and seven
lab collision diagnostics, but it did not produce a valid Swift Build graph.

Two clean `swift build --build-tests --build-system swiftbuild` attempts failed at 98% after 35.82 and 34.79
seconds. In both, Swift Build invoked the `AskiCLIRunner` module with an `aski.SwiftFileList` that contained
107 files from `Sources/Aski`, then failed because `main.d` was absent. On the host's case-insensitive volume,
the public `Aski` library and required `aski` executable product shared the same `aski.build` intermediate
directory. This is the exact upstream known-issue class, not evidence that another internal target rename is
needed.

SwiftPM exposes no root-package manifest setting that gives an executable product a different Swift Build
target namespace while retaining its installed product name. `--scratch-path` relocates the common scratch
root; it does not change product-derived target names. Dependency `moduleAliases` do not rename the root
package's public local module. A case-sensitive volume is not an upstream portability contract or a valid
project requirement. Renaming either `Aski` or `aski`, splitting the package, or adding wrapper/symlink
ceremony would violate settled project constraints.

No code from that feasibility worktree should land. ASKI-74 is therefore a Swift 6.4 validation gate for the
upstream fix, not a mandate to invent a Swift 6.3 repository workaround.

### Independently reachable probes

| Probe with explicit Swift Build | Result | Evidence |
| --- | --- | --- |
| `swift build --target Aski` | PASS | Completed in 10.15 seconds; top-level RSS 306872320 bytes. This is one capability probe, not a benchmark median. |
| `Aski_Aski.bundle` resources | PASS | Privacy manifest, Fonts, ShapeData, and Kernels all exist in the built bundle. All 14 source resource files compare byte-for-byte with their bundle copies. |
| `swift run BuildResearchIndex --check` | PASS | Built and ran; 7.65 seconds. A following `--skip-build` run passed in 4.30 seconds. |
| research-index drift falsification | PASS | A one-byte edit to `docs/Research/index.json` made the reused tool return nonzero. Restoration reproduced SHA-256 `4d45df5526e7210982cf9ada38ab913845b269524bfeda9ab89c659193031a7f`. |
| `swift run BuildRepoMap --check` | PASS | Built and ran; 6.76 seconds. A following `--skip-build` run passed in 4.04 seconds. |
| repo-map drift falsification | PASS | A one-byte edit to `docs/repo-map.generated.md` made the reused tool return nonzero. Restoration reproduced SHA-256 `7c49ab8cb235708d8fb183effa967f99f8c18b3e00f015bdcef2327385b66696`. |
| filtered `swift test` | FAIL | A narrow `ASCIIGridPatternOverlayTests` filter still plans the coupled test graph and fails on all seven lab collision families. |
| `swift test --skip-build` after the failed full build | FAIL | `AskiTests.xctest` exists without its executable and cannot load. The authoritative reuse contract is not established. |
| `swift package dump-symbol-graph` | FAIL | Whole-package planning reaches the seven collision families and emits no `Aski.symbols.json`; DocC catalog and Markdown validation therefore cannot start from a supported SwiftPM graph. |
| benchmark command plugin | PASS | `swift package --disable-sandbox benchmark --target AskiBenchmarks --no-progress` completed in 156.28 seconds; top-level RSS 817299456 bytes. |
| full `just check-fast` / `just check` | BLOCKED | Both require the test graph; `just check` begins with the failed `--build-tests` command. Running repeated failure wrappers would not create a valid warm graph or timing comparison. |

The target-scoped passes are useful, but they do not satisfy the product gate. In particular, success of
the two standalone drift tools does not replace the required one full build followed by every test and tool
with `--skip-build`.

## Ten promotion gates

| # | Gate | Disposition on 2026-09-04 | Reason |
| ---: | --- | --- | --- |
| 1 | Swift 6.4 and its Xcode are final | **FAIL** | The available Xcode 27 lane is beta; no final toolchain was available to qualify. |
| 2 | The toolchain is available in every real environment | **FAIL** | It is absent from this developer machine. No claim is made for other machines or advisory CI. |
| 3 | Repeated clean and warm `just check` pass | **CANNOT EVALUATE** | No Swift 6.4 toolchain exists locally. The current-compiler Swift Build precursor cannot build the full graph. |
| 4 | Metallib output is identical or explained | **CANNOT EVALUATE** | Regeneration under Swift 6.4/Xcode 27 requires the missing Metal toolchain. The checked-in library was not changed. |
| 5 | Snapshots and numerical goldens do not churn | **CANNOT EVALUATE** | No Swift 6.4 lane exists, and current Swift Build cannot construct the full test bundle. |
| 6 | Benchmark plugin and all package tools work under Swift Build | **FAIL** | The benchmark plugin and two index tools pass, but whole-package DocC and product/test execution do not. |
| 7 | Build-once then `--skip-build` works | **FAIL** | The full build fails; skipped tests then have no executable. Tool-only reuse is insufficient. |
| 8 | Performance and memory are acceptable | **CANNOT EVALUATE** | Native medians exist. Swift Build has only failure latency and target-scoped observations, not comparable successful medians. |
| 9 | Media-test stability is unchanged or better | **CANNOT EVALUATE** | The test graph cannot reach media execution under Swift Build; no Swift 6.4 lane exists. |
| 10 | Dependencies compile without unreviewed upgrades | **CANNOT EVALUATE** | `Package.resolved` is unchanged and no upgrade was attempted, but the final Swift 6.4 compiler was unavailable for the required compilation proof. |

All ten gates must pass. Four fail now and six cannot be evaluated; promotion is not close.

## Decision and repository effect

- **HOLD ASKI-41.** Keep `swift-tools-version: 6.3` and the current required toolchain.
- Do not change `Sources/`, `Package.swift`, `Package.resolved`, CI, release scripts, or the global Xcode
  selection in this spike.
- ASKI-74 is a required predecessor for any repeated Swift Build qualification. It must validate upstream
  PR #10067 on a genuine Swift 6.4 toolchain without renaming the public `Aski` module, `aski`, or any lab
  executable product, and without changing the one-package architecture.
- When ASKI-74 is complete, repeat the correctness and performance measurements from a fresh worktree. Do
  not infer performance from any failed Swift 6.3 run recorded here.
- Run the Swift 6.4/Xcode 27 lane only when a genuine side-by-side final toolchain exists. Re-run Metal,
  snapshots, numerical goldens, media counts and sentinels, DocC plus Markdown, plugin behavior, dependency
  compilation, and native-versus-Swift-Build timing before any promotion.


## ASKI-74 unchanged-graph replay — 2026-11-13 (partial)

[Compact command and comparison evidence](../../Scripts/research/aski74-2026-11-13/README.md).

The historical HOLD above remains the Swift 6.3.2 result. This replay starts from
`e9ac79bd48ab0d387d85cedf15f5bab244fc0aad` in two fresh worktrees on macOS 27.0.1
(26A434), Xcode 27.0 (27A266a), and Apple Swift 6.4
(`swiftlang-6.4.0.34.1`). All `Sources`, package manifests/lock, product names,
Swift tools version, and the one-package graph remain unchanged. No goldens,
thresholds, or checked-in resource bytes were changed.

| Check | Observed result |
| --- | --- |
| Clean `swift build --build-system swiftbuild --build-tests` | PASS; 37.88 seconds reported build time, 58.97 seconds process time. No prior case-only product/module collision diagnostics. |
| Explicit Swift Build filtered `--skip-build` tests | PASS; 30 tests. |
| Explicit Swift Build full split phases | PASS; 1,537 core, 177 serialized media, and two isolated deadlock sentinels. |
| Fresh explicit native control build | PASS; 63.30 seconds process time. |
| Explicit-backend `run --skip-build` reuse | PASS for all ten command products and both generated-index tools. |
| Command surface parity | PASS; 112 exact stdout/stderr comparisons cover help, version, bare exit, and seven unified lab namespaces. Native SwiftPM deprecation diagnostics are retained separately from product output. |
| Resource-copy parity | PASS; all 15 source resource files match both built bundles byte-for-byte. Bundle container layouts differ between backends. |
| Index drift rejection | PASS; both tools reject a one-byte generated-file change, then pass after exact SHA-256 restoration. |
| Supported SwiftPM symbol graph | PASS; explicit Swift Build `dump-symbol-graph` returns zero. |
| DocC and Markdown | PASS; the unmodified validator consumes the explicit Swift Build graph through its exact public cache-key calculation. Graph hashes are retained. |
| Explicit Swift Build benchmark plugin | PASS; all six validation-smoke workloads export nonempty wall-clock and malloc-count samples, including the video one-shot workload. No budget verdict is inferred. |
| Final canonical `just check` in control worktree | PASS in 206.05 seconds, including 1,537 core / 177 media / two sentinels and DocC. Its actual default backend is **Swift Build**, not native: the build-system marker changed from native to swiftbuild. The recipe was not changed. |
| `aski`, `AskiDemo`, and `AskiTileMatrix` generated output | PASS; corresponding text, PNG and matrix artifacts match exactly across backends; `aski` and `AskiDemo` render outputs match each other. |

All seven labs also ran through both legacy and unified routes on both backends
(28 successful commands). Six labs' deterministic artifacts match after normalizing
only output paths and the video lab's explicit throughput/RSS telemetry. The first
8-column decolor probe correctly rejected its own no-downscale precondition; the
qualified matrix uses the documented 80-column decolor/HDR settings. This was an
invalid probe input, not a backend defect or a relaxed oracle.

### HDR artifact boundary at the November 13 checkpoint

All HDR runs report PASS under their unchanged G1–G4 rules. All nine rendered
TIFFs match; corresponding routes preserve content headroom, float-integrity fields,
and display-query behavior. Legacy runs report display EDR headroom 16.00 while
unified runs report unavailable on both backends, matching the best-effort
main-thread query. That route difference is not a backend difference.

Compressed HEIC bytes and round-trip errors vary even in one repeat of the same
native executable. A read-only decoder compared all 36 HEICs as SDR bases and
expanded HDR in extended-linear sRGB, retaining exact Float pixel differences and
ImageIO properties for 108 file pairs. All corresponding metadata dictionaries match.
The same-native repeat's largest per-file mean absolute pixel difference is
0.00001980895 (SDR) / 0.00005300455 (expanded HDR). Replay cross-backend maxima are
0.00001159806 / 0.00004036760. Canonical cross-backend maxima are
0.00001350340 / 0.00005839134; its SDR maximum single-channel difference is
0.05103713 versus 0.04402679 in the same-native repeat.

Thus some decoded cross-backend measures exceed this single-repeat envelope,
even though every existing gate outcome is unchanged. Three replay fixtures and
ten canonical fixtures exceed their corresponding same-file repeat MAE. This does
not establish a compiler defect or a statistical variability bound, but it does not
satisfy the requested artifact comparison either. **ASKI-74 remained open at that checkpoint** for further
qualification; no tolerance or production behavior was changed to force acceptance.

### Additional generator observations

Both built `BuildKernelLibrary` tools run successfully in isolated copies of the
kernel inputs. Native, its one repeat, and Swift Build produce the same SHA-256
`bb663922b4e69c7507f1795cf91f2faa5fda0418693a0fa1195696821377ad38`, which differs
from checked-in `3df93d552f64cd8583182a3cd85a1ea24768674bf4f648b2906481e68e8f1b12`.
This fresh-regeneration observation is separate from the passing resource-copy check.

Read-only `BuildStandardVectors --audit` returns **1** on native, its one repeat,
and Swift Build: 10 sets, maximum delta 0.0451757461, changed sort permutation,
trigger fired. Both audit CSVs match byte-for-byte across all three runs. These are
consistent baseline-drift diagnostics, not passing freshness checks and not evidence
of a Swift Build regression. All generated files remain outside the source tree;
checked-in kernels and vectors were preserved. The local results qualify only this
checkout and host, not every package affected by the upstream issue.

## ASKI-74 HDR boundary qualification — 2026-11-14

The [committed diagnostic and readout](../../Scripts/research/aski74-hdr-boundary-2026-11-13/README.md#registered-result--2026-11-14)
complete the registered comparison on frozen product source `e9ac79b` plus
diagnostic commit `026a448`. Two independent processes per explicit backend
produced 432 encode records. All 36 SDR/HDR inputs and interpretation metadata
match exactly; all 12 existing G1–G4 gate sets pass. The unmodified comparator
returns 0, with no field classified as varying only across backends.

There are 66 varying case/field findings, 45 with no shared observed value
between backends. All also vary within an unchanged binary. This establishes
the registered boundary condition and framework variability on this regime;
it does not establish statistical equivalence, a future noise bound or the
absence of a concurrent backend effect. HEIC byte equality is not claimed,
and no tolerance changed. The earlier explicit legacy-native full gate
passed on identical source: 1,538 core, 177 media, two sentinels and DocC.

Together with the unchanged-graph command/resource/tool matrix above, this
closes the scoped ASKI-74 qualification. The original ASKI-41 performance
protocol remains superseded by the owner's decision, not retroactively passed.
The kernel/vector freshness observations remain unchanged and separate.
