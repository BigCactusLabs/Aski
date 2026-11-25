---
title: "ASKI-95 fallback noise raster reuse"
slug: "2026-11-25-aski95-fallback-noise-reuse"
date: "2026-11-25"
status: "complete"
subsystem: ["meta"]
summary: "Rejected: a 16 MiB process-wide cache of fallback noise rasters kept 96 outputs byte-identical and cut the 1920x1080 dust+grain same-seed fallback render by 78%, but two all-miss changing-seed dust cases regressed 4.2% and 2.8% against a 2% guard. Production keeps building the raster on each application."
next_action: "No adoption. A follow-up needs a fresh rule with disjoint seed streams, a non-thrashing bound and a measured noise floor."
related_specs: ["docs/agents/rendering-groundwork.md", "docs/agents/paired-benchmarks.md"]
---

## Outcome

**Rejected** under the rule below, which the lead set before any measurement and
which was committed with the harness at `a06ef864e6ac4481c76987642c7eaebcc66b5a2a`. Reachability (R1) and the
ceiling (R2) passed, so a candidate was built. It passed exact output parity and
the primary speed bar by a wide margin, but failed two changing-seed guards.
Production is unchanged. The
[result packet](../../Scripts/research/aski95-2026-11-25/README.md) holds the
harness, the rejected patch, the captures and their provenance.

## Decision rule

Recorded verbatim in ASKI-95's notes before timing:

> R1 Reachability. Establish, with file:line evidence, every configuration in which the stock Core Image dust/grain fallback runs in a shipping build (metallib missing or failing to load, unsupported device or OS, an explicit option, tests only). If it runs in no supported shipping configuration, the verdict is REJECT and no candidate is built.
>
> R2 Ceiling. Measure raster construction (seededNoise alone) separately from the end-to-end fallback render, release configuration, serial, under the gate lock: 512x512 and 1920x1080 output; dust, grain, and dust+grain chains; repeated same-seed and changing-seed workloads; at least 5 repetitions per case, reporting medians and spread. If raster construction is under 10% of the end-to-end same-seed repeated render wall time for the 1920x1080 dust+grain chain (the most a perfect cache could save), the verdict is REJECT and no candidate is built.
>
> R3 Candidate. Only if R1 and R2 both pass: build a bounded reuse candidate keyed by every raster-affecting input, with an explicit retained-memory bound and lifetime, deterministic under concurrent calls. ADOPT only if all hold: byte-identical output to the control across every measured case and the existing effect tests; paired (alternating control/candidate, at least 5 pairs) median end-to-end wall-time improvement of at least 10% for the 1920x1080 dust+grain same-seed case; no changing-seed case and no Metal-path case regresses by more than 2%; retained memory within the stated bound. Otherwise REJECT and keep the candidate only as a replay patch.

Operational definitions, ruled by the lead and registered in the same commit:

- **End-to-end fallback render** is the production effect stage only:
  `EffectsRenderEngine.runEffectChainSync` on a fixed CGImage-backed gradient
  input with a `reducedQuality(.metallibUnsupported)` context in extended linear
  sRGB, then `EffectsRenderEngine.shared.context.createCGImage` to RGBA8 sRGB.
  Glyph rasterization and composition are excluded. This smaller denominator
  makes R2 easier to pass.
- **Raster construction** is one call of a verbatim replica of the private
  `StockCIEffectKernel.seededNoise`, kept in the harness so production gains no
  seam. The harness checks that the replica's source text equals production's,
  and that production's dust and grain fallbacks over a clear input, rendered in
  RGBAf, equal the same operations fed the replica raster. It also checks that the
  replica's byte-to-rendered-value map is injective, so equal output implies equal
  raster bytes. Both checks passed at 512×512, 1920×1080 and a fractional offset
  extent, for five seeds.
- **R2 share** is 2 × the raster median at 1920×1080 over the same-seed
  dust+grain end-to-end median, because that chain builds the raster twice.
