---
title: "ASKI-70 package-boundary measurement - keep one Swift package"
slug: 2026-09-04-aski70-package-boundary-measurement
date: 2026-09-04
status: complete
subsystem: [meta]
summary: "Measured at commit 8bb6859 on an M3 Max with Swift 6.3.2. The root manifest has 17 targets and 15 products; Aski has no target dependencies, but SwiftPM still resolves the root's full dependency set. A same-package test-target model compiled the research tests even when the product test was filtered. A nested Research package could consume Aski's public research SPI, but could not consume the unpublished AskiToolSupport target and created a second Aski.build tree when invoked directly. Root orchestration can build a child lab module without a target cycle, but then the child is back in the root graph and its own tests still need a second package invocation. KILL the package split and keep ASKI-48's importable lab modules and replay shims in the root package."
related_specs: [docs/architecture.md, docs/Research/2026-09-03-future-direction-and-architecture.md]
next_action: "ASKI-48 is complete in the root package. Keep shipping generators, repository-governance tools, AskiToolSupport, labs, and their tests under the root manifest; reconsider a package split only if a later measured compile frontier satisfies the falsifiers in this note."
---

# ASKI-70 package-boundary measurement

**Verdict: KILL the nested package split. Keep one Swift package.**

This is a boundary decision, not a package move. `Package.swift` did not change. ASKI-48 keeps importable
lab modules and thin replay shims in the root package. Shipping generators and repository-governance tools
also stay at root.

## Question and frozen rule

The 2026-09-03 architecture review held a proposed `Research/Package.swift` split until it had evidence.
ASKI-70 compared the current package, separated test targets in the same package, and a nested package that
depends on root `Aski`.

The decision rule was recorded in the Backlog task before timing output was inspected. Each timing class
uses three samples and compares medians. PROMOTE required all current gates, no root-to-child target cycle
or product-only support API, no duplicate `Aski` compilation in the authoritative workflow, a normal
product or fast-loop improvement of at least 20% or 15 seconds, product regression no more than 5%, and
full-gate wall/RSS regression no more than 10%. HOLD required a plausible measured benefit with one named
dependency still open. KILL applied if the benefit missed the threshold, the design duplicated `Aski`,
weakened the build-once gate, or required product API only for research. No split was the default.

## Frozen baseline and method

- Commit: `8bb6859e5063599f7b98ccae526a13aea0ee09af`.
- Host: MacBook Pro `Mac15,10`, Apple M3 Max, 14 cores (10 performance and 4 efficiency), 36 GB RAM;
  macOS 26.6.2 (25G83).
- Toolchain: Xcode 26.5 (17F42), Apple Swift 6.3.2, swift-driver 1.148.6.
- Timing: `/usr/bin/time -lp`; `real` is wall time and `maximum resident set size` is reported in bytes.
  Clean samples ran `xcrun swift package clean` before the measured build. A warm sample immediately
  followed each clean product build. Full-check and check-fast samples used an already-built graph.
- Scope: default debug configuration, local dependency cache, no SwiftPM package cache override.

`/usr/bin/time` reports the top-level command's resource-accounting value, not a simultaneous census of
every descendant process. The workstation was not thermally isolated. The third check-fast sample was
directly contaminated by three other repository checks; it is retained rather than discarded after the
fact. The medians describe this developer workstation, not a portable performance claim.

## Current graph

`xcrun swift package describe --type json` reports 17 targets and 15 products. The product-only library
path is `Aski -> []`: the `Aski` target has no target or package-product dependencies. Building it still
resolves the five dependencies declared by the root manifest. The `aski` executable path is
`AskiDemo -> AskiToolSupport -> Aski`, with `ArgumentParser` on the two command targets.

The full test frontier is different. The one `AskiTests` target depends on `Aski`, `AskiToolSupport`, seven
lab targets, `BuildResearchIndex`, `BuildRepoMap`, and four package products (`ArgumentParser`,
`PropertyBased`, `SnapshotTesting`, and `Numerics`). The resolved graph contains 13 transitive packages.
This is repository build coupling, not downstream `Aski` library coupling.

Static import census at the frozen commit:

