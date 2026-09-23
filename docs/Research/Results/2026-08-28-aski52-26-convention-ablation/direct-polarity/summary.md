# Candidate-convention delta and sampling-support ablation (ASKI-52 / ASKI-26)

Query polarity: **direct**.

## Reproduce

```
swift run -c release AskiColorLab convention-ablation \
  --columns 80 --oversample 2 --footprint 24 \
  --cell-width 12 --cell-height 24 --stride 1 \
  --charset blocks,standard,braille \
  --query-polarity direct \
  --corpus docs/Research/Corpus/nasa-steerable-v1/assets,docs/Research/Corpus/nasa-occupancy-v1/assets \
  --output-dir docs/Research/Results/2026-08-28-aski52-26-convention-ablation/direct-polarity
```

## How to read these tables

- **The convention-delta table is a COMPOUND comparison, not a clean convention effect.**
  Production is one of its two sides, so the arm swaps the query path as well as the
  candidate vocabulary: production scores a descriptor taken from the shipped thumbnail
  cell (see `thumbCell`/`liveBins` in the geometry table), while the treatment side samples
  the native source block. The single-variable convention delta is ladder rung
  `squareSingleDisc` against `faithfulSingleDisc`, which holds the query support fixed.
- **The braille null control is in the LADDER, not the delta table.** `BrailleRasterizer`
  draws dots over the whole cell rect under either cell-aspect placement, so for braille
  `rectSingleDisc` and `faithfulSingleDisc` are the SAME vocabulary and every braille number
  must agree between those two rungs exactly. Braille production candidates really are
  rasterized at 64x64 (`BuildStandardVectors`), so rung `squareSingleDisc` is a different
  raster and is expected to differ.
- **Corpus caveat.** `nasa-occupancy-v1` and `nasa-isoluminant-v1` are committed as JPEGs.
  `RealFixture.load` accepted PNG only until this run, which is why no earlier Tools-side
  census could reach them (it threw rather than dropping them silently) and why
  `2026-08-19-sampling-lattice-support-collapse.md` had to retract two fixtures. JPEG is now
  accepted; the compression artifacts in those assets are part of the measurement, so any
  figure quoted from that corpus must name it.
- **MAE is the verdict oracle (ASKI-27).** SSIM ratios against a near-zero baseline are
  arithmetically true and perceptually meaningless; read the absolute means, not the percent.
- **Query polarity is a REGIME, not a detail.** Candidate rasters are ink-high
  (`RasterizedCharacterSet.rasterize` fills at gray 0, draws at gray 1). Production's shape
  query is `1 - luma` (`LogPolarKernel.baseInvertedLuma`), so its shape term treats DARK
  source regions as ink, while its tone pre-filter matches a BRIGHT cell to a dense glyph.
  Those two disagree inside production. `inverted` reproduces production's shape term;
  `direct` puts the query on the same footing as the candidates and the scoring path.
  Compare the two runs before reading any arm as a verdict on the candidate convention.

