---
title: "AskiVideoLab fps resampling — drop/duplicate retiming to a target frame rate (MP4 exact, GIF quantized)"
slug: 2026-06-04-fps-resample-lab
date: 2026-06-04
status: active
subsystem: [animation]
summary: "Resamples the decode->encode timing path to a caller-chosen target fps by nearest-frame drop/duplicate (FFmpeg-faithful round=near), splicing a media-agnostic selection core between decode and render. MP4 honors the rate exactly via CMTime CFR stamps; GIF quantizes the uniform delay to centiseconds and reports the achieved effective rate (e.g. requested 60 -> achieved 50). Records downsample drop ratio, upsample duplicate ratio, the MP4-exact vs GIF-quantized achieved-fps comparison across 15/24/30/60, and which stage dominates throughput for the fps-resampling milestone."
runners: [AskiVideoLab]
datasets: []
next_action: "Evaluate motion-aware drop selection only if judder is observed on real clips; otherwise the FFmpeg-faithful naive selection stands."
---

## Result

Two samples re-stream prior lab outputs through the resampler. The **GIF sample**
(`cycle.gif` → 15 fps) read 25 source frames and emitted **31 output frames**
(0 dropped, 6 duplicated) at **13.209 frames/sec** with a **peak resident
footprint of 76 218 992 bytes** (~72.7 MB, from `metrics.csv`). The **MP4 sample**
(`ascii.mp4` → 24 fps) read 60 source frames and emitted **49 output frames**
(12 dropped, 1 duplicated) at **15.239 frames/sec** with a **peak resident
footprint of 15 286 944 bytes** (~14.6 MB). Both runs preserved the
`targetFPS == nil` byte-for-byte path elsewhere in the suite (the passthrough
sentinel tests); only the explicit `--target-fps` runs retime.

## Drop/duplicate vs the FFmpeg-faithful expectation

The selection is the FFmpeg `fps` filter rule: each source frame `i` maps to
output slot `round(start_i · t)` (`round=near`, away-from-zero midpoint); a slot
collision keeps the **last** source frame, a slot gap repeats the **previous**.
The output count is `ceil(sourceDuration · t)`.

- **GIF upsample (15 fps):** `cycle.gif` plays slightly below 15 fps, so the
  resampler *duplicated* 6 frames and dropped none — 25 → 31. The achieved rate
  is the centisecond-quantized 14.2857 fps (7 cs uniform delay), so 31 frames
  span ≈ 2.17 s, matching `ceil(sourceDuration · 15)`.
- **MP4 downsample (24 fps):** `ascii.mp4` runs above 24 fps, so the resampler
  *dropped* 12 collided frames and duplicated 1 across a gap — 60 → 49. Decoded
  PTS land on the 1/24 s grid (the round-trip test asserts this directly).

Both match the nearest-slot selection: net change = `duplicated − dropped`
shifts the source count to the `ceil(duration · t)` output count.

## MP4 exact vs GIF quantized

MP4 carries exact `CMTime(value: k, timescale: t)` PTS, so `achievedFPS ==
requestedFPS` for every target (24 → 24.0000 measured). GIF cannot store
sub-centisecond delays, so the uniform per-frame delay is
`round(100 / t)` centiseconds and the honestly-reported achieved rate is
`100 / round(100 / t)`:

| Requested | GIF delay (cs) | GIF achieved fps | MP4 achieved fps |
| --- | --- | --- | --- |
| 15 | 7 | 14.286 (measured 14.2857) | 15.000 |
| 24 | 4 | 25.000 | 24.000 (measured 24.0000) |
| 30 | 3 | 33.333 | 30.000 |
| 60 | 2 | 50.000 | 60.000 |

Targets above 100 fps quantize to a 1 cs (0.01 s) delay, which is below the
0.02 s browser-portability floor and trips `subFloorDelayCount` (covered by the
`highFpsTargetTripsSubFloorDelayCount` operator test). The GIF achieved rate is
surfaced in `ResampleReport.achievedFPS` and narrated in `result.yaml`, never
silently dropped.

## Attribution

Throughput is dominated by the per-cell shape-matching converter, not the
decode/encode I/O — both samples land near 13–15 frames/sec end-to-end at 80
columns, the same order as the non-resampled C2a/C2b lab runs. Resampling
precedes render, so an upsample *re-renders* duplicated grids (the 6 GIF
duplicates each cost a full render), while the common downsample case *saves*
render work by dropping collided frames before they reach the converter (the 12
dropped MP4 frames are never rendered). Output is bounded by `maxResampledFrames`
(36 000) and, in the lab, the optional `--max-frames` source cap; the capped
span uses `min(trackDuration, N / nominalFrameRate)` so a capped resample retimes
only the frames it actually feeds.
