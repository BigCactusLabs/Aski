---
title: "Thread C: Ink-Fraction Color Pre-Compensation (negative result — gamut KILL)"
slug: 2026-06-10-thread-c-ink-precompensation
date: 2026-06-10
status: complete
subsystem: [color-science]
summary: "Back-solving FG′ = (target − (1−k)·BG)/k so the area-tone composite lands on the source cell is a measured KILL on the AskiDecolorLab oracle (absolute ink model): fullColor mean l_fidelity drops 0.185→0.102 but mean chroma_fidelity rises 0.036→0.078, because real glyph ink fractions (k ≈ 0.15–0.32) put the back-solved FG′ out of display gamut on essentially every compensated cell — rayTrace projection lands on the achromatic boundary (mean FG′ chroma 0.0000), recovering luminance by erasing all chroma. ASKI-68 later removed the production controls and compensation runner; this note and Git history retain the evidence. The Phase 0 relative_ramp gate is untouched and still PASSes."
related_specs: [docs/research-plan.md]
datasets: []
runners: [AskiDecolorLab]
next_action: "Closed by the measured KILL and ASKI-68 cleanup. Do not restore a compensation control or runner without a new pre-registered mechanism and qualifying Aski evidence."
---

# Thread C: Ink-Fraction Color Pre-Compensation (negative result — gamut KILL)

## Question

A sparse glyph composites to mostly-background and reads muddy: the eye sees
`k·FG + (1−k)·BG` in linear light (the validated AskiDecolorLab oracle thesis),
so emitting FG == source undershoots whenever `k < 1`. Thread C asks the
falsifiable question deferred from Phase 0 (`docs/research-plan.md` §Thread C):
does back-solving the foreground —

```
FG′ = (target − (1−k)·BG) / k          (linear light, per channel)
```

