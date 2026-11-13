# ASKI-91 pulse reuse — adopted

The adopted arm computes the pulse multiplier once per invocation and reuses it
for each cell. It preserves Double arithmetic through the animated entrance/pulse
product and converts to Float at the existing boundary. The overlay reuses its
already-clamped Float multiplier. Storage is local and fixed in size; no cache
or public API was added. Wave, reveal and neutral paths keep their existing
evaluation.

All three primary overlay cases meet the frozen benefit rule, and all 93
regression guards pass:

| Overlay columns | Median paired wall change | Improving pairs |
| ---: | ---: | ---: |
| 80 | -34.56% | 5/5 |
| 192 | -43.65% | 5/5 |
| 288 | -47.77% | 5/5 |

These are synthetic overlay grids on one Mac. The 24-case instrument does not
directly time animated pulse frames; those have exact parity coverage only.
No universal or additive speedup follows from this result.

## Complete paired evidence

Five adjacent alternating pairs cover all 24 registered workloads and require
wall time, CPU, total malloc count and absolute process peak RSS. Two complete
preparations are excluded. Every capture is valid, with no retry, replacement
or omitted observation. The packet contains 960 raw histogram exports, six
observations per export, and 480 paired rows. The pair is the repetition unit;
within-capture observations are not independent chronological runs.

The [frozen rule](pre-registration.json) requires at least 5% median paired wall
improvement in every pulse primary, with at least four of five pairs improving.
A regression greater than 3% in at least four pairs vetoes adoption: 21 control
wall cells and 72 CPU/allocation/RSS cells are guarded. No decision ratio is
undefined in this study. The explicit zero-control CPU/allocation policy was
added before any native capture; positive-control bars remained unchanged.

Reproduce the retained numerical result from this directory:

```sh
python3 -B reproduce.py --output-dir /tmp/aski91-new-readout
```

Use a new output directory. The script checks raw hashes, units, sample counts,
canonical comparisons and exact rule identity before evaluating the decision.
[The summary](summary.json), [paired rows](paired-medians.csv) and [compact
median/range/MAD table](all-cells.csv) preserve every case. The lead independently
recomputed the rules and compact table from the retained pairs. The machine
summary leaves adoption and budgets unevaluated; this note records the separate
source/gate/adoption decision.

## Correctness and existing gates

Both exact arms passed the full local gate: 1,539 core tests, 177 media tests,
two deadlock sentinels, formatting, drift checks and DocC. Both also passed 39
targeted release tests across six suites. Coverage includes exact alpha/color/
brightness/coverage bits, glyphs, mask/composition metadata, ragged overlays,
concurrent calls, nonfinite time and aesthetic defaults, off-grid reveal, public
invalid-parameter exits, and a one-bit witness against premature Float rounding.

The initial release runs failed the same two neutral-overlay oracle assertions
in both arms: the expected expression preserved signaling-NaN bits while the
runtime multiplication quieted them. A private test-only unoptimized primitive
keeps the intended multiplication in the oracle. Every exact assertion remains;
production optimization was unchanged. Both original failures and the successful
repaired checks are retained in [native-checks.json](native-checks.json). The
[optional diagnostic patch](original-test-oracle.patch) restores the original
failing test oracle and is separate from the measured snapshots.

A separate compatibility capture passed all 16 shared animation/GIF/video
workloads. All four unchanged animation absolute budgets passed on the first
attempt. The other media cases are capture-validity checks, not numerical budget
passes. Before invocation, two names belonging only to the rejected ASKI-4 GIF
streaming experiment were excluded from the reference inventory; neither exists
in either ASKI-91 arm. The exact names and this inventory correction are retained.

## Source and limits

[Source replay metadata](source-replay.json) binds the control support and
candidate treatment patches. The repaired tests, instruments, protocol and pins
are identical between arms; their only differences are the three production
animation files. Local study commits identify provenance, without assuming their
availability from a public remote. [Provenance](provenance.json) retains frozen
source identities, commands, allocator observations and original evidence hashes.

The host was an M3 Max, macOS 27.0.1, Xcode 27 and Swift 6.4, on AC power. Desktop
and system activity continued; no competing batch native work or thermal warning
was recorded. This was not an idle-host study. Histogram values remain quantized;
sampled RSS can miss transient peaks.

Per-capture executable hashes were not recorded. The native evidence includes
on-disk executable/interposer hashes observed after the study and existing checks;
they do not prove the loaded bytes of every earlier process. Source, pins, build
commands and allocator observations are retained at their recorded stages. The
final integrated repository gate is recorded separately from these frozen-arm
measurements.
