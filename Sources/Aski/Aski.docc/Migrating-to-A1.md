# Migrating from v0.1.0

Pre-1.0 breaking changes from the `v0.1.0` release to the current `main` API surface, including A1 character-mode changes and later Color Pipeline v2 palette migration.

## Removed

- `ASCIIConverter.widthRatio` — replaced by ``ASCIITileShape``.
  (Plain code formatting, not a doc link: the symbol has been removed
  and DocC can't resolve a relative reference to non-existent API.)

## Color Pipeline v2

Color Pipeline v2 intentionally breaks custom palette source compatibility while Aski is still pre-public-stability. The package is not preserving a hypothetical public SDK contract; the break removes OKLAB from palette interchange so future sampling, matching, gamut, CVD, HDR, and occupancy-aware color work can happen without another palette API break.

Custom palettes no longer implement `colorsOKLAB`:

```swift
// Before
struct MyPalette: ASCIIPalette {
    let colorsOKLAB: [SIMD3<Float>]
}
```

They now declare source colors explicitly:

```swift
// After
struct MyPalette: ASCIIPalette {
    let content: PaletteContent = .fixed([
        PaletteColor(SIMD3<Float>(1, 0, 0), colorSpace: .sRGB)
    ])
}
```

Use `PaletteColor(_:colorSpace:)` with `.sRGB` or `.displayP3` declared components. Aski resolves those declared colors into its internal matching space.

For pass-through source color, use ``PaletteContent/passThrough``:

```swift
struct SourceColorPalette: ASCIIPalette {
    let content: PaletteContent = .passThrough
}
```

Do not pass an empty color array to mean pass-through. `PaletteContent.fixed([])` is programmer error and traps with a precondition. `TilePalette.fixed([])` follows the same rule for tile-grid conversion. If a caller already owns OKLAB values, convert the palette back to declared sRGB or Display P3 colors and let Aski resolve its internal matching space.

## Migration

```swift
// Before
ASCIIConverter(
    characterSet: StandardCharacterSet.standard,
    palette: BuiltInPalette.fullColor,
    widthRatio: 2.2,
    colorSpace: .sRGB
)

// After
ASCIIConverter(
    characterSet: StandardCharacterSet.standard,
    palette: BuiltInPalette.fullColor,
    tileShape: .wide,         // 2.2 → .wide
    options: .default,
    colorSpace: .sRGB
)
```

The other discrete options are ``ASCIITileShape/square`` (1.0) and
``ASCIITileShape/tall`` (0.5). Pre-A1 callers using `widthRatio: 2.2`
get bit-identical output by switching to `tileShape: .wide`.

## ``ASCIICell/brightness`` semantic

The field's storage and type are unchanged but its semantic shifts: it now
holds the cell's adjusted OKLAB L (after `RenderingOptions.brightness` and
`.contrast`), not the raw source L. At default options the two values
agree bit-for-bit, so existing snapshots and consumers continue to match.

## Migrating from v0.1.0 → v0.2.0

`v0.2.0` is the first tagged release after the initial `v0.1.0`. The cumulative change list:

### Source-breaking removals

- `ASCIIConverter.widthRatio` — removed. Use ``ASCIITileShape`` instead (`.wide` reproduces the old `widthRatio: 2.2` default bit-identically).
- Custom palettes no longer expose `colorsOKLAB`. Adopt ``PaletteContent`` with ``PaletteColor`` declared in `.sRGB` or `.displayP3`, or use ``PaletteContent/passThrough`` for source-color rendering. The detailed migration with before/after code samples lives in the *Color Pipeline v2* section above — read it for the full pattern, especially if your palette source previously held precomputed OKLab vectors.

### Silent behavior changes

- `linearSRGBToOKLAB` and `linearP3ToOKLAB` now use `cbrt` instead of `sign · pow(·, 1/3)`. The canonical sRGB and Display P3 round-trip tolerances are unchanged. Pinned-OKLab regressions on ANSI16 and the P3 primaries are installed as silent-drift gates against future regressions.

### New opt-ins (defaults unchanged)

- ``ASCIIConverter/init(characterSet:palette:algorithm:tileShape:options:colorSpace:oversample:colorSampling:paletteMatching:gamutMapping:composition:)`` accepts ``ColorSamplingPolicy/linearLightAverage`` for the `colorSampling:` parameter in addition to the default ``ColorSamplingPolicy/encodedAverageLegacy``. Linear-light averaging is physically correct (avoids the gamma-domain averaging mistake) but is opt-in for v0.2.0; the default will flip in a later release.

### What did NOT change in v0.2.0

The following close-out items from earlier spec drafts are **deferred** to v0.3.0 or later. They do not exist on the v0.2.0 API surface:

- `PaletteMatchingPolicy.oklabHyAB` — experimental HyAB difference metric over OKLab a/b. Not in v0.2.0.
- `PaletteMatchingPolicy.helmlabMetric` — experimental Helmlab metric. Not in v0.2.0.
- `RenderColorSpacePolicy.extendedLinear` — per-gamut extended-linear working space. Not in v0.2.0.
- Linear-light sampling as the default (the flip). Default in v0.2.0 remains `.encodedAverageLegacy`.
- Ray Trace gamut policy as the default. Default in v0.2.0 remains the existing adaptive-L0 / clip selection.

## Migrating from v0.3.x → v0.4.0

`v0.4.0` changes the default gamut mapper from ``GamutMappingPolicy/adaptiveL0`` to ``GamutMappingPolicy/rayTrace``. This is a pre-1.0 default-output change: source code that constructs `DefaultConverter()` or omits `gamutMapping:` still compiles, but rendered colors can change for out-of-gamut chromatic inputs.

To compare against the previous default, pass ``GamutMappingPolicy/adaptiveL0`` explicitly:

```swift
let legacyGamutMapper = ASCIIConverter(
    characterSet: StandardCharacterSet.standard,
    palette: BuiltInPalette.fullColor,
    gamutMapping: .adaptiveL0
)
```

Ray Trace remains target-gamut aware for both `.sRGB` and `.displayP3`. Display P3 output still uses Aski's existing sRGB-style transfer encoding because sRGB and Display P3 share the same transfer curve.