| Boundary-sensitive touchpoint | Files | Package cost |
| --- | ---: | --- |
| `@_spi(AskiResearch) import Aski` | 36 | Works across a package product, but makes the SPI a deliberate cross-package contract. The public SPI declarations are in `Sources/Aski/ASCIIConverter+Research.swift:30-210`. |
| `@testable import Aski` | 110 | A local path dependency test can compile these with `-enable-testing`; this preserves access but keeps tests coupled to root internals. |
| direct `@testable` imports of labs or generators | 69 unique test files | These tests must move with the child modules or keep child modules visible to the root test graph. There are 78 import edges: Color 37, Motion 12, Video 4, Access 5, Decolor 4, HDR 4, Preset 1, research index 10, repo map 1. |
| `AskiToolSupport` imports | 92 | The nested prototype failed because root publishes no `AskiToolSupport` product. Publishing it would expose mixed product/research support; copying or splitting it adds a new ownership boundary. |
| current-directory assumptions | 16 | A second package root changes path resolution unless every call is routed from repository root. |
| source/test/research literal path users | 47 | These are repository-coupled and require explicit root injection or path migration. |

The 36 SPI imports are concentrated in AskiColorLab (22), AskiHDRLab (3), AskiMotionLab (2), tests (6),
AskiToolSupport (1), BuildStandardVectors (1), and benchmarks (1). The 92 `AskiToolSupport` imports are in
every lab/product command family and 37 tests. `AskiToolSupport` mixes product CLI support with image I/O,
provenance, research metrics, glyph rasterization, and validation; it is not a clean package seam today.

## Repeated measurements

| Command | Wall samples (s) | Median (s) | RSS samples (bytes) | Median RSS (bytes) |
| --- | --- | ---: | --- | ---: |
| clean `swift build -q --target Aski` | 71.41, 24.99, 28.79 | 28.79 | 545849344, 550780928, 540950528 | 545849344 |
| warm `swift build -q --target Aski` | 10.31, 8.26, 14.94 | 10.31 | 107298816, 108658688, 126369792 | 108658688 |
| clean `swift build -q --product aski` | 27.96, 30.23, 28.00 | 28.00 | 544325632, 601194496, 545374208 | 545374208 |
| warm `swift build -q --product aski` | 8.43, 8.37, 11.08 | 8.43 | 107380736, 121323520, 121208832 | 121208832 |
| clean `swift build -q --build-tests` | 99.89, 118.57, 113.00 | 113.00 | 602308608, 601161728, 616841216 | 602308608 |
| warm `just --quiet check-fast` | 145.04, 114.96, 305.26 | 145.04 | 743178240, 693469184, 698925056 | 698925056 |
| warm `just --quiet check` | 301.36, 196.28, 207.42 | 207.42 | 1573552128, 1720745984, 1579253760 | 1579253760 |

The first clean `Aski` sample includes first-worktree cache setup and is an outlier. Every root SwiftPM
invocation still performs dependency resolution, even when only the dependency-free `Aski` target builds.
The product-only build is already much smaller than the full graph: median clean `aski` is 28.00 seconds
against 113.00 seconds for `--build-tests`.

## Build-once contract

Root `just check` has one `xcrun swift build --build-tests`, followed by research-index drift, repo-map
drift, core tests, serialized media tests, deadlock sentinels, and DocC. Every Swift test/run after the build
uses `--skip-build`. `Tests/AskiTests/TestGateReuseTests.swift:12-84` pins that order and the single build.

The built control passed these direct reuse checks:

- `xcrun swift test --skip-build --filter TestGateReuseTests`: 4 tests passed; 7.74 seconds and 100319232
  bytes RSS. SwiftPM planned the build but emitted no compile step.
- `ASKI_SKIP_BUILD=1 just --quiet lifecycle-check`: passed; 8.84 seconds and 13238272 bytes RSS.
- `ASKI_SKIP_BUILD=1 just --quiet repo-map-check`: passed; 12.08 seconds and 9601024 bytes RSS.

## Boundary prototypes

The prototypes were disposable and are not part of this commit.

### No split

This is the measured control. It already gives downstream consumers a dependency-free `Aski` target and
keeps all repository validation under one root graph. Its cost is the broad repository test target, not the
consumer library target.

### Separated test targets in the current package

A minimal SwiftPM model had `ProductTests` and `ResearchTests`. `ResearchTests` emitted a unique compile
warning. After `swift package clean`, this command was run:

```bash
xcrun swift test -v --filter productTest
```