- Timing used `xcrun swift test -c release` in one serial process under the
  gate lock: 3 warmups, then 15 timed repetitions per case, cases interleaved
  round-robin. Metal-path rows were recorded for R3.

## R1: the fallback ships

The dust and grain effects always go through `MetallibEffectKernel`, whose
fallback is the stock kernel (`Sources/Aski/Effects/ASCIIGrid+Effects.swift:700`
and `:715`). It falls back in two cases:

1. The context reports `reducedQuality`
   (`Sources/Aski/Effects/Internal/MetallibEffectKernel.swift:18`). Rendering
   sets that when `MetalSupport.supportsStitchableKernels()` is false
   (`Sources/Aski/Effects/ASCIIGrid+Effects.swift:615-617`;
   `AskiRenderEngine.deviceCapability` uses the same test at
   `Sources/Aski/Effects/AskiRenderEngine.swift:10-13`). The test is
   `device.supportsFamily(.apple6)`, or false with no Metal device
   (`Sources/Aski/Effects/Internal/MetalSupport.swift:9-10`).
2. The kernel lookup returns nil
   (`Sources/Aski/Effects/Internal/MetallibEffectKernel.swift:22`): the
   metallib resource is missing or fails to load, or the function is absent
   (`Sources/Aski/Effects/Internal/CIKernelLibrary.swift:16`, `:21`, `:27`, `:30`).

Package.swift supports iOS 18, macOS 15 and visionOS 2 (`Package.swift:6`).
Several supported devices lack Apple GPU family 6, which starts at the A13
([Metal feature set tables](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)):

