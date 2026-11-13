# ASKI-4 streaming GIF memory protocol

`protocol.json` freezes the fixture, five-pair ordering and numeric decision rule
before native execution. No capture or bounded-memory result is recorded here.
The lead must commit a verified snapshot before timed runs.

The benchmark opt-in is `ASKI_GIF_MEMORY_MATRIX=1`; select one exact workload at a
time with `just bench --filter '^gif-render-encode-incremental-240frames$'
--require-metric peakMemoryResident --require-metric mallocCountTotal` (shown over
two lines for readability). Repeat the protocol's modes/counts and pairing order
in isolated processes. Do not interpret build/harness RSS as benchmark-process RSS.

Pinned package-benchmark 1.35.0 uses `BenchmarkUnits.count` for unscaled non-time
metrics. Both exports explicitly use `.count`: malloc count is allocations; the
resident metric quantity is bytes. Validate actual raw export labels and scale
before comparing them. There is no `BenchmarkUnits.bytes` case in that API.

After a normal native test build, run the opt-in ownership probe with:

```bash
ASKI_GIF_PROVIDER_LIFETIME=1 ASKI_GIF_PROVIDER_REPORT=/tmp/aski4-provider-lifetime.json \
  xcrun swift test --skip-build --no-parallel --filter AskiGIFProviderLifetimeTests
```

Preserve that JSON with the source hashes and host metadata. The fixed 640×360
bitmap payloads use release callbacks to count actual live provider storage and
report every append plus pre/post-finalize stages. There is intentionally no
bounded-lifetime assertion before observation. Internal ImageIO copies are not
visible to callbacks; independently captured process RSS is required. The retained
1200-frame case can hold about 1.1 GB of source bitmap storage, so this probe is
opt-in and must run alone on the assigned native host.

Successful replacement, content/metadata and temporary cleanup are ordinary GIF
encoder regressions. Malformed-source coverage reaches the real decoder's
source rejection (cannotOpenSource or noFrames). It does not claim an after-first-frame decode error. The
ImageIO-finalize-false branch is inspected but not fault-injected; the short/excess
count tests do not exercise that branch. No artificial production seam is added.
