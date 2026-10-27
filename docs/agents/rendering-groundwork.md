# Rendering task groundwork: ASKI-91, ASKI-94, ASKI-95

Prepared 2026-10-27 against PR #11, commit
`bbe65fa7ac7942449ce3b40f5df26c06143b32ca`. This is an independent sibling of the
ASKI-93 video candidate, not a stack of unmeasured optimizations. Production
sources, package/deployment requirements, goldens and existing budgets are unchanged.

## Delivered and still required

| Task | Executable preparation | Still required before adoption |
| --- | --- | --- |
| ASKI-91 | Nine Foundation-only evaluator contracts; native grid/metadata contracts; 24 frame/overlay workloads | Native public-boundary checks, an isolated implementation, allocation attribution and paired measurements |
| ASKI-94 | Native ragged-coverage and placement contracts; 27 original-image/control workloads | Measured draw census; full control/candidate pixel comparisons including fractional boundaries, P3, source alpha and target-width rendering |
| ASKI-95 | Forced reduced-route versus stock pixel checks, seed/extent interleaving, concurrency and CI cache-toggle checks | Product fallback frequency; 512-square/1080p construction/render timing, retained-memory accounting and normal-Metal controls |

No task is complete. Backlog files were deliberately not edited: the required
Backlog CLI was unavailable. This page and the PR carry the preparation handoff,
not a competing task tracker. The test names below all contain `Groundwork` or
`PatternFrameWork`, so native checks can select this batch without guessing files.

## ASKI-91: prepare one frame, not a global cache

Start at `PatternEvaluator.ongoingAlpha`, `entranceAlpha`, `radialDistance`,
`ASCIIGrid.applyingOngoingPattern`, and `AnimatedASCIIGrid.grid(at:)`.

The smallest candidate is an invocation-owned pulse multiplier, computed with the
same scalar arithmetic once per frame. Completed reveal can be considered
separately from anchor preparation. Keep directional-wave subtraction and sine
operation order: replacing it with a trigonometric identity need not preserve bits.
Do not combine all three ideas into the first measured change.

`PatternFrameWorkContractTests` pins pulse coordinate invariance, directional
arithmetic, neutral multipliers, aesthetic defaults, independent anchor-coordinate
fallback, off-grid origins, reveal endpoints and concurrent evaluation. Its scalar
expressions are independent expectations frozen from the control, not calls into
a second optimized helper. Same-host comparisons are not cross-OS libm goldens.
`PatternGridGroundworkTests` adds ragged rows, metadata and public time normalization.
Its neutral case also checks the existing `alpha * 1` operation on exceptional
Float values; an identity return must not silently redefine that behavior.

Preserve ASKI-18 validation *before* an empty-grid or neutral shortcut. The new
portable tests do not exercise a native public-boundary trap; run the existing
invalid-pattern boundary coverage on the Mac as well. Do not reinterpret a
nonfinite aesthetic value as zero: depth/amplitude use their documented defaults.

The 24 `aski91-` workloads cover 80/192/288 columns: pulse, horizontal and diagonal
wave, two neutral overlays, active/off-grid radial reveal, completed reveal, and a
no-pattern frame control. Overlay grids have `columns / 4` rows. Animation grids
come from the real 800x600 conversion, with cycling disabled. Schedule/conversion
construction is outside timed frame evaluation. These families have different
cell counts; compare matching identities, not an average across families.

## ASKI-94: one image draw through populated row spans

`ImageRenderer.drawMaskFallbackOverlay` currently draws the original image once
for each admitted cell. A completed mask-ground branch admits every existing cell,
regardless of coverage. It does not paint absent ragged cells. The clip limits the
paintable region; this source inspection does **not** prove that every draw
rasterizes the entire source image.

