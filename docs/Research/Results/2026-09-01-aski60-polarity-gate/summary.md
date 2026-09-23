# Shape-query polarity gate (ASKI-60)

Provenance: `009f249ad914717cd026a2594df58e5de9616fdb`.
Regime: columns 80, oversample 2, footprint 24, sampling cell 12x24, exhaustive census.
Fixtures: earth-limb-sunrise, sahara-dunes, vavilov-crater, apollo11-bootprint, apollo12-lunar-mound, aurora-expedition23, aurora-sts62, calbuco-plume, carina-cosmic-cliffs, cernan-portrait, daedalia-planum, earth-night-iss-090323, earth-night-iss-091208, iani-chaos, infrared-color-explosion, james-lovell-portrait, mark-lee-portrait, marsha-ivins-portrait, multicolor-aurora, new-york-night, rcs-function-diagram, reentry-communications-diagram, rocket-systems-diagram, san-francisco-night, saturn-infrared, spacecraft-attitude-diagram, tarantula-spitzer-3color.

## Reproduce

```
xcrun swift run -c release AskiColorLab polarity-gate \
  --columns 80 --oversample 2 --footprint 24 \
  --cell-width 12 --cell-height 24 \
  --charset blocks,standard,braille \
  --polarity inverted,direct \
  --corpus docs/Research/Corpus/nasa-steerable-v1/assets,docs/Research/Corpus/nasa-occupancy-v1/assets \
  --render-arm \
  --output-dir docs/Research/Results/2026-09-01-aski60-polarity-gate
```

## How to read this

- **MAE decides direction (ASKI-27).** It is printed first everywhere. GMSD is the
  convention-independent GUARD: Prewitt kernels are zero-mean, so a global negation of
  both planes leaves gradient magnitudes untouched and GMSD cannot be flattered by the
  ink convention under test. SSIM and HaarPSI are reported and do NOT decide —
  SSIM's luminance term is polarity-coupled by construction.
- **`improvement%` is signed so POSITIVE means `direct` picked better**, whichever way
  the oracle points.
- **A CANDIDATE verdict does not flip the default.** Standing rule ASKI-56: default
  promotion requires an `AskiColorLab arbiter score` sitting, in a follow-up PR.
- **The four outcomes are pre-registered.** KILL: `direct` is worse on blocks MAE on
  either corpus, or a non-blocks charset regresses > 3.0% MAE. CANDIDATE: blocks MAE
  lift > 3.0% on BOTH corpora with GMSD agreeing in sign and no regression.
  INCONCLUSIVE: `direct` wins blocks on both but inside the bar, or GMSD disagrees —
  it routes to the arbiter just as CANDIDATE does, because the bar sits inside the
  ASKI-56 JND75 band. INVALID: the negative control moved, or an arm is missing —
  a re-instrument, never a result about the treatment.

## Tone pre-filter reach (mechanism check)
`LogPolarKernel` prunes to `topK = 12 + round(density*24)` brightness-nearest
candidates and `ShapeMatching` takes `prefix(min(topK, count))`. Where `pruneBinds` is
`false` the pool holds EVERY glyph, the tone term selects nothing, and the shape term
decides the pick alone.
charset | glyphs | topK | poolSize | pruneBinds
blocks | 8 | 12 | 8 | false
standard | 95 | 12 | 12 | true
braille | 256 | 12 | 12 | true

