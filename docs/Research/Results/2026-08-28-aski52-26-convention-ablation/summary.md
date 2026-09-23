# Candidate-convention delta and sampling-support ablation (ASKI-52 / ASKI-26)

Query polarity: **inverted**.

## Reproduce

```
swift run -c release AskiColorLab convention-ablation \
  --columns 80 --oversample 2 --footprint 24 \
  --cell-width 12 --cell-height 24 --stride 1 \
  --charset blocks,standard,braille \
  --query-polarity inverted \
  --corpus docs/Research/Corpus/nasa-steerable-v1/assets,docs/Research/Corpus/nasa-occupancy-v1/assets \
  --output-dir docs/Research/Results/2026-08-28-aski52-26-convention-ablation
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
nasa-steerable-v1 | blocks | mae | 8640 | 8 | 0.66651 | 0.66626 | 0.04 | 0.2 | 0.5979 | 0.5973 | 0.8432
nasa-steerable-v1 | standard | mae | 8640 | 95 | 0.22860 | 0.23121 | -1.14 | 41.6 | 0.1717 | 0.1693 | 0.4926
nasa-steerable-v1 | braille | mae | 8640 | 256 | 0.23846 | 0.25355 | -6.33 | 96.6 | 0.1279 | 0.1403 | 0.3762
nasa-occupancy-v1 | blocks | mae | 66880 | 8 | 0.65714 | 0.66481 | -1.17 | 7.5 | 0.5806 | 0.5812 | 1.0000
nasa-occupancy-v1 | standard | mae | 66880 | 95 | 0.36692 | 0.37316 | -1.70 | 55.9 | 0.3135 | 0.3103 | 0.7799
nasa-occupancy-v1 | braille | mae | 66880 | 256 | 0.35285 | 0.35135 | 0.43 | 78.6 | 0.2455 | 0.2410 | 0.7131
nasa-steerable-v1 | blocks | rmse | 8640 | 8 | 0.70401 | 0.70382 | 0.03 | 0.2 | 0.5979 | 0.5973 | 0.8432
nasa-steerable-v1 | standard | rmse | 8640 | 95 | 0.24235 | 0.25214 | -4.04 | 41.6 | 0.1717 | 0.1693 | 0.4926
nasa-steerable-v1 | braille | rmse | 8640 | 256 | 0.26162 | 0.32468 | -24.11 | 96.6 | 0.1279 | 0.1403 | 0.3762
nasa-occupancy-v1 | blocks | rmse | 66880 | 8 | 0.69640 | 0.70427 | -1.13 | 7.5 | 0.5806 | 0.5812 | 1.0000
nasa-occupancy-v1 | standard | rmse | 66880 | 95 | 0.39922 | 0.41900 | -4.96 | 55.9 | 0.3135 | 0.3103 | 0.7799
nasa-occupancy-v1 | braille | rmse | 66880 | 256 | 0.41103 | 0.41885 | -1.90 | 78.6 | 0.2455 | 0.2410 | 0.7131
nasa-steerable-v1 | blocks | ssim | 8640 | 8 | 0.00395 | 0.00397 | 0.48 | 0.2 | 0.5979 | 0.5973 | 0.8432
nasa-steerable-v1 | standard | ssim | 8640 | 95 | 0.30793 | 0.30658 | -0.44 | 41.6 | 0.1717 | 0.1693 | 0.4926
nasa-steerable-v1 | braille | ssim | 8640 | 256 | 0.30590 | 0.02067 | -93.24 | 96.6 | 0.1279 | 0.1403 | 0.3762
nasa-occupancy-v1 | blocks | ssim | 66880 | 8 | 0.00499 | -0.00092 | -118.48 | 7.5 | 0.5806 | 0.5812 | 1.0000
nasa-occupancy-v1 | standard | ssim | 66880 | 95 | 0.10429 | 0.09756 | -6.45 | 55.9 | 0.3135 | 0.3103 | 0.7799
nasa-occupancy-v1 | braille | ssim | 66880 | 256 | 0.10052 | 0.06335 | -36.97 | 78.6 | 0.2455 | 0.2410 | 0.7131
nasa-steerable-v1 | blocks | gmsd | 8640 | 8 | 0.29523 | 0.29524 | -0.00 | 0.2 | 0.5979 | 0.5973 | 0.8432
nasa-steerable-v1 | standard | gmsd | 8640 | 95 | 0.20801 | 0.20407 | 1.89 | 41.6 | 0.1717 | 0.1693 | 0.4926
nasa-steerable-v1 | braille | gmsd | 8640 | 256 | 0.21198 | 0.31057 | -46.51 | 96.6 | 0.1279 | 0.1403 | 0.3762
nasa-occupancy-v1 | blocks | gmsd | 66880 | 8 | 0.25943 | 0.26120 | -0.68 | 7.5 | 0.5806 | 0.5812 | 1.0000
nasa-occupancy-v1 | standard | gmsd | 66880 | 95 | 0.29889 | 0.30884 | -3.33 | 55.9 | 0.3135 | 0.3103 | 0.7799
nasa-occupancy-v1 | braille | gmsd | 66880 | 256 | 0.25419 | 0.26375 | -3.76 | 78.6 | 0.2455 | 0.2410 | 0.7131
nasa-steerable-v1 | blocks | haarPSI | 8640 | 8 | 0.15399 | 0.15395 | -0.03 | 0.2 | 0.5979 | 0.5973 | 0.8432
nasa-steerable-v1 | standard | haarPSI | 8640 | 95 | 0.37808 | 0.37524 | -0.75 | 41.6 | 0.1717 | 0.1693 | 0.4926
nasa-steerable-v1 | braille | haarPSI | 8640 | 256 | 0.38143 | 0.09004 | -76.39 | 96.6 | 0.1279 | 0.1403 | 0.3762
nasa-occupancy-v1 | blocks | haarPSI | 66880 | 8 | 0.23542 | 0.23230 | -1.33 | 7.5 | 0.5806 | 0.5812 | 1.0000
nasa-occupancy-v1 | standard | haarPSI | 66880 | 95 | 0.18320 | 0.18402 | 0.45 | 55.9 | 0.3135 | 0.3103 | 0.7799
nasa-occupancy-v1 | braille | haarPSI | 66880 | 256 | 0.18462 | 0.13636 | -26.14 | 78.6 | 0.2455 | 0.2410 | 0.7131

## ASKI-26 AC#2 — ablation ladder (query and candidate sampled identically)
corpus | charset | arm | oracle | cells | cand | dim | win | mean | vsSquare% | prodAgree% | meanInkΔ
nasa-steerable-v1 | blocks | squareSingleDisc | mae | 8640 | 64x64 | 60 | 1 | 0.66651 | 0.00 | 100.0 | 0.5979
nasa-steerable-v1 | blocks | rectSingleDisc | mae | 8640 | 12x24 | 60 | 1 | 0.66132 | 0.78 | 95.0 | 0.5817
nasa-steerable-v1 | blocks | faithfulSingleDisc | mae | 8640 | 12x24 | 60 | 1 | 0.66626 | 0.04 | 99.8 | 0.5973
nasa-steerable-v1 | blocks | faithfulTiled | mae | 8640 | 12x24 | 4320 | 72 | 0.66651 | 0.00 | 100.0 | 0.5979
nasa-steerable-v1 | blocks | faithfulTiledNoBlur | mae | 8640 | 12x24 | 4320 | 72 | 0.66651 | 0.00 | 100.0 | 0.5979
nasa-steerable-v1 | standard | squareSingleDisc | mae | 8640 | 64x64 | 60 | 1 | 0.23066 | 0.00 | 76.9 | 0.1702
nasa-steerable-v1 | standard | rectSingleDisc | mae | 8640 | 12x24 | 60 | 1 | 0.23210 | -0.63 | 54.3 | 0.1688
nasa-steerable-v1 | standard | faithfulSingleDisc | mae | 8640 | 12x24 | 60 | 1 | 0.23121 | -0.24 | 58.4 | 0.1693
nasa-steerable-v1 | standard | faithfulTiled | mae | 8640 | 12x24 | 4320 | 72 | 0.22715 | 1.52 | 55.7 | 0.1688
nasa-steerable-v1 | standard | faithfulTiledNoBlur | mae | 8640 | 12x24 | 4320 | 72 | 0.22621 | 1.93 | 55.8 | 0.1683
nasa-steerable-v1 | braille | squareSingleDisc | mae | 8640 | 64x64 | 60 | 1 | 0.23911 | 0.00 | 40.0 | 0.1279
nasa-steerable-v1 | braille | rectSingleDisc | mae | 8640 | 12x24 | 60 | 1 | 0.25355 | -6.04 | 3.4 | 0.1403
nasa-steerable-v1 | braille | faithfulSingleDisc | mae | 8640 | 12x24 | 60 | 1 | 0.25355 | -6.04 | 3.4 | 0.1403
nasa-steerable-v1 | braille | faithfulTiled | mae | 8640 | 12x24 | 4320 | 72 | 0.23954 | -0.18 | 37.1 | 0.1279
nasa-steerable-v1 | braille | faithfulTiledNoBlur | mae | 8640 | 12x24 | 4320 | 72 | 0.23918 | -0.03 | 37.5 | 0.1279
nasa-occupancy-v1 | blocks | squareSingleDisc | mae | 66880 | 64x64 | 60 | 1 | 0.65656 | 0.00 | 95.3 | 0.5801
nasa-occupancy-v1 | blocks | rectSingleDisc | mae | 66880 | 12x24 | 60 | 1 | 0.65856 | -0.30 | 85.7 | 0.5641
nasa-occupancy-v1 | blocks | faithfulSingleDisc | mae | 66880 | 12x24 | 60 | 1 | 0.66481 | -1.26 | 92.5 | 0.5812
nasa-occupancy-v1 | blocks | faithfulTiled | mae | 66880 | 12x24 | 4320 | 72 | 0.66088 | -0.66 | 93.9 | 0.5803
nasa-occupancy-v1 | blocks | faithfulTiledNoBlur | mae | 66880 | 12x24 | 4320 | 72 | 0.65829 | -0.26 | 94.5 | 0.5773
nasa-occupancy-v1 | standard | squareSingleDisc | mae | 66880 | 64x64 | 60 | 1 | 0.36799 | 0.00 | 80.7 | 0.3142
nasa-occupancy-v1 | standard | rectSingleDisc | mae | 66880 | 12x24 | 60 | 1 | 0.37163 | -0.99 | 51.3 | 0.3102
nasa-occupancy-v1 | standard | faithfulSingleDisc | mae | 66880 | 12x24 | 60 | 1 | 0.37316 | -1.40 | 44.1 | 0.3103
nasa-occupancy-v1 | standard | faithfulTiled | mae | 66880 | 12x24 | 4320 | 72 | 0.36724 | 0.20 | 36.2 | 0.3079
nasa-occupancy-v1 | standard | faithfulTiledNoBlur | mae | 66880 | 12x24 | 4320 | 72 | 0.36551 | 0.68 | 40.3 | 0.3065
nasa-occupancy-v1 | braille | squareSingleDisc | mae | 66880 | 64x64 | 60 | 1 | 0.35336 | 0.00 | 39.9 | 0.2426
nasa-occupancy-v1 | braille | rectSingleDisc | mae | 66880 | 12x24 | 60 | 1 | 0.35135 | 0.57 | 21.4 | 0.2410
nasa-occupancy-v1 | braille | faithfulSingleDisc | mae | 66880 | 12x24 | 60 | 1 | 0.35135 | 0.57 | 21.4 | 0.2410
nasa-occupancy-v1 | braille | faithfulTiled | mae | 66880 | 12x24 | 4320 | 72 | 0.35446 | -0.31 | 29.3 | 0.2428
nasa-occupancy-v1 | braille | faithfulTiledNoBlur | mae | 66880 | 12x24 | 4320 | 72 | 0.35311 | 0.07 | 32.7 | 0.2418
nasa-steerable-v1 | blocks | squareSingleDisc | rmse | 8640 | 64x64 | 60 | 1 | 0.70401 | 0.00 | 100.0 | 0.5979
nasa-steerable-v1 | blocks | rectSingleDisc | rmse | 8640 | 12x24 | 60 | 1 | 0.70007 | 0.56 | 95.0 | 0.5817
nasa-steerable-v1 | blocks | faithfulSingleDisc | rmse | 8640 | 12x24 | 60 | 1 | 0.70382 | 0.03 | 99.8 | 0.5973
nasa-steerable-v1 | blocks | faithfulTiled | rmse | 8640 | 12x24 | 4320 | 72 | 0.70401 | 0.00 | 100.0 | 0.5979
nasa-steerable-v1 | blocks | faithfulTiledNoBlur | rmse | 8640 | 12x24 | 4320 | 72 | 0.70401 | 0.00 | 100.0 | 0.5979
nasa-steerable-v1 | standard | squareSingleDisc | rmse | 8640 | 64x64 | 60 | 1 | 0.24802 | 0.00 | 76.9 | 0.1702
nasa-steerable-v1 | standard | rectSingleDisc | rmse | 8640 | 12x24 | 60 | 1 | 0.25050 | -1.00 | 54.3 | 0.1688
nasa-steerable-v1 | standard | faithfulSingleDisc | rmse | 8640 | 12x24 | 60 | 1 | 0.25214 | -1.66 | 58.4 | 0.1693
nasa-steerable-v1 | standard | faithfulTiled | rmse | 8640 | 12x24 | 4320 | 72 | 0.24187 | 2.48 | 55.7 | 0.1688
nasa-steerable-v1 | standard | faithfulTiledNoBlur | rmse | 8640 | 12x24 | 4320 | 72 | 0.24143 | 2.66 | 55.8 | 0.1683
nasa-steerable-v1 | braille | squareSingleDisc | rmse | 8640 | 64x64 | 60 | 1 | 0.26240 | 0.00 | 40.0 | 0.1279
nasa-steerable-v1 | braille | rectSingleDisc | rmse | 8640 | 12x24 | 60 | 1 | 0.32468 | -23.74 | 3.4 | 0.1403
nasa-steerable-v1 | braille | faithfulSingleDisc | rmse | 8640 | 12x24 | 60 | 1 | 0.32468 | -23.74 | 3.4 | 0.1403
nasa-steerable-v1 | braille | faithfulTiled | rmse | 8640 | 12x24 | 4320 | 72 | 0.26287 | -0.18 | 37.1 | 0.1279
nasa-steerable-v1 | braille | faithfulTiledNoBlur | rmse | 8640 | 12x24 | 4320 | 72 | 0.26246 | -0.02 | 37.5 | 0.1279
nasa-occupancy-v1 | blocks | squareSingleDisc | rmse | 66880 | 64x64 | 60 | 1 | 0.69603 | 0.00 | 95.3 | 0.5801
nasa-occupancy-v1 | blocks | rectSingleDisc | rmse | 66880 | 12x24 | 60 | 1 | 0.69908 | -0.44 | 85.7 | 0.5641
nasa-occupancy-v1 | blocks | faithfulSingleDisc | rmse | 66880 | 12x24 | 60 | 1 | 0.70427 | -1.18 | 92.5 | 0.5812
nasa-occupancy-v1 | blocks | faithfulTiled | rmse | 66880 | 12x24 | 4320 | 72 | 0.70123 | -0.75 | 93.9 | 0.5803
nasa-occupancy-v1 | blocks | faithfulTiledNoBlur | rmse | 66880 | 12x24 | 4320 | 72 | 0.69930 | -0.47 | 94.5 | 0.5773
nasa-occupancy-v1 | standard | squareSingleDisc | rmse | 66880 | 64x64 | 60 | 1 | 0.40257 | 0.00 | 80.7 | 0.3142
nasa-occupancy-v1 | standard | rectSingleDisc | rmse | 66880 | 12x24 | 60 | 1 | 0.40869 | -1.52 | 51.3 | 0.3102
nasa-occupancy-v1 | standard | faithfulSingleDisc | rmse | 66880 | 12x24 | 60 | 1 | 0.41900 | -4.08 | 44.1 | 0.3103
nasa-occupancy-v1 | standard | faithfulTiled | rmse | 66880 | 12x24 | 4320 | 72 | 0.40168 | 0.22 | 36.2 | 0.3079
nasa-occupancy-v1 | standard | faithfulTiledNoBlur | rmse | 66880 | 12x24 | 4320 | 72 | 0.40000 | 0.64 | 40.3 | 0.3065
nasa-occupancy-v1 | braille | squareSingleDisc | rmse | 66880 | 64x64 | 60 | 1 | 0.41204 | 0.00 | 39.9 | 0.2426
nasa-occupancy-v1 | braille | rectSingleDisc | rmse | 66880 | 12x24 | 60 | 1 | 0.41885 | -1.65 | 21.4 | 0.2410
nasa-occupancy-v1 | braille | faithfulSingleDisc | rmse | 66880 | 12x24 | 60 | 1 | 0.41885 | -1.65 | 21.4 | 0.2410
nasa-occupancy-v1 | braille | faithfulTiled | rmse | 66880 | 12x24 | 4320 | 72 | 0.41313 | -0.26 | 29.3 | 0.2428
nasa-occupancy-v1 | braille | faithfulTiledNoBlur | rmse | 66880 | 12x24 | 4320 | 72 | 0.41198 | 0.01 | 32.7 | 0.2418
nasa-steerable-v1 | blocks | squareSingleDisc | ssim | 8640 | 64x64 | 60 | 1 | 0.00395 | 0.00 | 100.0 | 0.5979
nasa-steerable-v1 | blocks | rectSingleDisc | ssim | 8640 | 12x24 | 60 | 1 | 0.00321 | -18.88 | 95.0 | 0.5817
nasa-steerable-v1 | blocks | faithfulSingleDisc | ssim | 8640 | 12x24 | 60 | 1 | 0.00397 | 0.48 | 99.8 | 0.5973
nasa-steerable-v1 | blocks | faithfulTiled | ssim | 8640 | 12x24 | 4320 | 72 | 0.00395 | 0.00 | 100.0 | 0.5979
nasa-steerable-v1 | blocks | faithfulTiledNoBlur | ssim | 8640 | 12x24 | 4320 | 72 | 0.00395 | 0.00 | 100.0 | 0.5979
nasa-steerable-v1 | standard | squareSingleDisc | ssim | 8640 | 64x64 | 60 | 1 | 0.30763 | 0.00 | 76.9 | 0.1702
nasa-steerable-v1 | standard | rectSingleDisc | ssim | 8640 | 12x24 | 60 | 1 | 0.30653 | -0.36 | 54.3 | 0.1688
nasa-steerable-v1 | standard | faithfulSingleDisc | ssim | 8640 | 12x24 | 60 | 1 | 0.30658 | -0.34 | 58.4 | 0.1693
nasa-steerable-v1 | standard | faithfulTiled | ssim | 8640 | 12x24 | 4320 | 72 | 0.30607 | -0.51 | 55.7 | 0.1688
nasa-steerable-v1 | standard | faithfulTiledNoBlur | ssim | 8640 | 12x24 | 4320 | 72 | 0.30672 | -0.30 | 55.8 | 0.1683
nasa-steerable-v1 | braille | squareSingleDisc | ssim | 8640 | 64x64 | 60 | 1 | 0.30157 | 0.00 | 40.0 | 0.1279
nasa-steerable-v1 | braille | rectSingleDisc | ssim | 8640 | 12x24 | 60 | 1 | 0.02067 | -93.15 | 3.4 | 0.1403
nasa-steerable-v1 | braille | faithfulSingleDisc | ssim | 8640 | 12x24 | 60 | 1 | 0.02067 | -93.15 | 3.4 | 0.1403
nasa-steerable-v1 | braille | faithfulTiled | ssim | 8640 | 12x24 | 4320 | 72 | 0.29898 | -0.86 | 37.1 | 0.1279
nasa-steerable-v1 | braille | faithfulTiledNoBlur | ssim | 8640 | 12x24 | 4320 | 72 | 0.30104 | -0.17 | 37.5 | 0.1279
nasa-occupancy-v1 | blocks | squareSingleDisc | ssim | 66880 | 64x64 | 60 | 1 | 0.00633 | 0.00 | 95.3 | 0.5801
nasa-occupancy-v1 | blocks | rectSingleDisc | ssim | 66880 | 12x24 | 60 | 1 | 0.00504 | -20.40 | 85.7 | 0.5641
nasa-occupancy-v1 | blocks | faithfulSingleDisc | ssim | 66880 | 12x24 | 60 | 1 | -0.00092 | -114.55 | 92.5 | 0.5812
nasa-occupancy-v1 | blocks | faithfulTiled | ssim | 66880 | 12x24 | 4320 | 72 | -0.00242 | -138.15 | 93.9 | 0.5803
nasa-occupancy-v1 | blocks | faithfulTiledNoBlur | ssim | 66880 | 12x24 | 4320 | 72 | -0.00231 | -136.44 | 94.5 | 0.5773
nasa-occupancy-v1 | standard | squareSingleDisc | ssim | 66880 | 64x64 | 60 | 1 | 0.10386 | 0.00 | 80.7 | 0.3142
nasa-occupancy-v1 | standard | rectSingleDisc | ssim | 66880 | 12x24 | 60 | 1 | 0.10159 | -2.19 | 51.3 | 0.3102
nasa-occupancy-v1 | standard | faithfulSingleDisc | ssim | 66880 | 12x24 | 60 | 1 | 0.09756 | -6.06 | 44.1 | 0.3103
nasa-occupancy-v1 | standard | faithfulTiled | ssim | 66880 | 12x24 | 4320 | 72 | 0.09769 | -5.94 | 36.2 | 0.3079
nasa-occupancy-v1 | standard | faithfulTiledNoBlur | ssim | 66880 | 12x24 | 4320 | 72 | 0.09834 | -5.32 | 40.3 | 0.3065
nasa-occupancy-v1 | braille | squareSingleDisc | ssim | 66880 | 64x64 | 60 | 1 | 0.08707 | 0.00 | 39.9 | 0.2426
nasa-occupancy-v1 | braille | rectSingleDisc | ssim | 66880 | 12x24 | 60 | 1 | 0.06335 | -27.24 | 21.4 | 0.2410
nasa-occupancy-v1 | braille | faithfulSingleDisc | ssim | 66880 | 12x24 | 60 | 1 | 0.06335 | -27.24 | 21.4 | 0.2410
nasa-occupancy-v1 | braille | faithfulTiled | ssim | 66880 | 12x24 | 4320 | 72 | 0.08223 | -5.56 | 29.3 | 0.2428
nasa-occupancy-v1 | braille | faithfulTiledNoBlur | ssim | 66880 | 12x24 | 4320 | 72 | 0.08405 | -3.47 | 32.7 | 0.2418
nasa-steerable-v1 | blocks | squareSingleDisc | gmsd | 8640 | 64x64 | 60 | 1 | 0.29523 | 0.00 | 100.0 | 0.5979
nasa-steerable-v1 | blocks | rectSingleDisc | gmsd | 8640 | 12x24 | 60 | 1 | 0.29644 | -0.41 | 95.0 | 0.5817
nasa-steerable-v1 | blocks | faithfulSingleDisc | gmsd | 8640 | 12x24 | 60 | 1 | 0.29524 | -0.00 | 99.8 | 0.5973
nasa-steerable-v1 | blocks | faithfulTiled | gmsd | 8640 | 12x24 | 4320 | 72 | 0.29523 | 0.00 | 100.0 | 0.5979
nasa-steerable-v1 | blocks | faithfulTiledNoBlur | gmsd | 8640 | 12x24 | 4320 | 72 | 0.29523 | 0.00 | 100.0 | 0.5979
nasa-steerable-v1 | standard | squareSingleDisc | gmsd | 8640 | 64x64 | 60 | 1 | 0.20497 | 0.00 | 76.9 | 0.1702
nasa-steerable-v1 | standard | rectSingleDisc | gmsd | 8640 | 12x24 | 60 | 1 | 0.20478 | 0.09 | 54.3 | 0.1688
nasa-steerable-v1 | standard | faithfulSingleDisc | gmsd | 8640 | 12x24 | 60 | 1 | 0.20407 | 0.44 | 58.4 | 0.1693
nasa-steerable-v1 | standard | faithfulTiled | gmsd | 8640 | 12x24 | 4320 | 72 | 0.20980 | -2.36 | 55.7 | 0.1688
nasa-steerable-v1 | standard | faithfulTiledNoBlur | gmsd | 8640 | 12x24 | 4320 | 72 | 0.20932 | -2.12 | 55.8 | 0.1683
nasa-steerable-v1 | braille | squareSingleDisc | gmsd | 8640 | 64x64 | 60 | 1 | 0.20995 | 0.00 | 40.0 | 0.1279
nasa-steerable-v1 | braille | rectSingleDisc | gmsd | 8640 | 12x24 | 60 | 1 | 0.31057 | -47.93 | 3.4 | 0.1403
nasa-steerable-v1 | braille | faithfulSingleDisc | gmsd | 8640 | 12x24 | 60 | 1 | 0.31057 | -47.93 | 3.4 | 0.1403
nasa-steerable-v1 | braille | faithfulTiled | gmsd | 8640 | 12x24 | 4320 | 72 | 0.21046 | -0.24 | 37.1 | 0.1279
nasa-steerable-v1 | braille | faithfulTiledNoBlur | gmsd | 8640 | 12x24 | 4320 | 72 | 0.20998 | -0.01 | 37.5 | 0.1279
nasa-occupancy-v1 | blocks | squareSingleDisc | gmsd | 66880 | 64x64 | 60 | 1 | 0.26028 | 0.00 | 95.3 | 0.5801
nasa-occupancy-v1 | blocks | rectSingleDisc | gmsd | 66880 | 12x24 | 60 | 1 | 0.26203 | -0.67 | 85.7 | 0.5641
nasa-occupancy-v1 | blocks | faithfulSingleDisc | gmsd | 66880 | 12x24 | 60 | 1 | 0.26120 | -0.35 | 92.5 | 0.5812
nasa-occupancy-v1 | blocks | faithfulTiled | gmsd | 66880 | 12x24 | 4320 | 72 | 0.26133 | -0.41 | 93.9 | 0.5803
nasa-occupancy-v1 | blocks | faithfulTiledNoBlur | gmsd | 66880 | 12x24 | 4320 | 72 | 0.26174 | -0.56 | 94.5 | 0.5773
nasa-occupancy-v1 | standard | squareSingleDisc | gmsd | 66880 | 64x64 | 60 | 1 | 0.29796 | 0.00 | 80.7 | 0.3142
nasa-occupancy-v1 | standard | rectSingleDisc | gmsd | 66880 | 12x24 | 60 | 1 | 0.30068 | -0.91 | 51.3 | 0.3102
nasa-occupancy-v1 | standard | faithfulSingleDisc | gmsd | 66880 | 12x24 | 60 | 1 | 0.30884 | -3.65 | 44.1 | 0.3103
nasa-occupancy-v1 | standard | faithfulTiled | gmsd | 66880 | 12x24 | 4320 | 72 | 0.30229 | -1.45 | 36.2 | 0.3079
nasa-occupancy-v1 | standard | faithfulTiledNoBlur | gmsd | 66880 | 12x24 | 4320 | 72 | 0.30261 | -1.56 | 40.3 | 0.3065
nasa-occupancy-v1 | braille | squareSingleDisc | gmsd | 66880 | 64x64 | 60 | 1 | 0.25030 | 0.00 | 39.9 | 0.2426
nasa-occupancy-v1 | braille | rectSingleDisc | gmsd | 66880 | 12x24 | 60 | 1 | 0.26375 | -5.37 | 21.4 | 0.2410
nasa-occupancy-v1 | braille | faithfulSingleDisc | gmsd | 66880 | 12x24 | 60 | 1 | 0.26375 | -5.37 | 21.4 | 0.2410
nasa-occupancy-v1 | braille | faithfulTiled | gmsd | 66880 | 12x24 | 4320 | 72 | 0.25071 | -0.17 | 29.3 | 0.2428
nasa-occupancy-v1 | braille | faithfulTiledNoBlur | gmsd | 66880 | 12x24 | 4320 | 72 | 0.24812 | 0.87 | 32.7 | 0.2418
nasa-steerable-v1 | blocks | squareSingleDisc | haarPSI | 8640 | 64x64 | 60 | 1 | 0.15399 | 0.00 | 100.0 | 0.5979
nasa-steerable-v1 | blocks | rectSingleDisc | haarPSI | 8640 | 12x24 | 60 | 1 | 0.15090 | -2.01 | 95.0 | 0.5817
nasa-steerable-v1 | blocks | faithfulSingleDisc | haarPSI | 8640 | 12x24 | 60 | 1 | 0.15395 | -0.03 | 99.8 | 0.5973
nasa-steerable-v1 | blocks | faithfulTiled | haarPSI | 8640 | 12x24 | 4320 | 72 | 0.15399 | 0.00 | 100.0 | 0.5979
nasa-steerable-v1 | blocks | faithfulTiledNoBlur | haarPSI | 8640 | 12x24 | 4320 | 72 | 0.15399 | 0.00 | 100.0 | 0.5979
nasa-steerable-v1 | standard | squareSingleDisc | haarPSI | 8640 | 64x64 | 60 | 1 | 0.37696 | 0.00 | 76.9 | 0.1702
nasa-steerable-v1 | standard | rectSingleDisc | haarPSI | 8640 | 12x24 | 60 | 1 | 0.37756 | 0.16 | 54.3 | 0.1688
nasa-steerable-v1 | standard | faithfulSingleDisc | haarPSI | 8640 | 12x24 | 60 | 1 | 0.37524 | -0.46 | 58.4 | 0.1693
nasa-steerable-v1 | standard | faithfulTiled | haarPSI | 8640 | 12x24 | 4320 | 72 | 0.37809 | 0.30 | 55.7 | 0.1688
nasa-steerable-v1 | standard | faithfulTiledNoBlur | haarPSI | 8640 | 12x24 | 4320 | 72 | 0.37737 | 0.11 | 55.8 | 0.1683
nasa-steerable-v1 | braille | squareSingleDisc | haarPSI | 8640 | 64x64 | 60 | 1 | 0.37288 | 0.00 | 40.0 | 0.1279
nasa-steerable-v1 | braille | rectSingleDisc | haarPSI | 8640 | 12x24 | 60 | 1 | 0.09004 | -75.85 | 3.4 | 0.1403
nasa-steerable-v1 | braille | faithfulSingleDisc | haarPSI | 8640 | 12x24 | 60 | 1 | 0.09004 | -75.85 | 3.4 | 0.1403
nasa-steerable-v1 | braille | faithfulTiled | haarPSI | 8640 | 12x24 | 4320 | 72 | 0.37401 | 0.30 | 37.1 | 0.1279
nasa-steerable-v1 | braille | faithfulTiledNoBlur | haarPSI | 8640 | 12x24 | 4320 | 72 | 0.37437 | 0.40 | 37.5 | 0.1279
nasa-occupancy-v1 | blocks | squareSingleDisc | haarPSI | 66880 | 64x64 | 60 | 1 | 0.23494 | 0.00 | 95.3 | 0.5801
nasa-occupancy-v1 | blocks | rectSingleDisc | haarPSI | 66880 | 12x24 | 60 | 1 | 0.22875 | -2.64 | 85.7 | 0.5641
nasa-occupancy-v1 | blocks | faithfulSingleDisc | haarPSI | 66880 | 12x24 | 60 | 1 | 0.23230 | -1.13 | 92.5 | 0.5812
nasa-occupancy-v1 | blocks | faithfulTiled | haarPSI | 66880 | 12x24 | 4320 | 72 | 0.23461 | -0.14 | 93.9 | 0.5803
nasa-occupancy-v1 | blocks | faithfulTiledNoBlur | haarPSI | 66880 | 12x24 | 4320 | 72 | 0.23483 | -0.05 | 94.5 | 0.5773
nasa-occupancy-v1 | standard | squareSingleDisc | haarPSI | 66880 | 64x64 | 60 | 1 | 0.18432 | 0.00 | 80.7 | 0.3142
nasa-occupancy-v1 | standard | rectSingleDisc | haarPSI | 66880 | 12x24 | 60 | 1 | 0.18180 | -1.37 | 51.3 | 0.3102
nasa-occupancy-v1 | standard | faithfulSingleDisc | haarPSI | 66880 | 12x24 | 60 | 1 | 0.18402 | -0.16 | 44.1 | 0.3103
nasa-occupancy-v1 | standard | faithfulTiled | haarPSI | 66880 | 12x24 | 4320 | 72 | 0.18705 | 1.48 | 36.2 | 0.3079
nasa-occupancy-v1 | standard | faithfulTiledNoBlur | haarPSI | 66880 | 12x24 | 4320 | 72 | 0.18468 | 0.19 | 40.3 | 0.3065
nasa-occupancy-v1 | braille | squareSingleDisc | haarPSI | 66880 | 64x64 | 60 | 1 | 0.17777 | 0.00 | 39.9 | 0.2426
nasa-occupancy-v1 | braille | rectSingleDisc | haarPSI | 66880 | 12x24 | 60 | 1 | 0.13636 | -23.30 | 21.4 | 0.2410
nasa-occupancy-v1 | braille | faithfulSingleDisc | haarPSI | 66880 | 12x24 | 60 | 1 | 0.13636 | -23.30 | 21.4 | 0.2410
nasa-occupancy-v1 | braille | faithfulTiled | haarPSI | 66880 | 12x24 | 4320 | 72 | 0.17992 | 1.21 | 29.3 | 0.2428
nasa-occupancy-v1 | braille | faithfulTiledNoBlur | haarPSI | 66880 | 12x24 | 4320 | 72 | 0.17956 | 1.01 | 32.7 | 0.2418

<!-- HAND-WRITTEN BELOW. Everything above this marker is regenerated by the
     command in the Reproduce section; re-running clobbers this tail. The
     authoritative copy of this reading lives in
     docs/Research/2026-08-28-aski52-26-candidate-convention.md.
     Companion run at the other polarity: direct-polarity/ -->

## Interpretation (factual, no promotion claim)

**Read this together with `direct-polarity/`.** The tables above are the
production-matched `inverted` regime. The `direct` regime is the same census with the
query field the other way up. Neither is "the" answer; the pair is the finding.

**Instrument validation, and it is much stronger than the first version of this run.**
Under `inverted`, ladder rung (i) `squareSingleDisc` now reproduces production: MAE
0.66651 against production's 0.66651 on steerable blocks at **100.0% pick agreement**,
and 95.3% on occupancy. Rung (i) is supposed to BE the shipped convention, and it now
demonstrably is. The braille null control also holds in all four (polarity x corpus)
cells: `rectSingleDisc` and `faithfulSingleDisc` agree to the last digit for braille
(0.25355 / 0.35135 inverted, 0.25284 / 0.34897 direct).

**A cross-model review found two defects that had invalidated the first run's central
claim.** The first version of this census sampled the query field in RAW luma while
production's shape term uses `1 - luma` (`LogPolarKernel.baseInvertedLuma`), and
rasterized the square rung at 64pt Courier where `BuildStandardVectors` uses 32pt into
the same 64x64 canvas. Together those made rung (i) agree with production on only 12.4%
of cells, which was then misread as evidence that "the query path carries most of the
gap". It does not. With both defects fixed, rung (i) IS production, and the gap the
first run attributed to sampling support does not exist.

**The dominant defect is a polarity inconsistency inside production, and it is neither
ASKI-52 nor ASKI-26.** Candidate rasters are ink-high (`RasterizedCharacterSet.rasterize`
fills at gray 0, draws the glyph at gray 1). Production's tone pre-filter matches a BRIGHT
source cell to a DENSE glyph, which is what the renderer draws (light ink on a dark
ground) and what every archived pick-quality screen scores under. But production's shape
term inverts the query, so it treats DARK source regions as ink. The shape term and the
tone term disagree about which end of the source is ink. Holding everything else fixed and
flipping only the query polarity, on `blocks`:

| corpus | rung (i) inverted | rung (i) direct | MAE recovered |
| --- | --- | --- | --- |
| nasa-steerable-v1 | 0.66651 | 0.36031 | 0.306 |
| nasa-occupancy-v1 | 0.65656 | 0.40970 | 0.247 |

Production `blocks` SSIM is 0.0040 / 0.0050. Under `inverted` the position-faithful
vocabulary reproduces that (0.0040 / -0.0009); under `direct` it reaches 0.307 / 0.105.
So the near-zero structural agreement of the shipped `blocks` pick is a polarity
artifact, not a candidate-convention one.

**Caveat, stated plainly.** The scoring path (ink-high glyph raster against raw source
luma) shares its convention with `direct`, so `direct` is partly flattered by the oracle
it is judged under. What defends `direct` beyond the oracle is that it is also the
convention of the renderer and of production's own tone pre-filter, while `inverted`
agrees with none of the three. This is a strong signal, not a closed proof, and a
production change would need its own gate.

**The convention delta, measured properly, is small and mostly unfavourable.**
Rung (i) -> rung (iii), MAE, matched support:

| charset | inverted steerable | inverted occupancy | direct steerable | direct occupancy |
| --- | --- | --- | --- | --- |
| blocks | +0.04% | -1.26% | +2.40% | +3.17% |
| standard | -0.24% | -1.40% | -0.09% | -0.84% |
| braille | -6.04% | +0.57% | -6.67% | -1.51% |

Under production's own polarity the position-faithful convention is inert to harmful.
Under `direct` it helps `blocks` (+2.40 / +3.17) and still hurts `standard` and `braille`.
Note the sign flip against the first run, which reported blocks at -11.90 / -2.31: that
number was produced by the two defects above and should not be cited.

**The bounds-centred rung's apparent effect largely dissolved under review.** An earlier
revision of this file reported `rectSingleDisc` as the standout blocks arm at +12.64% /
+13.44% direct and +26.12% / +15.26% inverted. A third review pass found that rung was
rasterized through `GlyphRaster` at a canvas-derived 24pt with no supersampling while
`faithfulSingleDisc` went through `GlyphCellRaster` at an effective 20pt with 4x
supersampling, so the delta those two rungs isolate was confounded with a 20% scale change
and a different antialiasing path. Both placements now share one path and one scale, and
rung (ii) falls to +0.78% / -0.30% (inverted) and +3.88% / +3.92% (direct) — no longer a
standout, and inert under production's own polarity. What survives: bounds-centring still
edges out position-faithful on blocks by roughly 0.75-1.5% in all four cells, a consistent
sign at a small magnitude, confined to the 8-glyph blocks set and reversed on standard. No
explanation is offered at that size, and none is needed.

**Degeneracy check: the tiled arms still did not go degenerate.** 72 windows, 4320-D at
the 12x24 candidate geometry on both corpora and both polarities. The shipping thumbnail
cell is unchanged at 2x4 with ~3 of 60 live bins, and the four engineering-diagram
fixtures still carry 0.33-0.69 live bins of 60. The ASKI-55 support-collapse regime is
real and reproduced; what changed is that it is no longer credited with the blocks
failure.
