# Masking

Use ``MaskOptions`` when conversion should keep only part of the source image visible.

Aski accepts raster masks as `CGImage` values on both ``ASCIIConverter`` and ``TileGridConverter``. White means inside the mask and renders cells normally. Black means outside the mask and fades cells out. Intermediate luminance values become continuous per-cell coverage, so soft boundaries feather instead of aliasing.

```swift
let mask = MaskOptions(
    image: maskCGImage,
    fallback: .solid(CGColor(red: 0, green: 0, blue: 0, alpha: 1)),
    groundColor: nil,
    softEdges: true,
    invert: false
)

let grid = DefaultConverter().convert(sourceImage, columns: 80, mask: mask)
let rendered = grid.renderImage(
    font: .courierPrime(size: 10),
    backgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
    scale: 2
)
```

## Sampling Contract

The mask image is drawn into the output grid's exact `columns x rows` cell size. If the mask aspect ratio differs from the source image's aspect ratio, the mask is stretched to the grid. This is intentional: callers that need aspect-fit or aspect-fill mask placement should render that placement into a `CGImage` before calling Aski.

`softEdges: true` preserves grayscale luminance as coverage. `softEdges: false` thresholds luminance at `0.5`. `invert: true` flips coverage after thresholding, so hard inverted masks remain binary.

## Active-Region Grounds

``BuiltInPalette/fullColor`` keeps each glyph close to its source cell's color. When those glyphs are composited over the same photograph, they can merge visually with the image. Set ``MaskOptions/groundColor`` to put a caller-selected raster color behind glyphs or tiles only in the active mask branch.

The renderer completes both branches before it applies mask coverage:

```text
active   = glyphs over (ground over canvas)
inactive = fallback over canvas
result   = mix(inactive, active, maskCoverage)
```

This order matters at a soft boundary. Coverage interpolates once between the completed branches; it is not multiplied into glyph or tile alpha before that interpolation. Opaque and partially transparent grounds are supported. A `nil`, zero-alpha, or non-finite-alpha ground is an effective no-op and keeps the legacy raster path. Hard masks use the same branch model with binary coverage.

The following complete recipe uses the source photograph as both the canvas and the inactive-region fallback, then adds `#080808` behind the active glyphs:

```swift
import Aski
import CoreGraphics

let groundComponent = CGFloat(8) / 255
let mask = MaskOptions(
    image: maskCGImage,
    fallback: .originalImage(sourceImage, sizing: .fill),
    groundColor: CGColor(
        red: groundComponent,
        green: groundComponent,
        blue: groundComponent,
        alpha: 1
    ),
    softEdges: true
)

let grid = DefaultConverter().convert(sourceImage, columns: 60, mask: mask)
let rendered = grid.renderImage(
    font: .courierPrime(size: 8),
    backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
    scale: 1,
    composition: CompositionOptions(
        background: .original(sourceImage, sizing: .fill)
    )
)
```

Without a ground, the source-colored glyphs nearly disappear into the photograph:

![Source-colored glyphs over the same photograph without an active-region ground.](mask-ground-before.png)

With the `#080808` ground, the same glyphs remain distinct inside the mask:

![The same glyphs over a dark active-region ground.](mask-ground-after.png)

Both images use the same NASA public-domain `james-lovell-portrait.jpg` corpus asset, circle mask, full-color palette, 60 columns, Courier Prime 8-point font, and scale `1`. From the package root, regenerate the DocC assets and their reusable circle-mask input with this exact command:

```bash
ASKI_RECORD_MASK_GROUND_DOCC=1 just test-snapshots
```

## Command-Line Photo Dissolve

`aski render` uses the same converter and raster renderer as the library. This command uses the same portrait and generated circle mask as the library recipe above:

```bash
swift run aski render \
  docs/Research/Corpus/nasa-occupancy-v1/assets/james-lovell-portrait.jpg \
  --columns 60 \
  --font-size 8 \
  --render-png mask-ground-cli.png \
  --mask Sources/Aski/Aski.docc/Resources/mask-ground-circle.png \
  --mask-fallback original \
  --mask-fallback-sizing stretch \
  --mask-ground "#080808"
```

The matching library form uses the same mask/fallback/ground choices. The CLI has no image-composition option, so this form intentionally uses the normal opaque-black render background instead of a composition background:

```swift
let cliMask = MaskOptions(
    image: maskCGImage,
    fallback: .originalImage(sourceImage, sizing: .stretch),
    groundColor: CGColor(red: 8 / 255, green: 8 / 255, blue: 8 / 255, alpha: 1)
)
let cliGrid = DefaultConverter().convert(sourceImage, columns: 60, mask: cliMask)
let cliImage = cliGrid.renderImage(
    font: .system(size: 8),
    backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
    scale: 1,
    preserveSourceAspect: true
)
```

`--mask` alone also works for plain-text output: coverage below `0.5` becomes spaces. With a mask, the fallback defaults to `transparent`; original-image sizing defaults to `stretch`. `--mask-fallback solid` requires `--mask-fallback-color`, and `solid`, `original`, and `--mask-ground` require `--render-png`. Use `--mask-hard-edges` to threshold at `0.5` and `--mask-invert` to invert the resulting coverage. `clear` and `transparent` are not valid solid fallback colors or grounds.

When `--write-manifest` is present, render-manifest v1 adds a `mask` block only when `--mask` is supplied. That additive block records the resolved mask path, fallback, optional color or sizing, optional ground, hard-edge mode, and inversion state.

## Fallbacks

``MaskFallback/transparent`` shows the render background wherever coverage is zero.

``MaskFallback/solid(_:)`` paints a color behind cells in masked-out regions only.

``MaskFallback/originalImage(_:sizing:)`` paints an image behind masked-out regions using the same ``BackgroundSizing`` cases as composition backgrounds: ``BackgroundSizing/fill``, ``BackgroundSizing/fit``, and ``BackgroundSizing/stretch``.

``MaskFallback/character(_:color:)`` is available for ASCII grids. `color: nil` preserves each cell's display color and swaps only the glyph. A non-nil color paints fallback glyphs uniformly. Tile grids treat character fallbacks as transparent.

Fallbacks are never painted as a full backing layer. Without an effective ground, the renderer retains the legacy coverage path and an all-white mask renders identically to an unmasked grid. With a positive-alpha ground, the fallback completes the inactive branch and the ground completes the active branch before final coverage interpolation. A ground still applies when the sampled mask is entirely white.

Plain-text and attributed-string renderers threshold coverage at `0.5`: visible cells render normally, masked-out cells render the replacement character when ``MaskFallback/character(_:color:)`` is set, and otherwise render as spaces. These text renderers ignore ``MaskOptions/groundColor`` because it is a raster-only option.

## Effects

When a positive-alpha ground is present, effects renderers keep per-character effects and color overlays inside the active branch. They use Core Image `CIBlendWithMask` only after the active and inactive branches are complete, then apply lighting and the whole-image ``EffectChain``. Ground-enabled pixel-art, brick, and mosaic tile renders use this same grouped effects path; no-ground tile renders keep their direct legacy paths. See <doc:Effects> for the full ordering.
