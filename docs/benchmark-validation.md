# Benchmark evidence that can say “no”

`just bench` validates **completeness**, not a performance budget. A plugin exit of
zero is insufficient: a selected workload can fail before producing samples, and an
unsupported counter can disappear from otherwise plausible output. ASKI-86 owns this
validity check; ASKI-5 still owns numeric regression budgets and their gate placement.

## Run it

Use the selected Xcode toolchain on a Mac, Python 3.8+, and just 1.29+:

```bash
just bench                            # All discovered AskiBenchmarks workloads
just bench --smoke                    # All six ASKI-86 reproduction workloads
just bench --smoke --require-metric mallocCountTotal
just bench --filter '^convert-gradient-.*$' --require-metric mallocCountTotal
```

`--smoke` includes animation construction, animation frame evaluation, adaptive tile
quantization, masked conversion/rendering, the 720p one-shot video pipeline, and image
rendering. The exact six names live in the script's `SMOKE` constant. Every member is
required: a missing registration or rename fails rather than silently shrinking the
subset. It cannot be combined with `--filter`.

For a custom subset, `--filter` and `--skip` are **Python full-match regular expressions**.
Repeated filters are ORed; exclusions win. `--expect NAME` additionally requires that
exact workload to be selected, useful when a regex contains several named alternatives.
The adapter discovers all names first, selects them itself, then gives Swift a literal
exact-match filter. It does not pretend Python and Swift regex dialects are identical.
Current Aski workload IDs are untagged letters, digits, dots, underscores, and hyphens;
new naming/tagging conventions require an explicit adapter update.

The runner resolves the checkout from its own location. Direct invocation is equivalent:

```bash
python3 -B Scripts/validate-benchmarks.py --smoke --require-metric mallocCountTotal
```

`just bench` preserves shell argument boundaries with `"$@"`; regex operators and paths
containing spaces must reach Python as single arguments. There is no shell `eval`.

## What qualifies as complete

The runner requires a successful inventory, a nonempty selection, a successful process,
no recognized failure diagnostics, and nonempty, well-formed sample exports for every
selected workload and required metric. A malformed header, truncated row, unknown metric,
unexpected workload/file, changed dependency lock, or missing workload invalidates the
run. Setup, execution, teardown, and export errors are not rescued by other good results.
An actual measured zero is valid data; **absence is never replaced by zero**.

There is one unresolved export limit: package-benchmark 1.35.0 ignores the byte count
returned by its sample-file write. A short write that ends after a complete row leaves
a well-formed file with too few samples. The `histogramSamples` run prints file paths,
but no independent per-workload, per-metric sample counts in its captured output, so
this validator cannot detect that case. A complete report therefore does not certify
that every intended sample row reached disk. The regression fixture records this as
an expected failure until an independent count source is available.

`wallClock` is always required. `--require-metric` adds requirements; it does **not**
change the metrics requested by Swift, override benchmark configurations, or remove
thresholds. For example:

```bash
just bench --smoke --require-metric allocatedResidentMemory
```

This must fail when that counter is not exported. `mallocCountTotal` and
`allocatedResidentMemory`, the other default-configured counters, are explicitly listed
under `optional_not_exported` when absent and not required. Absence can mean “not
configured for this workload” or “unsupported by this backend”; retained warning logs
supply the backend's explanation when available. Optional absence is not evidence for a
required allocation/memory budget. Add a metric to the relevant Swift benchmark
configuration before requiring it if it is not currently collected. No automatic RSS or
other counter substitution is made.

The script intentionally exposes only run/selection/validity options, not baseline or
threshold mutation commands. Numeric thresholds and benchmark configurations stay in
`Benchmarks/AskiBenchmarks/`. `budget_verdict` is always `not_evaluated`; a complete run
can still be slow.

## Retained evidence

Each invocation creates a private, fresh directory beneath `.build/benchmark-validation/`.
Its location is printed before work begins. `--output-dir PATH` chooses another **new**
directory with an existing parent; existing output is refused, never reused or deleted.
Concurrent captures use separate directories, though concurrent performance measurements
are not comparable evidence. Raw logs and sample files are retained on failure as well as
success. Remove captures when no longer needed; raw-sample exports can be large.