- iPhone XS, XS Max and XR (A12, Apple family 5) run iOS 18
  ([iOS 18 device list](https://www.macrumors.com/how-to/get-your-iphone-ready-for-ios-18/)).
- The 7th-generation iPad (A10) runs iPadOS 18
  ([iPadOS 18](https://en.wikipedia.org/wiki/IPadOS_18)).
- Intel Macs that run macOS 15 have no Apple-family GPU.

There is no public option that forces the fallback. `MetalSupport.testOverride`
is an internal task-local used by tests
(`Sources/Aski/Effects/Internal/MetalSupport.swift:29`, `:42`). R1 passes.
**Frequency is unknown**: Aski has no telemetry, and the share of users on these
devices was not measured. Current Apple-silicon Macs and visionOS devices take
the Metal path.

## R2: construction is 44% of the fallback render

Control capture, medians with interquartile ranges, in milliseconds
([summary](../../Scripts/research/aski95-2026-11-25/r2-summary.csv),
[raw](../../Scripts/research/aski95-2026-11-25/r2-timings.csv)):

| Case | 512×512 same | 512×512 changing | 1920×1080 same | 1920×1080 changing |
| --- | ---: | ---: | ---: | ---: |
| Raster construction (one call) | 0.166 (0.163–0.169) | 0.164 (0.162–0.167) | 1.306 (1.297–1.341) | 1.335 (1.315–1.360) |
| Fallback, dust | 0.818 (0.802–0.839) | 0.722 (0.696–0.742) | 3.531 (3.334–3.683) | 3.557 (3.414–3.680) |
| Fallback, grain | 0.711 (0.668–0.739) | 0.680 (0.664–0.730) | 3.556 (3.327–3.635) | 3.699 (3.562–3.767) |
| Fallback, dust+grain | 1.037 (1.007–1.076) | 1.019 (0.993–1.054) | 5.997 (5.910–6.152) | 5.859 (5.740–5.924) |
| Metal, dust+grain | 0.430 (0.389–0.441) | 0.455 (0.433–0.470) | 1.239 (1.114–1.268) | 1.250 (1.143–1.273) |

R2 share: 2 × 1.306 / 5.997 = **43.6%**, above the 10% bar. R2 passes.

## R3: the candidate

The [candidate patch](../../Scripts/research/aski95-2026-11-25/candidate-treatment.patch)
adds an internal `FallbackNoiseCache`. It keys each entry by the exact output
extent (origin and size) and the seed, which are the only inputs `seededNoise`
reads, and stores the immutable image that `seededNoise` returned. Entries live
for the process. Retained raster bytes are capped at 16 MiB with least recently
used eviction; a raster above the cap is never kept. A lock guards the table and
construction happens outside it, so concurrent builders of the same key make
identical bytes and the first stored entry wins. The two `seededNoise` call
sites go through the cache; `seededNoise` itself is unchanged. Two unit tests
check the bound, the oversized path and key separation.

| Bar | Result |
| --- | --- |
| Exact output | **Pass.** 96 SHA-256 output hashes (both sizes, three chains, fallback and Metal, three same-seed then five changing-seed renders each) are identical; the two inventory files are byte-identical. The existing effect suites were not run on the candidate, because the timing veto decided the outcome. |
| Primary: 1920×1080 dust+grain same seed, ≥10% faster | **Pass.** Median −78.3%; pairs −77.9, −79.5, −78.3, −78.4, −77.2%. |
| Changing-seed guards, ≤2% slower | **Fail.** Dust 1920×1080 +4.21% (pairs +4.4, −6.3, +4.2, +0.6, +5.7) and dust 512×512 +2.78% (pairs +2.8, −7.5, +4.9, −2.7, +7.9). |
| Metal-path guards, ≤2% slower | Pass. All twelve medians range from −4.5% to −0.2%. |
| Retained memory within 16 MiB | Pass by construction and unit test; no workload-level retained-byte export was captured. |

[Every case](../../Scripts/research/aski95-2026-11-25/r3-paired.csv) lists its
five per-pair changes. Pairs ran C/T, T/C, C/T, T/C, C/T with both binaries
fixed (hashes in the [provenance](../../Scripts/research/aski95-2026-11-25/provenance.json)).

## Limitations

These flaws in the instrument were found after the pairs ran. They do not change
the verdict, which follows the frozen rule, but a follow-up must fix them.

- **Changing-seed streams overlap across cases.** Each case's changing seed is
  43 plus its call count, so within one round the dust, grain and dust+grain
  cases of a size use the same seed. Only the dust case misses; the grain and
  dust+grain "changing" cases reuse the raster the dust case just stored. Their
  −41% to −78% results are not evidence about changing-seed workloads. The two
  dust cases, which failed, are true all-miss workloads.
- **The 16 MiB bound thrashes on this mix.** Interleaving 512×512 and 1920×1080
  rasters evicts the seed-42 1920×1080 entry every round, so the same-seed dust
  cases also miss (+2.3% at 1920×1080, +2.2% at 512×512, descriptive). Hits in the
  grain and dust+grain cases come from rasters stored earlier in the same round.
- **The guard is below the noise floor.** The Metal path is unchanged by the
  patch, yet its medians moved −0.2% to −4.5%, and individual pairs ranged from
  −43% to +7%. A 2% guard cannot be resolved at this resolution, and the rule has
  no inconclusive branch for guards, so the dust results count as failures.
  The miss path does little extra work (a lock, a scan of a few entries and an
  insert), and this study does not establish whether the regression is real.
- **Reuse saved more than construction.** The R2 premise that construction is
  the most a perfect cache could save was wrong here: the dust+grain render fell
  78% against a 44% construction share. One explanation is that Core Image reuses
  the uploaded texture when it sees the same image object under
  `cacheIntermediates`. This study does not establish the cause.
- Timing ran in a release build with testability enabled (`@testable import`),
  on one M5 Max under macOS 27.2.1, Xcode 27.2 and Swift 6.4.2. The effect stage
  excludes glyph work, so whole-render savings are smaller. Fallback frequency on
  real devices is unknown, and no measurement ran on a device that actually
  lacks Apple family 6. Power and thermal state were observed after capture, not
  continuously.

A follow-up needs a fresh rule: disjoint per-case seed streams, workloads that
do not interleave sizes past the bound (or a bound sized for the stated
workload), A/A control pairs to measure the noise floor before setting guards,
and an inconclusive branch.
