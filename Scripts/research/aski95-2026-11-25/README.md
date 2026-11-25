# ASKI-95: fallback noise reuse rejected

A bounded reuse cache for the Core Image fallback's noise rasters kept output
byte-identical and made the 1920×1080 dust+grain same-seed render 78% faster.
It is still **rejected**: two changing-seed guard cases regressed by more than
the registered 2%. Production keeps building the raster on every application.
The [decision rule and analysis](../../../docs/Research/2026-11-25-aski95-fallback-noise-reuse.md)
were committed at `a06ef864e6ac4481c76987642c7eaebcc66b5a2a` before any timing.

## Files

| File | Contents |
| --- | --- |
| [ASKI95FallbackNoiseTimingTests.swift](ASKI95FallbackNoiseTimingTests.swift) | Harness: replica source and byte-equivalence checks, timing export, exact-output inventory export |
| [analyze.py](analyze.py) | R2 summary and ceiling test for one timing capture |
| [analyze_pairs.py](analyze_pairs.py) | R3 paired timing bars |
| [r2-timings.csv](r2-timings.csv), [r2-summary.csv](r2-summary.csv) | R2 control capture (15 timed repetitions per case) and its medians, quartiles and ranges |
| [r3-paired.csv](r3-paired.csv) | Per-pair and median changes for every case, with the bar applied |
| [parity-hashes.csv](parity-hashes.csv) | SHA-256 of 96 rendered outputs; control and candidate files are byte-identical |
| [candidate-treatment.patch](candidate-treatment.patch) | The rejected cache, its call sites and its unit tests |
| [provenance.json](provenance.json) | Commits, binary hashes, capture hashes and host facts |

## Replay

Run from a checkout of `4b3aa643bf9c895ed4e9688739b7c6a0b2f05ea5` on an Apple-family-6 Mac. Wrap each
command in the machine's gate lock if other work shares the host. Output paths
must be new absolute files. The harness lives here and is copied into the test
target only for the replay; delete the copy afterwards.

```bash
cp Scripts/research/aski95-2026-11-25/ASKI95FallbackNoiseTimingTests.swift Tests/AskiTests/
# Control: equivalence checks, exact outputs, one timing capture.
ASKI95_PARITY_OUTPUT="$out/parity-control.csv" ASKI95_TIMING_OUTPUT="$out/timings.csv" \
  xcrun swift test -c release --no-parallel --filter ASKI95FallbackNoiseTimingTests
python3 -B Scripts/research/aski95-2026-11-25/analyze.py "$out/timings.csv"
# Candidate in its own scratch directory.
git apply Scripts/research/aski95-2026-11-25/candidate-treatment.patch
ASKI95_PARITY_OUTPUT="$out/parity-candidate.csv" xcrun swift test -c release \
  --scratch-path .build/candidate --no-parallel --filter 'ASKI95FallbackNoiseTimingTests|FallbackNoiseCacheTests'
cmp "$out/parity-control.csv" "$out/parity-candidate.csv"
# Five pairs, C/T, T/C, C/T, T/C, C/T, without rebuilding either binary.
ASKI95_TIMING_OUTPUT="$out/pair1-C.csv" xcrun swift test -c release --skip-build --no-parallel --filter exportTimings
ASKI95_TIMING_OUTPUT="$out/pair1-T.csv" xcrun swift test -c release --skip-build --scratch-path .build/candidate --no-parallel --filter exportTimings
# ... pairs 2-5 in the registered order ...
python3 -B Scripts/research/aski95-2026-11-25/analyze_pairs.py "$out"
```

The control's `.build` binary must be built before the patch is applied;
`--skip-build` then runs it unchanged. Record both test-binary hashes before and
after the pairs. The release build has testability enabled because the harness
uses `@testable import Aski`.

## Disposition

AC1 and AC2 are satisfied by this packet and the note. AC3 to AC5 describe an
adopted implementation and stay unchecked. The candidate passed exact parity and
its bounded-memory unit tests, but it did not pass every timing bar, so it was
not adopted. The note lists instrument flaws that a follow-up study must fix.
