# Compare repeated benchmark captures

`Scripts/research/compare-benchmarks.py` reads complete ASKI-86 captures and produces
a per-workload comparison across repeated control/candidate pairs. It runs with
Python 3.8+ and the standard library; it does not build or run Aski. This is
groundwork for ASKI-5 and the open performance experiments, not a new budget gate.

The capture producer is in [PR #7](https://github.com/BigCactusLabs/Aski/pull/7).
Use its [capture guide](https://github.com/BigCactusLabs/Aski/blob/5493edb992ab57ee2c4a5e16e9ef8106068ab96e/docs/benchmark-validation.md)
on the experiment worktrees. This reader can run from a separate checkout, so it
does not need to be copied into or committed onto each measured candidate.

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
  "required_metrics": ["wallClock", "cpuTotal", "mallocCountTotal"],
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
the Swift benchmark thresholds. Add `peakMemoryResident` for experiments requiring
RSS; requiring it here cannot make a capture that omitted the counter valid.
Only lower-is-better cost metrics are compared. Throughput and signed-delta metrics
may be integrity-checked as optional exports, but are not comparison requirements.

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

PR #7 does not record a physical host identifier, so its captures require the
explicit host attestation above. A later report may provide a consistent
`identity.host_id`; the reader labels which basis it used. Neither a handwritten
timestamp nor a host label independently proves preregistration or machine
identity. Check clean source trees, identical harnesses, and actual allocator
behavior separately. The upstream complete-row short-write limitation also
remains: a hash cannot recover sample rows that never reached disk.

## Current experiments and next actions

Status checked on 2026-10-27. Existing PR descriptions contain the detailed rules.

| Task | Existing work | Next acceptance work |
| --- | --- | --- |
| ASKI-86 | [PR #7](https://github.com/BigCactusLabs/Aski/pull/7), complete-capture validator | Genuine native setup/execution failure probe and allocator provenance review. |
| ASKI-87 | [PR #8](https://github.com/BigCactusLabs/Aski/pull/8), reported native parity | Five pairs of all 52 workloads, including eager setup and small/dotMatrix controls. |
| ASKI-90 | [PR #9](https://github.com/BigCactusLabs/Aski/pull/9), reported native parity | Add the missing standalone setup measurement/profile; compare all 70 end-to-end workloads. |
| ASKI-92 | [PR #10](https://github.com/BigCactusLabs/Aski/pull/10), candidate awaiting native checks | Native palette/tile parity, then 66 end-to-end workloads and the separate 120 phase probes; measure sample-buffer/Wu-table lifetime overlap. |
| ASKI-93 | [Frame-selection contract](../../Scripts/research/video-frame-selection.md) | Run the synthetic matrix, then move conversion behind selection with native identity/pixel/cancellation and occupancy evidence. |

None of those performance tasks is completed by this readout tool. ASKI-5's
representative budget selection and gate placement remain separate work.

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
