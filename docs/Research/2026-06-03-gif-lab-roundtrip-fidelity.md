---
title: "AskiVideoLab GIF path — animated-GIF → ASCII → GIF round-trip fidelity"
slug: 2026-06-03-gif-lab-roundtrip-fidelity
date: 2026-06-03
status: active
subsystem: [animation]
summary: "Decodes an animated GIF via ImageIO (which returns composed full-canvas frames), converts each through the existing ASCIIConverter pipeline, and re-encodes an animated GIF via CGImageDestination — recording throughput, peak resident memory, and per-frame timing + loop-count preservation on a representative (ideally variable-delay) clip."
runners: [AskiVideoLab]
datasets: []
next_action: "Implement target-fps resampling (drop/duplicate to 15/24/30/60) as the C2 fps follow-up; evaluate whether the converter or ImageIO decode dominates GIF-path throughput."
---

## Result

AskiVideoLab streamed a 13-frame animated GIF through `CGImageSource` →
`ASCIIConverter` → `CGImageDestination`. Measured **throughput 10.490
frames/sec** and **peak resident footprint 36176472 bytes** (~34.5 MB, from
`metrics.csv`), where peak is the max `phys_footprint` sampled by a background
poller across the whole run (decode + convert + render + encode), not a post-hoc
reading.

Input: a synthetic looping GIF generated offline by `AskiMotionLab`
(`--preset cycle --columns 40 --fps 12 --duration 1.0`), so the clip is cited,
not committed; only the derived `ascii.gif` + metrics are kept as run output. A
photographic clip with genuinely variable per-frame delays would make a richer
narrative, but a synthetic looping GIF is sufficient to exercise and document the
path; the variable-delay timing case is covered directly by the round-trip tests
below.

## Round-trip fidelity (the C2b evidence)

The decode→encode→re-decode round-trip preserves the two GIF-specific concerns
the addendum flags:

- **Loop semantics preserved.** The source's reported `LoopCount` was `0`
  (infinite — the value MotionLab writes), and the re-encoded `ascii.gif` reads
  back as `0`. `convertGIF`/the lab pass the source loop count straight through;
  no default of `0` is ever synthesized. The `AskiGIFConverterTests` loop-count
  round-trip covers all three reported cases — absent → `1` (play once), explicit
  `0` → `0` (infinite), and the raw-Netscape `3` → reported `4` finite case — and
  each is stable across write→read. The high-level `kCGImagePropertyGIFLoopCount`
  property proved **symmetric** on this SDK, so no encoder compensation for the
  documented `N→N+1` read quirk was needed.

- **Per-frame timing preserved (unclamped).** This clip's frames are a uniform
  0.0800 s (12 fps rounded to 8 centiseconds; `delay_uniform=true`). The
  load-bearing fidelity case — reading the **unclamped** delay rather than the
  clamped one that silently floors fast GIFs to 0.1 s — is asserted directly by
  `AskiGIFDecoderTests`/`AskiGIFConverterTests` on a variable-delay fixture
  (0.02 s and 0.2 s frames survive decode→encode→re-decode within tolerance,
  *not* clamped to 0.1 s). The encoder writes preserved delays raw, never writes
  0, and reports (does not print) the count of sub-0.02 s frames so the lab can
  surface the browser-portability note.

## Attribution

Throughput is the whole pipeline (ImageIO decode + the per-cell shape-matching
converter + render + ImageIO encode), so this note attributes cost to the
pipeline as a whole rather than blaming ImageIO. ImageIO returns fully composed
full-canvas frames (placement + disposal already applied — see the addendum's
§Verification probe), so there is no manual compositor; a 3-frame disposal-guard
test (`AskiGIFDecoderTests`) is the regression sentinel that fails loudly if a
future SDK ever stops compositing. Batch export memory scales with frame count ×
rendered size, acceptable for short loops and bounded by `--max-frames`;
streaming export remains the documented escape hatch for long animations.
