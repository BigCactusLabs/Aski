---
title: "ASKI-75 unified aski CLI build and binary tax"
slug: 2026-11-25-aski75-cli-build-tax
date: 2026-11-25
status: complete
subsystem: [meta]
summary: "Measured at 99fc4c7 on an M5 Max with Swift 6.4.2 and the Swift Build backend pinned. Against a lab-free control of the same commit (lab imports, lab command group and the six lab target dependencies removed from AskiCLI), the clean swift build --product aski median is 9.95 s versus 7.84 s (+2.11 s, +26.9%) and the warm no-op median is 1.29 s versus 1.14 s (+0.15 s, +13.2%). Under the reading frozen before measurement (either the 20% or the 15 s limit fires), the clean class exceeds 20%: verdict INVESTIGATE. Under the alternative reading (both limits) it would be ACCEPT. The largest single build process peaks at 2.17 GiB versus 0.73 GiB. The lab modules double the aski executable (debug 13.3 MB vs 6.4 MB, release 8.7 MB vs 4.0 MB; AskiColorLab alone is 2.4 MB of linked symbols) and add CryptoKit and libswift_errno to the load commands; no distribution constraint was found. swift build --target Aski compiles no lab or CLI module."
related_specs: [docs/Research/2026-09-04-aski70-package-boundary-measurement.md, Package.swift, Tools/AskiCLI/AskiCommand.swift, Scripts/research/aski75-2026-11-25/README.md]
results: [docs/Research/Results/2026-11-25-aski75-cli-build-tax]
next_action: "ASKI-114 (filed 2026-11-25) carries the narrow CLI-linkage follow-up drafted in this note. Keep the unified aski lab tree, the one-package architecture and ASKI-70's KILL of a package split."
---

# ASKI-75 unified `aski` CLI build and binary tax

ASKI-48 made the canonical `aski` executable `AskiCLIRunner -> AskiCLI`, and `AskiCLI` statically
imports six lab modules so that `aski lab ...` is discoverable from one command. This note measures
what that costs the product build and the executable, against a lab-free control of the same commit.
It does not reopen ASKI-70's package-split decision.

## Pre-registered rule

Frozen in ASKI-75 AC#5 by owner decision on 2026-11-24, before any measurement:

> Record ACCEPT or INVESTIGATE. ACCEPT when current main's clean and warm product-build medians do not
> exceed the lab-free control's by more than 20% or 15 seconds and no distribution constraint is exposed.
> INVESTIGATE creates a narrow CLI-linkage optimization task only if that threshold fires; it does not
> automatically revive a package split.

"More than 20% or 15 seconds" can be read two ways. Before the first timed sample, the study packet
([README](../../Scripts/research/aski75-2026-11-25/README.md), committed in `7309337`) fixed the
deciding reading: the threshold fires when the median excess is more than 20% of the control median
**or** more than 15 seconds, in either the clean or the warm class. The other reading (fires only when
both limits are exceeded) is reported but does not decide the verdict. The lead was asked for a ruling
before measurement and did not change the default.

## Arms, host and method

- **Commit:** `99fc4c7c556ceaf947f223da93db4dee1ba94c4d` for both arms, each a detached worktree under
  one parent directory with equal-length names.
- **Control:** the same commit plus
  [lab-free-control.patch](../../Scripts/research/aski75-2026-11-25/lab-free-control.patch). It removes the
  imports of AskiAccessLab, AskiColorLab, AskiDecolorLab, AskiHDRLab, AskiMotionLab and AskiVideoLab, the
  `lab` group and its six adapters from `Tools/AskiCLI/AskiCommand.swift`, and the six lab dependencies of
  the `AskiCLI` target. It was never committed to a branch.
- **Host:** Apple M5 Max (`Mac17,11`), 18 cores, 64 GB; macOS 27.2.1 (26B8132); arm64.
- **Toolchain:** Xcode 27.2 (27B52); Apple Swift 6.4.2 (swiftlang-6.4.2.1.9, clang-2100.4.1.1);
  swift-driver 1.168.6; Swift Package Manager 6.4.2.
- **Backend:** `--build-system swiftbuild` passed on every build (it is also the 6.4.2 default; native and
  xcode are deprecated). Debug configuration and `--force-resolved-versions` unless noted.
