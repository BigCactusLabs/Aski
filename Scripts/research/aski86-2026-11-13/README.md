# ASKI-86 native validity evidence — 2026-11-13

The canonical validator accepted a complete render capture and rejected genuine
native setup and execution errors even though the benchmark plugin returned zero.
A separate capture rejected the required but unavailable `allocatedResidentMemory`.
The in-process probe resolved the loaded malloc-interposer image and observed
positive allocation and free counters. The counts include incidental probe work;
they are not attribution to a single allocation or a resident-memory measurement.

`native-readout.json` retains selected workloads, plugin exits, native error causes,
metric units/counts/hashes, exact toolchain and dependency identities, and normalized
runtime observations. Absolute loaded-image paths are redacted. It is a compact
readout, not a self-contained input to the paired reader: the raw capture directories
and histogram files remain in the local run archive. Original reports predate the
normalized-identity repair; their raw observations were replayed through the final
parser. Native helper bytes did not change. This is validity evidence, not a speedup.

To repeat the failure check in a disposable checkout, apply `native-failure.patch`
to `Benchmarks/AskiBenchmarks/Benchmarks.swift`, then run:

```bash
just bench --filter '^(aski86-native-setup-failure|aski86-native-execution-failure|render-image-gradient-80cols)$'
```

Both temporary registrations read a path below `/dev/null`, which is a file,
through Foundation. They must fail with the native not-a-directory error and no
samples. The valid render must still export results, and the canonical command
must return nonzero. Restore the temporary registrations after capture. There is
no permanent fault switch. To repeat the unavailable-metric check on this backend:

```bash
just bench --filter '^render-image-gradient-80cols$' --require-metric allocatedResidentMemory
```

A later backend that actually provides that metric may pass. Missing required
samples must never pass or be filled with zero. Full integration checks are
recorded separately in the task and benchmark-validation guide.

Final acceptance: the unchanged source passed `just check` (1,537 core, 177 media, two sentinels and DocC), all 139 infrastructure tests (one existing expected failure), and the complete six-workload wall/malloc smoke. The readout retains these exits, source hashes and per-workload counts. Only evidence, changelog and completion metadata changed afterward.
