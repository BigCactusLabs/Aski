---
title: "AskiVideoLab — streaming MP4 → ASCII → MP4 throughput and memory"
slug: 2026-06-03-video-lab-frame-throughput
date: 2026-06-03
status: active
subsystem: [animation]
summary: "Streams an MP4 through AVAssetReader, converts each frame via the existing ASCIIConverter pipeline, and re-encodes H.264 via AVAssetWriter — recording decode+encode throughput and peak resident memory on a representative clip to confirm the streaming (non-whole-asset) memory characteristic for the streaming-video milestone."
runners: [AskiVideoLab]
datasets: []
next_action: "Implement C2b (animated-GIF ingest + GIF export); add target-fps resampling; evaluate whether per-frame VTCreateCGImageFromCVPixelBuffer is the throughput bottleneck vs. the converter itself."
---

## Result

AskiVideoLab streamed a representative clip through `AVAssetReader` →
`ASCIIConverter` → `AVAssetWriter` (H.264). Measured **throughput
5.408 frames/sec** and **peak resident footprint 76202776
bytes** (from `metrics.csv`), where peak is the max `phys_footprint` sampled by a
background poller across the whole run (not a post-hoc reading).

Input: NASA SVS *Perpetual Ocean* (<https://svs.gsfc.nasa.gov/3827>), public
domain (NASA/Goddard Space Flight Center Scientific Visualization Studio; ocean
surface currents from the MIT/JPL ECCO2 model). The clip is cited, not committed;
only the derived `ascii.mp4` + metrics are kept as run output.

To show the pipeline streams rather than loading the whole asset (acceptance #4),
two runs at different frame caps were compared:

| `--max-frames` | frames | peak_memory_bytes | throughput_fps |
| --- | --- | --- | --- |
| 60 | 60 | 76202776 | 5.408 |
| 240 | 240 | 78267136 | 4.912 |

The 4× frame count did **not** scale peak memory ~4× (peak stayed within
2.7%), which is the streaming signature — a whole-asset buffer would grow
with frame count.

## Conversion-path observation

`VTCreateCGImageFromCVPixelBuffer` was used for `CVPixelBuffer → CGImage`. The
measured clip is stored upright (identity `preferredTransform`), so the decoder's
orientation pass did not run. Since ASTSK-12 the decoder applies a non-identity
`preferredTransform` (portrait/rotated/front-camera-mirror) by reorienting the
decoded `CGImage` through a reused `CIContext` — one extra Core Image render per
frame, but only for clips that need it. These throughput/memory numbers (an
upright clip) are therefore unaffected by that path.

## Attribution

Throughput is dominated by the per-cell shape-matching converter, not
AVFoundation I/O — the lab measures decode+convert+encode together, so this note
attributes the cost to the converter rather than claiming an AVFoundation
bottleneck.
