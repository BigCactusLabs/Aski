# Tile-grid Modes

Convert images to colored cell grids — pixel-art, brick, or mosaic styles in five cell shapes.

## Overview

The Tile API mirrors Aski's ASCII pipeline with one substitution: per-cell character matching is replaced by per-cell color quantization. The output is ``TileGrid``, a `Sendable` structural intermediate that carries no mode or
cell-shape configuration (it does retain grid-level render metadata — color space and
mask-fallback settings — from conversion). Mode and cell-shape are render-time parameters on ``TileGrid/renderImage(mode:cellShape:scale:backgroundColor:)``, so a single grid can be re-rendered with different visual styles without re-running the converter's sampling and quantization stages — "convert once, render many."

Given an `image: CGImage` (see <doc:GettingStarted> for image loading):

```swift
import Aski

let converter = TileGridConverter(palette: .adaptive(maxColors: 16))
let grid = converter.convert(image, columns: 80)

let pixelArtImage = grid.renderImage(mode: .pixelArt, cellShape: .square, scale: 16)
let brickImage    = grid.renderImage(mode: .brick,    cellShape: .hex,    scale: 16)
let mosaicImage   = grid.renderImage(mode: .mosaic(groutThickness: 0.05), cellShape: .square, scale: 16)
```

Tile grids support the same ``MaskOptions`` conversion parameter as ASCII grids. Pixel-art and brick modes apply coverage per tile; mosaic mode applies coverage to the complete raster so grout fades with the tile content. ``MaskFallback/transparent``, ``MaskFallback/solid(_:)``, and ``MaskFallback/originalImage(_:sizing:)`` work for tile grids; ``MaskFallback/character(_:color:)`` is ASCII-only and is treated as transparent for tiles.

## Choosing a mode and cell shape

3 modes × 5 cell shapes = 15 visual combinations.

| | pixelArt | brick | mosaic |
|---|---|---|---|
| **square** | flat color | color + circular stud | rounded-corner inset, grout gap |
| **hex** | flat color, offset rows | hex color + circular stud | rounded hex inset, grout gap |
| **triangle** | alternating up/down triangles | triangle + small stud at centroid | rounded triangle inset, grout gap |
| **diamond** | 45° rotated square | diamond + circular stud | rounded diamond inset, grout gap |
| **circle** | filled circles, gaps show background | concentric circles | filled circles with grout-filled gaps (no corner rounding) |

`circle` does not tile completely — gaps show the background (or the grout color in mosaic mode). This is the expected aesthetic.

`brick × triangle` places the stud at the triangle's geometric centroid (one-third up from the base, not center).

## Sampling fidelity

Sampling happens on a rectangular grid regardless of `cellShape`. Renderers position the rectangular sample cells per shape — hex/triangle/diamond cells leave a fringe of unrepresented source pixels at the edges. Inspect the result at its intended display size, especially when edge placement or mask alignment matters; changing the cell shape is a visual treatment, not a new source-sampling lattice.

## Palette strategies

``TilePalette`` exposes three strategies:

- ``TilePalette/adaptive(maxColors:)`` — Wu's algorithm + k-means refinement in OKLab. Output has at most `maxColors` entries (clamped to `2...256`); fewer if the source has fewer distinct colors.
- ``TilePalette/brick`` — approximated interlocking-brick-style palette (~30 colors).
- ``TilePalette/fixed(_:)`` — caller-supplied non-empty `[CGColor]` converted to OKLab at construction.

Adaptive quantization runs at convert time on the raw thumbnail pixels (not on per-cell averaged stats — averaging would smear the source distribution before clustering can find it).

`TilePalette.fixed([])` is programmer error and traps with a precondition; an empty fixed palette is not a pass-through signal. If adaptive quantization finds no visible source pixels, such as a fully transparent input, the converter treats that result as pass-through internally instead of indexing an empty concrete palette.

## Brick palette: non-affiliation disclaimer

The ``TilePalette/brick`` palette and ``TileGridMode/brick`` rendering ship approximated interlocking-brick-style colors and a circular-stud overlay, based on publicly-referenced values from BrickLink's Color Guide and the LDraw colour reference. Aski is not affiliated with the LEGO Group; LEGO® is a trademark of the LEGO Group and is not used in Aski's API surface or color names. The palette and rendering style are a generic stylistic reference, not a licensed reproduction.

## Rendering tradeoffs

- **`scale` semantics** are pixels per cell *width*. For non-square shapes the bounding-box height varies (hex height ≈ 1.155 × scale; triangle height ≈ 0.866 × scale).
- **Performance depends on the workload.** Grid dimensions, output scale, palette quantization, cell shape, effects, and hardware all matter. Start with a small preview, reuse the converted grid for style changes, and measure your target device before choosing a live-preview budget. Repository benchmarks are available through `just bench`; timings from one machine are not a device-wide guarantee.
- **Conversion is synchronous.** Keep substantial conversion work off the main actor using an appropriately isolated task or background queue.

## Topics

### Converting Images

- ``TileGridConverter``
- ``TileGrid``
- ``TileCell``

### Configuring the Output

- ``TileGridMode``
- ``TileCellShape``
- ``TilePalette``
