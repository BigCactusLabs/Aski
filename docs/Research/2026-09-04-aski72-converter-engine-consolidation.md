---
title: "ASKI-72 converter-engine consolidation"
slug: 2026-09-04-aski72-converter-engine-consolidation
date: 2026-09-04
status: complete
subsystem: [shape-context, meta]
summary: "The ordinary, ranked, and residual conversion surfaces now share one statically specialized row-walk engine. Frozen output fingerprints are unchanged, the fixed production scope falls by 62 lines, plain-path allocation count is unchanged, and representative release timings are neutral or better. This is a maintenance result, not a descriptor-speed claim."
related_specs: [docs/architecture.md, docs/Research/2026-09-03-future-direction-and-architecture.md, docs/Research/2026-09-04-aski68-production-experiment-cleanup.md]
next_action: "Keep temporal conversion separate. Extend the ordinary engine only with a concrete capture that has measured neutral-or-better cost and no per-cell existential dispatch."
---

# ASKI-72 converter-engine consolidation

## Result

The ordinary, ranked, and residual surfaces dispatch once per conversion into
one generic row walk. Concrete captures retain only the state used by their
surface. Dot-matrix keeps its ordered Floyd-Steinberg state on a forced-serial
walk and handles ranked singleton and residual `NaN` output explicitly.
Temporal conversion remains separate.

The fixed production scope is 962 lines, down from 1,024 at `45f687b` (62
lines removed). The removed `AlgorithmKernel` existential made dot-matrix
pretend to support log-polar ranking and residual semantics. The replacement
has one real common scoring capability and surface-specific concrete captures.

## Frozen output contract

Before production edits, 16 named conversion fingerprints were recorded from
the untouched `45f687b` code and record mode was removed. Each test run repeats
the complete matrix twice. It covers:

- log-polar plain, ranked, and residual output in serial and parallel modes;
- dot-matrix plain, ranked singleton, padded stride-one and stride-six, and
  residual-`NaN` output, including a forced-parallel request that stays serial;
- masked plain/ranked output, invalid columns, failed preparation, repeated
  determinism, and grid plus auxiliary-buffer bytes.

The same constants pass after the consolidation. Existing golden, mask,
ranked, residual, parallel-parity, and temporal tests remain authoritative.

## Performance method

Measured 2026-09-04 on an otherwise idle 14-core Apple M3 Max host with Apple
Swift 6.3.2. The before binary was built while `git diff -- Sources` was empty
at exact base `45f687bd0f1afbdc58fa8a4249ca512f395d7545`. The final candidate
binary was built at 2026-09-04T06:33:39-0400, after the production sources, and
had SHA-256
`e93516a93a82e1e1846d2f31519ba2da695e212727737a8ae33b3469b1ce6dda`.
The candidate `ASCIIConverter.swift` and `ConversionEngine.swift` SHA-256
values were `e4956da3a0ffffc6db54303d9f10a06c2e2fd94c27ad872736965c8629b65572`
and `e39ace08ba2fdf8910ecaf9b4d45fa1b217db66a4776067181f01ae2759f3f9c`.

Each case had three warmups and 20 measured samples. The table reports
nearest-rank `p50 / p90` for wall time, total process CPU time, and calls to
`malloc` while the conversion body ran.

The temporary test-only probe loaded package-benchmark's malloc interposer and
reset its counters around each conversion. The selected toolchain's `swift`
executable was invoked directly because the platform `xcrun` launcher removes
`DYLD_INSERT_LIBRARIES`; no global environment or Git configuration changed.
The exact launch shape was:

```bash
env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository \
  GIT_CONFIG_VALUE_0=all ASKI_RECORD_ENGINE_BASELINE=1 \
  DYLD_INSERT_LIBRARIES="$PWD/.build/arm64-apple-macosx/release/libMallocInterposerSwift.dylib" \
  "$(xcrun -f swift)" test -c release --disable-sandbox --skip-build \
  --filter ConverterEngineBaselineProbeTests
```

One final-candidate launch exited 139 before the test emitted output. It was
rejected as an interposer-launch failure. The immediate identical retry ran all
80 measured conversions and passed; only that complete run appears below.

| Case | Before wall (µs) | After wall (µs) | Before CPU (µs) | After CPU (µs) | Before malloc | After malloc |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| plain log-polar, auto, 800×600, 80 columns | 4,643 / 4,891 | 4,757 / 4,990 | 11,696 / 12,164 | 10,681 / 11,618 | 15,831 / 15,831 | 15,831 / 15,831 |
| ranked log-polar, auto, stride 6 | 4,867 / 5,050 | 4,894 / 5,174 | 12,918 / 13,286 | 12,034 / 12,568 | 20,153 / 20,153 | 20,153 / 20,153 |
| residual log-polar, auto | 4,765 / 4,952 | 4,718 / 4,871 | 11,691 / 12,046 | 11,385 / 11,813 | 15,832 / 15,832 | 15,832 / 15,832 |
| plain dot-matrix, forced serial | 4,364 / 4,534 | 4,442 / 4,586 | 4,350 / 4,530 | 4,439 / 4,570 | 763 / 763 | 763 / 763 |

All four cases have exact allocation-count parity. Every wall-time percentile
is within 2.5% of the untouched run, while residual wall time improves and
log-polar CPU time improves by 1.9% to 8.7%. Dot-matrix CPU time remains within
2.1%. No benchmark threshold moved.

This is maintenance evidence, not a descriptor-speed claim. Frozen output and
parity tests determine correctness; these timings only reject a new hot-path
tax.