`report.json` starts with `complete: false` and `status: running`. A finished capture is
`valid` only after all checks pass; interruptions/timeouts remain `invalid`. SIGINT and
SIGTERM stop processes in the invocation's isolated session, including child process
groups created by SwiftPM. Cleanup requires host `ps` access. An optional `--timeout SECONDS` applies to
each inventory/run subprocess. An uncatchable kill may leave `running`, which is **not**
a successful result.

The report retains selected and discovered identities, required metrics, per-metric
sample counts/headers/units, file hashes, plugin diagnostics, exact commands, timestamps,
Git revision, Swift/Xcode/macOS versions, and dependency pins. Backend identity is
**configured provenance** derived from the reviewed package, Swift 6.3+, default traits,
and backend-disable environment flags—not an independently probed runtime allocator.
The malloc-interposer pin is retained. Local `MALLOC_INTERPOSER_LOCAL_PATH` overrides are
rejected because their provenance is not established. Inspect logs before posting them:
compiler/AVFoundation diagnostics can contain local paths. No environment dump is saved.

The data files are the upstream `histogramSamples` export, with nanosecond units forced
for capture. They contain normalized HDR-histogram samples, not chronological observations.
Count headers may omit a suffix; the adapter records their unscaled unit as `#`, retaining
the original metric header as well. Do not reinterpret that generic display unit without
also considering the metric's identity. No rounded summary is used to infer sample presence.

The adapter is deliberately pinned to package-benchmark **1.35.0**, revision
`4b9ef5663e9c270419351a20392bf77b007f37f6`. A dependency upgrade requires reviewing the
inventory/export contract and updating fixtures, not silently accepting a new schema.

## Verification and current boundary

Portable regressions are included in the existing script-test discovery:

```bash
just test-infra
# Focused equivalent without just:
python3 -B -m unittest discover -s Scripts/tests -p 'test_benchmark_validation.py' -v
```

The fixtures reconstruct the pinned exporter and fake Apple tools. They cover intentional
setup/execution/teardown failures, exit-zero partial output, empty/missing selections,
empty/corrupt samples, required/optional metrics, stale output, dependency drift,
selection quoting, timeouts, and interruptions. **They are not real Swift benchmark runs.**

Before ASKI-86 can be closed, run the real smoke subset with encoder access on the recorded
Mac toolchain, exercise genuine plugin setup/execution failure paths, verify the captured
backend identity against that host, and run `just check` plus `just test-infra`. The initial
implementation was exercised in Linux/Python, not Xcode. Do not infer native acceptance,
encoder correctness, or end-to-end speedups from those portable results.

`just check` is unchanged: format, one shared build, drift checks, the existing three test
phases, then DocC. Benchmark discovery/run commands are separate and may each ask SwiftPM
for an incremental release build; they do not add a build to the acceptance gate.

## Work order for ASKI-87–95

This is a starting sequence, not completed optimization work. Keep each change isolated
against an unchanged control and use the existing task files as the acceptance checklist.

| Tasks | Next experiment | Adoption blocker |
| --- | --- | --- |
| 87, then 90 and 92 | Prepared footprint geometry, fixed-palette display colors, shared tile samples | Include preparation in repeated end-to-end measurements; prove exact descriptors/colors/palettes/grids and bounded lifetime. |
| 88, then 89 | Exact brightness-pool selection, then attributed descriptor scratch allocations | Preserve ties/ranking/residuals; isolate allocation attribution before choosing new storage. |
| 91 | Pattern-specific frame benchmarks before frame-wide reuse | Preserve validation-before-empty, neutral cell semantics, time boundaries, and composition metadata. |
| 93 and 94 | Lower-rate video fixture matrix and original-image fallback draw census | Preserve frame identity/CFR/transform behavior and ragged-grid populated coverage; native media/render verification is essential. |
| 95 | Reduced-capability seeded-noise construction versus CI rendering | Establish fallback frequency first; any reuse needs a measured memory bound and changing-seed control. |