— so the *composite* lands on the source cell, measurably improve perceived
fidelity under the **absolute** ink model (`.bin` v2 `rawDensityValues`,
shipped in PR #34)?

## Method

Implementation (ASTSK-29, this branch):

- Three `RenderingOptions` knobs — `inkPreCompensation` (strength 0…1, default
  **0** = off, byte-identical: frozen by the bit-exact
  `DefaultPathExactGoldenTests` golden captured pre-change),
  `inkPreCompensationFloor` (k_min, default 0.15; the back-solve divides by `k`
  and amplifies without bound as `k → 0`), and
  `inkPreCompensationBackground` (encoded display-RGB the composite sits over).
- Post-pick only: the glyph choice never changes; after the kernel picks the
  character, the cell's display color is re-derived from the same
  `CellSourceStats` aggregate the provisional color came from. The back-solved
  FG′ is blended toward the uncompensated target by strength, converted
  linear → OKLab (`cbrt` handles negative LMS natively), palette-matched, and
  gamut-mapped by the converter's existing `rayTrace` policy.
- Scored by the new reporter subcommand (exit 0 either way; `check` remains the
  only fail-fast gate):

```bash
swift run AskiDecolorLab compensation-ab --output-dir /tmp/thread-c-ink-precompensation-2026-06-10 --columns 80
swift run AskiDecolorLab compensation-ab --output-dir /tmp/aski-decolor-ab-s05 --columns 80 --strength 0.5
swift run AskiDecolorLab check --output-dir /tmp/aski-decolor-gate --columns 80   # Phase 0 gate, untouched
```

(Run at git `904efd0` on the ASTSK-29 branch.) Both arms composite with
`ink_model=absolute_density` — this is the absolute-fraction oracle work
`docs/research-plan.md:34` deferred to Thread C. The summarizer pairs the arms
cell-by-cell and **throws** if anything but FG/fidelity differs (glyph, k,
ink model, BG, source), so a run that violated the post-pick invariant cannot
emit plausible deltas. The verdict is decided mechanically: WIN requires
fullColor Δl < 0 AND Δchroma < 0 AND fullColor cancellation ≤ 0.5.

## Findings

Canonical run (`columns=80`, strength 1.0, floor 0.15, background `#101010`;
7,200 cells/arm/palette, 4,114 compensated):

| Palette | mean l_fidelity off → on (Δ) | mean chroma_fidelity off → on (Δ) | compensated | cancellation |
| --- | --- | --- | ---: | ---: |
| `monochrome` | 0.0956 → 0.0956 (+0.0000) | 0.0834 → 0.0834 (+0.0000) | 4114/7200 | 100.0% |
| `ansi16` | 0.1848 → 0.1102 (−0.0746) | 0.0329 → 0.0580 (+0.0251) | 4114/7200 | 25.1% |
| `fullColor` | 0.1851 → 0.1018 (−0.0833) | 0.0358 → 0.0775 (+0.0417) | 4114/7200 | 0.0% |

**verdict: KILL — no fullColor win (l_fidelity and chroma_fidelity did not both drop)**

Strength 0.5 sweep: same shape, proportionally smaller (fullColor Δl −0.0672,
Δchroma +0.0311; ansi16 cancellation rises to 39.1%). The verdict does not flip
anywhere on the strength axis — the tradeoff is monotone, not a tuning miss.

### Mechanism: the correction is out of gamut almost everywhere

A per-cell analysis of the 4,114 compensated `fullColor` cells (CSV pairing,
OKLab recomputed from the emitted hex):

| Quantity (compensated fullColor cells) | off arm | on arm |
| --- | ---: | ---: |
| mean FG chroma | 0.1240 | **0.0000** |
| mean perceived-chroma deficit vs source | 0.0511 | 0.1240 |
| mean l_fidelity | 0.2737 | 0.1279 |

**Every single compensated foreground collapsed to achromatic.** With real
glyph ink fractions — `StandardCharacterSet.standard` raw densities span
0.039 (`'`) to 0.317 (`M`); everything the converter actually picks sits in
k ≈ 0.15–0.32 — the back-solve divides the linear target by 3–7×, blowing all
three channels far above 1. rayTrace projects that point back into gamut at the
achromatic ceiling (white), so the "corrected" FG is white-ish everywhere:
luminance recovers (the eye-catching Δl ≈ −0.08 win), and the perceived chroma
deficit becomes exactly the source chroma — all of it is gone.

The display physically cannot emit `target/k` light through a glyph that covers
~25% of the cell. Area-tone pre-compensation at realistic ASCII ink fractions
is **gamut-infeasible**, not mis-tuned.

### Secondary findings

- **`cancellationRate` guarded the wrong failure mode.** It was designed to
  catch "projection snaps FG′ back to the uncompensated color" (fgHex
  unchanged). What actually happened is the opposite: fgHex changed on 100% of
  compensated fullColor cells (cancellation 0%) — to white. The Δchroma
  criterion is what caught the real failure; keep both.
- **`monochrome` is a structural no-op** (cancellation 100%): the single-ink
  palette quantizes every FG′ back to the one ink. Expected, documented, does
  not gate.
- **`ansi16` partially absorbs the white-collapse** (cancellation 25.1%): the
  16-color quantizer sometimes snaps FG′ back to the uncompensated entry, and
  its chroma penalty (+0.0251) is smaller than fullColor's — quantization
  accidentally rate-limits the damage.
- **The absolute ink model itself works.** Both arms composite with
  `rawDensityValues`; the off-arm absolute-model means (fullColor mean_l
  0.185) vs the Phase 0 relative-ramp means (0.056) quantify how much the
  relative ramp flattered absolute fidelity — consistent with the Phase 0
  caveat that `relative_ramp` is valid for ranking, biased for absolute error.

## Caveats

- The oracle scores per-cell composite fidelity; it cannot see spatial effects
  (a field of white-ish glyphs may still *look* brighter/livelier — but that is
  exactly the unfalsifiable hand-wave this lab exists to replace).
- CSV footprint: two ~7.5 MB row dumps, same platform-pinned-snapshot caveat as
  the Phase 0 oracle run (not a CI byte-diff baseline).
- The floor (0.15) excludes sparse glyphs from compensation; lowering it only
  widens the out-of-gamut region (k smaller → FG′ further out), so the KILL is
  not floor-sensitive.

## Decision

Per AC #4 the knobs **stay in** `RenderingOptions` — they are byte-identical at
the default (`inkPreCompensation = 0`, enforced by the bit-exact golden) and
carry doc comments marking the experimental status. Full-strength linear
back-solve is dead as a default-on candidate. The Phase 0 `evaluate`/`check`
gate stays on `relative_ramp` and still PASSes (d′ = 2.4937, exit 0).

## Pointers

- Spec: `docs/research-plan.md` §Thread C
- Related tasks: ASTSK-29 (this slice); ASTSK-7 (occupancy-weighted k — would raise
  effective k and shrink the infeasible region); PR #34 (`.bin` v2
  `rawDensityValues`, no new bin churn in this slice)
- Phase 0 oracle: `docs/Research/2026-06-09-decolor-oracle.md`
