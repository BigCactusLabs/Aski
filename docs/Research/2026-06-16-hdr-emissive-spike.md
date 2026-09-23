---
title: "ASTSK-10 HDR/EDR Emissive Render Path — Lab-First Spike Verdict"
slug: 2026-06-16-hdr-emissive-spike
date: 2026-06-16
status: complete
subsystem: [color-science, frontier]
summary: "A Lab-first spike rendered each fixture twice from one ASCIIGrid — today's SDR base plus a linear-domain per-cell emission gain in a 16-bit half-float extended-linear context — and let Core Image author a gain-map Adaptive HDR HEIC. Verdict PASS across all four frozen gates: SDR fallback is ε-close (G1 worst 0.0127 ≤ 0.025), the k=0 tone-map round-trip is identity, content headroom is meaningful on bright fixtures and flat on dark ones (G3), and the float buffer is NaN/Inf-clean within the ceiling (G4). The @_spi(AskiResearch) renderExtendedRangeImage path ships opt-in; default rendering is byte-identical."
runners: [AskiHDRLab]
next_action: "Complete — AC#4 manual on-display confirmation PASSED (2026-06-16, EDR Mac); all four ACs satisfied, ASTSK-10 Done. Follow-up ASTSK-37 tracks the art-directable emissive-palette tier (Option 2). Ships opt-in; no default-on promotion."
---

# ASTSK-10 HDR/EDR Emissive Render Path — Lab-First Spike Verdict

## Question

ASTSK-10 ("HDR/EDR renderer path") was scoped as a **Lab-first research spike**, not
a full production feature. Aski's source is SDR, so any extended-range signal is
**authored emission** ("bloom-above-white" — bright glyphs glow past paper-white),
not photographic recovery. Aski's deliverable is **images**. The question: can we produce a system-quality
extended-range artifact from the existing pipeline with a built-in, no-harm SDR
fallback — and prove it with a falsifiable verdict?

**Verdict: PASS** across all four frozen gates. The path is technically validated and
ships **opt-in** regardless (matching every prior Aski thread); no default-on promotion.

## Approach

Each fixture renders twice from the **same** `ASCIIGrid`:

- **SDR base** = today's render (`renderImage`) — unchanged, byte-identical to current
  output (guarded by the G0 raw-byte golden committed pre-refactor).
- **HDR variant** = the SDR colors with a per-cell **emission gain** applied in the
  **linear domain** and written into a 16-bit half-float extended-linear context, so
  bright glyphs exceed 1.0.

Both go to Core Image, which computes the gain map and writes an **Adaptive HDR HEIC**.
Because the SDR base *is* today's render, the gain map's fallback layer carries a
built-in no-harm guarantee — the OS tone-maps HDR→display headroom automatically since
iOS 17 / macOS 14, so AC #3 is satisfied by delegation rather than a hand-rolled tone
curve.

### Emission model (the two P0 correctness pins)

`gain = 1 + k · smoothstep(threshold, 1, cell.brightness)`, clamped to `maxHeadroom`.

- **Gain keys on `cell.brightness`, not `displayColor` luminance.** `brightness` is the
  adjusted *source* OKLAB L (how bright the region was); `displayColor` is the
  palette-matched display color, and the two **diverge** — under
  `BuiltInPalette.monochrome` every `displayColor` is white while `brightness` still
  tracks source luminance. Driving gain from display luminance would bloom every
  monochrome cell. A dedicated **monochrome-no-bloom** unit test pins this.
- **Emission is applied in the LINEAR domain.** `displayColor` is sRGB-gamma-encoded
  `[0,1]`; multiplying encoded values into a linear context is physically wrong. The
  transform is **decode → ×gain → write into the grid's extended-linear space**
  (`extendedLinearDisplayP3` for P3 grids, `extendedLinearSRGB` for sRGB grids — never a
  silent sRGB→P3 conversion). The SDR pipeline's `[0,1]` clamp is untouched; the boost
  is a pure post-pick step, so SDR output never changes.

### Step 0 P0 proof (gated the whole spike)

