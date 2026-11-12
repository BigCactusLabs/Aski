---
id: ASKI-104
title: CLI loader samples portraits at half the intended cell width
status: Done
assignee: []
created_date: '2026-11-10T20:31:00Z'
updated_date: '2026-11-10T21:20:00Z'
labels:
  - correctness
  - cli
  - sampling
dependencies: []
priority: high
type: bug
ordinal: 105000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
aski render and aski inspect (and AskiTileMatrix and aski lab motion --image) decode files through DemoImageIO.loadThumbnailForConversion (Tools/AskiToolSupport/ImageFileIO.swift), which caps the decoded thumbnail's longest side at ToolArgumentBounds.thumbnailMaxPixelSize = max(columns, rows) x oversample. That copy of the converter's budget never gained the portrait branch of ASCIIConverter.thumbnailMaxPixelSize (Sources/Aski/ASCIIConverter.swift), so on a portrait the cap lands on the height and the width falls well below columns x oversample. Example, release aski at d53570d: aski inspect docs/Research/Corpus/nasa-occupancy-v1/assets/james-lovell-portrait.jpg --columns 60 --format json reports normalizedPixelWidth 91 (height 120), so the converter samples cellWidth 1 where the budget intends 2. The converter then treats the 91x120 thumbnail as within its own budget and does not correct it. Two further gaps found while probing (2026-11-10): (1) the loader sizes from the stored pixel dimensions, but ImageIO applies EXIF orientation, so a portrait stored landscape with orientation 5-8 (the usual phone-camera layout) is budgeted as a landscape; (2) even at the library's portrait cap, ImageIO can land the width one pixel under the floor of the proportional size because it floors through a power-of-two subsample before scaling (Lovell at 60 columns: cap 158, proportional width 120.35, decoded 119). PR #23 (ASKI-1) fixes the library's own CGImage path and does not touch the CLI loader.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The CLI loader sizes its decode from the converter's own budget rule instead of a copy of it
- [x] #2 Portrait sources, including EXIF-rotated ones, decode at a width of at least columns x oversample when the source is that wide, and aski render samples them at cellWidth == oversample at default settings
- [x] #3 Landscape and square CLI decodes are unchanged
- [x] #4 A regression test pins portrait normalizedPixelWidth >= columns x oversample, the ImageIO undershoot case, an EXIF-rotated portrait, and unchanged landscape and square sizes
- [x] #5 CHANGELOG and the CLI normalization docs describe the new behavior
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-10: fixed on branch aski-104-cli-portrait-budget. ASCIIConverter and TileGridConverter gain package preparationMaxPixelSize(sourceWidth:sourceHeight:columns:); the loader takes the converter and asks it for the size, from displayed (EXIF-oriented) dimensions, and retries one pixel larger while a portrait decodes narrower than floor(cap x W/H). ToolArgumentBounds.thumbnailMaxPixelSize deleted; the shape-residual lab keeps its old formula as a private helper. Lovell at 60 columns now decodes 120x159 (was 91x120). ConversionThumbnailLoaderTests pins portrait width, cellWidth == oversample and supportsShapeDescriptor, EXIF orientations 5-8, and unchanged landscape/square sizes. No goldens moved, so no census. just check green on the committed tree. Follow-up: TileGridConverter's own size rule has no portrait case, so tile-matrix portraits still undersample.

2026-11-10: PR #24 merged as c84199d (merge tree = gated head e77a219, which includes main d6d838d with PR #23). just check passed on e77a219 under the shared lock: 1483 + 163 + 2 tests plus DocC. The TileGridConverter portrait follow-up is ASKI-105 (PR #25).
<!-- SECTION:NOTES:END -->
