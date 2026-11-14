# ASKI-108 capture

The [inspection and proposed future arm](../../2026-11-14-aski108-near-white-inspection.md)
record a visible cutoff in the portrait sky. Shipping behavior is unchanged.

Capture source: `bc0e31feb3e45e6ff03c26619ee0b9bdafc4e359`. The protocol and
runner were committed before this release capture. The diagnostic passed and
all four canonical images exactly match the independently rendered SPI grids.

## Native source/render pairs

| Fixture | Source | Canonical render | Query-state mask | Boundaries |
| --- | --- | --- | --- | --- |
| RCS function | [JPEG](rcs-function-diagram-source.jpg) | [PNG](rcs-function-diagram-canonical.png) | [Mask](rcs-function-diagram-mask.png) | [CSV](rcs-function-diagram-edges.csv) |
| Spacecraft attitude | [JPEG](spacecraft-attitude-diagram-source.jpg) | [PNG](spacecraft-attitude-diagram-canonical.png) | [Mask](spacecraft-attitude-diagram-mask.png) | [CSV](spacecraft-attitude-diagram-edges.csv) |
| Lovell portrait | [JPEG](james-lovell-portrait-source.jpg) | [PNG](james-lovell-portrait-canonical.png) | [Mask](james-lovell-portrait-mask.png) | [CSV](james-lovell-portrait-edges.csv) |
| Diagnostic ramp | [PNG](diagnostic-ramp-source.png) | [PNG](diagnostic-ramp-canonical.png) | [Mask](diagnostic-ramp-mask.png) | [CSV](diagnostic-ramp-edges.csv) |

Masks are one pixel per cell: white zero/space, red zero/glyph, blue nonzero/space,
black nonzero/glyph. They are diagnostics, not visibility scores. CSV coordinates
are zero-based, with the zero-query endpoint first. Lattice pitch is 2×4; geometry
and PNG/pixel equality are in `inspection.txt`. Adjusted L is not cutoff luma.

## Reproduce and provenance

At the captured commit, run:

```bash
bash Scripts/research/aski108-2026-11-14/capture.sh /absolute/new/output-directory
```

The wrapper builds from `git archive HEAD` and refuses a modified instrument or
existing output directory. `provenance.txt` retains exact argv with host paths
normalized to `$REPO`, `$CAPTURE`, and `$DEVELOPER_DIR`. `build.log` is the actual
release build log. The capture's raw log/archive hashes and path normalization
are recorded in `normalization.json`; the raw capture was preserved privately
before normalization. `SHA256SUMS` verifies the public capture artifacts. Native
PNG/JPEG and CSV bytes were not altered.

Source attribution and NASA IDs are retained in the
[corpus manifest](../../Corpus/nasa-occupancy-v1/manifest.yaml) and the committed
[protocol](../../../../Scripts/research/aski108-2026-11-14/PROTOCOL.md).
