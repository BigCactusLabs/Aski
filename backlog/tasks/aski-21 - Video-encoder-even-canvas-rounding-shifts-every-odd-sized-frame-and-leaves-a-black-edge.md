---
id: ASKI-21
title: >-
  Video encoder even-canvas rounding shifts every odd-sized frame and leaves a
  black edge
status: Done
assignee: []
created_date: '2026-08-19 05:23'
updated_date: '2026-08-24 15:36'
labels:
  - correctness
  - video
  - rendering
dependencies: []
references:
  - Sources/Aski/Video/ASCIIVideoEncoder.swift
  - Sources/Aski/Renderers/ImageRenderer.swift
priority: medium
type: bug
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ASCIIVideoEncoder` rounds the first frame's dimensions up to even (`even(_:)`, required for 4:2:0 codecs) but then draws each frame at `CGRect(x: 0, y: 0, width: image.width, height: image.height)`. In a CGBitmapContext the coordinate origin is bottom-left while memory row 0 is the TOP of the raster, so an odd-height frame lands one pixel low: the top scanline stays at the fill colour (black) and the whole picture is displaced down by one pixel. An odd width leaves the same artefact as a black column on the right.

Confirmed by reproducing the exact draw: a 4x3 source into the 4x4 canvas produces raster row0 = 0,0,0,0 (black) with the content in rows 1..3.

Odd dimensions are the common case, not an exotic one. Pixel size is `ceil(columns * pointSize * 0.6 * scale)` by `ceil(rows * pointSize * 1.2 * scale)`, and at the default 12pt/1x the width alone is odd for columns = 2, 4, 7, ... — so a large share of real exports carry the artefact on one or both axes.

Impact is cosmetic but systematic: a black scanline on every frame of the output MP4, plus a one-pixel vertical offset against the SDR render the same grid produces through renderImage. It also breaks pixel alignment for anyone diffing an exported frame against a direct render.

The fix is to place the image deliberately within the padded canvas — either anchor it at the top (`y = canvasHeight - image.height`) so the padding falls where a codec crop would expect it, or centre it — and to state which choice the encoder makes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An odd-width and/or odd-height rendered frame is placed at a documented, deliberate position within the even canvas, with no black scanline on the leading edge
- [x] #2 Exported frame pixels align with the same grid rendered directly through ASCIIGrid.renderImage, within the stated padding rule
- [x] #3 Even-dimension frames encode byte-identically to today
- [x] #4 Regression covers odd width only, odd height only, and both odd, asserting the padded rows and columns land where the rule says
- [x] #5 just check passes and the video suite stays green
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board audit 2026-08-24: implemented and merged to main in PR #28 (batch-validation wave, merge b835160); all ACs were already checked — status flip only.
<!-- SECTION:NOTES:END -->
