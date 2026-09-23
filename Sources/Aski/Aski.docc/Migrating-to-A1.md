# Migration Notes

Upgrade an existing integration without confusing private-development history with the public package.

## Start here

The public release history starts at **v0.7.0**. Earlier versions mentioned below were
private-development releases; their tags and commits are not available in this repository.
New integrations should use <doc:GettingStarted>, not apply each historical migration.

Aski remains pre-1.0. Source APIs and rendered output can change between minor releases.
Use an exact published version when reproducibility matters, and review the repository's
[changelog](https://github.com/BigCactusLabs/Aski/blob/main/CHANGELOG.md) before upgrading.

## Moving to v0.7.0

Once the public tag is published, update the package dependency:

```swift
.package(url: "https://github.com/BigCactusLabs/Aski.git", exact: "0.7.0")
```

Before publication, use a local source checkout rather than requesting an unavailable
private tag. Existing private-repository pins must be moved deliberately to the public
history; an old commit SHA is not a usable pin here.

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