## Oracle means per arm
corpus | charset | polarity | oracle | cells | mean
nasa-steerable-v1 | blocks | inverted | mae | 8640 | 0.66651
nasa-steerable-v1 | blocks | direct | mae | 8640 | 0.35330
nasa-steerable-v1 | standard | inverted | mae | 8640 | 0.22860
nasa-steerable-v1 | standard | direct | mae | 8640 | 0.22862
nasa-steerable-v1 | braille | inverted | mae | 8640 | 0.23846
nasa-steerable-v1 | braille | direct | mae | 8640 | 0.23794
nasa-occupancy-v1 | blocks | inverted | mae | 66880 | 0.65714
nasa-occupancy-v1 | blocks | direct | mae | 66880 | 0.39564
nasa-occupancy-v1 | standard | inverted | mae | 66880 | 0.36692
nasa-occupancy-v1 | standard | direct | mae | 66880 | 0.36693
nasa-occupancy-v1 | braille | inverted | mae | 66880 | 0.35285
nasa-occupancy-v1 | braille | direct | mae | 66880 | 0.36437
nasa-steerable-v1 | blocks | inverted | gmsd | 8640 | 0.29523
nasa-steerable-v1 | blocks | direct | gmsd | 8640 | 0.18781
nasa-steerable-v1 | standard | inverted | gmsd | 8640 | 0.20801
nasa-steerable-v1 | standard | direct | gmsd | 8640 | 0.20800
nasa-steerable-v1 | braille | inverted | gmsd | 8640 | 0.21198
nasa-steerable-v1 | braille | direct | gmsd | 8640 | 0.21208
nasa-occupancy-v1 | blocks | inverted | gmsd | 66880 | 0.25943
nasa-occupancy-v1 | blocks | direct | gmsd | 66880 | 0.25575
nasa-occupancy-v1 | standard | inverted | gmsd | 66880 | 0.29889
nasa-occupancy-v1 | standard | direct | gmsd | 66880 | 0.29891
nasa-occupancy-v1 | braille | inverted | gmsd | 66880 | 0.25419
nasa-occupancy-v1 | braille | direct | gmsd | 66880 | 0.29867
nasa-steerable-v1 | blocks | inverted | ssim | 8640 | 0.00395
nasa-steerable-v1 | blocks | direct | ssim | 8640 | 0.30673
nasa-steerable-v1 | standard | inverted | ssim | 8640 | 0.30793
nasa-steerable-v1 | standard | direct | ssim | 8640 | 0.30791
nasa-steerable-v1 | braille | inverted | ssim | 8640 | 0.30590
nasa-steerable-v1 | braille | direct | ssim | 8640 | 0.30836
nasa-occupancy-v1 | blocks | inverted | ssim | 66880 | 0.00499
nasa-occupancy-v1 | blocks | direct | ssim | 66880 | 0.10339
nasa-occupancy-v1 | standard | inverted | ssim | 66880 | 0.10429
nasa-occupancy-v1 | standard | direct | ssim | 66880 | 0.10439
nasa-occupancy-v1 | braille | inverted | ssim | 66880 | 0.10052
nasa-occupancy-v1 | braille | direct | ssim | 66880 | 0.10212
nasa-steerable-v1 | blocks | inverted | haarPSI | 8640 | 0.15399
nasa-steerable-v1 | blocks | direct | haarPSI | 8640 | 0.45345
nasa-steerable-v1 | standard | inverted | haarPSI | 8640 | 0.37808
nasa-steerable-v1 | standard | direct | haarPSI | 8640 | 0.37809
nasa-steerable-v1 | braille | inverted | haarPSI | 8640 | 0.38143
nasa-steerable-v1 | braille | direct | haarPSI | 8640 | 0.38149
nasa-occupancy-v1 | blocks | inverted | haarPSI | 66880 | 0.23542
nasa-occupancy-v1 | blocks | direct | haarPSI | 66880 | 0.29171
nasa-occupancy-v1 | standard | inverted | haarPSI | 66880 | 0.18320
nasa-occupancy-v1 | standard | direct | haarPSI | 66880 | 0.18316
nasa-occupancy-v1 | braille | inverted | haarPSI | 66880 | 0.18462
nasa-occupancy-v1 | braille | direct | haarPSI | 66880 | 0.18543

## direct vs inverted (positive = direct picked better)
corpus | charset | oracle | cells | inverted | direct | improve% | differPicks%
nasa-steerable-v1 | blocks | mae | 8640 | 0.66651 | 0.35330 | 46.99 | 38.6
nasa-steerable-v1 | standard | mae | 8640 | 0.22860 | 0.22862 | -0.01 | 0.1
nasa-steerable-v1 | braille | mae | 8640 | 0.23846 | 0.23794 | 0.22 | 4.1
nasa-occupancy-v1 | blocks | mae | 66880 | 0.65714 | 0.39564 | 39.79 | 35.5
nasa-occupancy-v1 | standard | mae | 66880 | 0.36692 | 0.36693 | -0.00 | 0.3
nasa-occupancy-v1 | braille | mae | 66880 | 0.35285 | 0.36437 | -3.26 | 19.5
nasa-steerable-v1 | blocks | gmsd | 8640 | 0.29523 | 0.18781 | 36.38 | 38.6
nasa-steerable-v1 | standard | gmsd | 8640 | 0.20801 | 0.20800 | 0.01 | 0.1
nasa-steerable-v1 | braille | gmsd | 8640 | 0.21198 | 0.21208 | -0.05 | 4.1
nasa-occupancy-v1 | blocks | gmsd | 66880 | 0.25943 | 0.25575 | 1.42 | 35.5
nasa-occupancy-v1 | standard | gmsd | 66880 | 0.29889 | 0.29891 | -0.01 | 0.3
nasa-occupancy-v1 | braille | gmsd | 66880 | 0.25419 | 0.29867 | -17.50 | 19.5
nasa-steerable-v1 | blocks | ssim | 8640 | 0.00395 | 0.30673 | 7660.11 | 38.6
nasa-steerable-v1 | standard | ssim | 8640 | 0.30793 | 0.30791 | -0.01 | 0.1
nasa-steerable-v1 | braille | ssim | 8640 | 0.30590 | 0.30836 | 0.80 | 4.1
nasa-occupancy-v1 | blocks | ssim | 66880 | 0.00499 | 0.10339 | 1973.37 | 35.5
nasa-occupancy-v1 | standard | ssim | 66880 | 0.10429 | 0.10439 | 0.10 | 0.3
nasa-occupancy-v1 | braille | ssim | 66880 | 0.10052 | 0.10212 | 1.59 | 19.5
nasa-steerable-v1 | blocks | haarPSI | 8640 | 0.15399 | 0.45345 | 194.46 | 38.6
nasa-steerable-v1 | standard | haarPSI | 8640 | 0.37808 | 0.37809 | 0.00 | 0.1
nasa-steerable-v1 | braille | haarPSI | 8640 | 0.38143 | 0.38149 | 0.02 | 4.1
nasa-occupancy-v1 | blocks | haarPSI | 66880 | 0.23542 | 0.29171 | 23.91 | 35.5
nasa-occupancy-v1 | standard | haarPSI | 66880 | 0.18320 | 0.18316 | -0.02 | 0.3
nasa-occupancy-v1 | braille | haarPSI | 66880 | 0.18462 | 0.18543 | 0.44 | 19.5

