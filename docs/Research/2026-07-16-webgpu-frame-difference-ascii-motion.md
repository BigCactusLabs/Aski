---
title: "WebGPU frame-difference ASCII motion tracking — source-code spike for Aski"
slug: 2026-07-16-webgpu-frame-difference-ascii-motion
date: 2026-07-16
status: active
subsystem: [animation, frontier]
summary: "Source inspection of Maxime Heckel's motion-tracking demo finds no object tracker or optical flow: a quarter-resolution WebGPU compute pass differences current and previous luminance, applies a content-specific water mask, accumulates a short ping-pong trail, maps trail intensity through an 11-glyph atlas, and adds color plus bloom. For Aski, the transferable primitive is a lab-only per-cell source-motion magnitude that could condition the existing temporal tether; the water mask, WebGPU presentation stack, and generic core API do not transfer."
related_specs: [docs/Research/2026-07-01-astsk45-source-tethered-hysteresis.md, docs/Research/2026-06-29-astsk41-nca-temporal-prior.md]
next_action: "If temporal coherence is reopened, add a lab-only per-cell source-motion magnitude to AskiMotionLab and pre-register a motion-conditioned hard-release gate over S1/S2 at columns 64/80 plus real video clips; do not add a public API or product effect before that gate passes."
---

# WebGPU frame-difference ASCII motion tracking

## Question

How does Maxime Heckel's [`motion-tracking-2`](https://r3f.maximeheckel.com/motion-tracking-2)
demo produce its glowing ASCII motion effect, and does any part of the mechanism fill the explicit
motion-signal gap left by Aski's ASTSK-41 and ASTSK-45 temporal-coherence experiments?