SwiftPM 6.3.2 compiled and linked both test targets, and the research warning fired twice, although only
`productTest` executed. Separating the real root test target can improve ownership and test selection, but
does not reduce the cold filtered-test compile frontier. It has no measured ASKI-70 performance benefit.

### Nested Research package

A child package with a local dependency on `..` built a probe that used
`@_spi(AskiResearch) import Aski` and `SamplingGeometry`; cross-package SPI access works. Adding
`AskiToolSupport` failed during planning:

```text
product 'AskiToolSupport' required by package 'research' target
'AskiResearchProbe' not found in package 'AskiRoot'
```

The direct child build created `Research/.build/.../Aski.build` (152 MB child scratch tree). A root build in
the same disposable worktree created a separate `.build/.../Aski.build` (412 MB root scratch tree). This
fires the pre-registered duplicate-compilation KILL rule.

A second model added a child lab library product to root `AskiDemo`. That target graph is acyclic:
`AskiDemo -> child lab -> root Aski`; SwiftPM built it. This is compatible with ASKI-48 in syntax, but it
does not create hard package isolation: root `aski` now pulls the lab module back into the root graph, and
child tests still require a child-package invocation that root `swift build --build-tests` does not build.
The alternative therefore either duplicates artifacts in ordinary direct use or replaces the one-build
gate with multi-package orchestration. It supplies no measured net benefit.

## ASKI-48 ruling

Keep the seven importable lab command modules and replay shims in the root package. Do not narrow the
planned `aski lab` tree to manufacture a package seam. Preserve the executable-launch test, exit-code
parity, full command-tree golden, replay surface, and shell completions already required by ASKI-48.

This does not make lab APIs part of the `Aski` library product. They remain repository modules under the
one manifest. Shipping generators (`BuildStandardVectors`, `BuildKernelLibrary`) and governance tools
(`BuildResearchIndex`, `BuildRepoMap`) also remain root targets. Do not publish `AskiToolSupport` only to
support a package split.

## One authoritative workflow

The root remains the only workflow authority:

- `just check` is the local pre-commit authority. It builds the full test graph once; runs research-index,
  repo-map, command-surface/shell-discovery, generated-resource, full repository, media, and deadlock tests;
  then validates DocC.
- `just release-preflight` is the pre-tag complement. `Scripts/repo-doctor.sh:8-24` checks toolchain,
  `Package.resolved`, formatting, research index, repo map, DocC, regenerated Metal library, immutable
  workflow references, and cleanliness. It passed all nine checks on the clean frozen control.
- `Makefile` only forwards the same command names to `just`; hosted CI remains advisory.

A nested package would need root wrappers for every child build/test/index command and a new cross-package
artifact-reuse contract. No prototype demonstrated that contract, while the default child workflow
demonstrated the opposite.

## Decision and falsifiers

| Option | Benefit | Counter-evidence | Decision |
| --- | --- | --- | --- |
| No split | Already isolates downstream `Aski`; preserves one build and one root command surface. | Root repository tests remain broad. | **KEEP** |
| Same-package test targets | Clearer ownership and possible future parallel scheduling. | Filtered test still compiles every test target; no threshold benefit. | **KILL as performance work**; a later organization-only task needs its own reason. |
| Nested package | Visual source boundary; direct child commands are possible. | Unpublished support target, duplicate scratch trees, path migration, second test invocation, or child pulled back into root graph. | **KILL** |

The decision is **KILL**, not HOLD: the prototype did not show a plausible benefit blocked only by ASKI-48.
ASKI-48 is simpler with one manifest, and the measured downstream product frontier is already isolated.

Reconsider only if all of these become true and are measured again on one named commit:

1. SwiftPM can select a product test target without compiling the research tests, or a new workflow proves
   at least 20% or 15 seconds of repeatable normal-loop savings.
2. Root and child tests consume one `Aski` compilation and keep full-gate wall time and peak RSS within 10%.
3. `AskiToolSupport` has a product/research ownership split justified independently of packaging.
4. All repository-root paths are injected explicitly, and direct child commands work from the child root.
5. `just check` and `just release-preflight` remain the only authoritative user entry points and validate
   both package graphs without hidden prerequisites.

Until those falsifiers fire, a package split is architecture ceremony around a graph SwiftPM still has to
compile.
