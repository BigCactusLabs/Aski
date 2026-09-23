# The Vesper Preset

One fixed recipe: block glyphs, bone ink, oxblood accents, and a charcoal canvas.

## Overview

``VesperPreset`` bundles a converter recipe and its rendering parameters into one
canonical configuration, ``VesperPreset/canonical``. It is a library preset, not a
separate Vesper app distributed with this package.

Given a portrait as a `CGImage`:

```swift
import Aski

let shareImage = VesperPreset.canonical.render(portrait)
```

``VesperPreset/render(_:)`` returns a `CGImage`. It converts at the preset's column
count and uses `preserveSourceAspect: true`, preserving the source aspect in the render.
The recipe is intentionally fixed rather than a general preset system.

## The frozen recipe

The configuration was selected through the portrait charset × columns A/B retained
in the preset lab. These are the choices for that look, not universal best settings:

- **Block glyphs:** `.blocks`, `.logPolar`, and the `.wide` tile shape.
- **76 columns:** selected within the 72–80 range examined at portrait thumbnail scale.
- **Bone and oxblood:** `#E8E2D2` ink declared in sRGB and `#5E1B18` accent declared in
  Display P3. Their declared color spaces are part of the recipe.
- **+0.15 contrast:** an OKLab-lightness adjustment. The preset enables none of the
  failed or inconclusive production controls removed in ASKI-68.
- **Display P3 output and 2× oversampling:** fixed conversion settings, not a promise
  that more oversampling would improve matching.
- **Courier Prime at 14 pt, rendered at 2×:** the bundled font is part of the recipe.
- **Charcoal canvas:** `#161616`, a deliberate alternative to pure black.

Golden tests protect intentional recipe changes. A bundled font reduces one source of
variation; it does **not** guarantee identical Core Text or GPU output on every OS and
device. The v0.7.0 render goldens were recorded on macOS 27 / Xcode 27. Compare on the
recorded toolchain before deciding that a snapshot difference is a preset regression.

The current matcher has measured limitations even on this preset. See <doc:Algorithms>
and the repository's [research index](https://github.com/BigCactusLabs/Aski/blob/main/docs/Research/README.md)
for the evidence and product-probe work. Freezing a recipe protects a look; it does not
establish universal perceptual superiority.

## Compose with the pieces

``VesperPreset/makeConverter()`` returns an
`ASCIIConverter<StandardCharacterSet, BuiltInPalette>` for callers that need the grid
rather than a finished raster—for example, attributed text or animation.
``VesperPreset/font`` exposes the bundled font at the preset's point size.

The memberwise
``VesperPreset/init(columns:ink:accent:contrast:colorSpace:oversample:fontSize:scale:backgroundColor:)``
lets labs and tests construct variants. Use ``VesperPreset/canonical`` when your
integration needs the documented Vesper look; variants are your own recipes.

## Topics

### The preset

- ``VesperPreset``
- ``VesperPreset/canonical``
- ``VesperPreset/render(_:)``

### Recipe components

- ``VesperPreset/makeConverter()``
- ``VesperPreset/font``
