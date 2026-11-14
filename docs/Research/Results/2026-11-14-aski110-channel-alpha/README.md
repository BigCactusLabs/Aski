# ASKI-110: channel-split brightness and alpha

Chromatic aberration (global and per-character) and the stock RGB-split fallback
added three copies of the source alpha. Native render tests reproduce brightening
and loss of transparency. The fix isolates straight color channels at unit alpha,
adds the shifted colors, discards summed alpha, and applies the unshifted source
alpha once. Shifted color stays inside the source coverage. Zero intensity is an
identity. This changes rendered output, not the public API.

## Evidence

The original implementation is at `4f4e6b1e0fc2a1e17b2730228347d44d4853ef96`.
`provenance.json` identifies the corrected source and regression test by SHA-256,
all six before/after PNGs, and the raw and path-normalized log hashes.

| Path / input | Original premultiplied RGBA8 | Independent expected RGBA8 |
| --- | --- | --- |
| Global aberration or RGB fallback, opaque uniform | 255, 178, 81, 255 | 153, 102, 51, 255 |
| Global aberration or RGB fallback, half-alpha uniform | 137, 89, 41, 255 | 77, 51, 26, 128 |
| Per-character aberration, half-alpha block interior | 112, 73, 35, 255 | 77, 51, 26, 128 |

Both sRGB and Display P3 cases reproduce the defect. Corrected assertions pass
within one 8-bit count per channel. The success log does not print exact corrected
bytes; the right column is the oracle, not a separate measurement. The signed-shift
edge test also verifies yellow/cyan internal edges and transparent exterior pixels.
The reduced-quality device context forces the RGB fallback. The existing Metal
RGB-split smoke test passes; this is not a cross-backend parity claim.

`before-render.log` exits 1 on the reproduced assertions. `after.log` exits 0
(seven test functions across the selected suites, with parameterized cases).
Earlier sandbox attempts failed before trustworthy rendering and are excluded.
`EffectChannelAlphaTests.swift` contains the reproducible native checks. Commands:

```bash
xcrun swift test --no-parallel --filter 'EffectChannelAlphaTests|StockCIEffectKernelTests/aberration|MetallibEffectKernelTests/rgbSplitProducesOutput'
xcrun swift test --skip-build --no-parallel --filter 'EffectKernelSnapshotTests|CompositionSnapshotTests|RGBSplitKernelTests'
```

The first command's historical Metal selector matches no test; the second uses
`RGBSplitKernelTests` and confirms the actual existing smoke test. The original
reproduction selected `EffectChannelAlphaTests` alone.

## Snapshot change

Exactly these three snapshots moved; their original and corrected PNGs are in
`before/` and `after/` with their original filenames:

- `effectSnapshot-name-effect.chromaticAberration-default.png`
- `effectSnapshot-name-effect.chromaticAberration-extreme.png`
- `compositionSnapshot-name.perCharacter-aberration-on.png`

The lead inspected the pairs: the global effect loses the excess bright channel
sum, and the per-character fringe keeps the glyph coverage. Snapshot comparison
(`snapshot-native.log`) exits 1 for these three differences only, across 24 effect
and 22 composition cases, while the Metal smoke test passes. Recording with
`SNAPSHOT_TESTING_RECORD=failed` (`snapshot-record.log`) writes these three PNGs
and intentionally still exits 1. A normal comparison is part of the combined
local gate. The frozen Vesper preset uses neither affected effect; its goldens did
not move, so this correction does not trigger a frozen-preset no-harm census.

## Color contract and limits

Apple documents [CIColorMatrix](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/)
as operating on unpremultiplied values. [CIColor](https://developer.apple.com/documentation/coreimage/cicolor)
uses unpremultiplied components, while Core Image image processing normally uses
premultiplied samples. Those contracts guided the fix; the native assertions above
establish its behavior in Aski. Metal kernels, the near-white ground decision,
benchmark thresholds, and the public API are unchanged.

`just check` passed on 2026-11-14: format, build, research/repo-map drift, core,
media, both deadlock sentinels, and DocC. `validation.json` retains the command,
UTC times, exact source/snapshot hashes, phase counts and full raw log hash.
Only evidence path normalization and task/document metadata changed afterward.