A starting decision bar for these experiments is at least a 5% end-to-end median wall-time
improvement across five alternating control/candidate pairs, with preparation included,
no reproducible regression above 3% on the named small/no-op/no-resampling controls,
exact task-specific output parity, and the required allocation/RSS evidence. These are
**proposed experiment decision bars, not replacements for existing benchmark thresholds**.
Register a different justified bar before measuring if the workload needs one. Report all
pairs, CPU/allocation results, and noise; a noisy 5% median alone is inconclusive. An isolated
histogram/cache microbenchmark is not an adoption verdict. No production optimization in
87–95 is adopted by this tooling change.

## ASKI-87: prepared-footprint candidate

**State: adopted by explicit maintainer exception on 2026-11-12; the full replay
rule remains unmet.** Seven of eight primary
cases exceed the 5% benefit bar; the 120-column, oversample-4 parallel case improves
by 2.10%. All control/resource guards pass. The adoption decision below preserves
the failed per-case benefit rule and every measured result. The 2026-11-12 replay starts from `main` at
`2c3d1bd1aee067a976e5db7cbf2aff3841e5a37b`.
Its scalar control removes only the footprint setup and use from the integrated
candidate; it does not restore older versions of whole files. `ShapeContext.Footprint` prepares the
pixel-to-bin map once per `ConversionContext`; the shared log-polar extractor uses
it for ordinary, ranked, residual, temporal, and research descriptor paths. The
original scalar histogram remains the per-glyph implementation and test control.
Radius/log/angle arithmetic, row-major additions, the 0.05 threshold, and normalization
order are unchanged. No matcher policy, public API, dependency, or golden changes.

