# Supplemental GIF pipeline replay

This is the exact standalone source used for the ten real-pipeline observations
in [the supplemental packet](../supplemental-evidence.json). It uses public Aski
APIs. It does not establish a new acceptance rule or a memory bound.

First recreate the candidate in a separate checkout using
[the source replay patch](../source-replay.json). Then set `ASKI_REPO_PATH` to
that checkout and build this package in release mode. Verify the actual source
and executable hashes independently: the harness's emitted revision is an
**expected** identity, not a Git attestation.

```sh
ASKI_REPO_PATH=/absolute/path/to/replayed-candidate \
  xcrun swift build -c release --product gif-memory-harness
```

The resolved standalone lock retains only `swift-argument-parser`; its identity,
location, version and revision exactly match the candidate lock. SwiftPM pruned
unused development dependencies and changed the origin hash for this manifest.
The original copied lock is retained as `original-copied.Package.resolved`.

[The protocol](protocol.json) specifies source generation and all ten measured
argument lists. Resolve its placeholders to built binaries and a new output
directory. Generate the 240/1,200-frame source GIFs outside measurement and verify
them with `check-distinct.swift`. The recorded sources decode to exactly 240 and
1,200 distinct RGBA hashes. Preserve their checksums and reuse the same sources.

Run each resolved command once in a separate process under `/usr/bin/time -l`,
then run the harness's `inspect` mode outside measurement. On the recorded Darwin
host, `maximum resident set size` is **bytes**; the manual hashes and rationale
are in the protocol. This is whole-process RSS, unlike the benchmark's sampled
RSS or the lab's internal footprint metric. Do not apply Linux KiB scaling.

Validate every output's frame count, canvas, loop and delays, plus public encode
reports and lab cap/resample metadata. The 12-fps requests produce 116/576 frames
with 0.08-second GIF delays (12.5 achieved fps). Capping the 1,200-frame source at
240 produces 240 native frames or 116 resampled frames. The original lab YAML
records Git SHA `unknown` because execution used a scratch working directory;
the evidence retains that value and the independent executable/source hashes.

The observations are one run per row on the recorded Mac, with normal desktop
activity. They corroborate the failed memory result and do not provide a repeat
distribution or a comparison against the original shipping encoder.
