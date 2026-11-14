# ASKI-92: shared tile-color samples rejected

The complete fresh study rejects adoption. **19 of 32 primary cases pass** the
frozen benefit rule; **154 of 160 regression guards pass**. All six failed guards
are small-input wall time. Every allocation-count and RSS guard passes. The
shared-sample candidate is not integrated into production. The separate allocator
classifier correction is retained and qualified.

The [numerical verdict](numerical-verdict.json) stays `not_supported`.
[Adoption](adoption.json) records rejection without an exception. AC4 is complete
through its explicit rejection route. AC3 remains unchecked because the small-input
regression condition is not met; the task is closed as rejected, not implemented.

## Frozen comparison

[The rule](pre-registration.json) was declared before the fresh captures. It keeps
five alternating pairs, all 66 end-to-end workloads and four required metrics.
Each primary requires at least 5% lower median paired wall time and improvement
in at least four of five pairs. A guard fails if cost rises more than 3% in at
least four pairs. No threshold changed and no failed observation was substituted.
Two valid preparation captures are excluded from the comparison.

All 32 primary median changes are negative, but 13 fail the required size or
consistency of benefit. The failing wall-time guards are all 16×16 inputs:

| Space / alpha / palette | Median paired change | Pairs above 3% |
| --- | ---: | ---: |
| sRGB / opaque / 8 | +9.82% | 4/5 |
| sRGB / opaque / 64 | +8.89% | 4/5 |
| sRGB / mixed / 8 | +7.57% | 4/5 |
| sRGB / mixed / 256 | +4.12% | 4/5 |
| P3 / opaque / 64 | +4.76% | 4/5 |
| P3 / mixed / 8 | +14.18% | 4/5 |

[Paired medians](comparison/paired-medians.csv) retain all 1,320 comparison rows.
[The canonical readout](comparison/comparison.json) validates five complete pairs,
compatible instrumentation identity, all sample hashes, units and counts. CPU
results are descriptive unless named by the rule; no extra adoption bar is inferred.

## Allocation lifetimes

Four separate native profiles completed normally on the same release binaries
used for capture. Each profile covers one warmup and six iterations of the
sRGB opaque, 16-color workload at the registered lattice size.

| Input | Control peak live requested bytes | Candidate | Change |
| --- | ---: | ---: | ---: |
| 160×160 | 1,008,748 | 1,418,396 | +40.61% |
| 512×512 | 8,389,984 | 5,203,100 | −37.98% |

These are **tracked algorithm array allocations**, including native interposer
and Swift array headers. They are not process RSS or mapped capacity. The scope
includes samples, Wu tables/split arrays and k-means working arrays. It excludes
common input/output buffers, runtime metadata, framework caches and VM.

The candidate sample array is half the size, but it is live with all seven Wu
tables. Control samples start after those tables are freed. The actual ordered
allocation/free intervals establish this overlap; a stride calculation alone
would not. Every tracked buffer has a matching free and no tracked storage
crosses conversion boundaries. Each arm has seven sample allocations and 49 Wu
table allocations per profile.

`MallocStackLoggingNoCompact=1` and `malloc_history -allEvents -fullStacks
-noContent` provide ordered events with source stacks. LLDB pauses the unchanged
executable at normal exit to export them, then resumes to exit zero. There are
**no clock timestamps**, so these records support overlap and peak-live totals,
not lifetime durations. Debugging and stack logging are absent from timed pairs.
The full native event histories and full parsed selections remain in the local
archive. [The portable profiles](allocation-profiles.json) retain the tracked
array intervals, deduplicated allocation/free stacks, source event/line ordinals,
raw-history hashes, binary hashes and matching dSYM UUIDs. Their selection and
peak calculations are implemented in [the analyzer](analyze-lifetimes.py).

## Checks and provenance

- Both frozen arms passed full `just check`: control 1,539 core tests; candidate
  1,549 including ten parity/storage tests; each also passed 178 media tests,
  two isolated sentinels and DocC. Exact palette/order and final tile parity passed.
- The separate candidate phase run completed all 120 workloads with four metrics.
  It is descriptive attribution, not another control comparison.
- All 27 existing tile/color workloads validated. The unchanged Helmlab absolute
  budget returned `EQUAL`.
- [The classifier qualification](../aski92-2026-11-13/classifier-correction/qualification.json)
  passed the native vendor suite, 122 portable validator tests (one expected
  failure), full integration gate, 237 benchmark workloads and 11 unchanged
  absolute budgets. Cross-family review was unavailable; the lead reviewed the
  source and evidence. No independent-review claim is made.
- [Frozen identities](frozen-identities.json) bind both arm commits and common
  instrument hashes. [Provenance](provenance.json) records command/log hashes and
  checks that source stayed clean and endpoint binary/dylib hashes still matched
  the profiles after the paired, phase and compatibility runs. This is endpoint
  evidence, not continuous in-memory authentication.

This is one M3 Max on macOS 27.0.1, Xcode 27 and Swift 6.4. Native jobs were
serialized, but normal desktop/system activity continued; this was not a quiet
host. No thermal warning was recorded. Histogram exports are quantized
distributions; each pair, not each histogram value, is the repetition unit.
Absolute RSS includes process startup. Candidate-only phase registration exists
in the candidate executable; its fixtures are lazy and end-to-end bodies match.
These results support this frozen decision, not a universal hardware claim.

The [earlier failed attempts](../aski92-2026-11-13/README.md) remain invalid and
separate. The proven classifier read fault is corrected. The historical reset
and CoreGraphics crash causes remain unproved; this successful study does not
retroactively diagnose them. No old measurement is pooled into this study.

## Portable verification and source replay

From the repository root, run:

```sh
python3 -B Scripts/research/aski92-2026-11-14/reproduce.py
```

This runs no native benchmarks. It reconstructs 3,703 retained histogram exports,
checks hashes and counts, uses the existing canonical paired reader, reproduces
all paired statistics/CSV and the frozen numerical verdict, recomputes the four
profile lifetime results, verifies address reuse/free matching, and applies both
source replay patches in a disposable directory. It compares all declared source
files against their SHA-256 inventories.

Capture reports are normalized to remove host-specific paths. Their original
native hashes remain in provenance, and the original comparison refers to those
hashes. Reproduction compares the numerical fields rather than asserting that a
normalized report has its original hash. Histogram strings are byte-preserved.
[Artifact hashes](artifact-hashes.json) cover the portable packet.

[Source replay](source-replay.json) starts at the retained classifier-fix commit
`4530b1a0afea94a20a8cffd6596a5b42b67f5229`. Apply `control-source.patch`, then
`candidate-treatment.patch` for the candidate. The patches reconstruct the listed
compilation/resources/test/runner inputs, not full repository documentation or
commit metadata. The first patch removes later unrelated batch features from
the base to recover the frozen experiment. Apply it only to an isolated replay.
Local study SHAs identify provenance; public availability of those study commits
is not assumed. No rejected production option is added by this evidence packet.
