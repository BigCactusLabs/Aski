---
id: ASKI-43
title: Add an active-region mask ground for source-colored glyph legibility
status: Done
assignee: []
created_date: '2026-08-20 23:58'
updated_date: '2026-08-27 12:32'
labels:
  - masking
  - rendering
  - api
  - docs
dependencies: []
references:
  - 'Source tracker issue #7 (not migrated)'
  - >-
    https://developer.apple.com/documentation/coreimage/ciblendwithmask/maskimage
  - 'https://www.w3.org/TR/css-masking-1/'
documentation:
  - Sources/Aski/Aski.docc/Masking.md
  - Sources/Aski/Aski.docc/Effects.md
modified_files:
  - Sources/Aski/Masking/MaskOptions.swift
  - Sources/Aski/ASCIIGrid.swift
  - Sources/Aski/Tiles/TileGrid.swift
  - Sources/Aski/ASCIIConverter.swift
  - Sources/Aski/Tiles/TileGridConverter.swift
  - Sources/Aski/Animation/AnimatedASCIIGrid.swift
  - Sources/Aski/Animation/ASCIIGrid+OngoingPattern.swift
  - Sources/Aski/Effects/AskiRenderEngine.swift
  - Sources/Aski/Masking/MaskRenderInput.swift
  - Sources/Aski/Masking/MaskFallbackImageFactory.swift
  - Sources/Aski/Masking/MaskCompositor.swift
  - Sources/Aski/Effects/Internal/CellRasterBuilder.swift
  - Sources/Aski/Effects/ASCIIGrid+Effects.swift
  - Sources/Aski/Effects/TileGrid+Effects.swift
  - Sources/Aski/Tiles/TileGrid+Rendering.swift
  - Sources/Aski/Renderers/ImageRenderer.swift
  - Sources/Aski/Aski.docc/Masking.md
  - Sources/Aski/Aski.docc/Effects.md
  - CHANGELOG.md
  - Tests/AskiTests/MaskOptionsTests.swift
  - Tests/AskiTests/ASCIIConverter+MaskTests.swift
  - Tests/AskiTests/TileGridConverter+MaskTests.swift
  - Tests/AskiTests/ImageRenderer+MaskTests.swift
  - Tests/AskiTests/AnimationMaskCompositionTests.swift
  - Tests/AskiTests/AskiRenderEngineTests.swift
  - Tests/AskiTests/TextRenderer+MaskTests.swift
  - Tests/AskiTests/MaskSnapshotTests.swift
priority: high
type: enhancement
ordinal: 45000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub issue #7 records a product-level compositing failure: `BuiltInPalette.fullColor` intentionally gives each glyph a color close to its source cell, so glyphs can nearly disappear when rendered over the same source photograph through `MaskFallback.originalImage` or a manual overlay. A contrasting backing color inside the active mask region restores the type, but `MaskOptions` currently controls only the inactive-region fallback.

Add a narrowly scoped, caller-controlled active-region ground to raster mask rendering. The public surface is `MaskOptions.groundColor: CGColor?`, defaulting to `nil`; `ASCIIGrid` and `TileGrid` retain the resolved value as `maskGroundColor`. Existing call sites remain source-compatible. A stored color with zero or non-finite alpha is an effective no-op and must take the legacy renderer path; positive-alpha colors, including partially transparent colors, use grouped mask composition.

The required soft-mask contract is:

```text
active   = glyphs over (ground over canvas)
inactive = fallback over canvas
result   = mix(inactive, active, maskCoverage)
```

Coverage is deferred until the completed branches are blended. Glyph/tile alpha is intrinsic inside the active branch. Per-character effects and color overlays occur before active-branch composition; lighting and the whole-image effect chain occur after the branch blend. Hard masks remain binary.

The nil/effective-no-ground path must stay on the current code path so existing snapshots and performance do not drift. A ground applies even when the sampled mask is entirely white. Plain-text and attributed-string output ignore it. The HDR SPI rejects any grid carrying a positive-alpha ground because masked ground composition is outside the current SDR/HDR alignment contract.

Tile grids honor the same public option. The direct Core Graphics tile renderer routes only ground-enabled renders through the existing effects engine, avoiding a second branch compositor; no-ground pixel-art, brick, and mosaic behavior stays unchanged.

