---
title: "AskiColorLab CAM16/HCT Reference Harness"
slug: 2026-06-05-cam16-hct-reference
date: 2026-06-05
status: active
subsystem: [color-science]
summary: "Adds a lab-local CAM16/HCT reference harness pinned to Material Color Utilities and records CAM16-UCS nearest-palette decisions alongside the existing OKLab Euclidean baseline."
datasets: []
runners: [AskiColorLab]
next_action: "Use the CAM16-UCS divergence rows as candidate evidence only; do not promote CAM16-UCS palette matching without visual/corpus review."
---

# AskiColorLab CAM16/HCT Reference Harness

## Question

Can Aski evaluate CAM16-UCS palette matching and HCT round-trip behavior in a
repeatable lab harness without adding runtime dependencies or widening the
library API?

## Method

The lab ran:

```bash
swift run AskiColorLab cam16-hct-reference --output-dir /tmp/cam16-hct-reference-2026-06-05 --aski-git-sha 35febb3f228519575868045ad53abffb1a27222f
```

The CAM16/HCT math is lab-local and pinned to Material Color Utilities
`6fd88eb3e95ba1d457842e2a2bf847d06b3a018a`. The command writes two CSVs:

- `cam16-hct-reference.csv`: Material primary-color CAM16/HCT reference rows
  plus the 512-color HCT round-trip grid used by Material tests.
- `palette-match-cam16-ucs.csv`: one CAM16-UCS nearest-palette decision per
  `PaletteMatchFixtures` source, with the existing OKLab Euclidean selection
  recorded as the baseline.

CAM16/HCT conversion uses D65 and Material's default sRGB viewing conditions.
HCT output remains sRGB/ARGB bounded, while the palette comparison converts both
sRGB and Display P3 declarations to XYZ D65 before CAM16-UCS measurement.

## Findings

The reference CSV contains 517 data rows: 5 Material primary references and
512 HCT round-trip checks. Every round-trip row preserved its original ARGB
value.

The palette comparison contains 15 data rows. CAM16-UCS differed from the OKLab
Euclidean baseline in 2 rows:

| Fixture | Palette | CAM16-UCS index | OKLab baseline index |
| --- | --- | ---: | ---: |
| `synthetic_srgb_neutral_lightness_ramp_step` | `synthetic_srgb` | 1 | 5 |
| `displayp3_neutral_midgray_srgb_declared` | `synthetic_displayp3` | 2 | 0 |

Those divergences are evidence for review, not a policy recommendation. The
fixture set is deliberately small and synthetic; it is useful for keeping the
measurement path deterministic, but it is not enough to replace OKLab matching.

## Next Action

Run CAM16-UCS over a visual corpus before considering it for production palette
matching. If it survives visual review, add a corpus-backed comparison that
records selected glyph/color output quality, not only palette index changes.
