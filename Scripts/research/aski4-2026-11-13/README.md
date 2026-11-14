# ASKI-4: ImageIO incremental append fails bounded lifetime

The candidate removes the application's rendered-frame arrays and appends each
frame to one ImageIO destination. It is **not adopted**: the independent provider
probe shows that ImageIO keeps every original bitmap until finalization. Removing
the arrays does not satisfy this task's bounded-memory requirement.

The candidate passes its full local correctness gate, including 1,537 core tests,
186 media tests, two deadlock sentinels and DocC. Output ordering, metadata,
cancellation, count mismatch and owned temporary-output cleanup have regression
coverage. These checks do not establish bounded storage. ImageIO returning false
from finalization was inspected, not fault-injected.

## Original-provider lifetimes

Each provider owns a distinct immutable 640 × 360 RGBA8 bitmap, 921,600 bytes.
The callback releases its payload and updates a locked counter. The incremental
arm creates and appends one frame inside each autorelease pool, retaining no
frame array. Its observed live payloads immediately before finalization were:

| Frames appended | Live providers | Live original payload bytes |
| ---: | ---: | ---: |
| 24 | 24 | 22,118,400 |
| 240 | 240 | 221,184,000 |
| 1,200 | 1,200 | 1,105,920,000 |

All incremental providers released after `finish`. The retained control also
kept every provider alive, then released them after its array was removed.
These are actual provider-lifetime observations, not process RSS measurements.
Callbacks cannot reveal any additional internal ImageIO copies.

[Raw stage observations](provider-lifetime.json) preserve every append and the
finalization/release stages. [The summary](provider-summary.json) records each
case. The [frozen protocol](protocol.json) required both bounded provider lifetime
and a separate RSS growth check; the lifetime requirement already fails.

## Process RSS

All 30 registered captures completed validly: five alternating adjacent pairs
for each frame count, one observation per metric in each separate invocation,
with no retry or replacement. Both modes use the same candidate binary; retained
mode is the application-array control, not the original shipping encoder.

| Frames | Retained median RSS (bytes) | Incremental median RSS (bytes) |
| ---: | ---: | ---: |
| 24 | 54,755,327 | 54,624,255 |
| 240 | 333,447,167 | 332,136,447 |
| 1,200 | 1,570,766,847 | 1,560,281,087 |

The rendered primary frame is 480 × 240 pixels with 1,920 bytes per row:
460,800 bytes. The frozen allowance is therefore 16,777,216 bytes. Incremental
median RSS grows by **1,228,144,640 bytes** from 240 to 1,200 frames and fails the
rule. The retained control grows by 1,237,319,680 bytes, showing clear sensitivity.
The independent provider-lifetime requirement also fails.

[Raw observations](primary-observations.csv), [paired deltas](primary-paired-deltas.csv)
and [the readout](primary-summary.json) are reproducible from exact retained
histogram text in [the evidence packet](evidence.json):

```sh
python3 -B reproduce.py --output-dir /tmp/aski4-new-readout
```

Use a new output directory. The replay verifies source identity, workload,
chronology, metric units, one-sample counts and raw hashes. Time/CPU/allocation
deltas are descriptive. The benchmark executable hash is a point-in-time
attestation recorded after the first 240-frame pair; capture reports identify
the frozen source but do not contain individual executable hashes. The packet
preserves that limit. Sampled RSS can miss transient peaks. Desktop/system
activity continued, with no competing batch native work or thermal warning.

## Real conversion paths

All ten supplemental rows passed output frame-count, canvas, loop and delay
checks. Public encode reports and all six VideoLab cap/resample metadata records
also agree with the frozen fixture expectations. Both generated source GIFs have
the declared number of distinct decoded frames. Native public conversion used
339,017,728 bytes of whole-process maximum RSS at 240 frames and 1,577,140,224 at
1,200. Resampling the latter to 576 output frames used 798,064,640 bytes. These
single observations corroborate growth; they are not repeated speed comparisons.

[The supplemental packet](supplemental-evidence.json) retains exact time output,
commands, metadata, original hashes and source identities. A [compact table](supplemental-summary.csv)
and [standalone replay harness](harness/README.md) are included. VideoLab's YAML
records Git SHA `unknown` because its working directory was scratch; the binary
and source hashes independently bind the runs, and that original value is kept.
The lab's internal footprint and Darwin `time -l` whole-process RSS are separate
metrics. Source generation and output inspection were outside measured processes.

## Source and final gates

[Source replay metadata](source-replay.json) binds the candidate and the retained
[source patch](candidate-source.patch). Apply the patch to its stated base to
recreate production, tests and benchmarks; it excludes task and documentation
changes. The local study commit is provenance, not a promise of remote access.

The default `just bench` validity gate passed all 239 workloads with the large
memory opt-in unset. The separate absolute check passed all 11 unchanged
configured budgets: four animation, six effect-chain and one Helmlab. Its first
attempt failed during setup (`degenerateOutput`) and produced no numeric verdict.
The one corrected invocation used the repository's standard SwiftPM mode and
exact-name selector. Both corrections were applied together; the isolated cause
of the first failure is not proved. The failed attempt remains retained.

[Native checks and provenance](native-checks.json) bind these results, the full
correctness gate, final clean source and unchanged binaries. Existing warnings
are recorded. No threshold, pin, source or primary observation changed during
memory verification. ASKI-4 remains open for an approach that satisfies the
original memory requirement. No code from this failed candidate is adopted.
