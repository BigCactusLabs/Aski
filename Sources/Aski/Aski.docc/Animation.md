# Animation

Synthesize time-based ASCII frames from one conversion pass.

## Overview

`ASCIIConverter.animate(_:columns:options:mask:)` converts a `CGImage` once, stores the matched base grid, and returns an `AnimatedASCIIGrid`. Use `grid(at:)` to synthesize frames lazily for live previews, or `materialize(frameRate:)` when a caller needs an array of frames.

```swift
let animated = DefaultConverter().animate(
    image,
    columns: 80,
    options: AnimationOptions(
        duration: 2,
        seed: 42,
        cycling: .default,
        entrance: .cascadeLR(easing: .easeOut),
        ongoing: .pulse(period: 1.2, depth: 0.35)
    )
)

let frame = animated.grid(at: 0.5)
let rendered = animated.renderImage(
    at: 0.5,
    font: .system(size: 12),
    backgroundColor: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
    scale: 2
)
```

Cycling rotates each participating cell through character candidates. With `.dotMatrix`, the base frame keeps the Floyd–Steinberg pick, and later slots use the glyphs nearest to that pick in normalized ink density. These alternatives do not affect error diffusion. With `.logPolar`, candidates follow the shape matcher ranking. Entrance and ongoing alpha patterns work with either algorithm.

Mask coverage is preserved on every synthesized frame. Renderers remain responsible for multiplying cell alpha by coverage, so masked cells are not dimmed twice.

To apply an ongoing pattern's alpha modulation to an arbitrary grid — for example, overlaying a pulse or wave on each video frame at its presentation time — use ``ASCIIGrid/applyingOngoingPattern(_:at:)``. It is a pure function of `(pattern, time)`, so feeding each frame its own timestamp keeps the global phase coherent across frames.

## Frame sampling and memory

`grid(at:)` samples lazily. Negative or non-finite times resolve to zero; finite
times beyond `duration` remain sampleable, so ongoing patterns and cycling can
continue after the entrance finishes. The same animation and time reproduce the
same grid; raster output still depends on the font, render path, and host.

`materialize(frameRate:)` allocates a full grid for every cadence step and includes
the duration endpoint. It requires a positive frame rate and at most
``AnimatedASCIIGrid/maxMaterializedFrameCount`` frames (10,000), rejecting an
oversized request rather than truncating it. Prefer `grid(at:)` when a preview or
encoder can consume frames individually.

The `AnimatedASCIIGrid.renderImage(at:...)` convenience uses the default glyph-cell
aspect. To use `preserveSourceAspect: true` or `targetPixelWidth:`, sample a grid and
call its renderer directly; see <doc:Rendering> and <doc:Duotone>. To convert a
changing source clip rather than animate one image, use <doc:Video>.

## Topics

### Creating Animations

- ``ASCIIConverter/animate(_:columns:options:mask:)``
- ``AnimationOptions``
- ``AnimatedASCIIGrid``

### Cycling

- ``CyclingOptions``

### Patterns

- ``EntrancePattern``
- ``OngoingPattern``
- ``WaveDirection``
- ``AnimationEasing``
- ``AnimationAnchor``
- ``ASCIIGrid/applyingOngoingPattern(_:at:)``
