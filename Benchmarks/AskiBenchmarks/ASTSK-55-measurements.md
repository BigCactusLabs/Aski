# ASTSK-55 Opt-in assist and gamut profiling record

Measured 2026-07-23 on an otherwise idle `arm64` Darwin 25.5.0 host. The
fixture baseline used the release `AskiBenchmarks` runner serially; results
below are wall-clock `p50 / p99`. All workloads opt in to one research path or
call one mapper directly, so none is folded into the default conversion matrix.

## Matrix

- `assist-steerable-signature-24px` invokes the fixed 24px, 24-bin signature
  construction directly.
- `assist-steerable-rasterized-800x600-32cols`,
  `assist-structure-800x600-32cols`, and
  `assist-chroma-isoluminant-800x600-32cols` each enable only their named
  default-off knob on a deterministic feature-bearing image. The 32-column
  grid stays below the parallel-row threshold so per-cell work is visible.
- `assist-rasterized-character-set-95glyphs-default` constructs the existing
  full-assist `RasterizedCharacterSet` over printable ASCII.
- `gamut-*-out-of-gamut-256` maps 256 deterministic out-of-gamut OKLAB
  samples directly, separating adaptiveL0's binary search from the default
  `.rayTrace` pipeline and exposing both RGB target converters.

No benchmark threshold changed.

## Baseline

| Benchmark | p50 / p99 | Notes |
| --- | ---: | --- |
| `assist-steerable-signature-24px` | `250 / 354 μs` | Includes per-call G2/H2 basis construction. |
| `assist-steerable-rasterized-800x600-32cols` | `95 / 96 ms` | Rasterized set, `steerableShapeAssist: 0.5`. |
| `assist-structure-800x600-32cols` | `17 / 19 ms` | `shapeStructureAssist: 1`. |
| `assist-chroma-isoluminant-800x600-32cols` | `4.772 / 8.339 ms` | `chromaShapeAssist: 1`. |
| `assist-rasterized-character-set-95glyphs-default` | `28 / 29 ms` | Existing default construction with all assist channels. |
| `gamut-adaptiveL0-srgb-out-of-gamut-256` | `30 / 53 μs` | 16-iteration binary-search baseline. |
| `gamut-adaptiveL0-displayp3-out-of-gamut-256` | `31 / 39 μs` | 16-iteration binary-search baseline. |
| `gamut-raytrace-srgb-out-of-gamut-256` | `37 / 55 μs` | Converter-dispatch inspection target. |
| `gamut-raytrace-displayp3-out-of-gamut-256` | `36 / 56 μs` | Converter-dispatch inspection target. |

## Decisions

| Finding | Decision | Before p50/p99 | After p50/p99 | Evidence |
| --- | --- | ---: | ---: | --- |
| 22: fixed-sigma bases and duplicated assist luma | Adopt | steerable `95/96 ms`; structure `17/19 ms` | steerable `94/95 ms`; structure `16/18 ms` | A shared immutable basis is used only in the default-off steerable conversion path, and its luma field is reused by the descriptor and assist query. The fixed-basis signature test is bit-identical; focused convert output and default golden tests pass. |
| 23: optional rasterized assist channels | Adopt | default construction `28/29 ms` | no-assist `1.567/1.935 ms` | `computeAssistChannels` defaults to `true`; final default re-measure is `28/29 ms`. The explicit `false` path leaves characters, normalized brightness, raw density, and 60D lanes bit-identical while returning nil assist channels. No `.bin` reader, writer, or resource changed. |
| 26: byte decode LUT for chroma assist | Reject | chroma `4.772/8.339 ms` | trials `4.751/7.340 ms`, then `4.776/5.341 ms` | The 256-value LUT was bit-identical to the transfer function, but the p50 difference was below measurement noise, so the candidate was removed and chroma retains its existing decode. |
| 27: adaptiveL0 iteration count | Reject | sRGB `30/53 μs`; P3 `31/39 μs` | 15-iteration trials: sRGB `29/52-57 μs`; P3 `30/55-58 μs` | 12 and 14 iterations changed 8-bit output on the 256-sample, both-gamut reference sweep in the full gate. Fifteen iterations retained accuracy but delivered only a 1μs median change with noisier tails, so the candidate was removed and 16 iterations remain. |
| 28: gamut converter function-value dispatch | Reject before source change | ray trace sRGB `37/55 μs`; P3 `36/56 μs` | no source change; re-run sRGB `37/46 μs`, P3 `37/44 μs` | Release-binary inspection shows no surviving `rayTraceToRGBGamut` generic helper and separate optimized SRGB/P3 wrapper specializations, so dispatch is already resolved. |

## Output review and golden status

`DefaultPathExactGoldenTests` passes unchanged. The explicit default-off guards
for steerable and rasterized-assist construction pass, as do the new fixed-basis
bit-pattern and adaptiveL0 8-bit-reference tests. All researched knobs retain a
zero default; no benchmark threshold, built-in shape-data resource, or `.bin`
reader/writer changed.
