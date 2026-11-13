# ASKI-88 heap selection — rejected

The exact size-K heap candidate is **not adopted**. Four of eight registered
primary cases passed, and 17 of 148 regression guards failed (13 CPU and four
wall-time guards). The shipping
full-sort matcher remains unchanged. The result closes this bounded heap
investigation; it does not establish that another selection strategy cannot help.

| Primary workload | Median paired wall change | Improving pairs | Rule |
| --- | ---: | ---: | --- |
| convert-braille-120cols-k12-serial | -28.37% | 5/5 | pass |
| convert-braille-80cols-k12-serial | -25.40% | 5/5 | pass |
| convert-standard-120cols-k12-serial | +9.86% | 0/5 | fail |
| convert-standard-80cols-k12-serial | +10.80% | 0/5 | fail |
| ranked-braille-120cols-k12-serial | -27.77% | 5/5 | pass |
| ranked-braille-80cols-k12-serial | -26.09% | 5/5 | pass |
| ranked-standard-120cols-k12-serial | +8.23% | 0/5 | fail |
| ranked-standard-80cols-k12-serial | +7.12% | 0/5 | fail |

The rule required at least 5% lower median paired wall time in **every** primary,
with at least four of five pairs improving. Braille improved, but all four
standard-character primaries slowed in all five pairs. No result was pooled
across character sets and no bank-dependent production switch was introduced.

## Complete paired evidence

The study contains five adjacent, alternating pairs for all 42 workload names:
18 pool batches and 24 conversion/ranked-animation cases. Wall time, CPU, total
malloc count and process peak RSS were required throughout. All captures were
valid, with no retry or replacement. Two complete preparations are excluded.
The packet retains 1,680 raw histogram exports, five observations per export,
and 840 paired workload/metric rows. A pair is the chronological repetition
unit; the five within-capture observations are not five independent runs.

Run the [standalone reproducer](reproduce.py) from this directory:

```sh
python3 -B reproduce.py --output-dir /tmp/aski88-new-readout
```

Use a new output directory. The replay verifies raw hashes, units, sample counts,
canonical pair comparisons, exact rule identity and the declared numerical rule.
The [summary](summary.json) and [paired table](paired-medians.csv) retain all
outcomes. A [compact table](all-cells.csv) also gives each cell’s median, range
and median absolute deviation. The machine summary leaves adoption and existing budgets unevaluated;
this note records the lead's rejection separately.

Pool cases measure batches of 64 calls. The table includes per-call attribution
for time, CPU and allocations, while RSS remains the absolute whole-process
measurement. All selection scans and setup are inside the measured operation;
there is no constructor cache or persistent index. The pre-capture rule amendment
made zero-control CPU/allocation guard handling explicit and labeled those
batches; it did not change the positive-control bars. No undefined decision
percentage occurred in this completed study.

## Correctness, source and scope

Both exact arms passed the full local gate: 1,541 core tests, 177 media tests,
two deadlock sentinels, formatting, drift checks and DocC. Both also passed all
21 targeted parity tests in release mode. Candidate infrastructure checks passed
139 tests with one existing expected failure. Exact Float distances/index ties,
scored/ranked wrappers, real final cells, query polarity, edge emphasis, forced
serial/parallel walks and degenerate footprints were covered. No golden,
benchmark threshold, dependency or matcher policy was changed.

A separate seven-workload compatibility capture passed: both existing gradient
conversions, four animation cases and Helmlab-compressed. The five configured
animation/Helmlab absolute budgets passed on the first attempt. Gradient capture
validity is not a numerical budget result. [Native checks](native-checks.json)
retain commands, exits, tested snapshot records and original evidence hashes.

[Source replay metadata](source-replay.json) binds the scalar support and candidate
patches. They reconstruct the measured source and portable historical fixture
without adding the rejected heap as a production option. Local commits identify
the experiments; their presence on a public remote is not assumed. The
[pre-registration](pre-registration.json) and [provenance](provenance.json) retain
the exact rule, sources, excluded preparations, commands and original evidence hashes.

These are synthetic gradient and pool fixtures on one M3 Max, macOS 27.0.1,
Xcode 27 and Swift 6.4. Desktop/system activity continued; there was no competing
batch native job or recorded thermal warning. This was not an idle-host study.
Histogram values remain quantized, and sampled RSS can miss transient peaks.
No universal performance or visual-quality claim follows from this result.

The capture tools retained source, report and log hashes, not per-invocation
executable hashes. Frozen source identities and build commands do not constitute
a hash attestation of every earlier loaded executable. This limit does not
change the retained numerical rejection.
