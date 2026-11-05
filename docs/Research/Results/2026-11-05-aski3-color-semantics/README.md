# ASKI-3 paired selection census

The production arm passes the pre-registered selection no-harm guard on all three
corpora. All six production MAE/GMSD after/before ratios are exactly `1.0`.
The census covers 75,468 cells per side: 59,964 occupancy, 7,752 steerable, and
7,752 structure. Every P/F quality and selection field is exactly unchanged;
timing and revision metadata differ. All emitted P and F rows are retained in the
six original CSVs. `comparison.csv` retains both arms' MAE/GMSD comparisons.

The [rule](../../2026-11-05-aski3-color-semantics.md) was committed at
`6b47141d13409e5fdde52bafb370e646b9d5c40a` before measurement. Its production-arm
bar is after/before <= 1.0100 for both MAE and GMSD on every corpus, with identical
configuration keys and cell counts and no missing or non-finite values.

## Method and identities

Both sides ran `aski lab color selection-ceiling` with blocks, 76 columns,
oversample 2, footprint 24, stride 1, and inverted shape-query polarity. The
unchanged instrument scores monochrome sRGB cell rasters and pools results by
corpus. P is production selection; F is the emitted brightness-floor comparator.
The full recorded arguments, input asset SHA-256 maps, executable hashes, run
exit status, timing, and toolchain are in `before/provenance.json` and
`after/provenance.json`. Output arguments use repository-relative paths. These
paths describe the original runs; packaged CSVs now live in this directory.

The before executable used code `14c8697ce0211098630088cab14ef9e8a79b048e`.
Its CSV `gitSHA` field records the documentation-only rule revision `6b47141`;
that field must not be mistaken for the executable's code revision. The after
executable used rule revision `6b47141` plus the production patch whose SHA-256 is
`0f4338104b5dbe897b1deef12150039c80ebe197fa4552fe006cb6f3b9ee2b78`.
`production.patch` preserves that source change; `production.patch.sha256` and
`source-sha256.json` identify the patch and the five corrected production files.
Both release executables ran on macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), and
Swift 6.4. Build commands and executable paths relative to each checkout are
recorded in provenance. Asset attribution remains with the linked corpus manifests.

## Limits

This is pooled monochrome sRGB selection evidence. It is not a score of Vesper's
Display P3 duotone colors, a per-fixture no-harm result, or a universal image-quality
claim. Equal pooled fields do not exclude cancelling per-fixture changes.
Native non-neutral pixel regressions establish source-color interpretation;
this census guards selection separately. Golden images, their visual review, and the full local gate are recorded in the
linked research note. The one-off tone attribution below does not establish a
universal quality improvement.

## Tone-sensitive SSIM test attribution

`ssim-attribution.json` contains measurements from the unchanged control and the
fixed renderer. Both use the original full-color gradient fixtures, system font
size 10, black background, scale 1, and the existing local-window MSSIM helper.

| Fixture | Control | Corrected | Corrected with old tone reproduced | Blank |
| --- | ---: | ---: | ---: | ---: |
| Horizontal | 0.07575288421475966 | 0.06950675148949562 | 0.07575288421475966 | 0.002477774855613454 |
| Diagonal | 0.07237566291470883 | 0.07008130072440694 | 0.07237566291470883 | 0.0008751375004695014 |

The probe independently converts each cell's old Generic RGB meaning to encoded
sRGB before sending it through the corrected renderer. That reproduces the
control's complete raw pixel hash **exactly** for both fixtures, as well as each
MSSIM score. Thus the observed score change is fully attributable to color
interpretation on these fixtures. It is not evidence of a glyph-order change.

The former total-MSSIM floor of 0.07 mixed tone and structure. It is replaced by a
strict comparison against the same cells arranged in reverse row/column order;
the existing `score > blankScore + 0.03` guard remains. This changes the test
contract: it detects wrong spatial order and blank collapse, but has no absolute
total-fidelity floor. Native source-color checks and inspected goldens cover tone
and color. Neither the reversed comparison nor this attribution is a universal
quality claim. No benchmark threshold changes.

For reproduction, temporarily copy `SSIMAttributionProbe.swift` into
`Tests/AskiTests/` on each revision and run
`xcrun swift test --no-parallel --filter SSIMAttributionProbe`. Remove only that
temporary copy afterward. The retained probe depends on that checkout's
`TestImages` helper and deliberately measures the old incorrect interpretation;
it is an evidence generator, not a permanent correctness oracle.

## Golden and alpha review

`golden-deltas.csv` records the before/after PNG hashes, dimensions, and decoded
RGBA differences for all 61 changed image references. Both sides were visually
inspected in paired sheets, with a larger Vesper comparison. Glyph/tile layouts
remain the same; color and tone change. Source control retains the old references
at the rule commit. The raw G0 reference was also inspected at enlarged scale:
both versions contain 7,744 bytes (44 by 44 RGBA). Its SHA-256 changes from
`448a88597e504830202aebe06a0934541723e5be2e159a0ba68259e2b09a5454` to
`4ae8fd3be3c5dfa7ead632c43725e1ed8f4273e564480ff3049431867c6ed75a`.

Four PNGs also change alpha at rendered edges: composition blurred background
(maximum 5 steps), fit background (26), xor (26), and character mask fallback (8).
The retained `RasterAttributionProbe.swift` reproduces these exact fixtures on
both revisions. Its independent legacy-tone remap restores the complete cell
raster bytes and final alpha-plane hash **exactly in all four cases**. For the
three composition cases it also restores the complete final render and PNG hash.
For character fallback, only the foreground cells are remapped; final RGB still
differs because the explicit fallback passes through a synthetic cell raster and
its former second Generic RGB interpretation is also corrected. The final alpha
hash still matches. `raster-attribution.json` retains every measurement.

These measurements attribute the alpha differences to the changed source color
stimulus on these native raster paths; they do not imply a changed cell alpha or
coverage rule. The explicit character fallback has independent caller-color
regression coverage as well. The probe runs like the SSIM probe above, using
`--filter RasterAttributionProbe`. No snapshot tolerance was relaxed.
