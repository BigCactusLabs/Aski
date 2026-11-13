# ASKI-93: select frames before paying for conversion

**ADOPT — 2026-11-12:** `convertVideo(targetFPS: ...)` selects decoded frames
before ASCII conversion and reuses the grid for duplicate output slots. The
complete nine-workload, five-pair replay supports the frozen rule below. This is
evidence for the synthetic 720p/80-column matrix on one Mac, not a universal gain.

The measured candidate is `d16896e5746f69a4d3ef86f29098cb2b134d8e0a`.
The measured control is `46024d6e28eb8f1ac019b2965d1a3cf5c6dc7993`: production
`main` at `c81861cb3960de91c2bd4ad90087eec51027b3f1`, plus identical benchmark
instruments and this protocol. Both retain the previously merged preparation and
orientation changes. The original candidate followed the contracts in
[PR #11](https://github.com/BigCactusLabs/Aski/pull/11).

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
  These candidate conversion counts passed native execution at the measured SHA.
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
inspection is outside timing. Peak RSS samples absolute process residency about
every 5 ms during the measured loop, including output inspection. The sampler
starts after warmup and resets its maximum; short-lived setup/warmup peaks are not
included unless their memory remains resident. Within each workload process its
samples are cumulative maxima, not independent repetitions. An output-inspection
peak can hide a smaller conversion-phase increase; this is not a stage-specific
allocation measurement.

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
ASKI-1/2 preparation/orientation changes out of this comparison.

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

## Verification history

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

The initial Linux environment could not run `just check` because `just` and Apple
frameworks were absent. The native evidence below supersedes that pending status.

## Native result — 2026-11-12

The measured candidate passed the full local `just check`: 1,529 core tests,
177 media tests, both deadlock sentinels, formatting, build, drift checks and DocC.
The media phase explicitly ran `VideoEarlySelectionIntegrationTests`,
`VideoEarlySelectionTests`, `VideoFrameSelectionCoreTests` and
`VideoSelectionLifetimeTests`. Exact identity/CFR/report/grid/rendered-pixel parity,
duplicate reuse, output-time patterns, cancellation/error cleanup and public
callback checks passed. All nine existing `video-` benchmark workloads also passed
with their original configurations. No threshold, golden or public API changed.

The release replay used Mac15,10, 14 logical CPUs, 36 GiB RAM, macOS 27.0.1
(26A434), Xcode 27.0 (27A266a), Swift 6.4 and package-benchmark 1.35.0. The host was
on AC power with no recorded thermal/performance warning. Builds and tests had
finished; desktop and security software remained active. This was not an idle
desktop. The five adjacent pairs alternated first arm and took **763.344 seconds
(12m43s)**. All ten captures were complete and valid, each with nine workloads and
all four metrics. All sources reported `created=false` and matched the seven
preparation hashes. No capture was excluded.

Median paired change is `100 × (candidate − control) / control`; negative is lower
cost. Each pair compares medians of exported samples; samples are not pooled.

| Workload | Wall | CPU | Allocations | Peak RSS |
| --- | ---: | ---: | ---: | ---: |
| 30 → 12 | −29.98% | −41.86% | −28.01% | −3.67% |
| 60 → 12 | −55.87% | −65.90% | −50.51% | −16.38% |
| 120 → 12 | −73.01% | −80.09% | −68.70% | −17.60% |
| No resampling, 30 fps | −0.37% | −2.45% | 0.00% | +0.92% |
| 12 → 12 | −0.25% | +0.12% | 0.00% | +1.92% |
| 12 → 30 | −1.40% | −0.88% | 0.00% | +0.95% |
| Variable rate → 12 | −7.85% | −14.54% | −5.22% | −10.87% |
| Rotated 60 → 12 | −39.77% | −57.72% | −52.41% | −1.08% |
| Ten-second 60 → 12 | −62.89% | −67.86% | ≈−52.20% | −2.43% |

All three primary wall-time cases improved in **5/5 pairs**, with medians well
beyond 5%. The rule's explicit four-of-five definition governs reproducible
regression: no guarded workload/metric reached it, including worst-case export
rounding. The controls do not establish a speedup or strict noninferiority in
every pair. Equal-rate wall time ranged from −3.6% to +5.5%; two pairs exceeded
+3%. Peak RSS had at most one possibly-above-3% pair per workload, including a
ten-second pair at +11.8%. These retained outliers do not meet the declared
reproducibility bar. Mixed primary benefit would have been inconclusive; all
primary directions agree. No threshold or sample requirement changed.

### Units, evidence and limits

The generic comparator stopped with `invalid` at the ten-second allocation unit
mismatch. That outcome is preserved in
[`comparison.json`](aski93-2026-11-12/comparison.json); it is not a passing generic
comparison. Its first-error exit does not prove later units match. The separate
[`reproduce.py`](aski93-2026-11-12/reproduce.py) checks every cell's units and
reproduces the [180 paired rows](aski93-2026-11-12/paired-medians.csv) and
[summary](aski93-2026-11-12/summary.json) from the parsed captures. The
[raw histogram strings](aski93-2026-11-12/histogram-samples.json) retain all 360
export files byte for byte; the reproducer checks their hashes, counts and medians.
[Provenance](aski93-2026-11-12/provenance.json) records fixture and instrument hashes.
Original report hashes refer to the private captures; the public bundle contains
their parsed measurements, not their host-path-bearing command logs.

```bash
python3 -B Scripts/research/aski93-2026-11-12/reproduce.py --output-dir /tmp/aski93-readout
```

The pinned package's `BenchmarkResult.swift` uses decimal count units and rounds
each normalized histogram value to the nearest-even integer;
`BenchmarkTool+Export.swift` uses that normalization for `histogramSamples`.
The ten-second control exports `10 M`, while the candidate exports `4780 K`.
Multiplying by the unit factor cannot recover lost precision. The supplement
therefore carries ±half an exported unit through each ratio. Even its conservative
upper bound leaves ten-second allocations at least 49.7% lower. The other 35
workload/metric cells have matching units across every capture.

These intervals cover export rounding, not host noise or HDR histogram
quantization. The histogram uses three significant digits (about 0.1% value
resolution); a ±0.25 percentage-point sensitivity around the export bounds does
not change any aggregate rule outcome. The pair is the repetition unit. RSS is a
sampled process high-water mark in the loop, not a whole-clip storage proof.
Allocator identity is configured provenance, not runtime introspection. Other
codecs, dimensions and hardware remain outside this experiment.

An independent Claude Opus review inspected the production change, tests,
instrument and unit-aware method before the adoption verdict. It found no
production defect and accepted the method. The final integration corrects the RSS
comment in the benchmark file; this is a comment-only change from the measured
instrument hash. Production, benchmark calls/configuration and dependency pins
remain identical to the measured candidate. The measured commits above identify
the performance evidence; later documentation is not presented as a new capture.