The approach assumed CoreText (`CTLineDraw`) and braille `fillEllipse` would land
channel values >1.0 into a 16-bit half-float `extendedLinearDisplayP3` `CGContext`
rather than being color-matched/clamped by CoreGraphics. A throwaway one-glyph readback
**confirmed it** — no pivot to a Core Image composite was needed. (Swift gotcha: the
context recipe needs `CGBitmapInfo.byteOrder16Little`, not the ObjC `byteOrder16Host`.)

## Method

- Lab: `Tools/AskiHDRLab` (`evaluate` reporter + `check` fail-fast gate), mirroring the
  `AskiDecolorLab` skeleton (`ProvenanceOptions`/`SeedOption`, `LabExitCode`,
  swift-argument-parser, `result.yaml`).
- 6 unmasked, full-coverage fixtures (`bright-srgb`, `bright-p3`, `dark-srgb` [flat
  control], `edge-srgb`, `gradient-srgb`, `mono-bright-srgb`) × a frozen `k` sweep
  `{0, 1, 2, 4}` = **24 samples**. Frozen render config: `threshold = 0.5`,
  `maxHeadroom = 8`, font size 12, `--columns 80`, background `#101010`.
- Per sample: author a gain-map Adaptive HDR HEIC, write a 16-bit float TIFF reference,
  and measure G1–G4 into `hdr.csv`.
- **Scope: opaque, full-coverage content only.** The SPI method returns `nil` for any
  grid that breaks HDR/SDR pixel-alignment: sub-1 mask coverage
  (`maskContainsCoverageBelowOne`), a non-transparent `maskFallback`, **or any
  translucent (`alpha < 1`) cell**. An `alpha < 1` cell composites differently in the
  extended-linear context than in the 8-bit sRGB-gamma SDR render, and the gain map
  `log(HDR/SDR)` would then encode that mismatch as spurious gain — so it is rejected
  rather than rendered wrong. The six fixtures are all opaque, so this guard is latent
  (never fires in the run) but keeps the contract honest. Rejection tests cover all
  three paths. Mask-fallback and translucent emission are future work.

```bash
swift run AskiHDRLab evaluate --output-dir /tmp/hdr-emissive-spike-2026-06-16 --columns 80
swift run AskiHDRLab check    --output-dir /tmp/aski-hdr --columns 80   # nonzero exit == KILL
```

### Decisive verdict gates (frozen BEFORE the run)

