---
id: ASKI-24
title: cgColorToOKLAB fast path reads components without the guard its fallback has
status: Done
assignee: []
created_date: '2026-08-19 05:25'
updated_date: '2026-08-20 04:14'
labels:
  - correctness
  - color
  - input-validation
dependencies: []
references:
  - Sources/Aski/ColorConversion.swift
  - Sources/Aski/Tiles/TilePalette.swift
priority: low
type: bug
ordinal: 26000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ColorConversion.cgColorToOKLAB` has two branches with different safety. The slow path guards before reading:

    guard let converted = color.converted(to: cgSRGBColorSpace, ...),
        let components = converted.components,
        components.count >= 3
    else { return SIMD3<Float>(0, 0, 0) }

The two fast paths — taken when the CGColor is already tagged sRGB, linearSRGB or displayP3 — read `components[0]`, `[1]` and `[2]` with no count check, falling back only to a hardcoded `[0, 0, 0, 1]` when `components` is nil. A CGColor tagged with an RGB-named space but carrying fewer than three components traps on the subscript.

This is reachable from public API: `TilePalette.fixed(_ colors: [CGColor])` maps caller-supplied CGColors straight through this function, so the input is not library-controlled.

The trap is unlikely in practice — CoreGraphics normally keeps component count consistent with the colour space — which is why this is low, not medium. But the function is written as if the count cannot be trusted (that is what the fallback branch's guard is for), and the two branches should not disagree about that.

Also worth settling while in here: the documented behaviour on failure is 'returns OKLAB black (caller's responsibility per spec section 4)'. A trap is not that.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Both fast paths validate components.count >= 3 before subscripting, matching the fallback path
- [x] #2 A CGColor tagged sRGB, linearSRGB or displayP3 with fewer than three components returns the documented OKLAB black instead of trapping
- [x] #3 Conversion results for all well-formed colours are byte-identical, including the linearSRGB no-decode branch and the P3 branch
- [x] #4 Regression covers a short-component colour on each fast path and on the fallback path, driven through TilePalette.fixed as well as directly
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Landed in merge commit da78b1a (Batch A).

cgColorToOKLAB's two fast paths (sRGB/linearSRGB and displayP3) read components[0...2] with no count check while the slow converted path guarded. All three now route through one ColorConversion.rgbTriple(from:) helper that checks for nil and count >= 3 in a single place, so a short-component colour returns the documented OKLAB black instead of trapping.

Reachable from public API via TilePalette.fixed, which is how the regression drives it rather than only calling the converter directly.

Coverage: ColorConversionShortComponentTests — a short-component colour on each fast path and on the fallback path, both directly and through TilePalette.fixed. Byte-identity for well-formed colours is asserted with Float.bitPattern equality (no epsilon), including the linearSRGB no-decode branch and the P3 branch; the colour surface had no baseline coverage, so the goldens capture pre-change values.
<!-- SECTION:NOTES:END -->
