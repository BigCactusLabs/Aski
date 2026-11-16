# ASKI-94: single original-image draw rejected

The one-draw candidate changed native pixels in **239 of 1,161 cases** and is
rejected. Production keeps the per-cell renderer. The
[decision rule](../../../docs/Research/2026-11-15-aski94-completed-original-fallback.md)
was committed before measurements at
`e44962a2e00bb1b0b63bf8a0d2f276d1bed30e18`. No tolerance, golden or benchmark
threshold changed.

## Exact parity

Both control release exports passed and matched all 1,161 cases. The candidate
export also passed; its comparator returned the registered mismatch exit 1.
All 239 differences are active pixel bytes, with identical native metadata.
All use partial ground; 119 are ragged and 120 rectangular. Fill, fit and stretch
have 80, 79 and 80 differences. The first differing byte in the first reported
case is 52 versus 53, at row 39, column 19, component byte 0.

[All mismatches](parity-mismatches.json) retain the exact first difference and
both raster hashes. [All-case inventory](parity-cases.csv) retains dimensions,
the three raster hashes, and metadata/pixel equality for all 1,161 cases.
[Grouped counts](parity-groups.json) describe marginal counts of the same cases;
they must not be added as separate failures. Native raster bytes and full logs
remain in the local study archive. Geometric clip equivalence did not establish
pixel equivalence on this host. The result does not establish the internal
Core Graphics cause.

## Control baseline

[The baseline](control-baseline.csv) has all 27 workloads and 108 valid metric
exports: wall time, CPU time, allocation calls and sampled process peak RSS.
It is one descriptive control capture. There is no candidate speedup, paired
no-harm result or mask/render compatibility result: the parity veto prevented
those measurements.

Time is in ns. The raw `#` units mean allocation calls and resident bytes for
their respective metrics. CSV values are medians of exported histogram samples,
not independent repeated captures or the plugin's HDR p50 budget statistic.
[The report](baseline-report.json) retains the validator result and allocator
identity with host paths normalized. [Sample exports](baseline-samples.json)
preserve all 108 TSV strings byte-for-byte, keyed by their report paths.

The draw census is source-derived, as registered before capture. Grounded
80/160/320-column controls call the source-image draw 1,600/6,400/25,600 times;
overlays call it 1,200/4,800/19,200 times. Other fallbacks call it zero times.
This counts source invocations, not executed traces or full-source raster work.
The rejected candidate would call it once in each nonempty grounded case.

This capture used arm64 macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Swift 6.4
and the reviewed native malloc interposer. Source provenance and positive runtime
allocator observations passed. AC power, 100% battery and nominal thermal state
were observed before and after the baseline, with no unrelated native jobs in
those observations. This is not continuous host telemetry. Sampled RSS includes
process residency outside rendering and can miss transient peaks.

## Replay and disposition

In an isolated checkout of the registration commit, apply
[candidate-treatment.patch](candidate-treatment.patch) to reconstruct the rejected
source. The patch changes only the completed original-image path. The existing
variable-coverage loop and non-image fallback arms remain byte-identical.
Run the exporter/comparator commands in the decision rule with fresh directories.
The native output is host/toolchain-specific; cross-OS pixel parity is not claimed.
[Provenance](provenance.json) binds the source, binary, manifest, native logs,
original report and portable artifact hashes.

ASKI-94 closes through its explicit rejection route. AC1 records the control
matrix and source-derived draw census; AC5 records the rejection. AC2–4 remain
unchecked: the candidate was not adopted, exact parity failed, and comparative
regression measurements did not run. The experiment adds no production option.
