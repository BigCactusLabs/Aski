# ASKI-88: exact brightness-pool selection groundwork

Prepared against PR #11 at `bbe65fa7ac7942449ce3b40f5df26c06143b32ca`.
Recovered files are committed at `dd9e8ab96322a765dc3ee21b2a82e3c5a2021a1f`;
verification below was repeated on 2026-10-27 rather than inferred from the
interrupted upload. Production source and existing benchmark budgets are unchanged.

## What must stay identical

[`ShapeMatching`](../../Sources/Aski/ShapeMatching.swift) sorts each candidate by
`abs(candidateBrightness[index] - queryBrightness)` computed in **Float**, then
original candidate index. Candidate arrays need not be sorted. Do not reorder a
glyph bank, widen the subtraction, change the brightness limit, or replace the
pool with an approximate nearest-neighbor result.

The tests include a concrete trap: with query `1`, brightness `0` and `2^-26`
have equal rounded Float distances. Float ordering therefore keeps index 0
first; Double subtraction would prefer index 1. Other cases cover duplicates,
midpoint neighbors, signed zero, finite subtraction overflow, every positive K
through N+1, immutable inputs, and concurrent calls. An independent rank-counting
oracle checks the full-sort control without using another sort implementation.

NaN is a separate policy problem. Apple's [sort contract](https://developer.apple.com/documentation/swift/array/sort(by:))
requires a strict weak ordering; the existing distance comparator does not provide
one for arbitrary NaN inputs. Both lab arms delegate to the unchanged full-sort
control when any input is nonfinite. Those tests check same-host delegation,
not a portable NaN ordering guarantee. No new input rejection is introduced.

## Two lab-only alternatives

[`SelectionArms.swift`](../../Scripts/research/brightness-pool/SelectionArms.swift)
is outside every production package target. The portable runner copies it into
an isolated package beside the extracted production pool method.

| Arm | Selection strategy | Worst-case work for K < N |
| --- | --- | --- |
| Control | Sort all N entries, return the first K | O(N log N) |
| Insertion | Keep a sorted K-entry buffer, discard worse entries | O(N K), including shifts |
| Heap | Keep the worst retained entry at the root, then sort retained K | O(N log K + K log K) |

