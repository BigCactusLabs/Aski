# Exact-render baseline evidence

This change updates 16 exact render PNGs using the measurements below. No comparator tolerance, renderer source, font vector, or frozen Vesper preset test was changed.

## Provenance

- Original golden commit: `0e654023`, recorded on macOS 27.0 (26A428) with the same Xcode and Swift versions.
- Unchanged control: `06adfdb`; changed checkout: `b17e791a8a8ddb3b4d09cf330d6928db46ef3c07`.
- Recorded host: macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Swift 6.4.
- The same 16 mismatches occurred on the control and changed checkouts. Four isolated control captures (initial plus three repeats) produced byte-identical candidate PNGs for every listed image. Passing cases emitted no PNG and are outside this identity claim.
- Capture command, repeated in the control checkout: `xcrun swift test --skip-build --no-parallel --filter 'compositionSnapshot|effectSnapshot|sameSourceCorpusGroundComparison'`. Each repeat exited 1 with the same 16 snapshot issues.
- Before copying any candidate, all 16 current golden SHA-256 values were checked against the preserved reference values in the diagnostic raw-pixel evidence. Each copied candidate then matched its preserved actual SHA-256 and all three repeat files. [drift.csv](drift.csv) retains the reference and candidate hashes.

## Exact image measurements

Each changed RGB channel differs by one 8-bit step. Alpha is unchanged, and differing pixels are opaque in both images. Dimensions, RGBA mode, sRGB intent 0, EXIF metadata, and absent ICC profiles match. Independent native decoding through both the comparator color-space route and canonical sRGB reproduced the raw changed-pixel counts and maximum channel delta of 1. An extra AppKit PNG round trip introduced no pixel changes.

| Suite | Snapshot | Dimensions | Changed pixels | Fraction | Max channel delta | Four captures byte-identical |
| --- | --- | --- | ---: | ---: | ---: | --- |
| CompositionTests | `compositionSnapshot-name.background-solid-red.png` | 173 × 231 | 7 | 0.0175162025% | 1 | yes |
| CompositionTests | `compositionSnapshot-name.background-original-fill.png` | 173 × 231 | 454 | 1.1360508470% | 1 | yes |
| CompositionTests | `compositionSnapshot-name.background-sizing-fill.png` | 173 × 231 | 454 | 1.1360508470% | 1 | yes |
| CompositionTests | `compositionSnapshot-name.background-sizing-fit.png` | 173 × 231 | 130 | 0.3253009033% | 1 | yes |
| CompositionTests | `compositionSnapshot-name.background-sizing-stretch.png` | 173 × 231 | 420 | 1.0509721492% | 1 | yes |
| CompositionTests | `compositionSnapshot-name.blend-normal.png` | 173 × 231 | 454 | 1.1360508470% | 1 | yes |
| CompositionTests | `compositionSnapshot-name.blend-overlay.png` | 173 × 231 | 456 | 1.1410554763% | 1 | yes |
| CompositionTests | `compositionSnapshot-name.blend-screen.png` | 173 × 231 | 468 | 1.1710832520% | 1 | yes |
| CompositionTests | `compositionSnapshot-name.blend-multiply.png` | 173 × 231 | 942 | 2.3571803919% | 1 | yes |
| CompositionTests | `compositionSnapshot-name.blend-plusLighter.png` | 173 × 231 | 462 | 1.1560693642% | 1 | yes |
| CompositionTests | `compositionSnapshot-name.blend-xor.png` | 173 × 231 | 456 | 1.1410554763% | 1 | yes |
| CompositionTests | `compositionSnapshot-name.overlay-plusDarker.png` | 173 × 231 | 1 | 0.0025023146% | 1 | yes |
| CompositionTests | `compositionSnapshot-name.perCharacter-bloom-on.png` | 173 × 231 | 1 | 0.0025023146% | 1 | yes |
| EffectKernelTests | `effectSnapshot-name-effect.vignette-extreme.png` | 173 × 231 | 1 | 0.0025023146% | 1 | yes |
| MaskSnapshotTests | `sameSourceCorpusGroundComparison.docc-mask-ground-before.png` | 288 × 336 | 1 | 0.0010333995% | 1 | yes |
| MaskSnapshotTests | `sameSourceCorpusGroundComparison.docc-mask-ground-after.png` | 288 × 336 | 2 | 0.0020667989% | 1 | yes |

The fraction is changed pixels divided by total pixels; CSV fractions are unitless. RGB changes are -1 (candidate minus reference), except blend-multiply has 19 +1 channel changes among 1,880 changed channels. These measurements describe deterministic raster drift in the isolated captures; they do not establish a framework cause.

## Separate vector audit

[vector-glyph-drift.csv](vector-glyph-drift.csv) and [vector-set-summary.csv](vector-set-summary.csv) are byte-for-byte copies of the read-only `BuildStandardVectors --audit` outputs from this host. The audit generated v3 vectors in memory and did not update committed ShapeData. Nine of ten sets had byte drift; braille was identical. The largest component delta was 0.0451757461 and the standard-set brightness sort changed. This is separate corroborating platform-sensitive evidence, not proof that vector drift caused these PNG differences. The copied audit CSVs contain no date; this result manifest uses the actual capture date, 2026-11-05, rather than the audit writer's hardcoded 2026-09-04.

## Scope and limits

- Only these 16 render PNGs are replaced. The frozen Vesper preset tests, selection goldens, matching vectors, production source, and strict comparison settings remain unchanged.
- The old OS is unavailable, so this run cannot directly reproduce the original raster environment or isolate the exact OS/framework cause.
- Four stable isolated captures establish repeatability in that context. A fresh parallel control core run (1,434 tests) also emitted all 16 images byte-identical to the isolated captures. An earlier changed-tree core run reported 15 issues, omitting mask-before; the fresh control run did not reproduce that discrepancy. The original run's image was not retained separately, so its cause is unproved.
- No before/after matcher quality claim is made. This change does not change a frozen-preset golden; a future change that does must carry its required MAE/GMSD no-harm census.
- The changed tree passes the three affected snapshot test functions plus all seven `VesperPresetTests` (10 tests total). Final full-gate and parallel-core stability results are recorded in ASKI-97. This evidence makes no cross-OS exact-render reproducibility claim.

The parallel control command was `ASKI_SKIP_BUILD=1 ASKI_SKIP_REGISTRY_TESTS=1 ASKI_SKIP_MEDIA_TESTS=1 just test-without-video-deadlock`; it exited 1 with exactly the same 16 snapshot issues in 138.651 seconds. The changed-tree targeted command added `|VesperPresetTests` to the isolated filter above and passed in 1.390 seconds.
