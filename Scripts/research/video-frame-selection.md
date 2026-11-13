# ASKI-93: select frames before paying for conversion

Candidate initially prepared on 2026-10-27, stacked on the contracts in
[PR #11](https://github.com/BigCactusLabs/Aski/pull/11),
`bbe65fa7ac7942449ce3b40f5df26c06143b32ca`. The control production code matches
`main` at `4c675957547cb0dffdcce886a073bd2f340a5d26`.

The candidate implements early selection for `convertVideo(targetFPS: ...)`.
Native verification was reported at `b83d74f265444bf2b659002eea84caf7c2e183bf`
on 2026-11-10, including real-MP4 parity and lifetime tests. That evidence does not
establish performance or acceptance on a later integration. The bounded replay
below was registered on 2026-11-12 before reading native benchmark results.

## The boundary to preserve

The frozen [`convertVideo`](../../Sources/Aski/Video/ASCIIVideoConverter.swift) control asks
`pipelinedGrids` to convert each source image, then applies
[`resampledVideoFrames`](../../Sources/Aski/Video/FrameResampler.swift). The generic
[`ResampleSession`](../../Sources/Aski/Video/ResampleSession.swift) chooses the last
frame assigned to each output slot, holds a frame across gaps, and retimes video
output to `CMTime(value: slot, timescale: targetFPS)`. The candidate moves ASCII
conversion after that same actor. It does not introduce a second selection policy.

[`VideoFrameSelectionContractTests`](../../Tests/AskiTests/VideoFrameSelectionContractTests.swift)
feeds single-cell identity markers through the real public video operator and its
generic session. The shared
[`VideoFrameSelectionFixtures`](../../Tests/AskiTests/VideoFrameSelectionFixtures.swift)
also drive the Foundation-only core suite and the candidate's conversion-count
suite. Pull-based sources record reads as well as returned frames. Expectations
are literals, not outputs from a second selector.

| Fixture | Source frames supplied | Frames pulled by selector | Output | Dropped | Duplicated |
| --- | ---: | ---: | ---: | ---: | ---: |
| 60 → 12 fps, one second | 60 | 59 | 12 | 46 | 0 |
| 30 → 12 fps, one second | 30 | 30 | 12 | 17 | 0 |
| Variable rate: 0, 10, 60, 400, 410, 900 ms | 6 | 6 | 12 | 2 | 8 |
| 2 → 4 fps, 1.5 seconds | 3 | 3 | 6 | 0 | 3 |
| 12 → 12 fps, half a second | 6 | 6 | 6 | 0 | 0 |
| 20-second source origin, 30 → 12 fps | 6 | 6 | 3 | 3 | 0 |
| Exact half-slot ties | 5 | 5 | 4 | 0 | 0 |
| Last frame held to declared duration | 2 | 2 | 3 | 0 | 1 |
| One frame, declared duration zero | 1 | 1 | 1 | 0 | 0 |
| Empty source, declared duration one second | 0 | 0 | 0 | 0 | 0 |

At 60 → 12, output
identities are `2, 7, 12, 17, 22, 27, 32, 37, 42, 47, 52, 57`. Identity 58 is pulled
as lookahead but never selected; identity 59 is never pulled by this session.
Consequently, `sourceFrameCount` is not the file's frame count, and
`droppedCount + distinct selected frames` need not equal it. The existing
[`VideoFramePrefetchPump`](../../Sources/Aski/Video/ASCIIVideoDecoder.swift) can also
pull one frame beyond the selector's requests. Instrument decoder, converter, and
selector counts separately; do not call this table a measurement of conversion
calls in the control export pipeline.

## Candidate and ownership

| Stage | Control | Candidate |
| --- | --- | --- |
| Decode, materialize CGImage, orient | Every pulled source | Every pulled source, same code |
| ASCII conversion | Before selection | Only a newly selected source identity |
| Selection and CFR stamping | `ResampleSession<ASCIIVideoFrame>` | Same policy over `DecodedVideoFrame` |
| One-frame prefetch | Before selection | After selection and conversion |
| Pattern, effects, render, encode | Output timestamp | Same output timestamp and render path |

[`VideoFrameSelectionPump`](../../Sources/Aski/Video/VideoFrameSelectionPump.swift)
caches one `(sourceID, ASCIIGrid)` pair. An ordinal identifies a source independently
of its PTS; equal timestamps do not accidentally collapse different source images.
Duplicates reuse the unpatterned grid. There is no image cache or clip-wide map.
Conversion remains synchronous and serial on a dedicated dispatch executor. The
new actor boundary still changes scheduling, which belongs in the measurements.

The public `grids` and `pipelinedGrids` APIs still invoke their arbitrary caller
transform for every yielded source, on the decoder's executor. `targetFPS == nil`
still uses `pipelinedGrids`. Splitting its internal decode helper adds a carrier
and ordinal, so the no-resampling benchmark remains a required regression control.
No public API, deployment floor, GIF behavior or shared selector policy changes.

Raw pixel-buffer access and reader state remain isolated to `DecodeSession`.
Only immutable `CGImage`, `CMTime` and an integer identity cross to selection;
no unchecked sendability is added. Apple's
[`VTCreateCGImageFromCVPixelBuffer`](https://developer.apple.com/documentation/videotoolbox/vtcreatecgimagefromcvpixelbuffer(_:options:imageout:))
may retain the source pixel buffer for the image's lifetime. Its storage therefore
can outlive the decode call. No code mutates that storage after image creation;
this also preserves the contract of
[`alwaysCopiesSampleData = false`](https://developer.apple.com/documentation/avfoundation/avassetreaderoutput/alwayscopiessampledata).

The persistent selection window is two oriented images: held source and lookahead.
The one-grid prefetch adds no third decoded image. Across the pump's cache and a
consumer processing one output at a time, up to two distinct converted grids may
be live. Orientation can temporarily retain both an original and an oriented
image; conversion, rendering and encoding allocate more storage. The old blanket
two-frame claim is not an aggregate memory bound for this pipeline.

This can **increase RSS** even while avoiding conversion work: the old selector
held small grids. The new lifetime tests count synthetic image-provider storage,
not codec buffers or native process RSS. EOS, failure and observed cancellation
clear the selection actor and grid cache. Consumer release must also cancel a
suspended output prefetch through the existing pump ownership chain.

## Regression coverage

- [`VideoFrameSelectionCoreTests`](../../Tests/AskiTests/VideoFrameSelectionCoreTests.swift)
  runs the actual Foundation-only selection actor over the ten shared fixtures,
  plus the 120 → 12 and ten-second benchmark count guards.
- [`VideoEarlySelectionTests`](../../Tests/AskiTests/VideoEarlySelectionTests.swift)
  checks exact selected conversion identities, duplicate reuse, CFR times, all
  report counts, source pulls, output-time patterns, invalid preflight, propagated
  lookahead failure, cancellation and one-output-ahead prefetch. The 60 → 12 case
  requires 12 conversions for 59 selector pulls; 2 → 4 requires 3 for 6 outputs.
  These candidate conversion counts are assertions awaiting native execution.
- [`VideoEarlySelectionIntegrationTests`](../../Tests/AskiTests/VideoEarlySelectionIntegrationTests.swift)
  compares the retained convert-then-select pipeline with the candidate over real
  MP4s: lower/equal/higher rates, VFR, 90°/270° transforms and mirroring. It checks
  cells, CFR times, four stats, conversion counts and complete rendered RGBA bytes
  before another lossy encode. Public callback counts and encoder failure have
  separate checks. Existing round-trip tests exercise `convertVideo` itself.
- [`VideoSelectionLifetimeTests`](../../Tests/AskiTests/VideoSelectionLifetimeTests.swift)
  checks lazy image storage and cleanup without retaining an array of inputs.
  Existing [`VideoPipelineTests`](../../Tests/AskiTests/VideoPipelineTests.swift)
  continue to cover the unchanged prefetch implementation.

## Frozen measurement plan

[`VideoSelectionBenchmarks`](../../Benchmarks/AskiBenchmarks/VideoSelectionBenchmarks.swift)
registers nine end-to-end workloads, all at 720p and 80 columns. Each workload ID
has the prefix `aski93-video-` and suffix `-720p-80cols`:

| Middle of workload ID | Purpose |
| --- | --- |
| `source-30fps` | `targetFPS == nil` regression control |
| `60to12` | Primary rate-reduction case |
| `120to12` | Primary high-rate case |
| `30to12` | Primary modest-rate case |
| `12to12` | Unchanged-rate selection overhead |
| `12to30` | Duplicate-grid reuse |
| `vfrto12` | Literal collisions and gaps |
| `60to12-rotated` | Orientation remains unchanged |
| `60to12-10s` | Longer duration and memory diagnostic |

These are instruments, not new regression thresholds. They request wall time,
CPU, total malloc count and absolute peak resident memory. Source preparation and
verification are outside timed work; each timed iteration includes converter
construction, decode, selection, conversion, rendering and encoding. Output
inspection is outside timing. Peak RSS covers the whole process, including setup,
warmup and output inspection; it is not an isolated-stage allocation measurement.

Source generation draws and appends one pixel buffer at a time. A shared
`ASKI93_FIXTURE_ROOT` retains MP4s and SHA-256 files, verifies duration, dimensions,
orientation and every PTS, and prints the source hash. Populate all sources in a
preparation run **before** recorded captures. Every retained run must report
`created=false` and the same source hashes in both arms. Run serially against that
cache; do not treat source creation in one arm as comparable process-RSS evidence.

### Prepare clean, comparable revisions

For the 2026-11-12 replay, start both arms from current `main` at
`c81861cb3960de91c2bd4ad90087eec51027b3f1`. The candidate integrates this PR; the
control adds only its benchmark file, registration and this protocol. Commit both
before capturing. Do not copy tests that require candidate-only types into the
control. Keep all other production sources identical, including the already
merged preparation/orientation fixes. Both arms run the same public `convertVideo`
calls; the older serial pipeline benchmark is a different comparison because it
also removes prefetch.

Use the merged [`Scripts/validate-benchmarks.py`](../validate-benchmarks.py),
byte-identical in both arms. Record the final clean control/candidate SHAs, matching
benchmark and validator hashes, dependency lock, toolchain and host conditions.
The pair manifest must name those measured commits, not this preparation base.

With the same absolute fixture-cache path in both shells, use a new output
directory for every invocation:

```bash
python3 -B Scripts/validate-benchmarks.py \
  --filter '^aski93-video-.*$' \
  --require-metric cpuTotal \
  --require-metric mallocCountTotal \
  --require-metric peakMemoryResident \
  --output-dir ../evidence/aski93-control-01
```

The first complete invocation prepares fixtures; retain it as preparation, outside
the paired series. Require the exact nine-workload inventory and all four metrics
in every recorded capture. Collect at least five adjacent control/candidate pairs,
alternating the first arm, on one quiet physical Mac. Retain failed and noisy runs
with explanations. Use the [paired comparison guide](../../docs/agents/paired-benchmarks.md)
to read the complete reports without pooling samples across runs.

### Bounded replay budget — 2026-11-12

Keep all nine workloads and all four metrics. This selects the smallest complete
experiment among the remaining PRs; it does not remove controls or change the
decision bars below. Build and list the instruments before timed captures. Allow
at most 600 seconds per cold build/preparation subprocess, then 180 seconds per
inventory or run subprocess during the paired series. Use the preparation run's
elapsed execution time to check that ten warm captures can fit within 20 minutes.
Stop if that projection exceeds the budget, a required metric is unavailable, or
fixture identity cannot be verified. The paired series has a 20-minute wall limit;
an incomplete series is inconclusive and cannot support a merge.

Run the existing nine `video-` benchmark workloads once on the candidate as a
separate compatibility check with their original configurations. They do not
replace the nine `aski93-video-` paired workloads or their absolute RSS metric.

### Decision rule, declared before native captures

Native exact identity/CFR/report/grid/rendered-pixel parity, duplicate reuse,
cancellation/error behavior, public callbacks and bounded image lifetimes are
prerequisites, followed by the full `just check` and existing video benchmarks.
For numerical evidence, require at least five complete pairs and:

1. At least 5% median paired wall-time improvement in **each** primary 60/120/30 →
   12 case, with improvement in at least 80% of pairs (four of the minimum five).
2. No reproducible regression above 3% in wall or CPU time for the no-resampling,
   equal-rate or upsampling controls. Apply the same 3% guard to CPU, allocations
   and peak RSS across the full matrix; a wall-time win cannot hide extra memory.
3. Here, reproducible means at least 80% of paired deltas exceed the bar.
   Mixed or noisy evidence is inconclusive. Longer-clip RSS and live-image counts
   diagnose retention; neither alone establishes a whole-process memory bound.

These experiment rules do not loosen existing benchmark budgets. A result that
fails a prerequisite or resource guard does not promote this candidate. Keep
ASKI-1/2 preparation/orientation changes out of this comparison. ASKI-93 stays open.

## Research constraints

- Apple's [`copyNextSampleBuffer`](https://developer.apple.com/documentation/avfoundation/avassetreaderoutput/copynextsamplebuffer())
  distinguishes decoded output from compressed sample output. Dropping ASCII
  work does not establish that interdependent codec frames can be skipped.
- The newer [`outputProvider(for:)`](https://developer.apple.com/documentation/avfoundation/avassetreader/outputprovider(for:))
  requires iOS/macOS 26. ASKI targets iOS 18/macOS 15; adopting that API is a
  separate availability and ownership decision, not required for early selection.
- [FFmpeg's `fps` filter](https://ffmpeg.org/ffmpeg-filters.html#fps) documents
  nearest-slot rounding and separately configurable end-of-file behavior. It is
  background for the existing policy, not a substitute oracle: ASKI's declared
  duration uses a ceiling and a one-slot floor, which these fixtures preserve.

## Verification status

Executed with the official **Swift 6.3.3 Ubuntu 24.04 x86_64** toolchain, under
Swift 6 strict concurrency and warnings-as-errors: the actual `ResampleSession.swift`
and `ResampleReport.swift`, copied unchanged into an isolated temporary package,
passed 16 existing core/reporting tests and the new 12-case fixture function.
Swift Testing reports 17 test functions in three suites; there are 28 concrete
executions. No Apple types or APIs were replaced with stand-ins, and the real
package manifest was not changed.

The portable package has an `Aski` target containing those two production files,
and an `AskiTests` target containing `AskiResampleCoreTests.swift`,
`VideoFrameSelectionFixtures.swift`, and `VideoFrameSelectionCoreTests.swift`.
Both use `.swiftLanguageMode(.v6)` in a Swift-tools-version 6.3 manifest. The command
is `swift test --package-path <isolated-package> -Xswiftc -strict-concurrency=complete
-Xswiftc -warnings-as-errors`. Its success verifies the unchanged selection policy
and shared expectations, **not** the new Apple-facing pump or decoder.

All changed Swift files were syntax-parsed and format-linted with that toolchain.
The actual `BuildRepoMap` scanner was compiled and used to regenerate and check
the symbol map. These checks do not resolve Apple imports or prove native strict
concurrency. Xcode and Apple frameworks were absent in that initial environment.
The later native check at `b83d74f` passed 1,454 core tests, 170 media tests and both
deadlock sentinels, plus DocC. Repeat the native gate on the integration that will
be measured; neither record establishes a performance/resource verdict.

On the recorded Mac toolchain, build once before the focused serial media tests:

```bash
xcrun swift build --build-tests
xcrun swift test --skip-build --no-parallel \
  --filter 'VideoFrameSelection|VideoEarlySelection|VideoSelectionLifetime|VideoFramePrefetch|PipelinedVideo|AskiResampleVideo'
```

Then run `just check` and the existing video benchmarks before accepting the
candidate. `just check` was attempted here but could not start because `just` is
absent; a Linux Swift installation is not the complete native gate. Native parity,
real converter-call/lifetime assertions, nine-workload capture validity and all
performance/resource verdicts remain pending.