Both alternatives reserve at most K entries, retain exact distance/index ties,
and use the old control when K >= N. Their O(N) finite-input scan is inside the
measured operation. Smaller asymptotic work is not an adoption result; shifting,
branches, full-pool dispatch and setup can outweigh it. Swift Collections'
[heap guide](https://github.com/apple/swift-collections/blob/main/Documentation/Heap.md)
is background, not a new dependency or evidence about Aski's actual speed.

## Run the portable experiment

Python 3.8+ and Swift 6.2+ can run this isolated diagnostic. The real Aski package
still requires Swift 6.3+ and Apple frameworks; this probe does not change that.

```bash
python3 -B Scripts/research/check-brightness-pool.py \
  --output-dir ../aski88-probe-01 --timing --passes 5 --iterations 500
python3 -B -m unittest discover -s Scripts/tests -p test_brightness_pool_probe.py -v
```

The output directory must be new and its parent must exist. The runner pins the
whole production file to Git blob `5c9d5882fc69b8ae242b4f608b4df5975d2cd8c5`,
extracts `poolIndices` unchanged, and removes only its unused `simd` import and
unrelated methods. It adds no substitute SIMD or Apple framework implementation.
It records source hashes, compiler identity, commands, return codes, a test log,
and optional timing CSV. Source drift fails instead of silently changing control.
The runner is a developer diagnostic, not the process-supervised ASKI-86 capture
validator; an abrupt process termination may leave its report incomplete.

Timing covers N=8/95/256; K=1/12/24/36/N/N+1; shuffled, ascending, descending and
all-equal inputs. Each pass rotates/reverses arm order and warms each arm.
Every output position contributes to a checked checksum. Wall and process CPU
include checksum work and call overhead. These are 72 synthetic configurations,
not 72 independent product workloads or chronological histogram samples.
Do not interpret this shared Linux host as an Apple performance or allocation test.

## Native instruments and remaining integration

The [inventory](../../Scripts/research/brightness-pool/workloads.json) freezes
**42 expected identities** from [benchmark registration](../../Benchmarks/AskiBenchmarks/BrightnessPoolGroundworkBenchmarks.swift):
18 pool batches plus 24 conversion/ranked-animation cases. The latter cover
standard/braille at 80/120 columns, serial/parallel walks, a wider K=36 arm, and
blocks controls. All request wall time, CPU, total malloc count and peak RSS.

Input images, converter construction and animation options are outside timing.
Conversion preparation inside `convert`/`animate` is included. Any future bank
index or constructor-time cache must therefore receive a separate setup-inclusive
measurement; this matrix cannot hide its cost. Peak RSS covers the whole child
process, including setup. These are gradient fixtures, not representative-photo
coverage. The instruments currently time the **unchanged production matcher**, not
the lab arms; a later candidate must wire its implementation into real callers.

[`BrightnessRankingContractTests`](../../Tests/AskiTests/BrightnessRankingContractTests.swift)
checks all best/ranked/scored wrappers, pool exclusion, ties, and residual bits
with exact small-integer descriptors. It is not a converted-grid or renderer test.
Before adoption add native descriptor/winner/residual/final-cell comparisons
against a frozen control, including forced serial/parallel conversion, both query
polarities, edge emphasis, and representative mixed-tone inputs. Keep the SIMD
reduction expression and accumulation order unchanged. Pool construction currently
appears separately in `findBestScored`, `findRanked` and `findRankedScored`; optimizing
only the research `poolIndices` entry point will not accelerate conversion.
`findBestScored` is `@inlinable`, so any shared internal helper must also satisfy
Swift's inlinable visibility rules without adding a public API just for the probe.

On the recorded Mac toolchain:

```bash
xcrun swift build --build-tests
xcrun swift test --skip-build --filter 'Brightness(Pool|Ranking)ContractTests'
just check
```

For a subsequent production candidate, keep a clean control at this groundwork
revision with identical instruments. Install and commit the same complete-capture
validator from [PR #7](https://github.com/BigCactusLabs/Aski/pull/7) in both measured
worktrees; record their final SHAs, lockfile, toolchain and allocator identity.
Run the validator with `--filter '^aski88-.*$'` and require `cpuTotal`,
`mallocCountTotal`, and `peakMemoryResident` as well as its mandatory wall time.
Require the complete 42-name inventory; retain failures and missing counters.
Use [paired readouts](paired-benchmarks.md), not pooled synthetic timing samples.

Proposed next-candidate rule, to freeze before native captures: at least five
complete alternating pairs on one quiet physical Mac; exact native parity; at
least 5% median paired wall improvement in each default-K standard/braille
serial conversion and ranked-animation case at 80/120 columns, with an improving
direction in at least 80% of pairs. Reject reproducible regressions above 3% in
small-bank/full-pool/parallel controls or CPU/allocation/RSS costs across the matrix.
Here reproducible means at least 80% of paired deltas exceed the bar. Ambiguous
results remain inconclusive; do not loosen existing benchmark budgets. A constructor
cache requires setup-inclusive evidence before this rule can promote it.

## Repeated verification and status

Linux x86_64, Swift 6.2.1, Python 3.13.5:

- 12 Swift Testing functions passed in release mode, representing 18 concrete
  executions across two suites, with complete strict concurrency and warnings-as-errors.
- Eight Python runner tests passed. Mocked compiler calls in those tests are
  failure-path fixtures, not native Swift evidence.
- Five diagnostic timing passes completed: 1,080 rows / 360 three-arm groups,
  with matching checksums throughout. No Aski end-to-end speedup is claimed.
- All seven changed Swift files passed strict format lint with the repository
  configuration and syntax parsing; recovered file bytes match their Git blob IDs.
- The manifest has 42 unique IDs; removing the single new registration restores
  the base registry byte-for-byte. Python 3.8 grammar parsing passed.

The native ranking tests, 42 benchmarks, Apple build, real allocation/RSS
measurement, and converted-grid parity remain **unverified**. `just check` was
attempted and exited 127 because `just` is unavailable; Xcode/Apple frameworks
are absent too. Only the focused Python suite ran, not all infrastructure tests.
Backlog files are untouched because the required CLI is unavailable. ASKI-88 is
not closed, and neither experimental arm is adopted in production.
