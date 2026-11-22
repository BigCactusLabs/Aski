# Migration Notes

Upgrade an existing integration without confusing private-development history with the public package.

## Start here

The public release history starts at **v0.7.0**. Earlier versions mentioned below were
private-development releases; their tags and commits are not available in this repository.
New integrations should use <doc:GettingStarted>, not apply each historical migration.

Aski remains pre-1.0. Source APIs and rendered output can change between minor releases.
Use an exact published version when reproducibility matters, and review the repository's
[changelog](https://github.com/BigCactusLabs/Aski/blob/main/CHANGELOG.md) before upgrading.

## Unreleased changes

These changes describe the current `main` checkout after v0.8.0. They are separate
from the tagged release migrations below.

### Decoded image preparation

`ImageIOThumbnail.decode(image:maxPixelSize:)` was removed. Pass an already decoded
`CGImage` directly to `ASCIIConverter.convert` or `TileGridConverter.convert`;
the converter now prepares the sampling lattice itself. For encoded input, keep
using `ImageIOThumbnail.decode(data:maxPixelSize:)` or
`ImageIOThumbnail.decode(source:maxPixelSize:)` to avoid full-raster decoding and
apply EXIF orientation.

Large decoded images now use direct vImage preparation instead of a PNG/ImageIO
round trip. The CLI's portrait thumbnail budget, portrait tile sampling, and `.tall`
sampling were also corrected. Affected inputs can change colors, glyph picks, or
CLI row counts. Re-render those references on the intended host; an unchanged
invocation is not a promise of the previous raster. See <doc:Algorithms> and
<doc:CommandLine> for current geometry and input handling.

### Character-set extension code

Code that names `ShapeQueryPolarity` now requires:

```swift
@_spi(AskiResearch) import Aski
```

Ordinary rendering keeps the `.inverted` default. The low-level
``ASCIICharacterSet`` array contract remains available with converter snapshots
at initialization and reassignment; use ``RasterizedCharacterSet`` when your input
is a font and glyph list. See <doc:CharacterSets>.

### Rendered output to review

| Affected integration | Current behavior and migration |
| --- | --- |
| Mask paints, color overlays, and point lights | Colors are interpreted in their declared `CGColor` space. Use explicitly tagged sRGB or Display P3 colors for intentional components; remove compensation for the previous raw-component interpretation. See <doc:Masking> and <doc:Effects>. |
| Soft masks on Core Image paths | Coverage is a linear weight; partially covered cells can change. Deferred `CIImage` evaluation still uses the consumer's working space for branch interpolation. See <doc:Masking>. |
| Point lighting | The source alpha is preserved and the old over-brightening is corrected. Review exposure; adjust ambient or intensity for the intended look. See <doc:Effects>. |
| Chromatic aberration and the stock RGB-split fallback | Shifted color preserves input alpha instead of accumulating three copies. Existing renders can be less bright. See <doc:Effects>. |
| Ragged, manually constructed grids | Image width follows the widest row; missing cells preserve the canvas during mask composition. Text retains supplied row lengths. See <doc:Rendering>. |
| MP4 export | Pixel buffers and tracks use explicit gamut and transfer tags; exported bytes change. Resampled exports select frames before ASCII conversion while preserving the timing/report contract. See <doc:Video>. |

The composition policy still controls the ASCII CoreGraphics raster stage rather
than every later Core Image operation. The clarified route tables in
<doc:Rendering> and <doc:Masking> do not themselves change that policy.

### Compose render recipes directly

`VesperPreset` has been removed from the public library. Replace
`VesperPreset.canonical.render(image)` with the complete `renderDuotone(image)`
example in <doc:Duotone>. It uses the same canonical conversion and render settings
on the same checkout; this removal does not change the rendering engine or its
reference image. Cross-version or cross-host pixel equality is not implied.

For `makeConverter()` callers, use the example's `ASCIIConverter` construction and
retain the grid. Its palette is the example's `DuotonePalette`; if you explicitly
typed the old result as `DefaultConverter` or
`ASCIIConverter<StandardCharacterSet, BuiltInPalette>`, let Swift infer the new type
or change that palette type argument to `DuotonePalette`. Replace `font` with
`.courierPrime(size: 14)` for the former canonical look. Callers of the configurable initializer should pass their own columns, palette,
contrast, color space, oversample, font size, scale, and background directly to the
converter and renderer. Keep `preserveSourceAspect: true` to retain that geometry.

The `AskiPresetLab` executable and `aski lab preset` namespace were also removed,
including `ab`, `probe-stimuli`, `probe-score`, and their four product-probe schemas.
They have no replacement command. For ordinary conversion, use `aski render` or the
library recipe. For a parameter comparison, render explicit configurations and compare
the outputs. Historical study results and dated replay instruments remain tied to their
recorded revisions; do not run an old instrument against an arbitrary current checkout.

This is a product-scope retirement, not a failed human-study verdict. The recipe used
for research and regression tests remains package-only tool support, with its original
settings and raster baseline. It is not a replacement public API.

## Moving to v0.8.0

Update the package dependency:

```swift
.package(url: "https://github.com/BigCactusLabs/Aski.git", exact: "0.8.0")
```

### Raster colors

ASCII, tile, and effects rendering now interpret cell colors in the grid's declared
sRGB or Display P3 space instead of Generic RGB, so raster colors change, including
mid-gray neutrals. Glyph choices and attributed-string colors do not change. Review saved
render references and remove any palette compensation for the old output. Build
background, mask-fallback, and ground colors as explicitly tagged `CGColor` values, for
example `CGColor(srgbRed:green:blue:alpha:)`. See <doc:Rendering> for the details.

The CLI builds `--background`, `--mask-fallback-color`, and `--mask-ground` in sRGB, so
`--background "#808080"` now writes `#808080` pixels where it previously wrote
`#929292`. Regenerate saved CLI renders before comparing them.

### GIF loop counts

``ASCIIGIFEncoder`` accepts `loopCount` in `0...32767` and throws
``GIFEncodeError/invalidLoopCount(_:)`` for any other value instead of writing it. Add a
branch for that case to any exhaustive `switch` over ``GIFEncodeError``, and validate or
override source loop counts outside the range. ``GIFEncodeReport/loopCount`` now reports
the value read back from the written file. See <doc:Video>.

### CLI output destinations

`aski render --output` writes directly to `/dev/null` and `/dev/stdout`. Other special
destinations, such as FIFOs, are rejected before any output changes; PNG and manifest
destinations must be regular files. See <doc:CommandLine>.

## Moving to v0.7.0

Update the package dependency:

```swift
.package(url: "https://github.com/BigCactusLabs/Aski.git", exact: "0.7.0")
```

When moving an existing private-repository pin, select an available public tag or
a local source checkout deliberately. A private tag or commit SHA is not a usable
pin in this public history.

### Removed experiments

`ASCIIAlgorithm.edgeMap` was removed. Choose ``ASCIIAlgorithm/logPolar`` or
``ASCIIAlgorithm/dotMatrix``; they have different visual behavior, so review your output
rather than treating either as an equivalent edge-map replacement.

The removed `RenderingOptions` experiment families are `occupancyMatching`,
`chromaShapeAssist`, `shapeStructureAssist`, `steerableShapeAssist`, and
`inkPreCompensation`, including its floor/background controls. Remove those arguments
and property accesses. They are not deprecated aliases; the failed or inconclusive
production paths were deleted. Their evidence remains in the research records.

### Custom character sets

``ASCIIConverter`` snapshots a custom character set's per-glyph arrays at initialization
and whenever `characterSet` is assigned. A reference-type conformance that mutates those
arrays in place must be assigned again before the next conversion. See <doc:CharacterSets>.
`rawDensityValues` remains part of ``ASCIICharacterSet``; it was not removed with the
experimental controls.

### Output changes to review

The sampling lattice now includes the full bottom and right edges of the source, so
an unchanged invocation can produce a different grid from an earlier checkout.
Exact-width raster output is available through `targetPixelWidth:` and CLI `--width`;
the latter requires `--render-png`. See <doc:Algorithms> and <doc:Rendering>.

The current defaults are `linearLightAverage` sampling, `oklabEuclidean` palette
matching, and `rayTrace` gamut mapping. Historical defaults described below are **not**
the defaults to copy into a new integration.

For tool users, prefer `aski render`, `aski inspect`, and `aski lab …`. Surviving
`Aski*Lab` executables remain compatibility entry points; removed experiment runners
are not promised in the public checkout. See <doc:CommandLine>.

## Historical A1 geometry migration

`ASCIIConverter.widthRatio` was replaced by ``ASCIITileShape``:

```swift
// Before: private pre-A1 API; this no longer compiles.
ASCIIConverter(
    characterSet: StandardCharacterSet.standard,
    palette: BuiltInPalette.fullColor,
    widthRatio: 2.2,
    colorSpace: .sRGB
)

// After: current spelling.
ASCIIConverter(
    characterSet: StandardCharacterSet.standard,
    palette: BuiltInPalette.fullColor,
    tileShape: .wide,
    options: .default,
    colorSpace: .sRGB
)
```

At that migration, `.wide` reproduced the old `widthRatio: 2.2` geometry. The other
choices are ``ASCIITileShape/square`` (1.0) and ``ASCIITileShape/tall`` (0.5). Later
pipeline changes mean this geometry mapping alone is not a promise of historical bytes.

## Color Pipeline v2

This section describes a private-development migration.

Custom palettes stopped exposing `colorsOKLAB`. Declare source colors and their color
space instead; Aski owns the internal matching representation:

```swift
// Before: private legacy API.
struct MyPalette: ASCIIPalette {
    let colorsOKLAB: [SIMD3<Float>]
}

// After: current API. Use this definition instead of the one above.
struct MyPalette: ASCIIPalette {
    let content: PaletteContent = .fixed([
        PaletteColor(SIMD3<Float>(1, 0, 0), colorSpace: .sRGB)
    ])
}
```

Use `.sRGB` or `.displayP3` with the corresponding declared components. For source-color
pass-through, use ``PaletteContent/passThrough``:

```swift
struct SourceColorPalette: ASCIIPalette {
    let content: PaletteContent = .passThrough
}
```

`PaletteContent.fixed([])` is a programmer error and traps; an empty palette is not a
pass-through signal. `TilePalette.fixed([])` follows the same rule. Convert externally
held OKLab colors back to declared sRGB or Display P3 colors before creating a palette.

## ASCIICell brightness semantics

``ASCIICell/brightness`` holds adjusted source OKLab L after brightness and contrast,
not raw source lightness or final glyph display-color luminance. The field's storage
and type did not change at the historical transition. At default brightness/contrast,
adjusted and unadjusted source lightness agree.

## Historical v0.1.0 to v0.2.0

That private release introduced the geometry/palette migrations above and replaced
sign-corrected `pow` cube roots with `cbrt` in color conversion. Linear-light averaging
was initially opt-in; `.encodedAverageLegacy` was the v0.2.0 default. This describes that
release only. Current palette metrics and defaults are documented in <doc:PaletteMatching>
and <doc:GettingStarted>, not by old deferred-work lists.

## Historical v0.3.x to v0.4.0

v0.4.0 changed the default gamut mapper from ``GamutMappingPolicy/adaptiveL0`` to
``GamutMappingPolicy/rayTrace``. Omitting `gamutMapping:` still compiled, but out-of-gamut
colors could change. To compare with the former mapper explicitly:

```swift
let legacyGamutMapper = ASCIIConverter(
    characterSet: StandardCharacterSet.standard,
    palette: BuiltInPalette.fullColor,
    gamutMapping: .adaptiveL0
)
```

Ray Trace is target-gamut aware for both sRGB and Display P3. Keep an explicit legacy
policy only for an intentional comparison or integration requirement, not because a
historical example happened to contain it.