Storage is one logical byte per footprint pixel (zero for a degenerate footprint),
plus the Array allocation/header. It lives only with that conversion context; row
workers share immutable geometry and allocate separate histograms. This uses ordinary
[Sendable value types](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/#Sendable-Types),
not a global cache or shared mutable scratch. The candidate eagerly prepares contexts
used by dotMatrix too: the dedicated negative controls must establish whether that
unused setup is acceptable before merging. Do not infer a heap/RSS bound from the
logical payload count alone.

### Executed core checks and diagnostic timings

```bash
Scripts/research/check-shape-context.sh test
Scripts/research/check-shape-context.sh timing 5 > histogram-timing.csv
```

The script copies the actual source/tests into an isolated temporary Swift 6.2 core
package, runs in release mode with Swift 6 language mode and warnings as errors, and
removes its temporary build on exit. It never lowers the real package's Swift 6.3+
requirement or substitutes for `just check`. On Linux x86_64 / Swift 6.2.1, all six
core tests passed: over 30,000 bit-pattern comparisons across odd/even/degenerate
footprints, threshold neighbors, impulses, exceptional weights, and concurrent reuse.

The [raw CSV](../Scripts/research/aski87-histogram-timing.csv) and
[provenance/summary JSON](../Scripts/research/aski87-histogram-timing.json) retain all
240 measurements (120 pairs), including CPU seconds, checksums, source hashes, zero
fields, and one-cell losses. These are standalone histogram timings in a shared
container, **not native Aski conversion benchmarks or allocation measurements**.
Preparation is inside each measured batch, with five alternating scalar/prepared passes.
For mixed fields, 2,400 histograms per preparation and 10 batches per measurement:

| Footprint | Scalar median, ms | Prepared median, ms | Wall-time change |
| --- | ---: | ---: | ---: |
| 2 × 3 | 4.680 | 2.885 | −38.4% |
| 3 × 3 | 6.149 | 2.906 | −52.7% |
| 8 × 12 | 27.002 | 4.013 | −85.1% |
| 16 × 24 | 104.536 | 8.127 | −92.2% |

Each table measurement covers 24,000 histograms, not one conversion. Preparing a map
for every single histogram was slower on all four mixed-field shapes (about 2.7–35.0%),
and zero-field preparation can be substantially worse because the scalar path skips
geometry for under-threshold pixels. At 32 zero-field cells, the 16 × 24 candidate
regressed 23.7%. These losses are why the native setup and small-grid controls matter;
the table is not a product speedup or an adoption verdict.

### Native acceptance protocol

`ShapeContextFootprintBenchmarks.swift` registers 52 measurement-only workloads under
`aski87-`: scalar/prepared histograms, 1/8/80/120-column conversions, oversample 2/4/8,
forced serial/parallel walks, repeated frames, ranked animation construction, and
dotMatrix controls. Conversion-map preparation is inside the measured conversion.
All collect wall/CPU/malloc counts; existing budget values remain untouched.
`LogPolarFootprintIntegrationTests` adds scalar-control descriptor, ordinary/ranked
winner, residual, held-glyph distance, and final-grid checks. The original Linux
preparation only syntax-parsed these sources. A later native `just check` at
`0af4bf6` passed 1,442 core tests, 152 media tests, both sentinels and DocC. Repeat
that gate on the current-main integration; neither earlier record proves a native
performance benefit.

On the recorded Mac toolchain, run:

```bash
just check
just bench --filter '^aski87-.*$' --require-metric cpuTotal --require-metric mallocCountTotal
```

Require all 52 workload identities in the inventory/report; do not accept a partial
matrix. For the end-to-end control, create a separate worktree from the integrated
candidate. Remove **only** the footprint property and initialization in
`Sources/Aski/CellSampling.swift`, and restore the scalar `ShapeContext.histogram60`
call in `Sources/Aski/Algorithms/LogPolarKernel.swift`; commit that treatment reversal.
Keep the same new instrumentation and `ShapeContext` source
in both worktrees. This removes map setup and usage from the control without changing
its benchmark harness, while giving each arm an honest recorded Git identity. Verify
the resulting diff contains only that treatment reversal before collecting five
alternating complete runs on the same toolchain/allocator. Do not measure concurrent
runs or compare a dirty control labeled with the candidate SHA.

Use the decision bar above: material end-to-end benefit, no reproducible small-grid
or dotMatrix regression above 3%, exact native parity, and allocation evidence.
The initial evidence did not satisfy that bar. The completed native replay below
records the remaining acceptance shortfall and the explicit adoption exception.

### Bounded replay — registered 2026-11-12

Keep all 52 workload identities and all three metrics, with the existing one
warmup, ten-iteration and three-second per-workload limits. Build/list both arms
before capturing; do not overlap captures with builds, tests or other measurements.
Commit both arms and verify matching instrument, dependency-lock and validator
hashes. Use one complete control preparation run, outside the paired series, to
project runtime. Ten warm captures must fit a **20-minute wall budget**. If the
projection does not fit, stop and redesign the selection before a new experiment;
do not start an hours-long run. Retain every failed or noisy capture.

Allow at most 600 seconds per cold inventory/preparation subprocess, then 180
seconds per inventory/run subprocess in the five adjacent alternating pairs.
The entire paired series stops at 1,200 seconds; an incomplete series cannot adopt.
Record AC power, thermal status and desktop contention. An active desktop is a
disclosed deviation from the quiet-host goal; a small noisy gain is inconclusive.

To make the existing 5% benefit / 3% regression bars explicit before this replay:

- The eight primary workloads are `aski87-convert-{80,120}cols-os{4,8}-{serial,parallel}`.
  They cover both larger grids, both higher sampling settings named by ASKI-87,
  and both row modes. Each must improve median paired wall time by at least 5%,
  with improvement in at least four of five pairs. Default-oversample, repeated
  and ranked workloads remain in the full matrix; no histogram win substitutes
  for an end-to-end result.
- For all 36 end-to-end workloads, reject a reproducible regression above 3% in
  wall time, CPU or total allocations. This includes every 1/8-column and dotMatrix
  control, 80/120-column conversion, repeated conversion and ranked construction.
  Reproducible means at least four of five paired deltas exceed +3%. Mixed signs
  do not establish a speedup or strict per-pair noninferiority. Report them.
- Exact native descriptor/winner/residual/grid parity and bounded immutable map
  storage are prerequisites. Run `just check` and the existing conversion and
  animation workloads with their original configurations. No golden or threshold
  changes are permitted for acceptance.

Read all required cells, not only a generic comparator's first error. For every
allocation cell, including matching units, use the pinned exporter contract to
convert decimal units with ±half an exported unit propagated through each paired
ratio. Retain the generic comparator's result, including any invalid unit-mismatch
result. Scaling cannot recover lost precision. If the bounds change the four-of-five
regression outcome, that cell is undetermined and blocks adoption. Resolve only
affected workloads with a separate paired diagnostic that forces unscaled allocation
counts identically in both arms; keep the original benchmark instrument and captures.
If that diagnostic cannot fit the remaining bounded session, leave the result
inconclusive. Disclose three-significant-digit histogram quantization and host noise.
Report sample counts per arm for every primary and guard cell, including counts
below ten when the original duration limit ends an arm early.
Before the first capture, both instruments explicitly set
`units: [.mallocCountTotal: .count]`. The pinned executor uses this per-metric
setting before its automatic units, so the counter exports unscaled values instead
of rounding to whole thousands. This output-unit change does not alter the timed
work, sample limits or thresholds. Raw values still have HDR histogram quantization;
unscaled export does not turn them into exact chronological counts.
An independent cross-model review must accept the instrument and readout method
before the numbers support a verdict.

### Native replay result — 2026-11-12

Measured candidate: `51b736924fbcd4f4868ef5adf99fac9dfa51b3cd`.
Measured scalar control: `0c8c1bfeef85f44990e6bd0f5c7590010ca44708`.
Their difference is exactly the footprint property/initialization and its use in
the extractor. All benchmark, validator and dependency-lock hashes match.

All **52 workloads × three metrics × five adjacent alternating pairs** completed
in **641.749 seconds (10m42s)**. Every capture was valid, with ten exported samples
per workload/metric/arm; no capture or workload was removed. The preparation run,
excluded from those pairs, took 68.33 seconds. The host was Mac15,10, 14 logical
CPUs, 36 GiB RAM, macOS 27.0.1, Xcode 27.0 and Swift 6.4, on AC power with no
recorded thermal/performance warning. Builds and tests finished before captures;
the desktop remained active. This was not an idle-host measurement.

Median paired wall-time change below uses `100 × (candidate − control) / control`.
Negative means lower cost. Each pair compares exported-sample medians; samples
are not pooled across captures.

| Columns | Oversample | Row mode | Median wall change | Improving pairs |
| ---: | ---: | --- | ---: | ---: |
| 80 | 4 | serial | −6.85% | 5/5 |
| 80 | 4 | parallel | −7.25% | 4/5 |
| 80 | 8 | serial | −15.71% | 5/5 |
| 80 | 8 | parallel | −8.88% | 5/5 |
| 120 | 4 | serial | −9.19% | 5/5 |
| 120 | 4 | parallel | **−2.10%** | 5/5 |
| 120 | 8 | serial | −12.80% | 5/5 |
| 120 | 8 | parallel | −7.63% | 5/5 |

All **108 end-to-end guard cells** (36 workloads × wall/CPU/allocations) pass the
registered four-of-five >3% regression test. Small controls add one allocation:
56→57 for one-column conversions, 51→52 and 52→53 for the smallest dotMatrix cases,
all below 2%. Unscaled integer export adds no rounding error at these magnitudes;
the HDR histogram also has single-unit resolution for these small counts. The
initial readout's ±half-base-unit interval was unnecessarily broad and is corrected
in the reproducer. Larger HDR values remain quantized; this is not exact allocation
tracing or a process-RSS measurement. All 108 guard outcomes remain unchanged in a
separate sensitivity calculation that raises each candidate median by 0.1% and
lowers its control by 0.1%; this does not bound host noise.

The sole below-bar primary improves in every original pair, but its changes range
from −0.44% to −8.08%, and its median does not reach 5%. One separately registered,
three-minute-capped repeat selected only that workload. It produced one complete
pair: individual captures still took 59–65 seconds. A remaining-time inventory
timeout stopped the next capture after 142.876 seconds total. The incomplete repeat
is retained and cannot replace the original result. No cap extension or further
repeat was made.

Native `just check` on integration `2890a8b` passed **1,537 core tests, 177 media
tests, both deadlock sentinels, formatting/build/drift checks and DocC**, including
both footprint parity suites. The later executable difference is solely the
benchmark's explicit allocation output unit; both release instruments were rebuilt.
All six existing conversion/animation workloads produced complete captures, and the
four animation workloads passed their unchanged inline absolute budgets via
`benchmark baseline check --check-absolute`. No public API, golden, timed workload,
iteration limit or budget threshold changed. Independent Opus review found no
production correctness defect; its allocation-unit concern was fixed before capture.

The final publication `just check` also passed in **156.719 seconds**, with the same
1,537 core / 177 media / two sentinel counts and DocC. It checked source `51b7369`
plus the uncommitted evidence, documentation and backlog updates. Only result
metadata and backlog completion notes changed afterward; the tested source,
instruments, raw exports, readout code and decision rule are unchanged.

The synthetic gradient exercises much more admitted weight than an all-zero field;
the earlier diagnostic losses remain relevant. These results establish this matrix
on one Mac, not a general product speedup. Eager setup also affects tile and temporal
contexts, which have no paired workloads here. Logical map payload is not an RSS bound.

### Adoption decision — 2026-11-12

The maintainer explicitly approved merging PR #8 with the recorded exception for
the 120-column, oversample-4 parallel case: 2.10% improvement instead of the
registered 5%. The decision accepts the material benefit in the other seven
primary cases, exact native parity, and all 108 passing regression guards.
The stricter per-case rule was introduced for this replay; the original task asked
for material end-to-end benefit. This is a product adoption decision with a known
shortfall, not a passing verdict under the registered rule. The rule, raw exports,
incomplete focused attempt, and reproducer's `not_supported` result remain unchanged.
No additional performance run or budget-threshold change accompanies this decision.
Only adoption documentation, changelog and backlog metadata changed after the
passing final native gate; its executable validation carries forward unchanged.

Evidence: [original comparison](../Scripts/research/aski87-2026-11-12/comparison.json),
[780 paired rows](../Scripts/research/aski87-2026-11-12/paired-medians.csv),
[all 1,560 raw exports](../Scripts/research/aski87-2026-11-12/histogram-samples.json),
[summary](../Scripts/research/aski87-2026-11-12/summary.json),
[incomplete focused attempt](../Scripts/research/aski87-2026-11-12/focused-attempt.json),
and [provenance](../Scripts/research/aski87-2026-11-12/provenance.json).
The [portable reproducer](../Scripts/research/aski87-2026-11-12/reproduce.py) verifies
every export hash, unit, count and median before evaluating the unchanged rule:

```bash
python3 -B Scripts/research/aski87-2026-11-12/reproduce.py --output-dir /tmp/aski87-readout
```

## Source audit

The implementation follows the pinned upstream code rather than assuming the latest
package has the same behavior:

- [Format stability guidance](https://github.com/ordo-one/benchmark/blob/1.35.0/README.md#api-and-file-format-stability): exported formats are the intended persistence interface; internal baselines/histogram Codable are not stable APIs.
- [Runner failure and unsupported-metric paths](https://github.com/ordo-one/benchmark/blob/1.35.0/Sources/Benchmark/BenchmarkRunner.swift): setup/teardown errors and unsupported backend metrics need explicit treatment.
- [Inventory and filename rules](https://github.com/ordo-one/benchmark/blob/1.35.0/Plugins/BenchmarkTool/BenchmarkTool%2BOperations.swift) and [per-metric sample export](https://github.com/ordo-one/benchmark/blob/1.35.0/Plugins/BenchmarkTool/BenchmarkTool%2BExport.swift): the adapter's source of truth.
- [Plain JSON](https://github.com/ordo-one/benchmark/blob/1.35.0/Plugins/BenchmarkTool/BenchmarkTool%2BExport%2BJSON.swift) omits sample counts; [JMH](https://github.com/ordo-one/benchmark/blob/1.35.0/Plugins/BenchmarkTool/BenchmarkTool%2BExport%2BJMHFormatter.swift) requires throughput, which Aski's default configuration does not request. Neither is used to certify this capture.
- [just positional arguments](https://just.systems/man/en/positional-arguments.html): the per-recipe attribute preserves argument boundaries without changing other recipes.
