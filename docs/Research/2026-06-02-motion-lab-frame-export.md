---
title: "AskiMotionLab - frame materialization, presets, and GIF export spike"
slug: 2026-06-02-motion-lab-frame-export
date: 2026-06-02
status: active
subsystem: [animation]
summary: "Materializes deterministic ASCII frame sequences from a synthetic image, demonstrates reveal (alpha-axis) and cycle (glyph-axis) presets, spikes a native CGImageDestination GIF export, and reports glyph-churn and alpha-churn as an ASCII Temporal Flicker Index feeding the HDR/EDR scope."
runners: [AskiMotionLab]
datasets: []
next_action: "Add a wave (ongoing-axis) preset; re-run the presets on a real photo via --image to validate synthetic-only findings; evaluate gifski-grade encoding if GIF banding blocks the HDR work."
---

## Summary

`AskiMotionLab` (`Tools/AskiMotionLab`) materializes deterministic multi-frame
ASCII sequences from a deterministic synthetic image and exercises the two axes
the animation engine actually animates: **visibility** (the `reveal` preset,
driven by `EntrancePattern.reveal`) and **glyph** (the `cycle` preset, driven by
seeded candidate cycling). Color does not animate - `displayColor` is copied
unchanged on every frame - so the metric measures only those two axes.

## The ASCII Temporal Flicker Index (theory)

The video-generation literature's temporal-flicker family maps onto ASCII via
two channels:

- **Glyph-churn** - fraction of cells whose `character` changed between
  consecutive frames. Discrete, the perceptual-flicker proxy. This is the
  **ASCII Temporal Flicker Index** that the HDR/EDR work (ASTSK-10) inherits as
  its frame-stability measure.
- **Alpha-churn** - mean `|Delta alpha|` per cell. Continuous, the
  motion-smoothness proxy.

Per-preset axis isolation (from `flicker.csv`): the `reveal` preset shows
alpha-churn with zero glyph-churn; the `cycle` preset shows glyph-churn with
zero alpha-churn. A static grid is zero on both. The canonical run measured:

- `reveal`: mean glyph-churn `0.000000`, max glyph-churn `0.000000`, mean
  alpha-churn `0.041667`, max alpha-churn `0.098633`.
- `cycle`: mean glyph-churn `0.204630`, max glyph-churn `0.249653`, mean
  alpha-churn `0.000000`, max alpha-churn `0.000000`.

## GIF export spike + recorded limitation

Native `CGImageDestination` GIF export (infinite loop, per-frame delay) works
with no new dependency. The recorded caveat: ImageIO's built-in quantizer caps
at a 256-color global palette without gifski-grade dithering, so **colored
ASCII frames band in GIF** - visible on the `cycle` preset's rich color. Because
OKLAB color is the point of Aski, the deterministic canonical artifact is the
`frames/<preset>/*.txt` sequence; the GIF is the shareable spike. Recorded byte
sizes: `reveal.gif` `148018` bytes; `cycle.gif` `393776` bytes.

## Next

See `next_action`.