## Resolved geometry (the regime, measured)
corpus | fixture | native | thumb | grid | thumbCell | windows@thumbCell | nativeBlock(min-max) | liveBins/60 | cells
nasa-steerable-v1 | earth-limb-sunrise | 3072x3072 | 160x160 | 36x80 | 2x4 | 2 | 38-39x76-77 | 3.00 | 2880
nasa-steerable-v1 | sahara-dunes | 3072x3072 | 160x160 | 36x80 | 2x4 | 2 | 38-39x76-77 | 3.00 | 2880
nasa-steerable-v1 | vavilov-crater | 3072x3072 | 160x160 | 36x80 | 2x4 | 2 | 38-39x76-77 | 3.00 | 2880
nasa-occupancy-v1 | apollo11-bootprint | 1280x1280 | 160x160 | 36x80 | 2x4 | 2 | 16x32 | 3.00 | 2880
nasa-occupancy-v1 | apollo12-lunar-mound | 1280x1241 | 160x155 | 35x80 | 2x4 | 2 | 16x32 | 3.00 | 2800
nasa-occupancy-v1 | aurora-expedition23 | 1280x876 | 160x110 | 24x80 | 2x4 | 2 | 16x31-32 | 3.00 | 1920
nasa-occupancy-v1 | aurora-sts62 | 1280x844 | 160x106 | 23x80 | 2x4 | 2 | 16x31-32 | 2.99 | 1840
nasa-occupancy-v1 | calbuco-plume | 1280x1150 | 160x144 | 32x80 | 2x4 | 2 | 16x31-32 | 3.00 | 2560
nasa-occupancy-v1 | carina-cosmic-cliffs | 1280x741 | 160x92 | 21x80 | 2x4 | 2 | 16x32-33 | 3.00 | 1680
nasa-occupancy-v1 | cernan-portrait | 1026x1280 | 160x200 | 45x80 | 2x4 | 2 | 12-13x25-26 | 3.00 | 3600
nasa-occupancy-v1 | daedalia-planum | 578x1280 | 160x355 | 80x80 | 2x4 | 2 | 7-8x14-15 | 3.00 | 6400
nasa-occupancy-v1 | earth-night-iss-090323 | 1280x851 | 160x106 | 24x80 | 2x4 | 2 | 16x32-33 | 3.00 | 1920
nasa-occupancy-v1 | earth-night-iss-091208 | 1280x851 | 160x106 | 24x80 | 2x4 | 2 | 16x32-33 | 3.00 | 1920
nasa-occupancy-v1 | iani-chaos | 600x1280 | 160x342 | 77x80 | 2x4 | 2 | 7-8x14-15 | 3.00 | 6160
nasa-occupancy-v1 | infrared-color-explosion | 1280x1280 | 160x160 | 36x80 | 2x4 | 2 | 16x32 | 3.00 | 2880
nasa-occupancy-v1 | james-lovell-portrait | 975x1280 | 160x211 | 47x80 | 2x4 | 2 | 12-13x24-25 | 2.22 | 3760
nasa-occupancy-v1 | mark-lee-portrait | 1029x1280 | 161x200 | 45x80 | 2x4 | 2 | 12-13x25-26 | 2.99 | 3600
nasa-occupancy-v1 | marsha-ivins-portrait | 1016x1280 | 160x202 | 45x80 | 2x4 | 2 | 12-13x25-26 | 3.00 | 3600
nasa-occupancy-v1 | multicolor-aurora | 1280x853 | 160x106 | 24x80 | 2x4 | 2 | 16x32-33 | 3.00 | 1920
nasa-occupancy-v1 | new-york-night | 1280x834 | 160x104 | 23x80 | 2x4 | 2 | 16x32-33 | 3.00 | 1840
nasa-occupancy-v1 | rcs-function-diagram | 1280x1024 | 160x128 | 29x80 | 2x4 | 2 | 16x32 | 0.33 | 2320
nasa-occupancy-v1 | reentry-communications-diagram | 1029x1280 | 161x200 | 45x80 | 2x4 | 2 | 12-13x25-26 | 0.57 | 3600
nasa-occupancy-v1 | rocket-systems-diagram | 1280x1024 | 160x128 | 29x80 | 2x4 | 2 | 16x32 | 0.69 | 2320
nasa-occupancy-v1 | san-francisco-night | 1280x851 | 160x106 | 24x80 | 2x4 | 2 | 16x32-33 | 3.00 | 1920
nasa-occupancy-v1 | saturn-infrared | 1280x690 | 160x86 | 19x80 | 2x4 | 2 | 16x32-33 | 3.00 | 1520
nasa-occupancy-v1 | spacecraft-attitude-diagram | 1280x1024 | 160x128 | 29x80 | 2x4 | 2 | 16x32 | 0.46 | 2320
nasa-occupancy-v1 | tarantula-spitzer-3color | 1280x720 | 160x90 | 20x80 | 2x4 | 2 | 16x32 | 3.00 | 1600