- **Package cache:** the shared SwiftPM repository cache in `~/Library/Caches/org.swift.swiftpm` was already
  populated. Each sample resolved its checkouts from it with an untimed `swift package resolve` into the
  sample's own scratch path before timing, so no fetch ran inside a timed build.
- **Clean sample:** `swift build --product aski` into a fresh `--scratch-path` that no build had used.
  Swift Build kept its explicit-module and precompiled-module caches inside the scratch path
  (`out/Intermediates.noindex/SwiftExplicitPrecompiledModules`, `out/SDKExplicitPrecompiledModules`).
- **Warm sample:** ASKI-70's definition, the same command repeated immediately after the clean build
  (a no-op rebuild).
- **Link-only sample:** after the warm build, delete only the `aski` executable in the
  `--show-bin-path` directory and rebuild. No compile step ran in those logs; the only task was
  `aski-product`. Optimization settings were not changed.
- **Order:** one priming pair (`p0`), excluded before measurement, then control, main, main, control,
  control, main (`s1` to `s3`). Each sample (clean, warm and link) ran inside the machine-wide build lock,
  with `vm.loadavg` recorded at the start of each step.
- **Measures:** `/usr/bin/time -lp` `real` is wall time. Its "maximum resident set size" is the largest
  RSS of a **single process** in the build's process tree, not the sum across concurrent compiler
  processes. "SwiftPM reported" is the `Build complete! (N sec)` figure, which excludes process start-up
  and package loading.

Sampler, summarizer and diagnostic passes: [Scripts/research/aski75-2026-11-25](../../Scripts/research/aski75-2026-11-25/README.md).

## Samples

| Sample | Run order | Arm | Step | Wall (s) | SwiftPM reported (s) | Max single-process RSS (MiB) | 1-min load at start |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: |
| p0 (priming, excluded) | 1 | control | clean | 8.70 | 6.37 | 755 | 13.90 |
| p0 (priming, excluded) | 1 | control | warm | 1.15 | 0.30 | 155 | 12.60 |
| p0 (priming, excluded) | 1 | control | link | 1.37 | 0.53 | 296 | 12.60 |
| p0 (priming, excluded) | 2 | main | clean | 10.92 | 8.70 | 2181 | 3.54 |
| p0 (priming, excluded) | 2 | main | warm | 1.38 | 0.38 | 164 | 6.03 |
| p0 (priming, excluded) | 2 | main | link | 1.48 | 0.59 | 331 | 6.03 |
| s1 | 3 | control | clean | 7.88 | 6.72 | 745 | 5.87 |
| s1 | 3 | control | warm | 1.16 | 0.30 | 155 | 6.44 |
| s1 | 3 | control | link | 1.48 | 0.63 | 297 | 6.16 |
| s1 | 4 | main | clean | 9.74 | 8.64 | 2208 | 5.75 |
| s1 | 4 | main | warm | 1.26 | 0.36 | 164 | 6.80 |
| s1 | 4 | main | link | 1.47 | 0.60 | 329 | 6.80 |
| s2 | 5 | main | clean | 10.30 | 9.07 | 2218 | 6.42 |
| s2 | 5 | main | warm | 1.41 | 0.51 | 161 | 8.21 |
| s2 | 5 | main | link | 1.50 | 0.59 | 330 | 8.21 |
| s2 | 6 | control | clean | 7.84 | 6.68 | 751 | 7.79 |
| s2 | 6 | control | warm | 1.06 | 0.28 | 154 | 7.06 |
| s2 | 6 | control | link | 1.24 | 0.46 | 296 | 7.06 |
| s3 | 7 | control | clean | 7.32 | 6.22 | 759 | 6.57 |
| s3 | 7 | control | warm | 1.14 | 0.31 | 154 | 7.56 |
| s3 | 7 | control | link | 1.29 | 0.47 | 296 | 7.56 |
| s3 | 8 | main | clean | 9.95 | 8.75 | 2223 | 7.28 |
| s3 | 8 | main | warm | 1.29 | 0.39 | 165 | 7.74 |
| s3 | 8 | main | link | 1.49 | 0.56 | 331 | 7.28 |

CSV: [samples.csv](Results/2026-11-25-aski75-cli-build-tax/samples.csv). The priming control sample ran
at load 13.9 while other workers' builds were draining; it is excluded by the pre-registered rule, not
after the fact.

