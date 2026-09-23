---
title: "AskiAccessLab Accessibility Palette Audit"
slug: 2026-06-04-access-lab
date: 2026-06-04
status: active
subsystem: [color-science]
summary: "AskiAccessLab audits default ANSI16, monochrome, and a lab-local accessible ANSI16 candidate under severity-1.0 protanopia, deuteranopia, and tritanopia, recording WCAG-style contrast and OKLab separation for palette chips and rendered ASCII-grid fixtures."
datasets: []
runners: [AskiAccessLab]
next_action: "Iterate accessible-ansi16-v1 before promotion; the first candidate slightly lowers OKLab confusion flags versus ANSI16 but increases luminance-threshold misses."
---

# AskiAccessLab Accessibility Palette Audit

## Question

Can a lab-local accessible ANSI16 candidate reduce CVD confusion and
luminance-threshold misses compared with the current ANSI16 and monochrome
baselines, without turning the result into a public palette preset before
evidence exists?

## Method

The lab ran:

```bash
swift run AskiAccessLab audit --output-dir /tmp/access-lab-2026-06-04 --columns 24 --aski-git-sha 620a610b00d29ccc99db21a0902fd1bc7febfa00
```

It evaluated:

- `ansi16`
- `monochrome`
- `accessible-ansi16-v1`

For each palette it scored palette-chip comparisons and rendered ASCII-grid
fixture comparisons under severity-1.0 `protanopia`, `deuteranopia`, and
`tritanopia` using `brettel1997_dichromacy_srgb`.

All rendered-grid samples were produced through `ASCIIConverter` pinned to
`.sRGB`. `ASCIICell.displayColor` was treated as transfer-encoded sRGB,
linearized before CVD simulation, WCAG relative luminance, and OKLab separation.
CSV colors are delimiter-safe `#RRGGBB` values.

The committed result uses `--columns 24` to keep the CSV artifact comparable to
the existing committed Results footprint. The lab is deterministic on a given
Aski revision, Swift toolchain, SDK, and OS, but exact glyph/color rows can
drift across platform revisions; treat this as a platform-pinned research
snapshot, not a CI byte-diff baseline.

The CSV-first result shape is supported by the verified arXiv source
<https://arxiv.org/abs/2602.24067>, which demonstrates reproducible static
color-contrast auditing over many foreground/background pairings.

## Findings

The run produced 4,023 scored rows. It flagged 2,599 rows below
`minimumOKLabDelta = 0.02` and 3,399 rows below the WCAG-style contrast
threshold of 3.0.

By palette:

| Palette | Rows | OKLab confusion flags | Luminance-threshold misses |
| --- | ---: | ---: | ---: |
| `ansi16` | 1,491 | 786 | 1,133 |
| `monochrome` | 1,041 | 1,038 | 1,038 |
| `accessible-ansi16-v1` | 1,491 | 775 | 1,228 |

The first accessible candidate is not ready for promotion. It slightly reduces
OKLab confusion flags versus ANSI16, but it increases luminance-threshold
misses. That is the wrong trade-off for a candidate whose purpose is practical
accessibility improvement.

See the run's `accessibility.csv` for the
row-level audit. The `luminance_threshold_met` column is an audit metric. It is
not a WCAG conformance claim for unordered color-vs-color palette pairs.
`minimumOKLabDelta = 0.02` is a conservative v1 confusion marker. It should be
calibrated upward if known dichromat confusion pairs are under-reported.

## Next Action

Iterate or reject `accessible-ansi16-v1` before any promotion into
`BuiltInPalette`. The next candidate needs to reduce both OKLab confusion flags
and luminance-threshold misses relative to ANSI16 on the same lab run.