## ASKI-52 AC#1 — convention delta (production vs position-faithful vocabulary)
corpus | charset | oracle | cells | glyphs | prod | faithful | improve% | differ% | inkΔ(prod) | inkΔ(faithful) | maxInkΔ
nasa-steerable-v1 | blocks | mae | 8640 | 8 | 0.66651 | 0.35167 | 47.24 | 42.7 | 0.5979 | 0.2786 | 0.8432
nasa-steerable-v1 | standard | mae | 8640 | 95 | 0.22860 | 0.23105 | -1.07 | 42.0 | 0.1717 | 0.1697 | 0.4926
nasa-steerable-v1 | braille | mae | 8640 | 256 | 0.23846 | 0.25284 | -6.03 | 96.2 | 0.1279 | 0.1406 | 0.3762
nasa-occupancy-v1 | blocks | mae | 66880 | 8 | 0.65714 | 0.39669 | 39.63 | 40.7 | 0.5806 | 0.3074 | 1.0000
nasa-occupancy-v1 | standard | mae | 66880 | 95 | 0.36692 | 0.37125 | -1.18 | 54.8 | 0.3135 | 0.3107 | 0.7794
nasa-occupancy-v1 | braille | mae | 66880 | 256 | 0.35285 | 0.34897 | 1.10 | 77.2 | 0.2455 | 0.2404 | 0.7131
nasa-steerable-v1 | blocks | rmse | 8640 | 8 | 0.70401 | 0.37132 | 47.26 | 42.7 | 0.5979 | 0.2786 | 0.8432
nasa-steerable-v1 | standard | rmse | 8640 | 95 | 0.24235 | 0.25200 | -3.98 | 42.0 | 0.1717 | 0.1697 | 0.4926
nasa-steerable-v1 | braille | rmse | 8640 | 256 | 0.26162 | 0.32396 | -23.83 | 96.2 | 0.1279 | 0.1406 | 0.3762
nasa-occupancy-v1 | blocks | rmse | 66880 | 8 | 0.69640 | 0.46321 | 33.48 | 40.7 | 0.5806 | 0.3074 | 1.0000
nasa-occupancy-v1 | standard | rmse | 66880 | 95 | 0.39922 | 0.41735 | -4.54 | 54.8 | 0.3135 | 0.3107 | 0.7794
nasa-occupancy-v1 | braille | rmse | 66880 | 256 | 0.41103 | 0.41678 | -1.40 | 77.2 | 0.2455 | 0.2404 | 0.7131
nasa-steerable-v1 | blocks | ssim | 8640 | 8 | 0.00395 | 0.30673 | 7660.12 | 42.7 | 0.5979 | 0.2786 | 0.8432
nasa-steerable-v1 | standard | ssim | 8640 | 95 | 0.30793 | 0.30938 | 0.47 | 42.0 | 0.1717 | 0.1697 | 0.4926
nasa-steerable-v1 | braille | ssim | 8640 | 256 | 0.30590 | 0.02774 | -90.93 | 96.2 | 0.1279 | 0.1406 | 0.3762
nasa-occupancy-v1 | blocks | ssim | 66880 | 8 | 0.00499 | 0.10457 | 1997.02 | 40.7 | 0.5806 | 0.3074 | 1.0000
nasa-occupancy-v1 | standard | ssim | 66880 | 95 | 0.10429 | 0.10516 | 0.84 | 54.8 | 0.3135 | 0.3107 | 0.7794
nasa-occupancy-v1 | braille | ssim | 66880 | 256 | 0.10052 | 0.07272 | -27.65 | 77.2 | 0.2455 | 0.2404 | 0.7131
nasa-steerable-v1 | blocks | gmsd | 8640 | 8 | 0.29523 | 0.18986 | 35.69 | 42.7 | 0.5979 | 0.2786 | 0.8432
nasa-steerable-v1 | standard | gmsd | 8640 | 95 | 0.20801 | 0.20465 | 1.62 | 42.0 | 0.1717 | 0.1697 | 0.4926
nasa-steerable-v1 | braille | gmsd | 8640 | 256 | 0.21198 | 0.31094 | -46.69 | 96.2 | 0.1279 | 0.1406 | 0.3762
nasa-occupancy-v1 | blocks | gmsd | 66880 | 8 | 0.25943 | 0.25966 | -0.09 | 40.7 | 0.5806 | 0.3074 | 1.0000
nasa-occupancy-v1 | standard | gmsd | 66880 | 95 | 0.29889 | 0.30960 | -3.58 | 54.8 | 0.3135 | 0.3107 | 0.7794
nasa-occupancy-v1 | braille | gmsd | 66880 | 256 | 0.25419 | 0.26197 | -3.06 | 77.2 | 0.2455 | 0.2404 | 0.7131
nasa-steerable-v1 | blocks | haarPSI | 8640 | 8 | 0.15399 | 0.45149 | 193.19 | 42.7 | 0.5979 | 0.2786 | 0.8432
nasa-steerable-v1 | standard | haarPSI | 8640 | 95 | 0.37808 | 0.37583 | -0.60 | 42.0 | 0.1717 | 0.1697 | 0.4926
nasa-steerable-v1 | braille | haarPSI | 8640 | 256 | 0.38143 | 0.09051 | -76.27 | 96.2 | 0.1279 | 0.1406 | 0.3762
nasa-occupancy-v1 | blocks | haarPSI | 66880 | 8 | 0.23542 | 0.28653 | 21.71 | 40.7 | 0.5806 | 0.3074 | 1.0000
nasa-occupancy-v1 | standard | haarPSI | 66880 | 95 | 0.18320 | 0.18312 | -0.04 | 54.8 | 0.3135 | 0.3107 | 0.7794
nasa-occupancy-v1 | braille | haarPSI | 66880 | 256 | 0.18462 | 0.13629 | -26.18 | 77.2 | 0.2455 | 0.2404 | 0.7131

