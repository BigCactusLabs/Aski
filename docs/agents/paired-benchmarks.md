# Compare repeated benchmark captures

`Scripts/research/compare-benchmarks.py` reads complete ASKI-86 captures and produces
a per-workload comparison across repeated control/candidate pairs. It runs with
Python 3.8+ and the standard library; it does not build or run Aski. It validates
and compares evidence; it does not enforce the package's numeric budgets or
decide adoption.

The capture producer is the checked-in
[`Scripts/validate-benchmarks.py`](../../Scripts/validate-benchmarks.py), invoked
by `just bench`. Follow the [current capture guide](../benchmark-validation.md),
and freeze identical instrument versions in both experiment worktrees. The
reader can run from a separate checkout, so it does not need to be copied into
or committed onto each measured candidate. For closed and pending studies, use
the [research decision map](research.md#performance-groundwork-decisions-already-made).

## Prepare the comparison before running it

1. Freeze the rule, full workload inventory, required metrics, and two exact Git
   revisions before reading measurements. The control must retain byte-identical
   benchmark instrumentation. Commit the control under a distinct SHA; a branch
   name or dirty worktree is not enough to identify the experiment.
2. Run native parity and the appropriate gate on the candidate. Keep setup inside
   end-to-end timing. Stage-only measurements explain a result; they do not replace
   it. Follow each PR's control-restoration instructions rather than comparing
   against an unrelated checkout of main.
3. Collect at least five complete adjacent pairs on one quiet physical Mac with
   the same toolchain, dependency lock, and allocator configuration. Run serially;
   alternate which arm goes first to expose order effects. Retain failed and noisy
   runs with their explanation. Do not silently remove an unfavorable pair.
4. Retain each entire capture directory, including `report.json` and `samples/`.
   Put their paths in a manifest. The expected workload list must be the full
   predeclared selection, including small-input and no-op controls.

The following is a **template**, not evidence. Replace the angle-bracket fields
and paths with the committed rule, actual inventory, and captures. Paths are
relative to the manifest. List pairs chronologically; either arm may start a pair.

```json
{
  "schema_version": 1,
  "experiment": "aski-87-prepared-footprint",
  "control_revision": "<full 40-character control SHA>",
  "candidate_revision": "<full 40-character candidate SHA>",
  "expected_workloads": ["<every selected workload ID>"],
  "required_metrics": ["wallClock", "mallocCountTotal"],
  "decision_rule": {
    "reference": "<committed rule path and SHA>",
    "declared_at": "<pre-run ISO-8601 timestamp with timezone>",
    "minimum_pairs": 5,
    "improvement_percent": 5,
    "regression_percent": 3
  },
  "host_attestation": {
    "label": "<stable local machine label>",
    "same_physical_host": true,
    "conditions": "<power, thermal and contention conditions; disclose deviations>"
  },
  "pairs": [
    {"control": "pair-1/control/report.json", "candidate": "pair-1/candidate/report.json"},
    {"control": "pair-2/control/report.json", "candidate": "pair-2/candidate/report.json"},
    {"control": "pair-3/control/report.json", "candidate": "pair-3/candidate/report.json"},
    {"control": "pair-4/control/report.json", "candidate": "pair-4/candidate/report.json"},
    {"control": "pair-5/control/report.json", "candidate": "pair-5/candidate/report.json"}
  ]
}
```

The 5%/3% bars above reflect the existing experiment proposals. They do not modify
the Swift benchmark thresholds. Every required metric applies to every selected
workload. Check their configured metrics before capture, and pass each requirement
as `--require-metric` to the capture command (`wallClock` is already required).
Split inventories with different available metrics into separate manifests.

The default workloads do not collect `cpuTotal`; require it only for workloads
configured to export it. Memory counters also differ: `allocatedResidentMemory`
may be unavailable on the active backend, and selected video/preparation workloads
collect `peakMemoryResidentDelta`. Neither is a substitute for a task's absolute
process peak-RSS requirement. If that measurement is needed, establish the same
measurement setup on both arms before capture; requiring a missing counter here
cannot collect it. Only lower-is-better cost metrics are compared. Throughput and
signed-delta metrics may be integrity-checked as optional exports, but are not
comparison requirements.

## Run and interpret

```bash
python3 -B Scripts/research/compare-benchmarks.py \
  --manifest ../evidence/pairs.json --output-dir ../evidence/comparison-01
```

The output directory must be new and its parent must exist. Omit `--output-dir`
for JSON on stdout. Files are `comparison.json` and `paired-medians.csv`.

| Exit | Meaning |
| --- | --- |
| `0` | Enough complete compatible pairs for a numerical readout; inspect noise, controls and native evidence. |
| `1` | Invalid evidence or manifest. Failed entries and reasons remain in the JSON; no partial aggregate is presented as a result. |
| `2` | Valid captures, but fewer than the required pairs. Descriptive values are retained with `insufficient_pairs`. |

For each workload and required metric, the reader reports each run's ordinary
median of the exported histogram values, each paired percentage/absolute change,
and the median, range and median absolute deviation across pairs. A positive
percentage means increased cost. A zero control produces an explicit undefined
percentage with an absolute delta; absence is never filled with zero. Histogram
rows are a quantized distribution, not independent chronological repetitions.
The exported-sample median is explicitly **not** a reproduction of the plugin's
HDR p50 rank/rounding operation, so it must not silently replace an existing p50
budget. Do not average unlike workloads into one universal speedup.

The reader rejects changed selections, missing required metrics, changed pins or
toolchain/backend identities, corrupt or stale samples, header/unit/count/hash
mismatches, reused reports, overlapping runs, and nonadjacent pairs. Units must
match across runs for each workload/metric; they are not silently converted.
The reviewed producer forces nanoseconds for time. Optional omissions remain
visible. `adoption_verdict` and `budget_verdict` always remain `not_evaluated`.

Do not copy numbers from `swift package benchmark baseline compare` markdown output
into a before/after table unchecked. With package-benchmark 1.35.0 it labeled some
millisecond tables as μs (a 24 ms to 5.2 ms wall-clock change printed as `24 → 5 (μs)`)
while other tables in the same report were labeled correctly, and `--time-units` did not
change it. Read the raw values from
`swift package benchmark baseline read <name> --format influx --path stdout` instead.
The value is the fifth field from the end of each row, and the `unit` column names its unit.

The original ASKI-86 captures do not record a physical host identifier, so they require the
explicit host attestation above. A later report may provide a consistent
`identity.host_id`; the reader labels which basis it used. Neither a handwritten
timestamp nor a host label independently proves preregistration or machine
identity. Check clean source trees, identical harnesses, and actual allocator
behavior separately. The upstream complete-row short-write limitation also
remains: a hash cannot recover sample rows that never reached disk.

## Current experiments and next actions

The earlier October work-order table is superseded by the
[research decision map](research.md#performance-groundwork-decisions-already-made).
ASKI-86–95 have recorded outcomes, including rejected candidates. Read the [current task](backlog.md) and the
linked study before starting another run. ASKI-5's representative budget selection
and gate placement remain separate work.

## Verification and sources

```bash
python3 -B -m unittest discover -s Scripts/tests -p 'test_benchmark_comparison.py' -v
```

These portable tests use explicitly synthetic captures. They do not establish
native speed, allocation reduction, rendering parity, or a passing `just check`.
The existing `just test-infra` discovery includes them; the full gate is unchanged.

The reader follows the producer's pinned package-benchmark 1.35.0 contract:
[histogram export](https://github.com/ordo-one/benchmark/blob/4b9ef5663e9c270419351a20392bf77b007f37f6/Plugins/BenchmarkTool/BenchmarkTool%2BExport.swift),
[metric normalization](https://github.com/ordo-one/benchmark/blob/4b9ef5663e9c270419351a20392bf77b007f37f6/Sources/Benchmark/BenchmarkResult.swift),
and [metric identities](https://github.com/ordo-one/benchmark/blob/4b9ef5663e9c270419351a20392bf77b007f37f6/Sources/Benchmark/BenchmarkMetric.swift).
Review those contracts again before accepting a dependency or export-schema change.