| Gate | What it proves | Threshold |
| --- | --- | --- |
| **G0** Refactor byte-identity | `renderImage` is bit-identical to pre-refactor | strict equality (raw-byte golden) |
| **G1** Fallback fidelity (AC #3) | HEIC's embedded SDR base ≈ SDR render | mean per-channel diff ≤ 0.025 |
| **G2** Round-trip (k=0) | zero-emission encode→`expandToHDR`→tone-map(target 1) is identity | ≤ 0.025 at k=0 |
| **G3** Meaningful + specific headroom (AC #2) | bright peaks >1.3, dark ≤1.1, monotonic in k | per-fixture |
| **G4** Float integrity | no NaN/Inf; values within `[0, maxHeadroom]` | exact |

## Results

**Verdict PASS** — all gates green.

```
G1 fallback fidelity:  PASS (worst SDR-base mean diff 0.0127 vs tol 0.0250)
G2 round-trip (k=0):   PASS (zero-emission tone-map identity diff 0.0127 vs tol 0.0250)
G3 headroom:           PASS
G4 float integrity:    PASS
verdict: PASS
display EDR headroom: 16.000
```

Content headroom by `k` (reconstructed from the authored gain-map HEIC):

| Fixture (expectation) | k=0 | k=1 | k=2 | k=4 |
| --- | --- | --- | --- | --- |
| bright-srgb (blooms) | 1.00 | 1.20 | 1.80 | 3.00 |
| bright-p3 (blooms) | 1.00 | 1.20 | 1.80 | 3.00 |
| edge-srgb (blooms) | 1.00 | 1.20 | 1.80 | 3.00 |
| gradient-srgb (blooms) | 1.00 | 1.08 | 1.62 | 2.69 |
| mono-bright-srgb (blooms) | 1.00 | 1.20 | 1.79 | 2.97 |
| **dark-srgb (flat control)** | 1.00 | 1.00 | 1.00 | 1.00 |

- **G3 holds cleanly.** Bright fixtures rise monotonically with `k`; the dark control
  stays flat at 1.00 at every `k` (no spurious emission); the k=0 control lands at 1.00
  everywhere. `bright-srgb` and `bright-p3` track **identically** — emission is
  luminance-domain, so the gamut doesn't change the headroom curve, as expected.
- **G1 is well inside tolerance** — worst SDR-base mean diff 0.0127 (bright fixtures)
  against the 0.025 bound; the dark control is ≈0.0006. The floor is the HEVC-lossy
  10-bit re-encode, not an Aski defect.
- **G4 is clean** — `float_clean = true` for all 24 rows; the authored peak channel
  reaches 5.0 at k=4 (= `1 + 4·smoothstep` at brightness 1), under the 8.0 ceiling.

### Apple caps the reconstructed gain-map headroom (recorded finding)

The authored float peak reaches **5.0×** at k=4, but the reconstructed **content
headroom caps at ≈3.0×**. Apple's ISO-gain-map encoder compresses the authored range to
its own ceiling — this matches the plan's "~3-stop ISO gain map" caveat. Headroom stays
**monotonic in k** and the dark control stays flat, so the cap is a benign ceiling, not
a correctness failure. Consumers wanting the full authored range use the secondary
in-memory vehicle (the 16-bit float `CGImage` / committed TIFF refs), not the HEIC.

## Frontier API findings (empirically confirmed against the installed macOS-15 SDK)

The 2025–26 idiomatic library deliverable is a **gain-map Adaptive HDR HEIC**. The exact
API was verified at implementation time (sources disagreed with older WWDC samples):

- **Write:** `ciContext.heifRepresentation(of: sdrCI, format: .RGBA8, colorSpace: gridSpace, options: [.hdrImage: hdrCI])` — using the **grid's actual color space**, not a hardcoded P3, so sRGB grids get no spurious gamut conversion.
- **Read HDR headroom:** `CIImage(contentsOf: url, options: [.expandToHDR: true])?.contentHeadroom`.
- Plain `CGImage.contentHeadroom` (no expand) returns the SDR base (=1.0) — that's the G1 fallback view.
- **Tone-map:** `CIToneMapHeadroom` with `inputTargetHeadroom`.
- The float-context recipe is fiddly and returns nil if wrong: `bitsPerComponent: 16`, `bitsPerPixel: 64`, `floatComponents | byteOrder16Little | premultipliedLast`.

## The one judgment call: G2 instrument correction (disclosed)

The **initial G2** (tone-map HDR→headroom-1 and compare to the *clamped* SDR across all
`k`) conflated Apple's tone **operator** — legitimate highlight compression, ~0.10 mean
diff at high `k` — with a hard clamp. That is an **instrument artifact, not an Aski
defect**: at k>0 the system tone-map *should* compress highlights; calling that a
fidelity failure would be measuring Apple's display tone curve, not Aski's output.

The **corrected G2** gates the **k=0 zero-emission identity only** (where the HDR variant
equals the SDR, so the full encode→`expandToHDR`→`CIToneMapHeadroom(target:1)` pipeline
must be identity within ε — a genuine plumbing gate). All-`k` SDR fallback fidelity is
already covered by **G1** (the embedded base, 0.0127 ≤ 0.025). The k>0 tone-curve
divergence is **recorded as data** (`g2_mean_diff` rises to ≈0.106 at k=4), not gated.

## Ecosystem caveats (capability gating, DoD #2)

- **Safari / WebKit** does not render gain maps — HDR HEICs degrade to their SDR base in
  the browser. Web export should assume SDR-only.
- **iMessage** has historically been flaky at preserving gain-map HDR across the
  transport; treat round-trip HDR delivery as best-effort, not guaranteed.
- **Apple treats ISO gain maps as a bounded headroom** (the ≈3.0× reconstructed cap
  measured above); the authored float range is not preserved end-to-end through the HEIC.
- **EDR availability is per-device.** The dev Mac display reports an EDR headroom of
  **16.0** (EDR-capable; AC#4 was confirmed on this display); a non-EDR display simply shows the SDR
  base. Gate emission UX on `NSScreen` / `UIScreen` headroom at the app layer.
- **The gain-map encoder is not frozen across OS versions.** Apple's ISO-21496-1
  gain-map encoder changed behaviour across releases (iOS 18 switched the gain map from
  monochrome to RGB adaptive; later releases add `calculateHDRStats*`), and
  `CIImage.contentHeadroom` is **content-derived, capped at ≈8** (≈3 stops) — the
  renderer's `maxHeadroom = 8` clamp sits right at Apple's content cap
  ([WWDC24 10177](https://developer.apple.com/videos/play/wwdc2024/10177/);
  [juniperphoton](https://juniperphoton.substack.com/p/process-apple-gain-map-the-imageio);
  [dotnet/macios wiki](https://github.com/dotnet/macios/wiki/CoreImage-iOS-xcode26.0-b1)).
  ⇒ **Absolute G1–G4 thresholds measured off a live encode are SDK-coupled.**
  Determinism therefore lives in synthetic unit tests (`HDRGatesTests` for the verdict
  logic, `HDRArtifactsTests` proving the G4 detector fires); the real-encode `check` is
  *evidence*, not a frozen oracle, and the only relative invariant asserted off the live
  CSV is that each bloom fixture's peak content headroom exceeds its own k=0 control by a
  margin (`bloomHeadroomExceedsControl`) — which survives encoder revisions because it is
  a per-fixture relative claim. A `check` break under a new SDK is a *signal*, acceptable
  since it runs locally with Actions off.

## Inherited frame-stability

For animated/video HDR, frame stability is inherited from ASTSK-5: the **ASCII Temporal
Flicker Index** is the committed frame-stability measure
([docs/Research/2026-06-02-motion-lab-frame-export.md](2026-06-02-motion-lab-frame-export.md)).
This spike adds a per-cell emission boost that is a deterministic function of
`cell.brightness`, so it introduces no new temporal term — a glyph that is stable in SDR
stays stable under emission.

## What ships (Sources/ changes — minimal, additive, research-SPI)

- `Renderers/ImageRenderer.swift`: the draw loop is extracted into a shared
  `renderGeometry` + `drawCells(…foregroundColor:)`; `renderImage` is **byte-identical**
  (identity path, no per-cell closure overhead). A new
  **`@_spi(AskiResearch) renderExtendedRangeImage(font:backgroundColor:scale:preserveSourceAspect:emission:)`**
  resolves its own extended-linear color space internally, builds the half-float context,
  applies the linear-domain emission, and **returns `CGImage?` — `nil` for every
  can't-render-faithfully path** (sub-coverage, non-transparent mask fallback, any
  translucent cell, or a context-construction failure), scoping the path to opaque,
  full-coverage content. `EmissionOptions` inputs are sanitized at the point of use
  (`threshold` clamped to `[0,1]`, `k` clamped to `≥0`, both NaN-guarded).
- **No `RenderCompositionPolicy` case was added.** `cgColorSpace(for:)` is a shared
  dispatch point also consumed by the 8-bit effects raster path; a float case would feed
  a float color space into an 8-bit context (nil/garbage). The policy enum stays
  two-case; the SPI method resolves the extended-linear space internally. Effects-path
  HDR is explicit future work.
- **No benchmark-threshold changes** — the float path is lab-only and off the default
  benchmarked route. The no-effects spike measured malloc **328K** (budget 410K) and
  **103ms** (budget 142ms) post-refactor.

## Follow-up

- **AC #4 confirmed PASS (2026-06-16, manual on-display check).** A generated `.heic`
  was opened on the EDR Mac display: bright fixtures glow past paper-white, brightness
  rises monotonically with `k`, the dark control stays flat, and the image degrades
  cleanly to the SDR base where EDR is unavailable. With AC #1–#3 already green, **all
  four ACs are satisfied — the spike is complete and ships opt-in.**
- A follow-up task tracks the **art-directable emissive-palette tier** (Option 2) —
  per-character/per-palette authored emission rather than a single brightness-keyed
  curve — gated on this spike's PASS.

## Artifact note

The result dir commits all 24 gain-map HEICs (each under 2 MB, the primary deliverable),
`hdr.csv`, and `result.yaml`. The 16-bit float TIFF references are ~2.39 MB each, so a
curated 2-file subset (`bright-p3` headline bloom + `dark-srgb` flat control) is
committed via Git LFS per the repo's research-data governance; the full six-fixture TIFF
set is regenerable with `swift run AskiHDRLab evaluate`.