Automatic contrast choice, blur/fog, gradients, halos, per-cell polarity changes, and a generic background abstraction remain out of scope and are tracked by ASKI-45 and its subtasks.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `MaskOptions` exposes `groundColor: CGColor? = nil`; `ASCIIGrid` and `TileGrid` expose `maskGroundColor: CGColor? = nil`; existing initializer call sites remain source-compatible.
- [x] #2 The converter stores fallback, hard-edge state, and ground only when mask sampling succeeds, and every grid-copy path (`AnimatedASCIIGrid`, ongoing-pattern copies, and `AskiRenderEngine` color-space adaptation) preserves all three fields.
- [x] #3 A nil, zero-alpha, or non-finite-alpha ground uses the legacy render path and remains byte-identical to current outputs for transparent, solid, original-image, and character fallbacks.
- [x] #4 A positive-alpha ground applies even for an all-white mask and supports opaque and partially transparent `CGColor` values in the grid color space.
- [x] #5 For fractional coverage, output pixels equal one interpolation between the completed inactive and active branches; cell coverage is not multiplied into glyph/tile alpha before the branch blend.
- [x] #6 Transparent, solid, original-image, and character fallbacks preserve their inactive-branch semantics, including original-image orientation and `fill`, `fit`, and `stretch` sizing.
- [x] #7 The basic ASCII Core Graphics renderer preserves `preserveSourceAspect`; effects sync/async and `CGImage`/`CIImage` paths implement the same grouped semantics.
- [x] #8 Ground-enabled pixel-art, brick, and mosaic renders use grouped semantics through the effects engine; every no-ground tile path remains unchanged.
- [x] #9 Per-character effects and color overlays stay inside the active branch; lighting and whole-image effects run after the masked branch blend.
- [x] #10 The extended-range HDR renderer returns `nil` for any grid with a positive-alpha mask ground, and its existing opaque/full-coverage contract remains documented.
- [x] #11 Plain-text and attributed-string output stays byte-identical and explicitly documents that raster grounds are ignored.
- [x] #12 Tests cover API storage/defaults, converter and grid-copy propagation, effective-no-ground parity, all-white masks, 0/fractional/1 coverage pixels, partial-alpha grounds, every fallback, source sizing, renderer parity, tile modes, HDR rejection, and text-renderer no-op behavior.
- [x] #13 `Masking.md` explains same-source disappearance and grouped branches, includes a complete `groundColor + originalImage` recipe and generated before/after assets, and `CHANGELOG.md` records the additive API without an accessibility-conformance claim.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Focused mask/render/animation tests pass with no snapshot loosening.
- [ ] #2 `just check` passes on the final implementation tree.
- [ ] #3 DocC, changelog, generated assets, and the issue/PR linkage are committed.
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
### File map and interfaces

- `Sources/Aski/Masking/MaskOptions.swift`: add `public let groundColor: CGColor?` and the defaulted initializer argument immediately after `fallback`.
- `Sources/Aski/ASCIIGrid.swift` and `Sources/Aski/Tiles/TileGrid.swift`: add `public let maskGroundColor: CGColor?` and a defaulted initializer argument immediately after `maskFallback`.
- `Sources/Aski/ASCIIConverter.swift`: extend `PreparedConversion` with `maskGroundColor`; set it to `mask?.groundColor` only when `MaskSampler.sample` succeeds; pass it through normal and ranked conversions.
- `Sources/Aski/Tiles/TileGridConverter.swift`: mirror the ASCII conversion propagation.
- `Sources/Aski/Animation/AnimatedASCIIGrid.swift`, `Sources/Aski/Animation/ASCIIGrid+OngoingPattern.swift`, and `Sources/Aski/Effects/AskiRenderEngine.swift`: preserve `maskGroundColor` in every grid reconstruction.
- `Sources/Aski/Masking/MaskRenderInput.swift`: add `activeGround: CIImage?`, a `usesGroupedComposition` computed property, and `effectiveMaskGroundColor(_:)` (`alpha.isFinite && alpha > 0`). A positive-alpha ground creates mask input even when every coverage value is 1; fallback-only input still requires coverage below 1.
- `Sources/Aski/Masking/MaskFallbackImageFactory.swift`: expose `makeGround(_:extent:colorSpace:)` using the existing solid-color normalization/conversion code.
- `Sources/Aski/Masking/MaskCompositor.swift`: add a finite-extent source-over helper for composing a full fallback or ground over the canvas; keep `blendWithMask` as the final branch interpolation.
- `Sources/Aski/Effects/Internal/CellRasterBuilder.swift`: add an internal `CellCoverageMode` with `.multiplyCoverage` and `.intrinsicAlpha`; default every existing call to `.multiplyCoverage`.
- `Sources/Aski/Effects/ASCIIGrid+Effects.swift`: retain the exact legacy graph when no effective ground exists; add the grouped graph only for a positive-alpha ground.
- `Sources/Aski/Effects/TileGrid+Effects.swift` and `Sources/Aski/Tiles/TileGrid+Rendering.swift`: defer coverage and skip mosaic pregating for grouped composition; route the basic tile API through the effects engine only when a positive-alpha ground exists.
- `Sources/Aski/Renderers/ImageRenderer.swift`: retain the existing function body as the legacy path; add a ground path that renders full active/inactive `CGImage` branches at the existing `RenderGeometry`, builds coverage with `CoverageImageBuilder`, and calls `MaskCompositor.blendWithMask` through the shared CI context. Add a coverage-mode argument to `drawCells`, defaulting to the current multiplication.

