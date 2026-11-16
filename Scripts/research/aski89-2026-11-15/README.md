# ASKI-89: scoped histogram storage rejected

The candidate lowered allocation counts but failed the registered end-to-end
speed rule. **Three primary benefit bars fail; one is inconclusive.** Production
keeps the owning histogram. No golden, package requirement or threshold changed.

## Decision

The [original rule](../../../docs/Research/2026-11-15-aski89-histogram-storage.md)
was committed at `062c5c8d1ac02c58dc2a332deee8ddb9393f4321` before measurements.
It requires at least 5% median wall improvement and at least four of five pairs
meeting that bar for each primary. Allocation counts must also decrease.

| Primary | Median wall improvement | Pairs meeting 5% | Wall verdict | Median allocation-call change |
| --- | ---: | ---: | --- | ---: |
| 80 columns, serial | 3.30% | 1/5 | Fail | −2,160 |
| 80 columns, parallel | 1.75% | 1/5 | Fail | −2,160 |
| 120 columns, serial | 6.18% | 3/5 | Inconclusive | −4,816 |
| 120 columns, parallel | 1.87% | 0/5 | Fail | −4,816 |

These primaries use oversample 2 and zero edge emphasis. All four allocation
reduction bars pass in five of five pairs. The counts are quantized benchmark
histogram observations; the 4,816 delta is not an exact source-site census.

Across all 148 registered bars, **139 pass, three fail and six are inconclusive**.
The other five inconclusive results concern emphasized parallel wall time,
120-column dotMatrix wall/CPU time and two parallel temporal sampled-RSS guards.
No guard is classified as failed. A valid primary failure rejects the candidate
even when other bars are inconclusive. [Every bar](bars.json),
[all 720 paired metric rows](paired-medians.csv) and
[the lead decision](decision.json) preserve the full result, without pooling
unlike workloads or changing thresholds.

## Separate studies and capture validity

Study 1 is inconclusive. Both arms qualified, but an unrelated native build
overlapped its first pair. Nine of 14 host observations detected that work.
Both captures remain retained and excluded, with no numerical comparison used
for adoption. Its remaining pairs did not run.

One [fresh study](study-02-registration.json) was registered at
`bdb11b4be90742fbd5a68c9e5fa0dff7e16ea64f` before new measurements. It used the
same sources, instruments, 36 workloads, metrics and decision rule. Five startup
observations spanned 60.82 seconds of observed quiet conditions. The five fresh
pairs then ran C/T, T/C, C/T, T/C, C/T without replacement. All ten captures
passed the native validator with 36 workloads and four metrics. Qualification
and all study-1 samples remain outside the comparison.

The fresh study has 56 valid host observations, including startup: AC power,
unchanged power mode, nominal thermal state and no detected unrelated native
build, benchmark or media job. Monitoring was sampled at approximately 15-second
intervals and pair boundaries; shorter unseen jobs could escape detection.
This is one arm64 Mac on macOS 27.0.1, Xcode 27.0 and Swift 6.4, not a universal
hardware claim. [Host facts and original log hashes](host-summary.json) omit the
private process inventory retained in the local archive.

The reviewed native allocator was active in every capture. Source, dependency
locks, qualified Release executable/dylib hashes, export units, sample counts
and hashes were checked. Wall/CPU units are ns; `#` means allocation calls or
resident bytes for the respective metric. Sample medians differ from the
plugin's HDR p50 budget statistic. Sampled RSS includes process residency outside
conversion and can miss transient peaks.

## Control allocation attribution

Four separate formal control profiles identify grayscale base storage,
grayscale copy-on-write, histogram, owned SIMD lanes and Sobel backing through
source and Swift array-owner stacks. Size is not the classifier. Each profile
covers one warmup and six benchmark iterations; temporal iterations convert
two frames. The earlier capability pilot is separate.

| Control workload | Tracked generations | Combined peak live requested bytes |
| --- | ---: | ---: |
| 80 columns, os2, e0, serial | 45,360 | 656 |
| 120 columns, os8, e50, serial | 168,000 | 1,872 |
| 120 columns, os8, e50, parallel | 168,000 | 20,880 |
| Temporal, 120 columns, os8, e50, serial | 336,000 | 1,872 |

All **717,360 target generations have matching frees**. Every trace has zero
unknown extractor allocations, empty attribution blockers and zero live target
generations/bytes at EOF. Other score/sort, temporal result and runtime allocations
remain separately reported. Some runtime/nonselected storage remains live at
exit; the zero-live result applies to the five target families.

[Family totals and individual peaks](allocation-families.csv) and
[complete profile summaries](profiles/index.json) retain those distinctions.
Compressed target intervals and deduplicated stacks permit lifetime replay.
The native method uses complete malloc stack logging, UUID-matched symbols and
a normal-exit breakpoint, then resumes the unchanged executable to exit zero.
All native exports and selected workloads passed. Raw event streams remain in
the local archive, bound by hashes. Requested bytes include native allocator
and Swift array overhead. They are neither RSS nor mapped capacity; event order
does not provide elapsed durations. Parallel live-byte overlap is an observation
of this diagnostic run.

The frozen [parser](analyze.py) passed eight regressions, the capability pilot
and all four formal traces. It received local source review; independent
cross-family parser review was unavailable. Earlier common-support and treatment
source reviews were separate independent checks. Parser exit zero establishes
structural parsing; attribution also requires its blockers and source groups
to pass inspection.

## Parity, floors and unperformed adoption checks

All 15 parity cases match exactly in both debug and release, including grids,
ranked/residual/temporal behavior, retained descriptors, a seeded texture and a
degenerate cell. Both arms passed the full local gate. The candidate gate covered
1,519 core tests, 178 media tests, two deadlock sentinels and DocC. Six exact API
probes passed under Swift 6.3.1 and Swift 6.4 at macOS 15, iOS 18 simulator and
visionOS 2 simulator targets. Those probes check the new storage API; they are
not full mobile package builds. InlineArray remains above the deployment floors.

Candidate allocation profiles, separate direct OS peak-RSS pairs and the
ASKI-87/static/ranked compatibility budget runs stopped at the valid timing veto.
There is no claim of candidate source-site removal without compensation, a
direct-RSS guard pass or adoption. The task closes through its rejection route.

## Replay

From the repository root:

```sh
python3 -B Scripts/research/aski89-2026-11-15/verify-results.py
```

This checks artifact hashes, reconstructs all 2,016 byte-preserved metric exports,
runs the existing canonical reader on only the fresh five pairs, reproduces all
148 bars, recalculates the four target lifetime results with address-generation
matching, and applies the rejected source patch in a temporary directory.
It launches no native benchmark or profiler. Native report hashes are retained
separately from the copies whose host paths are normalized.

The [source replay](source-replay.json) starts from the retained control commit
and applies [candidate-treatment.patch](candidate-treatment.patch). The candidate
commit is `d96c9c1206d50d8ddd406eb699bda198cf687dfc`; the patch and source hashes
permit replay without assuming that this local candidate ref is published.
The result packet adds no production option.
