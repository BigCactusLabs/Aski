---
title: "ASKI-89 — Scoped log-polar histogram storage decision rule"
slug: "2026-11-15-aski89-histogram-storage"
date: "2026-11-15"
status: "complete"
subsystem: ["shape-context"]
summary: "Rejected: scoped histogram storage lowered allocation counts but failed three primary speed-benefit bars in five valid pairs. Native parity and API-floor probes passed; four control profiles attributed the temporary arrays. Production retains the owning histogram."
next_action: "No adoption. Preserve the rejected candidate and complete measurement evidence."
related_specs: ["docs/agents/paired-benchmarks.md", "docs/benchmark-validation.md"]
---

## Control and treatment

**Outcome:** rejected. The fresh study completed all five valid pairs. Three
primary wall-benefit bars fail, one is inconclusive, and all four primary
allocation-reduction bars pass. The full readout has 139 passing, three failing
and six inconclusive bars. Four formal control profiles matched all 717,360
target allocation lifetimes, with no unknown extractor sites or open target
generations. Candidate source profiles, separate OS RSS pairs and compatibility
budgets did not run after the timing veto. No production or golden change was
adopted. The [result packet](../../Scripts/research/aski89-2026-11-15/README.md)
retains the complete numerical readout, source replay and profile evidence.
The registered study history and decision rule follow.

Study 1 is **inconclusive**. Both arms qualified, but an unrelated native build
overlapped its first pair. Nine of 14 host observations detected that work, starting
at 2026-11-16 02:07:20 UTC. Both captures remain retained, with no numerical
comparison used for adoption. Pairs 2–5 did not run. Exact debug and release parity
passed all 15 cases, and the candidate passed the full repository gate.

The [fresh-study registration](../../Scripts/research/aski89-2026-11-15/study-02-registration.json)
permits one separate five-pair series after 60 seconds of observed quiet host
conditions. It keeps the same source revisions, instruments, workloads, metrics,
thresholds and decision logic below. It excludes every qualification and study-1
capture from study 2, preserves their hashes, and allows no replacement or third
series. This registration precedes the fresh measurements; it does not turn the
first series into a pass. Diagnostic allocation profiles are separate from timing.

Control uses the owning scalar histogram and then packs its values into the owned SIMD lane array. The single candidate uses the typed `withUnsafeTemporaryAllocation` API for the 60 scalar bins and packs the same owned lanes within the scope. It preserves raster traversal, Float addition and normalization order, lane order, independent call storage and research ownership. Grayscale, Sobel, glyph preparation, matching and public entry points keep their existing behavior. The package histogram wrapper still returns an owned array. Release profiles must establish that the temporary allocation avoids the heap.

InlineArray reaches the Swift 6.3 compiler but requires OS 26. Swift 6.4's new storage APIs exceed the supported compiler floor. Type-check the exact typed temporary-buffer API with `check-api.sh` on Swift 6.3.1 and native Swift 6.4 at macOS 15, iOS 18 simulator and visionOS 2 simulator. [API check script](../../Scripts/research/aski89-2026-11-15/check-api.sh), [Swift 6.3 declaration](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/stdlib/public/core/InlineArray.swift), [availability mapping](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/utils/availability-macros.def), [Swift 6.4 release](https://www.swift.org/blog/swift-6.4-released/).

## Frozen evaluation

Freeze clean arm SHAs, common instrument and input hashes, toolchain and reviewed allocator identity before collecting any arm measurements. The end-to-end group uses a 2400×1800 horizontal gradient and crosses ordinary conversion, ranked animation construction, residual conversion and two-frame tethered temporal conversion with forced serial and parallel execution. It covers 80, 120 and 240 columns at oversample 2, plus 120 columns at oversample 8 and 0.5 edge emphasis. Temporal conversion starts with no prior and feeds the first returned state into a second frame on the reversed gradient. The four controls cover very small ordinary grids and dotMatrix. Conversion setup stays within the timed region. [Literal 36-workload inventory](../../Scripts/research/aski89-2026-11-15/workloads.txt).

Collect five adjacent pairs on one physical Mac. Start with control and alternate order. Use validated end-to-end captures and require `wallClock`, `cpuTotal`, `mallocCountTotal` and `peakMemoryResident`, with raw count units for malloc and resident bytes. Require positive control wall times. For each timing or RSS pair, record normal thermal state immediately before and after, plugged-in power, unchanged power mode and absence of unrelated build, benchmark or media jobs throughout. A noisy pair has an observed disturbance such as an unrelated job, an unplug or power-mode change, or a non-normal thermal report. Score all pairs with attested quiet conditions regardless of statistical spread. Retain every invalid, noisy or unattested attempt. A series with such a registered pair is inconclusive. Keep the original five pairs without replacement or pooling.

