# The Vesper Preset

The single frozen render recipe the Vesper app ships.

## Overview

``VesperPreset`` bundles a complete converter recipe *and* the render parameters (font, ground color, output scale) into one drift-proof source of truth. It is deliberately one recipe, not a preset *system*: the app calls exactly one entry point, ``VesperPreset/render(_:)``, and there is exactly one canonical configuration, ``VesperPreset/canonical``.

```swift
import Aski

let shareImage = VesperPreset.canonical.render(portrait)
```

`render(_:)` converts the image at the preset's column count and renders it with `preserveSourceAspect: true`, so the output reproduces the source image's aspect ratio.

## The frozen recipe

Every knob is a settled one-way-door choice, resolved on rendered evidence (the `AskiPresetLab` charset × columns A/B) rather than intuition:

- **Charset and matching** — `.blocks` under the `.logPolar` algorithm with the `.wide` tile shape: a bold duotone look.
- **76 columns** — reads best at 9:16 thumbnail scale; the 72–80 band won the A/B (60 is coarse, 96 muddies).
- **Bone ink on oxblood ground** — a fixed two-color palette. The ink (`#E8E2D2`, sRGB) is high-lightness and near-neutral, owning the mids and highlights; the accent (`#5E1B18`, Display P3) is darkened so its OKLAB basin retreats to the shadows, making red the figure/ground field rather than a mid-tone-grabbing crimson.
- **+0.15 contrast** — an OKLAB-L contrast bump for gothic shadows. ASKI-68 removed the failed or inconclusive production controls; the preset enables no experimental treatment.
- **Display P3 output** — the gothic red sits outside sRGB gamut on P3 phones.
- **2× oversample** — the shipping coverage-sampling default; balances fidelity and cost.
- **Bundled Courier Prime at 14 pt, @2x scale** — a bundled font keeps the byte snapshot deterministic across devices.
- **Charcoal background (`#161616`)** — never pure black, which would halate around bright glyphs on OLED.

## Composing with the pieces

``VesperPreset/makeConverter()`` returns the frozen `ASCIIConverter<StandardCharacterSet, BuiltInPalette>` on its own, for callers that want the recipe's grid without the image render — for example to feed ``ASCIIGrid/renderAttributedString()`` or an animation pipeline. ``VesperPreset/font`` exposes the bundled Courier Prime at the preset's point size.

The memberwise ``VesperPreset/init(columns:ink:accent:contrast:colorSpace:oversample:fontSize:scale:backgroundColor:)`` exists so labs and tests can build variants, but app code should treat ``VesperPreset/canonical`` as the only configuration.

## Topics

### The preset

- ``VesperPreset``
- ``VesperPreset/canonical``
- ``VesperPreset/render(_:)``

### Recipe components

- ``VesperPreset/makeConverter()``
- ``VesperPreset/font``