## ASKI-26 AC#2 — ablation ladder (query and candidate sampled identically)
corpus | charset | arm | oracle | cells | cand | dim | win | mean | vsSquare% | prodAgree% | meanInkΔ
nasa-steerable-v1 | blocks | squareSingleDisc | mae | 8640 | 64x64 | 60 | 1 | 0.36031 | 0.00 | 62.2 | 0.2923
nasa-steerable-v1 | blocks | rectSingleDisc | mae | 8640 | 12x24 | 60 | 1 | 0.34632 | 3.88 | 51.0 | 0.2559
nasa-steerable-v1 | blocks | faithfulSingleDisc | mae | 8640 | 12x24 | 60 | 1 | 0.35167 | 2.40 | 57.3 | 0.2786
nasa-steerable-v1 | blocks | faithfulTiled | mae | 8640 | 12x24 | 4320 | 72 | 0.35600 | 1.20 | 59.5 | 0.2869
nasa-steerable-v1 | blocks | faithfulTiledNoBlur | mae | 8640 | 12x24 | 4320 | 72 | 0.36518 | -1.35 | 62.3 | 0.2966
nasa-steerable-v1 | standard | squareSingleDisc | mae | 8640 | 64x64 | 60 | 1 | 0.23083 | 0.00 | 76.9 | 0.1704
nasa-steerable-v1 | standard | rectSingleDisc | mae | 8640 | 12x24 | 60 | 1 | 0.23253 | -0.74 | 53.1 | 0.1689
nasa-steerable-v1 | standard | faithfulSingleDisc | mae | 8640 | 12x24 | 60 | 1 | 0.23105 | -0.09 | 58.0 | 0.1697
nasa-steerable-v1 | standard | faithfulTiled | mae | 8640 | 12x24 | 4320 | 72 | 0.22705 | 1.64 | 54.5 | 0.1688
nasa-steerable-v1 | standard | faithfulTiledNoBlur | mae | 8640 | 12x24 | 4320 | 72 | 0.22602 | 2.08 | 54.8 | 0.1684
nasa-steerable-v1 | braille | squareSingleDisc | mae | 8640 | 64x64 | 60 | 1 | 0.23704 | 0.00 | 35.5 | 0.1282
nasa-steerable-v1 | braille | rectSingleDisc | mae | 8640 | 12x24 | 60 | 1 | 0.25284 | -6.67 | 3.8 | 0.1406
nasa-steerable-v1 | braille | faithfulSingleDisc | mae | 8640 | 12x24 | 60 | 1 | 0.25284 | -6.67 | 3.8 | 0.1406
nasa-steerable-v1 | braille | faithfulTiled | mae | 8640 | 12x24 | 4320 | 72 | 0.23615 | 0.38 | 35.9 | 0.1281
nasa-steerable-v1 | braille | faithfulTiledNoBlur | mae | 8640 | 12x24 | 4320 | 72 | 0.23639 | 0.28 | 36.2 | 0.1280
nasa-occupancy-v1 | blocks | squareSingleDisc | mae | 66880 | 64x64 | 60 | 1 | 0.40970 | 0.00 | 66.9 | 0.3283
nasa-occupancy-v1 | blocks | rectSingleDisc | mae | 66880 | 12x24 | 60 | 1 | 0.39364 | 3.92 | 51.3 | 0.2855
nasa-occupancy-v1 | blocks | faithfulSingleDisc | mae | 66880 | 12x24 | 60 | 1 | 0.39669 | 3.17 | 59.3 | 0.3074
nasa-occupancy-v1 | blocks | faithfulTiled | mae | 66880 | 12x24 | 4320 | 72 | 0.39896 | 2.62 | 62.9 | 0.3156
nasa-occupancy-v1 | blocks | faithfulTiledNoBlur | mae | 66880 | 12x24 | 4320 | 72 | 0.41161 | -0.47 | 66.4 | 0.3292
nasa-occupancy-v1 | standard | squareSingleDisc | mae | 66880 | 64x64 | 60 | 1 | 0.36817 | 0.00 | 81.5 | 0.3143
nasa-occupancy-v1 | standard | rectSingleDisc | mae | 66880 | 12x24 | 60 | 1 | 0.37112 | -0.80 | 36.9 | 0.3097
nasa-occupancy-v1 | standard | faithfulSingleDisc | mae | 66880 | 12x24 | 60 | 1 | 0.37125 | -0.84 | 45.2 | 0.3107
nasa-occupancy-v1 | standard | faithfulTiled | mae | 66880 | 12x24 | 4320 | 72 | 0.36746 | 0.19 | 34.2 | 0.3100
nasa-occupancy-v1 | standard | faithfulTiledNoBlur | mae | 66880 | 12x24 | 4320 | 72 | 0.36503 | 0.85 | 53.9 | 0.3085
nasa-occupancy-v1 | braille | squareSingleDisc | mae | 66880 | 64x64 | 60 | 1 | 0.34379 | 0.00 | 33.6 | 0.2392
nasa-occupancy-v1 | braille | rectSingleDisc | mae | 66880 | 12x24 | 60 | 1 | 0.34897 | -1.51 | 22.8 | 0.2404
nasa-occupancy-v1 | braille | faithfulSingleDisc | mae | 66880 | 12x24 | 60 | 1 | 0.34897 | -1.51 | 22.8 | 0.2404
nasa-occupancy-v1 | braille | faithfulTiled | mae | 66880 | 12x24 | 4320 | 72 | 0.34254 | 0.36 | 30.2 | 0.2390
nasa-occupancy-v1 | braille | faithfulTiledNoBlur | mae | 66880 | 12x24 | 4320 | 72 | 0.34300 | 0.23 | 31.8 | 0.2391
nasa-steerable-v1 | blocks | squareSingleDisc | rmse | 8640 | 64x64 | 60 | 1 | 0.37466 | 0.00 | 62.2 | 0.2923
nasa-steerable-v1 | blocks | rectSingleDisc | rmse | 8640 | 12x24 | 60 | 1 | 0.36541 | 2.47 | 51.0 | 0.2559
nasa-steerable-v1 | blocks | faithfulSingleDisc | rmse | 8640 | 12x24 | 60 | 1 | 0.37132 | 0.89 | 57.3 | 0.2786
nasa-steerable-v1 | blocks | faithfulTiled | rmse | 8640 | 12x24 | 4320 | 72 | 0.37458 | 0.02 | 59.5 | 0.2869
nasa-steerable-v1 | blocks | faithfulTiledNoBlur | rmse | 8640 | 12x24 | 4320 | 72 | 0.38282 | -2.18 | 62.3 | 0.2966
nasa-steerable-v1 | standard | squareSingleDisc | rmse | 8640 | 64x64 | 60 | 1 | 0.24815 | 0.00 | 76.9 | 0.1704
nasa-steerable-v1 | standard | rectSingleDisc | rmse | 8640 | 12x24 | 60 | 1 | 0.25199 | -1.55 | 53.1 | 0.1689
nasa-steerable-v1 | standard | faithfulSingleDisc | rmse | 8640 | 12x24 | 60 | 1 | 0.25200 | -1.55 | 58.0 | 0.1697
nasa-steerable-v1 | standard | faithfulTiled | rmse | 8640 | 12x24 | 4320 | 72 | 0.24267 | 2.21 | 54.5 | 0.1688
nasa-steerable-v1 | standard | faithfulTiledNoBlur | rmse | 8640 | 12x24 | 4320 | 72 | 0.24177 | 2.57 | 54.8 | 0.1684
nasa-steerable-v1 | braille | squareSingleDisc | rmse | 8640 | 64x64 | 60 | 1 | 0.26127 | 0.00 | 35.5 | 0.1282
nasa-steerable-v1 | braille | rectSingleDisc | rmse | 8640 | 12x24 | 60 | 1 | 0.32396 | -24.00 | 3.8 | 0.1406
nasa-steerable-v1 | braille | faithfulSingleDisc | rmse | 8640 | 12x24 | 60 | 1 | 0.32396 | -24.00 | 3.8 | 0.1406
nasa-steerable-v1 | braille | faithfulTiled | rmse | 8640 | 12x24 | 4320 | 72 | 0.25980 | 0.56 | 35.9 | 0.1281
nasa-steerable-v1 | braille | faithfulTiledNoBlur | rmse | 8640 | 12x24 | 4320 | 72 | 0.25952 | 0.67 | 36.2 | 0.1280
nasa-occupancy-v1 | blocks | squareSingleDisc | rmse | 66880 | 64x64 | 60 | 1 | 0.47077 | 0.00 | 66.9 | 0.3283
nasa-occupancy-v1 | blocks | rectSingleDisc | rmse | 66880 | 12x24 | 60 | 1 | 0.46031 | 2.22 | 51.3 | 0.2855
nasa-occupancy-v1 | blocks | faithfulSingleDisc | rmse | 66880 | 12x24 | 60 | 1 | 0.46321 | 1.61 | 59.3 | 0.3074
nasa-occupancy-v1 | blocks | faithfulTiled | rmse | 66880 | 12x24 | 4320 | 72 | 0.46365 | 1.51 | 62.9 | 0.3156
nasa-occupancy-v1 | blocks | faithfulTiledNoBlur | rmse | 66880 | 12x24 | 4320 | 72 | 0.47662 | -1.24 | 66.4 | 0.3292
nasa-occupancy-v1 | standard | squareSingleDisc | rmse | 66880 | 64x64 | 60 | 1 | 0.40284 | 0.00 | 81.5 | 0.3143
nasa-occupancy-v1 | standard | rectSingleDisc | rmse | 66880 | 12x24 | 60 | 1 | 0.41056 | -1.92 | 36.9 | 0.3097
nasa-occupancy-v1 | standard | faithfulSingleDisc | rmse | 66880 | 12x24 | 60 | 1 | 0.41735 | -3.60 | 45.2 | 0.3107
nasa-occupancy-v1 | standard | faithfulTiled | rmse | 66880 | 12x24 | 4320 | 72 | 0.40209 | 0.19 | 34.2 | 0.3100
nasa-occupancy-v1 | standard | faithfulTiledNoBlur | rmse | 66880 | 12x24 | 4320 | 72 | 0.40019 | 0.66 | 53.9 | 0.3085
nasa-occupancy-v1 | braille | squareSingleDisc | rmse | 66880 | 64x64 | 60 | 1 | 0.40385 | 0.00 | 33.6 | 0.2392
nasa-occupancy-v1 | braille | rectSingleDisc | rmse | 66880 | 12x24 | 60 | 1 | 0.41678 | -3.20 | 22.8 | 0.2404
nasa-occupancy-v1 | braille | faithfulSingleDisc | rmse | 66880 | 12x24 | 60 | 1 | 0.41678 | -3.20 | 22.8 | 0.2404
nasa-occupancy-v1 | braille | faithfulTiled | rmse | 66880 | 12x24 | 4320 | 72 | 0.40197 | 0.47 | 30.2 | 0.2390
nasa-occupancy-v1 | braille | faithfulTiledNoBlur | rmse | 66880 | 12x24 | 4320 | 72 | 0.40238 | 0.37 | 31.8 | 0.2391
nasa-steerable-v1 | blocks | squareSingleDisc | ssim | 8640 | 64x64 | 60 | 1 | 0.30335 | 0.00 | 62.2 | 0.2923
nasa-steerable-v1 | blocks | rectSingleDisc | ssim | 8640 | 12x24 | 60 | 1 | 0.30378 | 0.14 | 51.0 | 0.2559
nasa-steerable-v1 | blocks | faithfulSingleDisc | ssim | 8640 | 12x24 | 60 | 1 | 0.30673 | 1.11 | 57.3 | 0.2786
nasa-steerable-v1 | blocks | faithfulTiled | ssim | 8640 | 12x24 | 4320 | 72 | 0.30641 | 1.01 | 59.5 | 0.2869
nasa-steerable-v1 | blocks | faithfulTiledNoBlur | ssim | 8640 | 12x24 | 4320 | 72 | 0.30509 | 0.57 | 62.3 | 0.2966
nasa-steerable-v1 | standard | squareSingleDisc | ssim | 8640 | 64x64 | 60 | 1 | 0.30674 | 0.00 | 76.9 | 0.1704
nasa-steerable-v1 | standard | rectSingleDisc | ssim | 8640 | 12x24 | 60 | 1 | 0.30814 | 0.45 | 53.1 | 0.1689
nasa-steerable-v1 | standard | faithfulSingleDisc | ssim | 8640 | 12x24 | 60 | 1 | 0.30938 | 0.86 | 58.0 | 0.1697
nasa-steerable-v1 | standard | faithfulTiled | ssim | 8640 | 12x24 | 4320 | 72 | 0.31050 | 1.23 | 54.5 | 0.1688
nasa-steerable-v1 | standard | faithfulTiledNoBlur | ssim | 8640 | 12x24 | 4320 | 72 | 0.30969 | 0.96 | 54.8 | 0.1684
nasa-steerable-v1 | braille | squareSingleDisc | ssim | 8640 | 64x64 | 60 | 1 | 0.31656 | 0.00 | 35.5 | 0.1282
nasa-steerable-v1 | braille | rectSingleDisc | ssim | 8640 | 12x24 | 60 | 1 | 0.02774 | -91.24 | 3.8 | 0.1406
nasa-steerable-v1 | braille | faithfulSingleDisc | ssim | 8640 | 12x24 | 60 | 1 | 0.02774 | -91.24 | 3.8 | 0.1406
nasa-steerable-v1 | braille | faithfulTiled | ssim | 8640 | 12x24 | 4320 | 72 | 0.32339 | 2.16 | 35.9 | 0.1281
nasa-steerable-v1 | braille | faithfulTiledNoBlur | ssim | 8640 | 12x24 | 4320 | 72 | 0.32136 | 1.51 | 36.2 | 0.1280
nasa-occupancy-v1 | blocks | squareSingleDisc | ssim | 66880 | 64x64 | 60 | 1 | 0.10020 | 0.00 | 66.9 | 0.3283
nasa-occupancy-v1 | blocks | rectSingleDisc | ssim | 66880 | 12x24 | 60 | 1 | 0.10087 | 0.67 | 51.3 | 0.2855
nasa-occupancy-v1 | blocks | faithfulSingleDisc | ssim | 66880 | 12x24 | 60 | 1 | 0.10457 | 4.36 | 59.3 | 0.3074
nasa-occupancy-v1 | blocks | faithfulTiled | ssim | 66880 | 12x24 | 4320 | 72 | 0.10469 | 4.48 | 62.9 | 0.3156
nasa-occupancy-v1 | blocks | faithfulTiledNoBlur | ssim | 66880 | 12x24 | 4320 | 72 | 0.10181 | 1.61 | 66.4 | 0.3292
nasa-occupancy-v1 | standard | squareSingleDisc | ssim | 66880 | 64x64 | 60 | 1 | 0.10308 | 0.00 | 81.5 | 0.3143
nasa-occupancy-v1 | standard | rectSingleDisc | ssim | 66880 | 12x24 | 60 | 1 | 0.10418 | 1.06 | 36.9 | 0.3097
nasa-occupancy-v1 | standard | faithfulSingleDisc | ssim | 66880 | 12x24 | 60 | 1 | 0.10516 | 2.02 | 45.2 | 0.3107
nasa-occupancy-v1 | standard | faithfulTiled | ssim | 66880 | 12x24 | 4320 | 72 | 0.10915 | 5.89 | 34.2 | 0.3100
nasa-occupancy-v1 | standard | faithfulTiledNoBlur | ssim | 66880 | 12x24 | 4320 | 72 | 0.10824 | 5.01 | 53.9 | 0.3085
nasa-occupancy-v1 | braille | squareSingleDisc | ssim | 66880 | 64x64 | 60 | 1 | 0.11934 | 0.00 | 33.6 | 0.2392
nasa-occupancy-v1 | braille | rectSingleDisc | ssim | 66880 | 12x24 | 60 | 1 | 0.07272 | -39.06 | 22.8 | 0.2404
nasa-occupancy-v1 | braille | faithfulSingleDisc | ssim | 66880 | 12x24 | 60 | 1 | 0.07272 | -39.06 | 22.8 | 0.2404
nasa-occupancy-v1 | braille | faithfulTiled | ssim | 66880 | 12x24 | 4320 | 72 | 0.12701 | 6.43 | 30.2 | 0.2390
nasa-occupancy-v1 | braille | faithfulTiledNoBlur | ssim | 66880 | 12x24 | 4320 | 72 | 0.12407 | 3.96 | 31.8 | 0.2391
nasa-steerable-v1 | blocks | squareSingleDisc | gmsd | 8640 | 64x64 | 60 | 1 | 0.18861 | 0.00 | 62.2 | 0.2923
nasa-steerable-v1 | blocks | rectSingleDisc | gmsd | 8640 | 12x24 | 60 | 1 | 0.19034 | -0.92 | 51.0 | 0.2559
nasa-steerable-v1 | blocks | faithfulSingleDisc | gmsd | 8640 | 12x24 | 60 | 1 | 0.18986 | -0.66 | 57.3 | 0.2786
nasa-steerable-v1 | blocks | faithfulTiled | gmsd | 8640 | 12x24 | 4320 | 72 | 0.18943 | -0.43 | 59.5 | 0.2869
nasa-steerable-v1 | blocks | faithfulTiledNoBlur | gmsd | 8640 | 12x24 | 4320 | 72 | 0.18995 | -0.71 | 62.3 | 0.2966
nasa-steerable-v1 | standard | squareSingleDisc | gmsd | 8640 | 64x64 | 60 | 1 | 0.20541 | 0.00 | 76.9 | 0.1704
nasa-steerable-v1 | standard | rectSingleDisc | gmsd | 8640 | 12x24 | 60 | 1 | 0.20568 | -0.13 | 53.1 | 0.1689
nasa-steerable-v1 | standard | faithfulSingleDisc | gmsd | 8640 | 12x24 | 60 | 1 | 0.20465 | 0.37 | 58.0 | 0.1697
nasa-steerable-v1 | standard | faithfulTiled | gmsd | 8640 | 12x24 | 4320 | 72 | 0.21021 | -2.34 | 54.5 | 0.1688
nasa-steerable-v1 | standard | faithfulTiledNoBlur | gmsd | 8640 | 12x24 | 4320 | 72 | 0.20957 | -2.03 | 54.8 | 0.1684
nasa-steerable-v1 | braille | squareSingleDisc | gmsd | 8640 | 64x64 | 60 | 1 | 0.21063 | 0.00 | 35.5 | 0.1282
nasa-steerable-v1 | braille | rectSingleDisc | gmsd | 8640 | 12x24 | 60 | 1 | 0.31094 | -47.62 | 3.8 | 0.1406
nasa-steerable-v1 | braille | faithfulSingleDisc | gmsd | 8640 | 12x24 | 60 | 1 | 0.31094 | -47.62 | 3.8 | 0.1406
nasa-steerable-v1 | braille | faithfulTiled | gmsd | 8640 | 12x24 | 4320 | 72 | 0.21049 | 0.07 | 35.9 | 0.1281
nasa-steerable-v1 | braille | faithfulTiledNoBlur | gmsd | 8640 | 12x24 | 4320 | 72 | 0.20997 | 0.32 | 36.2 | 0.1280
nasa-occupancy-v1 | blocks | squareSingleDisc | gmsd | 66880 | 64x64 | 60 | 1 | 0.25835 | 0.00 | 66.9 | 0.3283
nasa-occupancy-v1 | blocks | rectSingleDisc | gmsd | 66880 | 12x24 | 60 | 1 | 0.26061 | -0.87 | 51.3 | 0.2855
nasa-occupancy-v1 | blocks | faithfulSingleDisc | gmsd | 66880 | 12x24 | 60 | 1 | 0.25966 | -0.51 | 59.3 | 0.3074
nasa-occupancy-v1 | blocks | faithfulTiled | gmsd | 66880 | 12x24 | 4320 | 72 | 0.25855 | -0.08 | 62.9 | 0.3156
nasa-occupancy-v1 | blocks | faithfulTiledNoBlur | gmsd | 66880 | 12x24 | 4320 | 72 | 0.26013 | -0.69 | 66.4 | 0.3292
nasa-occupancy-v1 | standard | squareSingleDisc | gmsd | 66880 | 64x64 | 60 | 1 | 0.29838 | 0.00 | 81.5 | 0.3143
nasa-occupancy-v1 | standard | rectSingleDisc | gmsd | 66880 | 12x24 | 60 | 1 | 0.30268 | -1.44 | 36.9 | 0.3097
nasa-occupancy-v1 | standard | faithfulSingleDisc | gmsd | 66880 | 12x24 | 60 | 1 | 0.30960 | -3.76 | 45.2 | 0.3107
nasa-occupancy-v1 | standard | faithfulTiled | gmsd | 66880 | 12x24 | 4320 | 72 | 0.30362 | -1.76 | 34.2 | 0.3100
nasa-occupancy-v1 | standard | faithfulTiledNoBlur | gmsd | 66880 | 12x24 | 4320 | 72 | 0.30405 | -1.90 | 53.9 | 0.3085
nasa-occupancy-v1 | braille | squareSingleDisc | gmsd | 66880 | 64x64 | 60 | 1 | 0.24358 | 0.00 | 33.6 | 0.2392
nasa-occupancy-v1 | braille | rectSingleDisc | gmsd | 66880 | 12x24 | 60 | 1 | 0.26197 | -7.55 | 22.8 | 0.2404
nasa-occupancy-v1 | braille | faithfulSingleDisc | gmsd | 66880 | 12x24 | 60 | 1 | 0.26197 | -7.55 | 22.8 | 0.2404
nasa-occupancy-v1 | braille | faithfulTiled | gmsd | 66880 | 12x24 | 4320 | 72 | 0.24339 | 0.08 | 30.2 | 0.2390
nasa-occupancy-v1 | braille | faithfulTiledNoBlur | gmsd | 66880 | 12x24 | 4320 | 72 | 0.24329 | 0.12 | 31.8 | 0.2391
nasa-steerable-v1 | blocks | squareSingleDisc | haarPSI | 8640 | 64x64 | 60 | 1 | 0.44895 | 0.00 | 62.2 | 0.2923
nasa-steerable-v1 | blocks | rectSingleDisc | haarPSI | 8640 | 12x24 | 60 | 1 | 0.44741 | -0.34 | 51.0 | 0.2559
nasa-steerable-v1 | blocks | faithfulSingleDisc | haarPSI | 8640 | 12x24 | 60 | 1 | 0.45149 | 0.56 | 57.3 | 0.2786
nasa-steerable-v1 | blocks | faithfulTiled | haarPSI | 8640 | 12x24 | 4320 | 72 | 0.45208 | 0.70 | 59.5 | 0.2869
nasa-steerable-v1 | blocks | faithfulTiledNoBlur | haarPSI | 8640 | 12x24 | 4320 | 72 | 0.45015 | 0.27 | 62.3 | 0.2966
nasa-steerable-v1 | standard | squareSingleDisc | haarPSI | 8640 | 64x64 | 60 | 1 | 0.37684 | 0.00 | 76.9 | 0.1704
nasa-steerable-v1 | standard | rectSingleDisc | haarPSI | 8640 | 12x24 | 60 | 1 | 0.37740 | 0.15 | 53.1 | 0.1689
nasa-steerable-v1 | standard | faithfulSingleDisc | haarPSI | 8640 | 12x24 | 60 | 1 | 0.37583 | -0.27 | 58.0 | 0.1697
nasa-steerable-v1 | standard | faithfulTiled | haarPSI | 8640 | 12x24 | 4320 | 72 | 0.37830 | 0.39 | 54.5 | 0.1688
nasa-steerable-v1 | standard | faithfulTiledNoBlur | haarPSI | 8640 | 12x24 | 4320 | 72 | 0.37704 | 0.06 | 54.8 | 0.1684
nasa-steerable-v1 | braille | squareSingleDisc | haarPSI | 8640 | 64x64 | 60 | 1 | 0.37102 | 0.00 | 35.5 | 0.1282
nasa-steerable-v1 | braille | rectSingleDisc | haarPSI | 8640 | 12x24 | 60 | 1 | 0.09051 | -75.61 | 3.8 | 0.1406
nasa-steerable-v1 | braille | faithfulSingleDisc | haarPSI | 8640 | 12x24 | 60 | 1 | 0.09051 | -75.61 | 3.8 | 0.1406
nasa-steerable-v1 | braille | faithfulTiled | haarPSI | 8640 | 12x24 | 4320 | 72 | 0.37460 | 0.96 | 35.9 | 0.1281
nasa-steerable-v1 | braille | faithfulTiledNoBlur | haarPSI | 8640 | 12x24 | 4320 | 72 | 0.37535 | 1.17 | 36.2 | 0.1280
nasa-occupancy-v1 | blocks | squareSingleDisc | haarPSI | 66880 | 64x64 | 60 | 1 | 0.28574 | 0.00 | 66.9 | 0.3283
nasa-occupancy-v1 | blocks | rectSingleDisc | haarPSI | 66880 | 12x24 | 60 | 1 | 0.28161 | -1.44 | 51.3 | 0.2855
nasa-occupancy-v1 | blocks | faithfulSingleDisc | haarPSI | 66880 | 12x24 | 60 | 1 | 0.28653 | 0.28 | 59.3 | 0.3074
nasa-occupancy-v1 | blocks | faithfulTiled | haarPSI | 66880 | 12x24 | 4320 | 72 | 0.28952 | 1.32 | 62.9 | 0.3156
nasa-occupancy-v1 | blocks | faithfulTiledNoBlur | haarPSI | 66880 | 12x24 | 4320 | 72 | 0.28575 | 0.00 | 66.4 | 0.3292
nasa-occupancy-v1 | standard | squareSingleDisc | haarPSI | 66880 | 64x64 | 60 | 1 | 0.18382 | 0.00 | 81.5 | 0.3143
nasa-occupancy-v1 | standard | rectSingleDisc | haarPSI | 66880 | 12x24 | 60 | 1 | 0.18085 | -1.62 | 36.9 | 0.3097
nasa-occupancy-v1 | standard | faithfulSingleDisc | haarPSI | 66880 | 12x24 | 60 | 1 | 0.18312 | -0.38 | 45.2 | 0.3107
nasa-occupancy-v1 | standard | faithfulTiled | haarPSI | 66880 | 12x24 | 4320 | 72 | 0.18341 | -0.23 | 34.2 | 0.3100
nasa-occupancy-v1 | standard | faithfulTiledNoBlur | haarPSI | 66880 | 12x24 | 4320 | 72 | 0.18152 | -1.25 | 53.9 | 0.3085
nasa-occupancy-v1 | braille | squareSingleDisc | haarPSI | 66880 | 64x64 | 60 | 1 | 0.17701 | 0.00 | 33.6 | 0.2392
nasa-occupancy-v1 | braille | rectSingleDisc | haarPSI | 66880 | 12x24 | 60 | 1 | 0.13629 | -23.01 | 22.8 | 0.2404
nasa-occupancy-v1 | braille | faithfulSingleDisc | haarPSI | 66880 | 12x24 | 60 | 1 | 0.13629 | -23.01 | 22.8 | 0.2404
nasa-occupancy-v1 | braille | faithfulTiled | haarPSI | 66880 | 12x24 | 4320 | 72 | 0.18205 | 2.85 | 30.2 | 0.2390
nasa-occupancy-v1 | braille | faithfulTiledNoBlur | haarPSI | 66880 | 12x24 | 4320 | 72 | 0.18155 | 2.57 | 31.8 | 0.2391