### Implementation sequence

1. Add failing API and propagation tests in `MaskOptionsTests`, `ASCIIConverter+MaskTests`, `TileGridConverter+MaskTests`, `AnimationMaskCompositionTests`, and `AskiRenderEngineTests`. Include a zero-alpha color that remains stored but is renderer-effective nil.
2. Add the new public fields and conversion/copy propagation. Run the focused propagation suites before touching compositing.
3. Add `CellCoverageMode` and prove `.multiplyCoverage` is byte-identical to the pre-change raster on existing fixtures. Add a focused intrinsic-alpha test showing a 0.5-coverage cell rasterizes at full intrinsic alpha when requested.
4. Extend `MaskRenderInput`, the color-image factory, and `MaskCompositor`. `makeASCIIMaskInput`/`makeTileMaskInput` must enter grouped mode whenever `effectiveMaskGroundColor` returns a color, including an all-white mask; no-ground fallback-only input keeps the current coverage-below-one guard. Unit-test alpha-preserving source-over and `CIBlendWithMask` branch interpolation with opaque and translucent branches.
5. Implement the effects grouped graph. The exact grouped order is: raster → per-character effects → color overlay → active over `(ground over canvas)`; inactive is `(fallback over canvas)`; coverage blends inactive/active; lighting; effect chain. Keep the old graph in a separate `else` branch rather than algebraically rewriting it.
6. Implement the basic ASCII ground path using the existing render geometry and Core Text/Braille drawing. Render fallback characters at full branch strength, not `1 - coverage`; final masking supplies the inverse weight. Add pixel tests for coverage 0, 0.5, and 1 on transparent and opaque canvases, plus `preserveSourceAspect` dimensions.
7. Implement tile grouped rendering. Pass `.intrinsicAlpha` to the tile raster builder and disable `pregateMosaicRasterIfNeeded` only when `activeGround != nil`. Route direct ground-enabled tile renders through `EffectsRenderEngine`; leave direct no-ground code untouched.
8. Add `maskGroundColor == nil || effective alpha == 0` to the HDR admissibility contract and add a rejection test for a positive-alpha all-white-mask grid.
9. Add same-source synthetic snapshots: one original-image fallback without ground and one with `#080808`; use the same source, mask, font, palette, columns, and scale. Generate DocC before/after assets from one existing public-domain corpus image and record the exact generation command in `Masking.md`.
10. Update `Masking.md`, the minimal cross-reference in `Effects.md`, `CHANGELOG.md`, and the generated repo map if public declarations move.

### Verification

Run focused red/green cycles while implementing, then:

```bash
xcrun swift test --filter 'MaskOptionsTests|ASCIIConverterMaskTests|TileGridConverterMaskTests'
xcrun swift test --filter 'ImageRendererMaskTests|AnimationMaskCompositionTests|AskiRenderEngineTests'
xcrun swift test --filter 'MaskSnapshotTests|TextRendererMaskTests'
just check-fast
just check
```

Do not loosen snapshot, benchmark, or test thresholds. No Metal source changes are expected.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design pass completed 2026-08-20. Implementation has not started.

Shipped in the four-task mask batch, PR #31 (merge f761952, 2026-08-27). MaskOptions.groundColor + grid maskGroundColor landed with the grouped soft-mask contract (active = glyphs over ground over canvas); nil/zero-alpha grounds stay byte-identical on the legacy path; HDR SPI rejects positive-alpha-ground grids; tile grids route ground-enabled renders through the effects engine. Same-source snapshots + DocC before/after assets committed. Full just check green before merge.
<!-- SECTION:NOTES:END -->