A bounded first experiment is the completed branch only: construct one rectangle
per nonempty populated row, intersect that region with the existing clip, and draw
the original image once. Keep the canvas sizing rectangle unchanged. Apple's
[`clip(to: [CGRect])`](https://developer.apple.com/documentation/coregraphics/cgcontext/clip(to:)-2eg0)
provides the required region operation. A single bounding rectangle is incorrect
for ragged rows. Row rectangles reduce temporary geometry from cells to rows, but
clipping preparation and fractional-edge behavior still need measurement.

Do not apply this directly to the ordinary overlay: inverse coverage varies per
cell there. Do not promise exact pixels from geometric equivalence alone; removing
adjacent cell clips can alter edge rasterization. Start with an exact comparison
against the retained renderer. Register any proposed tolerance with evidence before
acceptance, not after a failed diff.

The 27 `aski94-` workloads cover 80/160/320 columns, all three image sizing modes,
with/without mask ground, and transparent/solid/character fallback controls.
They use mixed coverage `[0, 0.25, 0.75, 1]`, scale 1 and `columns / 4` rows.
For this exact source matrix, the control's source-level image-draw expectations
are 1,600/6,400/25,600 for grounded cases, and 1,200/4,800/19,200 for overlays.
These are derived call counts, **not executed draw traces or raster-cost results**.
Obtain an exact diagnostic call census outside timing; do not confuse sampled
profiler stacks with an exact invocation counter.

The coverage test samples interiors of `[4, 1, 0, 1, 4]`-length rows under hard/soft
masks, with/without ground, at 1x and 1.25x. Placement has separate fill/fit/stretch
rect expectations. These do not substitute for full boundary-pixel parity. Add
P3, translucent source pixels, partial source alpha, ragged rows longer than the
first, empty-first-row behavior and exact target-width output before adoption;
ASKI-7's geometry policy must not be changed incidentally.

## ASKI-95: prove reachability, then consider render-local reuse

`FallbackNoiseGroundworkTests` forces
`DeviceCapability.reducedQuality(.metallibUnsupported)` through the actual
`MetallibEffectKernel` fallback dispatch and compares its pixels with the stock
kernel. It covers dust, grain and their combination, repeated/changing seeds,
shifted/fractional extents, intervening dimensions, concurrent seeds, and explicit
`CIContext.cacheIntermediates` settings. It renders RGBA bytes rather than merely
constructing a `CIImage`. The fixtures are small software-rendered contracts;
they neither measure production fallback frequency nor benchmark a GPU context.

The next harness must report three distinct quantities: CPU raster construction,
CI recipe construction (including that raster work), and forced final rendering.
`seededNoise` is private; use a diagnostic source-level probe or native allocation
profile for isolated raster attribution, rather than opening new public API or
calling recipe construction "noise-only timing". A `CIImage` is a deferred recipe
([Apple's processing guide](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_tasks/ci_tasks.html));
use a synchronous
[`CIContext.render(...toBitmap...)`](https://developer.apple.com/documentation/coreimage/cicontext/render(_:toBitmap:rowBytes:bounds:format:colorSpace:))
to force the measured output. Reuse the context rather than rebuilding it inside
the timed section, and record whether intermediate caching is enabled.

Predeclare 512x512 and 1920x1080, dust/grain/combined, fixed seed and changing seed,
plus normal-Metal controls. Record why fallback was reached on each product host;
forced fallback proves reachability, not its frequency. The first reuse candidate
should share one immutable raster within a dust-plus-grain render, with render-local
lifetime. Only test cross-frame retention if frequency and cost warrant it.

Raster-affecting inputs include dimensions after ceiling, seed/algorithm, format
and color interpretation. An origin-free raster may be reused at different origins
only if translation/cropping is applied anew. A cache of an already-translated
CIImage also needs origin/extent in its identity. The raw RGBA payload is 1 MiB at
512-square and 8,294,400 bytes at 1080p; neither number includes retained CF/CG/CI
objects, allocator overhead or GPU intermediates. Measure total live storage and
RSS. Apple's [`cacheIntermediates`](https://developer.apple.com/documentation/coreimage/cicontextoption/cacheintermediates)
trades memory for repeated-render work; it does not establish reuse of the fresh
CPU-generated raster in this code. No cache is introduced by this groundwork.

## Native verification and measurement

On the recorded Mac, use the normal single build before focused checks, then the
full repository gate. Formatting and parsing alone do not type-check Apple APIs.

```bash
xcrun swift build --build-tests
xcrun swift test --skip-build --no-parallel \
  --filter 'PatternFrameWorkContractTests|PatternGridGroundworkTests|MaskFallbackGroundworkTests|FallbackNoiseGroundworkTests'
just check
```

For complete captures, the ASKI-86 validator currently lives on PR #7, not this
parent branch. Install the exact
[`Scripts/validate-benchmarks.py` at 5493edb](https://github.com/BigCactusLabs/Aski/blob/5493edb992ab57ee2c4a5e16e9ef8106068ab96e/Scripts/validate-benchmarks.py)
in both measurement worktrees and commit it identically. Its blob is
`4dc8e9c545c5164c287f43664d2a351edba06bb4`. Do not assume main's `just bench`
already accepts the adapter's `--require-metric` arguments.

```bash
python3 -B Scripts/validate-benchmarks.py --filter '^aski91-.*$' \
  --require-metric cpuTotal --require-metric mallocCountTotal --require-metric peakMemoryResident
python3 -B Scripts/validate-benchmarks.py --filter '^aski94-.*$' \
  --require-metric cpuTotal --require-metric mallocCountTotal --require-metric peakMemoryResident
```

Freeze the exact identities from
[`rendering-groundwork-workloads.json`](../../Scripts/research/rendering-groundwork-workloads.json)
into each pair manifest's `expected_workloads` (24 and 27 respectively). Native
inventory must match; these counts were derived from registration source, not run.
Start both arms from the same groundwork commit, then alter only the intended
production code in the candidate. Keep fixtures and instruments byte-identical.
Use the [paired readout](paired-benchmarks.md) for at least five adjacent,
order-alternated complete pairs on the same quiet host/toolchain/backend. Report
wall, CPU, allocations, all pairs and noise. Peak RSS is whole-process, including
setup and warmup, not an isolated-phase allocation sum.

Before any optimization measurements, name its affected identities and controls.
A proposed starting bar is at least 5% median paired wall improvement in each named
primary workload, with improving direction in at least 80% of pairs; no reproducible
>3% wall/CPU/allocation/RSS regression in controls. Treat mixed/noisy results as
inconclusive. These are proposed experiment bars, not modified package budgets.
Correctness, public-boundary behavior and lifetime checks are prerequisites.
ASKI-95 needs its separate native harness and memory bound before this rule can
be applied to a cache candidate.

## Portable evidence and limits

```bash
python3 -B Scripts/research/check-pattern-contracts.py --output-dir /tmp/aski91-pattern-probe-new
```

The runner copies six actual production files and the evaluator contract suite
unchanged into an isolated package, recording their SHA-256 values, compiler
identity and log. Its probe manifest permits Swift 6.2; this does **not** lower
Aski's Swift 6.3+ requirement. No Apple types are replaced with stand-ins.

Executed here: nine evaluator tests passed in release mode on Linux x86_64 / Swift
6.2.1, complete strict concurrency and warnings-as-errors. All six changed Swift
files passed format lint with the repository configuration and frontend parsing.
The native grid/mask/noise suites and all 51 workloads remain uncompiled/unrun on
Apple platforms. `just check` could not start (`just` was absent). No native gate,
render parity, fallback-frequency, allocation reduction or speedup is claimed.
