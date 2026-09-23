# ASKI-69 render-space matcher challenge

Verdict: **KILL**

The frozen MAE and GMSD rule was applied separately to `blocks` and `standard` on both corpora. Generated metric grids are not perceptual votes. If an objective candidate exists, its human and pinned-VLM disposition remains open under a new ASKI-62-compatible treatment.

## Regime census

corpus | charset | arm | cells | glyphs used | largest share | churn | MAE | GMSD | seconds | ratio P | selector bytes
--- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---:
nasa-structure-v1 | blocks | P | 8640 | 3/8 | 98.80% | 0.00% | 0.454399 | 0.282597 | 0.0022 | 1.00x | 89856
nasa-structure-v1 | blocks | A | 8640 | 8/8 | 71.91% | 94.97% | 0.223688 | 0.218828 | 0.0284 | 12.94x | 89856
nasa-structure-v1 | blocks | S1 | 8640 | 8/8 | 67.64% | 94.97% | 0.223905 | 0.221465 | 0.2951 | 134.39x | 89856
nasa-structure-v1 | blocks | TF | 8640 | 8/8 | 65.24% | 93.81% | 0.255304 | 0.215168 | 0.0756 | 34.41x | 89856
nasa-structure-v1 | standard | P | 8640 | 15/95 | 36.86% | 0.00% | 0.249745 | 0.232020 | 0.0065 | 1.00x | 290304
nasa-structure-v1 | standard | A | 8640 | 59/95 | 56.04% | 75.62% | 0.237824 | 0.223882 | 0.3002 | 45.91x | 290304
nasa-structure-v1 | standard | S1 | 8640 | 59/95 | 37.04% | 75.88% | 0.239553 | 0.229079 | 3.0628 | 468.29x | 290304
nasa-structure-v1 | standard | TF | 8640 | 86/95 | 46.16% | 79.81% | 0.252533 | 0.211807 | 0.6905 | 105.57x | 290304
nasa-steerable-v1 | blocks | P | 8640 | 1/8 | 100.00% | 0.00% | 0.455718 | 0.317364 | 0.0014 | 1.00x | 89856
nasa-steerable-v1 | blocks | A | 8640 | 4/8 | 58.65% | 100.00% | 0.214142 | 0.197882 | 0.0248 | 17.63x | 89856
nasa-steerable-v1 | blocks | S1 | 8640 | 4/8 | 55.98% | 100.00% | 0.214224 | 0.198280 | 0.2535 | 180.02x | 89856
nasa-steerable-v1 | blocks | TF | 8640 | 7/8 | 89.26% | 95.90% | 0.246184 | 0.171745 | 0.0592 | 42.07x | 89856
nasa-steerable-v1 | standard | P | 8640 | 11/95 | 38.82% | 0.00% | 0.240037 | 0.194818 | 0.0066 | 1.00x | 290304
nasa-steerable-v1 | standard | A | 8640 | 32/95 | 52.18% | 60.94% | 0.231257 | 0.199579 | 0.2979 | 45.12x | 290304
nasa-steerable-v1 | standard | S1 | 8640 | 27/95 | 42.12% | 61.16% | 0.232126 | 0.199566 | 3.1776 | 481.19x | 290304
nasa-steerable-v1 | standard | TF | 8640 | 73/95 | 74.07% | 64.39% | 0.246722 | 0.171992 | 0.6878 | 104.15x | 290304

## Frozen-rule comparisons

corpus | charset | arm | MAE improve | GMSD regress | time / P | memory
--- | --- | --- | ---: | ---: | ---: | ---:
nasa-structure-v1 | blocks | A | 50.77% | -22.57% | 12.94x | 89856
nasa-structure-v1 | standard | A | 4.77% | -3.51% | 45.91x | 290304
nasa-steerable-v1 | blocks | A | 53.01% | -37.65% | 17.63x | 89856
nasa-steerable-v1 | standard | A | 3.66% | 2.44% | 45.12x | 290304
nasa-structure-v1 | blocks | S1 | 50.72% | -21.63% | 134.39x | 89856
nasa-structure-v1 | standard | S1 | 4.08% | -1.27% | 468.29x | 290304
nasa-steerable-v1 | blocks | S1 | 52.99% | -37.52% | 180.02x | 89856
nasa-steerable-v1 | standard | S1 | 3.30% | 2.44% | 481.19x | 290304
nasa-structure-v1 | blocks | TF | 43.82% | -23.86% | 34.41x | 89856
nasa-structure-v1 | standard | TF | -1.12% | -8.71% | 105.57x | 290304
nasa-steerable-v1 | blocks | TF | 45.98% | -45.88% | 42.07x | 89856
nasa-steerable-v1 | standard | TF | -2.79% | -11.72% | 104.15x | 290304

## Decision

- Objective candidates: none.
- Selected arbiter treatment: none.
- Selected treatment meets the frozen time and memory cost budgets: no.
- Measurement wall time: 18.416 seconds.
- Process maximum resident size: 474775552 bytes. This is descriptive; the per-row selector estimate is the memory gate.

## Complexity boundary

- Production source files changed: 0.
- Public APIs or defaults added: 0.
- Permanent production matcher paths added: 0.
- Research selectors added: 3, contained in `AskiColorLab`.
- A replacement task with a negative production-complexity budget is created only after PROMOTE. HOLD or KILL creates no production option.
