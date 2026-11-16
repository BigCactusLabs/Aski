# ASKI-103 composition-space capture

Verdict: **KEEP current per-stage behavior** under the [registered protocol](../../../../Scripts/research/aski103-2026-11-15/PROTOCOL.md). Capture revision: `e609764b0c186880a5175a037a4e9014e07007f0`, clean tree. The native diagnostic exited 0 in 3.902 seconds.

The [CSV](composition.csv) contains 520 unique data rows: 432 opaque-mask rows, 48 ASCII glyph rows, 24 tile glyph placeholders, and 16 calibration controls. All 496 applicable rows pass. The unique key is `path, grid_gamut, output_gamut, policy, raster_space, consumer, fixture, coverage`.

| Group | Largest RGB MAE | Largest RGB error | Smallest alternative-model MAE |
| --- | ---: | ---: | ---: |
| Mask (432 rows) | 1.25 | 1.25 | 32.75 |
| ASCII glyph (48 rows) | 0.2782 | 0.9381 | 9.6732 |
| Non-target-width glyph subset (44 rows) | 0.2448 | 0.5112 | 57.4111 |
| Controls (16 rows) | 0.4840 | 0.4840 | 44.6265 |

Units are encoded 8-bit channel values. Each glyph row uses all eligible antialiasing pixels; `samples` counts three color channels per pixel. Target-width glyph rows only check model consistency, so they have no alternative-model separation gate. The synthetic reducer controls supply that discriminator. The largest alpha discrepancy is 0.5 in the target-width reference alignment; opaque alpha error is zero. Full-precision aggregates are in [summary.json](summary.json).

At 0.5 soft fallback coverage on the sRGB neutral fixture, direct encoded ASCII is 128 per channel, direct linear ASCII is 188, and effects ASCII is 187 under either policy. A deferred CI output gives 127 with an encoded consumer and 187 with a linear consumer, again under either grid policy. These values demonstrate stage-specific interpolation and rounding; they are not universal pixel constants.

[provenance.json](provenance.json) records source hashes and the Apple M3 Max / macOS 27.0.1 (26A434) / Xcode 27.0 (27A266a) / Swift 6.4 environment. [test.log](test.log) and [exit-status.txt](exit-status.txt) retain the capture result. [coretext-control.log](coretext-control.log) records the pre-capture standalone font check described in the protocol. CSV and capture-log bytes were copied unchanged. SHA256SUMS covers the retained machine artifacts.

The test bundle was built by the preceding full `just check` on exactly the source tree committed for capture, with the opt-in diagnostic disabled. That gate passed 1,518 core tests, 178 serialized media tests, both deadlock sentinels and DocC. Capture reused it with `--skip-build`. Replay the committed revision with the protocol's fresh-directory command; current later commits contain documentation and result bookkeeping.

See the [decision and limitations](../../2026-11-15-aski103-composition-spaces.md). No renderer behavior, ShapeData, or golden files changed, and no no-harm census is claimed or required for this documentation/visibility batch.