## Medians and verdict

| Class | Control median (s) | Main median (s) | Excess (s) | Excess (%) | >20%? | >15 s? | Control RSS (MiB) | Main RSS (MiB) |
| --- | ---: | ---: | ---: | ---: | --- | --- | ---: | ---: |
| clean | 7.84 | 9.95 | +2.11 | +26.9 | **yes** | no | 751 | 2218 |
| warm (no-op) | 1.14 | 1.29 | +0.15 | +13.2 | no | no | 154 | 164 |
| link-only | 1.29 | 1.49 | +0.20 | +15.5 | (not in rule) | | 296 | 330 |

The clean ranges do not overlap (control 7.32 to 7.88 s, main 9.74 to 10.30 s). The SwiftPM-reported
clean medians, 6.68 s and 8.75 s, give the same ratio (+31%).

**Verdict: INVESTIGATE.** Under the pre-registered reading the clean product build exceeds the control by
more than 20%. The 15-second limit is not approached in either class, so under the alternative
both-limits reading the result would have been ACCEPT. The threshold fired on a 2.1-second absolute cost.
That is what the frozen rule asks for, and the follow-up below is scoped to that size.

The verdict does not reopen ASKI-70. A narrower CLI-linkage implementation must keep the same command
surface; a package split is not indicated by these numbers.

## Link step

Isolated by deleting only the linked executable after a warm build (see method). Link-only medians are
1.49 s for main and 1.29 s for control in wall time (+0.20 s), and 0.59 s versus 0.47 s as reported by
SwiftPM (+0.12 s). Linking is not where the clean-build excess comes from; the extra time is in compiling
the six lab modules. Swift Build's debug link passes `-Xlinker -dead_strip` for this product (confirmed
in a separate `--very-verbose` pass for both arms), so the executable bytes below are what survives dead
stripping, not whole-module inclusion.

## Peak memory

The largest single build process reaches 2.16 to 2.17 GiB in every main clean sample and 0.73 to 0.74 GiB in the
control (×2.95). The release build shows the same split (2.12 GiB vs 0.69 GiB). This note does not
attribute the peak to a process. AskiColorLab is the likely candidate (about 20,600 Swift source lines,
against about 13,800 in `Sources/Aski`), but that is a hypothesis for the follow-up, not a measurement.

## Binary footprint

From separate, untimed passes per arm with `-Xlinker -map` (debug) and `-c release` (the configuration
`Scripts/package-cli.sh` ships). Timed debug samples produced the same sizes (control 6,383,040 bytes,
main 13,304,480 bytes in every sample; the map pass differs by a few hundred bytes of scratch-path strings).

| Arm | Config | Bytes | `__TEXT` | `__DATA_CONST` | `__DATA` | `__LINKEDIT` | Linked libraries | Load commands |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| control | debug | 6,383,280 | 2,834,432 | 81,920 | 147,456 | 3,440,640 | 39 | 60 |
| main | debug | 13,304,848 | 6,111,232 | 147,456 | 278,528 | 7,012,352 | 41 | 62 |
| control | release | 4,009,912 | 1,441,792 | 81,920 | 131,072 | 2,457,600 | 39 | 59 |
| main | release | 8,711,160 | 3,440,640 | 163,840 | 245,760 | 5,062,656 | 41 | 61 |

`otool -L` differs by two entries, both present only in main: `CryptoKit.framework` (imported by
`Tools/AskiColorLab/Arbiter/ArbiterJudge.swift` and `Tools/AskiColorLab/TargetWidth/TargetWidthGate.swift`)
and `/usr/lib/swift/libswift_errno.dylib`. Both ship with macOS at the package's macOS 15 floor. Both
release bin directories contain the same single resource bundle, `Aski_Aski.bundle`; the labs add no
resource bundle or dynamic framework (`PackageFrameworks` is empty in both). The binary stays arm64-only.

Linked symbol bytes by module from the debug linker maps
([debug-link-map-by-module.csv](Results/2026-11-25-aski75-cli-build-tax/debug-link-map-by-module.csv)):