## Negative control (both planes negated)
corpus | charset | polarity | pairs | max|ΔGMSD| | max|ΔMAE|
nasa-steerable-v1 | blocks | inverted | 8640 | 1.2245182640091556e-07 | 1.4487240296290338e-09
nasa-steerable-v1 | blocks | direct | 8640 | 1.230575366051312e-07 | 2.521523545517823e-09
nasa-steerable-v1 | standard | inverted | 8640 | 1.1336671854045299e-07 | 3.20788889895951e-09
nasa-steerable-v1 | standard | direct | 8640 | 1.1336671854045299e-07 | 3.20788889895951e-09
nasa-steerable-v1 | braille | inverted | 8640 | 1.1336671854045299e-07 | 5.018793880484651e-09
nasa-steerable-v1 | braille | direct | 8640 | 1.1336671854045299e-07 | 5.018793880484651e-09
nasa-occupancy-v1 | blocks | inverted | 66880 | 1.5022077037851744e-07 | 4.967053768289986e-09
nasa-occupancy-v1 | blocks | direct | 66880 | 2.8835344330346846e-07 | 9.8892390574222e-09
nasa-occupancy-v1 | standard | inverted | 66880 | 2.8835344330346846e-07 | 1.647923558723008e-08
nasa-occupancy-v1 | standard | direct | 66880 | 2.8835344330346846e-07 | 1.647923558723008e-08
nasa-occupancy-v1 | braille | inverted | 66880 | 2.8835344330346846e-07 | 1.474594080175251e-08
nasa-occupancy-v1 | braille | direct | 66880 | 2.8835344330346846e-07 | 1.474594080175251e-08

## Pre-registered decision rule
clause | result | detail
full matrix measured | PASS | 2 corpora × blocks,standard,braille × MAE+GMSD, no fixture limit
both arms measured | PASS | inverted and direct both ran
blocks MAE lift > 3.0% on both corpora | PASS | nasa-steerable-v1: 46.99229892655098%, nasa-occupancy-v1: 39.794560304871354%
GMSD agrees with MAE in sign on blocks, both corpora | PASS | nasa-steerable-v1: GMSD 36.38378379189423%, nasa-occupancy-v1: GMSD 1.4164483359926832%
no other charset regresses > 3.0% MAE | FAIL | nasa-occupancy-v1/braille: -3.263165699146376%
negative control | PASS | max |ΔGMSD| 2.8835344330346846e-07, max |ΔMAE| 1.647923558723008e-08 over 453120 pairs (tolerance 1e-06)

**Verdict: KILL.**

Deciding clause: no other charset regresses > 3.0% MAE.

Failing clause(s): no other charset regresses > 3.0% MAE.

## Real-renderer arm (sign agreement, not a second verdict)
One fixture per corpus rendered through the shipped `ImageRenderer` (blocks, 76 columns, white ink on black), area-weighted down to the source geometry and scored against the source luma. What matters is whether the SIGN of the polarity difference matches the cell-wise census above.
corpus | fixture | polarity | rendered | source | MAE | GMSD
nasa-steerable-v1 | earth-limb-sunrise | inverted | 548x539 | 3072x3072 | 0.78143 | 0.40123
nasa-steerable-v1 | earth-limb-sunrise | direct | 548x539 | 3072x3072 | 0.03710 | 0.17503
nasa-occupancy-v1 | apollo11-bootprint | inverted | 548x539 | 1280x1280 | 0.48325 | 0.29853
nasa-occupancy-v1 | apollo11-bootprint | direct | 548x539 | 1280x1280 | 0.46659 | 0.30486