This is a source-code spike, not a visual imitation and not an executed Aski experiment. The evidence is
the deployed page and its immutable Next.js
[`motion-tracking-2` route bundle](https://r3f.maximeheckel.com/_next/static/chunks/pages/motion-tracking-2-9cee9a334dd4c381.js),
inspected on 2026-07-16. Framework behavior is cross-checked against the official
[Three.js TSL specification](https://threejs.org/docs/TSL.html) and
[React Three Fiber hook documentation](https://r3f.docs.pmnd.rs/api/hooks).

## Finding in one sentence

The demo is **temporal frame differencing, not tracking**: it compares each video pixel's current and
previous luminance on the GPU, masks the result to water-like colors, accumulates a fading scalar trail,
and uses that trail as the intensity input to an ASCII-atlas post-process.

It does not identify an object, preserve an identity, estimate a displacement vector, track a pose, or
run a learned model. Camera motion, exposure changes, compression noise, and animated texture can all
trigger it because the signal is only per-pixel change magnitude.

## What the deployed implementation does

```text
looping MP4 VideoTexture
  -> quarter-resolution current-vs-previous luminance difference
  -> low-saturation / non-green / non-dark content mask
  -> short scalar motion trail in ping-pong storage textures
  -> 96-row ASCII atlas lookup
  -> blue or red colorization
  -> five-level bloom composite
```

### 1. Input and render ownership

The page autoplays a looping, muted prerecorded asset,
`river4-compressed.mp4`, as a Three.js `VideoTexture`. There is no webcam input. React Three Fiber owns
the canvas and lifecycle, but the component passes render priority `1` to `useFrame`, which disables the
normal automatic render and makes the component responsible for the frame. Each display frame it:

1. dispatches the compute pass,
2. points the post-processor at the texture just written,
3. clears and renders the fullscreen output, and
4. flips the ping-pong index.

There are no scene meshes doing the work. The video and final image are sampled directly by Three.js TSL
nodes and a fullscreen `PostProcessing` output graph. The renderer is explicitly a `WebGPURenderer`.

### 2. Motion detection

The detection textures are one quarter of the drawing-buffer width and height. That is one sixteenth of
the full pixel count. For each detection pixel, the WGSL compute function cover-maps the source video to
the viewport, samples RGB, and computes encoded-video luma with the Rec. 601-style coefficients:

```text
Yt = 0.299 R + 0.587 G + 0.114 B
delta = abs(Yt - Yt-1)
thresholded = smoothstep(0.005, 0.020, delta)
motion = sqrt(thresholded) * contentMask
```

The square root boosts weak above-threshold differences. The first frame writes history but emits no
motion because there is no valid previous frame.

This is a scalar magnitude. The bundle contains an earlier directional-trail sketch based on neighboring
frame differences, but that block is commented out. The live path does not calculate optical-flow
direction or velocity.

### 3. The content-specific mask

The demo names its selector `waterColorMask`. It multiplies three soft masks:

- **neutral color:** full below saturation `0.125`, falling to zero by `0.130`;
- **visible luminance:** zero below luma `0.02`, rising to full by `0.20`;
- **non-green:** full until green exceeds `max(red, blue)` by `0.02`, falling to zero by `0.12`.

This is an art-directed segmentation heuristic for the supplied river clip. It is not part of the motion
detector's general mechanism and should not transfer to Aski. A different clip would need a different
mask, or no semantic color mask at all.

### 4. Temporal trail and ping-pong state

The implementation owns two previous-frame textures and two trail textures. One pair is read while the
other is written, then the roles swap next frame. This avoids reading and writing the same storage texture
in one dispatch.

The trail is scalar grayscale, not a vector field:

```text
decayed = max(previousTrail * 0.995 - 0.025, 0)
trail = max(decayed, motion) * contentMask
```

A full-strength isolated hit reaches zero after about 37 display frames (roughly 0.6 seconds at 60 Hz),
with weaker hits disappearing sooner. Because decay runs on the display loop, its wall-clock duration
changes with refresh rate unless the frame cadence is fixed.

### 5. ASCII presentation

At startup the code rasterizes this 11-character ramp into a one-row HTML canvas atlas, using 512 × 512
pixels per glyph:

```text
" .,:-=+*%#$"
```

The output grid is fixed at 96 rows; its column count is `round(96 * viewportAspect)`. Inside each cell,
trail intensity selects an atlas glyph from space through dollar sign. The source video remains visible as
a very dark, eight-level grayscale base. Motion regions are colored blue or red, and the glyph coverage
mixes their strokes toward white.

The route also defines a 4 × 4 Bayer ordered-dither function, but its returned value is not consumed by
the output graph. A green effect-color branch exists in the shader graph, while the visible controls expose
only blue and red. Both are implementation leftovers, not load-bearing parts of the result.

### 6. Bloom

The final node adds a custom five-mip bloom pass with strength `0.75`, radius `0.15`, and threshold `0.19`.
That makes the sparse bright ASCII strokes read as emissive. Bloom is presentation only; it does not feed
back into detection.

## Why this matters to Aski

The demo's visual product and Aski's temporal-coherence research are different problems:

- Heckel's effect **emphasizes change** and is allowed to discard static content.
- ASTSK-41/45 tried to **reduce glyph churn while preserving the source**.

The useful transfer is therefore not the final look. It is the missing input signal: explicit source
motion magnitude before the discrete glyph decision.

ASTSK-41 showed that smoothing continuous cell state was inert or harmful. ASTSK-45 showed that a fixed
source-tether tolerance reduced churn on slow motion but freeze-trapped fast motion. Its recorded remaining
direction was an explicit motion signal that weakens or releases the hold when the source moves. The web
demo demonstrates the cheapest version of that signal, although it does not establish that the signal will
improve Aski.

### Direct mapping to current repo truth

| Web demo primitive | Current Aski equivalent | Transfer decision |
|---|---|---|
| `VideoTexture` frame | `ASCIIVideoDecoder` yields an oriented `CGImage` per source PTS | Existing path; no change needed |
| Quarter-resolution detection buffer | Converter thumbnail and cell grid | Work at cell resolution first; do not add a second raster pipeline |
| Current luma | `CellSourceStats.adjustedL` inside `convertTemporalFrame` | Reuse the source statistic already calculated for each cell |
| Previous luma texture | `TemporalPriorState.emaAdjustedL` with `alpha = 1` stores the previous raw source L | No extra per-cell history is required for a lab spike |
| Scalar frame difference | `abs(rawSource.adjustedL - prior.emaAdjustedL[index])` | Candidate lab-only motion magnitude |
| Ping-pong trail texture | No equivalent needed for hold release | Do not add trail state unless testing the separate visual effect |
| ASCII atlas lookup | `LogPolarKernel` glyph selection plus `ASCIIGrid` rendering | Existing pipeline is substantially richer; do not replace it |
| Bloom composite | `Effect.bloom` / per-character bloom | Already available as a presentation option |
| Water color mask | None | Reject; it is clip-specific art direction |

The cell loop is the right first experiment because the converter has already paid for thumbnail decode,
cell partitioning, alpha handling, and OKLab aggregation. One subtraction and a small transfer function per
cell are cheaper and easier to falsify than a new Metal optical-flow or full-resolution frame-difference
stage. They also keep the signal aligned with the exact cell whose glyph decision it conditions.

## What we pick

**Keep this as a lab-only temporal-coherence lead. Do not add a public motion API, WebGPU/Metal backend, or
new product effect from this spike.**

If temporal coherence is reopened, test a hard-release rule rather than another continuous smoother:

```text
deltaL = abs(currentSourceL - previousSourceL)
motion = transfer(deltaL)

if motion >= releaseThreshold:
    choose the current-frame winner       // no hold during real motion
else:
    apply the existing source tether      // debounce only stable/slow cells
```

Hard release is important. Merely scaling `rho` toward zero is insufficient because ASTSK-45 already found
that even `rho = 0` could retain a stale glyph on S2 whenever the held glyph had not yet degraded relative
to its lock distance. An explicit moving-cell branch can bypass the hold altogether.

The first transfer function should use Aski's existing OKLab `adjustedL`, not the web demo's encoded-video
Rec. 601 luma, and it should omit trail accumulation and color masking. Thresholds from the river demo are
not portable to per-cell OKLab averages. Calibrate candidate thresholds on a separate diagnostic set, freeze
them, then run the decisive gate.

## Proposed falsification gate

This is a proposal for a future pre-registration, not a result of this note.

1. Add the motion magnitude and hard-release branch only to the existing `@_spi(AskiResearch)` temporal
   path and `AskiMotionLab`; production `convert` remains byte-identical.
2. Reuse S1 slow disc and S2 fast bar at columns `64` and `80`, `N = 48`, `alpha = 1`, with the same GMSD,
   HaarPSI, glyph-churn, and drift-vs-baseline instruments as ASTSK-41/45.
3. Add at least one static/noisy clip and two real moving clips through the video decode path. The static
   clip is necessary because compression noise is the detector's obvious false-positive mode; a global-pan
   clip is necessary because frame differencing should intentionally release every cell there.
4. Use one frozen operating point across all resolutions and clips.
5. Require slow/static regions to reduce glyph churn by at least 20% while holding the existing fidelity
   bands (`GMSD <= baseline * 1.02`, `HaarPSI >= baseline * 0.99`).
6. Require fast/global-motion regions to hold those fidelity bands and avoid a material churn increase;
   no churn reduction is required where the mechanism correctly releases the hold.
7. KILL if the signal cannot separate stable from fast-motion cells, if compression noise causes persistent
   false release, if the S2 freeze-trap remains, or if one shared operating point does not survive the real
   clips.

This gate deliberately changes the old success criterion for S2. A motion-conditioned stabilizer should
not be rewarded for suppressing legitimate fast changes; on S2, preserving fidelity by getting out of the
way is the intended behavior.

## Out of scope

- object identity, pose, segmentation, or optical-flow direction;
- a general camera-motion compensation layer;
- a public `MotionTracker` abstraction;
- a new Metal compute kernel before the cell-resolution CPU instrument proves value;
- shipping the river demo's motion-only visual treatment as a default Aski effect;
- copying its clip-specific water mask or refresh-rate-dependent decay constants.

## Sources

- Maxime Heckel — [Motion tracking demo](https://r3f.maximeheckel.com/motion-tracking-2)
- Maxime Heckel — [deployed `motion-tracking-2` route bundle](https://r3f.maximeheckel.com/_next/static/chunks/pages/motion-tracking-2-9cee9a334dd4c381.js)
- Three.js — [TSL specification: compute, storage textures, and render pipeline](https://threejs.org/docs/TSL.html)
- React Three Fiber — [`useFrame` and render-loop takeover](https://r3f.docs.pmnd.rs/api/hooks)
- Aski — [ASTSK-41 temporal-prior verdict](2026-06-29-astsk41-nca-temporal-prior.md)
- Aski — [ASTSK-45 source-tether verdict](2026-07-01-astsk45-source-tethered-hysteresis.md)
