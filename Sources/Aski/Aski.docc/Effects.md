# Effects, Composition, and Lighting

Build styled ASCII and tile renders with Core Image composition, lighting, and ordered effect chains.

## Overview

Aski's effects pipeline transforms ``ASCIIGrid`` and ``TileGrid`` output through a Core Image graph:

1. Resolve the background.
2. Rasterize cells.
3. When per-character bloom or chromatic aberration is enabled, derive the glyph or cell alpha mask; otherwise
   skip mask construction.
4. Apply the enabled per-character effects.
5. Apply color overlay.
6. Compose mask branches. With a positive-alpha ``MaskOptions/groundColor``, the active branch is the processed cells over the ground and canvas, the inactive branch is the fallback over the canvas, and coverage blends those completed branches once. Without an effective ground, keep the legacy fallback and cell-coverage graph.
7. Apply radial lighting to the branch-blended image.
8. Run the ordered ``EffectChain`` on the whole image.
9. Render a final `CGImage` or return a `CIImage`.

The original `renderImage` entry points remain source-compatible. New composition, lighting, and effects parameters default to no-op values.

Active-region grounds use the same grouped ordering in synchronous and asynchronous `CGImage` and `CIImage` paths. Per-character bloom, per-character chromatic aberration, and color overlays stay inside the active branch; lighting and whole-image effects always run after mask interpolation. Ground-enabled pixel-art, brick, and mosaic tile renders enter this effects pipeline, while no-ground tile renders keep the direct legacy renderer. See <doc:Masking> for the branch equations, fallback semantics, and a same-source example.

## ASCIIGrid quick start

```swift
import Aski
import CoreGraphics

let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
let grid = DefaultConverter().convert(image, columns: 120)

let rendered = grid.renderImage(
    font: .system(size: 14),
    backgroundColor: background,
    scale: 2,
    composition: CompositionOptions(
        background: .blurred(image, radius: 16, opacity: 0.6, sizing: .fill),
        characterBlendMode: .screen,
        colorOverlay: ColorOverlay(
            color: CGColor(red: 1, green: 0.8, blue: 0.6, alpha: 1),
            blendMode: .multiply
        ),
        perCharacter: PerCharacterEffects(
            bloom: BloomOptions(intensity: 0.4, radius: 8)
        )
    ),
    lighting: LightingOptions(
        lights: [
            PointLight(
                position: CGPoint(x: 0.7, y: 0.3),
                radius: 0.4,
                intensity: 1.2,
                color: CGColor(red: 1, green: 0.8, blue: 0.4, alpha: 1)
            )
        ],
        ambient: 0.6
    ),
    effects: EffectChain([
        .scanLines(intensity: 0.6, frequency: 4),
        .filmGrain(intensity: 0.15, seed: 42),
        .vignette(intensity: 0.4),
    ])
)
```

## Live preview

Use ``AskiRenderEngine`` when rendering from an async preview loop. The actor delegates to the same render paths as the grid APIs and exposes ``AskiRenderEngine/flushCaches()`` for memory-pressure handling.

```swift
let engine = AskiRenderEngine()
let image = try await engine.render(
    grid,
    font: .system(size: 14),
    backgroundColor: background,
    scale: 2,
    composition: composition,
    effects: effects
)
```

Use ``AskiRenderEngine/deviceCapability`` to decide whether to present full-quality or reduced-quality labels in UI.

## CIImage output

Use `renderCIImage` when the caller owns the final Core Image render or wants to compose Aski output into a larger graph.

```swift
let ciImage = grid.renderCIImage(
    font: .system(size: 14),
    backgroundColor: background,
    scale: 2,
    composition: composition,
    effects: effects
)
```

The sync overloads absorb effect failures and return fallback output. The async overloads throw ``EffectError`` so preview pipelines can distinguish cancellation, unsupported blend modes, and degenerate output.

## Effect ordering

``EffectChain`` honors array order. Recommended ordering:

- Early: `bloom`, `chromaticAberration` to emphasize highlights and fringes.
- Middle: composition-stage overlays, then `vignette`.
- Late: geometric effects such as `crtCurvature`, `pixelate`, and `halftone`.
- Last: `filmGrain` and `filmDust`, so film texture sits on top.

## Determinism and seeds

`filmGrain`, `glitch`, and `filmDust` take a `seed: UInt64`. With the same machine, OS, render path, and Apple GPU family, seeded stochastic effects are intended to produce byte-identical output.

## Applying effects per frame (video)

When the same ``EffectChain`` is rendered across a sequence of frames — as `aski lab video` does via the `renderImage(…, effects:)` overload — prefer **time-invariant** effects (`bloom`, `scanLines`, `vignette`) that use the same parameters every frame. Holding the parameters constant makes the overlay temporally stable: it is a deterministic function of the frame and carries no per-frame phase, so it cannot shimmer. The stochastic effects (`filmGrain`, `glitch`, `filmDust`) reseed per call; varying their seed per frame injects per-frame noise that flickers in the band the eye is most sensitive to, so they are intended for stills or a single held frame, not animated sequences. The video lab therefore exposes only the three time-invariant cosmetics. Animate brightness or coverage with ``ASCIIGrid/applyingOngoingPattern(_:at:)`` instead — it carries an explicit, phase-coherent time parameter.

A note on `scanLines` visibility: ASCII output is already a dense, high-frequency texture, so fine scanlines tend to read subtly against the glyph grid (and any downscaled preview blurs them further). The default `frequency` of `8` is intentionally conservative — it minimizes moiré at arbitrary output scales. Raise `frequency` (e.g. `16`–`40`, larger = wider, more prominent bands) when you want the CRT scanline look to be clearly visible at the final display size; the banding is most apparent at 1:1 pixels.

## Async cancellation

The async overloads check `Task.checkCancellation()` between effect-chain steps. The final `CIContext.createCGImage` render is atomic; cancellation arriving during that call lands after it returns.

## GPU-family fallback

Seven effects require stitchable Metal kernels: `scanLines`, `crtCurvature`, `halftone`, `filmDust`, `glitch`, `rgbSplit`, and `filmGrain`. On devices without Apple GPU family 6 or newer, each effect substitutes a Core Image approximation and the engine reports ``DeviceCapability/reducedQuality(_:)``.

``DeviceCapability/full`` means the full effect roster is available.

## Topics

### Composition

- ``CompositionOptions``
- ``Background``
- ``BackgroundSizing``
- ``ColorOverlay``
- ``PerCharacterEffects``
- ``BloomOptions``
- ``AberrationOptions``

### Lighting

- ``LightingOptions``
- ``PointLight``

### Effects

- ``Effect``
- ``EffectChain``
- ``AskiRenderEngine``
- ``DeviceCapability``
- ``EffectError``