| Module | Main | Control | Delta |
| --- | ---: | ---: | ---: |
| AskiColorLab | 2,405,222 | 0 | +2,405,222 |
| AskiVideoLab | 271,332 | 0 | +271,332 |
| AskiMotionLab | 270,208 | 0 | +270,208 |
| AskiDecolorLab | 157,005 | 0 | +157,005 |
| AskiHDRLab | 147,182 | 0 | +147,182 |
| AskiAccessLab | 136,374 | 0 | +136,374 |
| AskiCLI | 174,508 | 115,805 | +58,703 |
| Aski, AskiToolSupport, ArgumentParser, ArgumentParserToolInfo | 2,839,585 | 2,839,753 | −168 |
| linker-synthesized, runtime shims and stubs | 92,634 | 61,619 | +31,015 |
| **Total** | **6,494,050** | **3,017,177** | **+3,476,873** |

AskiColorLab alone is 37% of main's linked symbol bytes. The product modules link to within 76 bytes of the same size in both
arms, so the lab tree adds code without changing what the product path links.

**Distribution constraint: none found.** The executable roughly doubles (release +4.7 MB) and gains two
system libraries, but it needs no new platform floor, resource bundle, dynamic library, architecture or
entitlement. Download size is a product concern the owner may weigh; no recorded distribution budget
exists to test it against.

Supplementary single samples, not part of the rule: the release build took 34.69 s wall for main and
13.87 s for control.

## Library target frontier (AC#3)

`swift package describe --type json` at 99fc4c7 lists the `Aski` target with no target or product
dependencies; its transitive frontier is `{Aski}`. The `AskiCLIRunner` frontier is
`{Aski, AskiAccessLab, AskiCLI, AskiCLIRunner, AskiColorLab, AskiDecolorLab, AskiHDRLab, AskiMotionLab,
AskiToolSupport, AskiVideoLab}` plus `ArgumentParser` on main, and `{Aski, AskiCLI, AskiCLIRunner,
AskiToolSupport}` plus `ArgumentParser` on the control.

`swift build --target Aski --build-system swiftbuild -v` at main, fresh scratch path: 10.07 s wall
(6.72 s reported), 569 MiB maximum single-process RSS, exit 0
([target-aski.csv](Results/2026-11-25-aski75-cli-build-tax/target-aski.csv)). The build log's
`-module-name` values are `main` (the manifest), `BenchmarkPlugin` (package-benchmark's build-tool
plugin) and `Aski`; the product directory holds only `Aski.o`, `Aski.swiftmodule` and
`Aski_Aski.bundle`. No lab or CLI module is compiled.

Compiling `BenchmarkPlugin` for a library-only build is a root-manifest cost, not a CLI cost. It is noted
here, not investigated; ASKI-70 already records that every root invocation resolves the full manifest.

## AC#4 preservation

No product file changed. The control existed only in a disposable worktree and is preserved as a patch for
replay. The one-package architecture, the `aski lab` command tree, the historical replay shims, help,
version, error and shell-completion behaviour are untouched on this branch.

## Proposed follow-up (INVESTIGATE)

Narrow CLI-linkage task, filed by the lead as ASKI-114 on 2026-11-25: reduce the clean `aski` product-build cost of the
unified lab tree without changing the command surface. First establish what the 2.1 s and the 2.17 GiB peak
come from (Swift Build trace events, per-process memory with `footprint`, per-module compile timing), then
test link-topology options that keep `aski lab ...` byte-identical in help, metadata and replay
(for example a thinner lab adapter layer, or splitting AskiColorLab's arbiter and target-width code from its
command surface). Re-measure with this packet's sampler and the same frozen 20%-or-15-second rule. A
package split stays out of scope.

## Limitations

- One host, three samples per class. The host was shared: other workers' builds ran between samples
  (1-minute load 5.8 to 8.2 at the start of included steps). Each sample held the build lock, but background processes
  outside the lock were not controlled.
- Builds on this host are short. A 20% bar on a 7.8-second build is a 1.6-second bar; the verdict reflects
  the frozen rule, not a judgement that 2 seconds is large.
- Peak RSS is per process, not tree-wide. No tree-wide memory measure was taken.
- Global caches outside the scratch path (the SwiftPM repository cache, the toolchain's own caches) were
  shared by both arms and warmed by the priming pair.
- The control removes the lab tree and nothing else. It does not model any proposed optimization.