- The four ordinary 80/120-column, oversample-2, edge-0 workloads each have two bars. Wall-time reduction must be at least 5%, computed as `(control − candidate) / control`. Malloc count must decrease, so the paired absolute change `candidate − control` must be below zero.
- Every other workload guards wall time. Every workload guards CPU, malloc and sampled resident memory. The guard bar is at most 3% cost rise, computed as `(candidate − control) / control`. With a zero control, a zero candidate counts as 0% and a positive candidate ranks above all finite rises for the median and pair count. Retain the absolute difference.
- Each bar passes when the median and at least four of the five pairs meet that bar. It fails when the median and at least four pairs fall on the failing side of that bar. Every other split is inconclusive. Use the same rule for the separate OS peak RSS guard.

## Native parity and prerequisites

Require bit-identical grids, candidate order, residuals, temporal state and retained descriptors in both debug and release. `ASKI89ParityTests` is opt-in via `ASKI89_PARITY_DIR`. Its 15 cases include an opaque black flat Sobel case, a one-pixel-wide cell with unsupported shape descriptors and all-zero lanes, and a 320×240 seeded SplitMix64 texture at 40 columns, oversample 8 and edge emphasis 0.5. The texture and degenerate fixtures run only in the parity export. [Exporter](../../Tests/AskiTests/ASKI89ParityTests.swift), [literal parity cases](../../Scripts/research/aski89-2026-11-15/parity-cases.txt), [comparator](../../Scripts/research/aski89-2026-11-15/compare-parity.py).

From each arm root set `ARM` to `control` or `candidate` and `RUN` to the absolute path of an existing evidence directory. Use new export directories. Retain both streams and the exit status for each command. Require exit zero from the API check and the four exporter processes, with retained logs, before comparing.

```bash
support=Scripts/research/aski89-2026-11-15
bash "$support/check-api.sh" > "$RUN/$ARM-api.log" 2>&1
ASKI89_PARITY_DIR="$RUN/$ARM-debug" xcrun swift test --filter ASKI89ParityTests > "$RUN/$ARM-debug.log" 2>&1
ASKI89_PARITY_DIR="$RUN/$ARM-release" xcrun swift test -c release --filter ASKI89ParityTests > "$RUN/$ARM-release.log" 2>&1
```

With valid export runs, compare debug and release against the same configuration in the other arm. Exit 0 confirms exact equality, exit 1 rejects the candidate on a valid exact mismatch, and exit 2 indicates invalid inputs and leaves parity inconclusive. An unsuccessful export or missing logs also leaves parity inconclusive.

```bash
python3 -B "$support/compare-parity.py" "$RUN/control-debug" "$RUN/candidate-debug"
python3 -B "$support/compare-parity.py" "$RUN/control-release" "$RUN/candidate-release"
```

Run the scalar, temporal and row-walk tests, full `just check`, existing ASKI-87 benchmark selection and unchanged static-convert and ranked-animation budgets. Exact output parity leaves existing goldens in place.

## Attribution and OS peak RSS

Profile `aski89-convert-80cols-os2-e0-serial`, `aski89-convert-120cols-os8-e50-serial`, `aski89-convert-120cols-os8-e50-parallel` and `aski89-temporal-120cols-os8-e50-serial`. Require attributable grayscale, histogram, SIMD lane and optional Sobel backing, including grayscale copy-on-write where observed. Keep unrelated and unknown allocations outside those families. Require complete matched lifetimes, observed histogram allocation in control, and candidate histogram removal without heap fallback or a compensating extractor allocation. [Qualified stack-logging method](../../Scripts/research/aski92-2026-11-14/README.md#allocation-lifetimes).

For each of the same four IDs, run five separate alternating pairs with the same host attestation and 3% guard. From each arm root set `RELEASE_BIN` to the verified absolute path of that arm's release `AskiBenchmarks` executable, `ID` to one of the four exact IDs, and `RSS_LOG` to a fresh log path for the arm, workload and pair. Time the release executable directly to measure its process RSS. SwiftPM wrapper runs are invalid for this guard.

```bash
if (
    unset MallocStackLogging MallocStackLoggingNoCompact
    /usr/bin/time -l "$RELEASE_BIN" --filter "^${ID}$"
) > "$RSS_LOG" 2>&1; then
    rss_exit=0
else
    rss_exit=$?
fi
printf '%s\n' "$rss_exit" > "$RSS_LOG.exit"
```

Require exit zero and a single completed `Debug results for <ID>:` block for the requested ID with a wall-clock result and no benchmark error. Read the single Darwin `maximum resident set size` value in bytes. Retain the binary identity, command and full log with its exit. A missing or invalid value makes the RSS series inconclusive. This process peak guards resident memory. Source-attributed live bytes come from the separate profiles.

Adopt only when parity, source attribution, every numeric bar and the required checks pass. A valid failed bar or parity mismatch rejects the candidate. Record the failed criterion, retain the frozen candidate for replay and keep the control in production. Missing or invalid inputs leave the affected criteria inconclusive. With no valid rejection and any inconclusive criterion, the verdict is inconclusive.
