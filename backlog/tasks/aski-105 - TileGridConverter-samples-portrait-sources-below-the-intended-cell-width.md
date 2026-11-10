---
id: ASKI-105
title: TileGridConverter samples portrait sources below the intended cell width
status: In Progress
assignee: []
created_date: '2026-11-10T21:04:00Z'
updated_date: '2026-11-10T21:30:00Z'
labels:
  - correctness
  - tiles
  - sampling
dependencies: []
priority: medium
type: bug
ordinal: 106000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TileGridConverter sizes its sampling lattice with max(columns, rows) x oversample. That caps the longest side, which in a portrait is the height, so the prepared width lands below columns x oversample and each cell is sampled narrower than the oversample. A 975x1280 portrait at 60 columns with the default oversample 2 prepares 119 pixels wide: one source pixel per cell instead of two. ASCIIConverter.thumbnailMaxPixelSize already has a portrait branch that sets the cap to ceil(columns x oversample x H/W); the tile converter never gained it. ASKI-104 (PR #24) fixed the copy of this rule in the CLI loader and left the library rule alone. Fix it in the library by sharing one rule between both converters. The rule must not lower the cap below max(columns, rows) x oversample: for the .tall sampling shape a portrait already has more rows than columns, and the ASCII portrait branch alone would halve the cell height there.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A regression test pins a portrait TileGridConverter conversion at cellWidth == oversample
- [x] #2 Landscape and square tile output is unchanged: the shared rule equals max(columns, rows) x oversample whenever height <= width
- [x] #3 ASCIIConverter and TileGridConverter call one shared size rule instead of keeping separate copies
- [x] #4 Moved goldens are re-recorded; a moved frozen-preset golden carries the selection-ceiling no-harm census CSV
- [x] #5 CHANGELOG records the tile portrait sampling change
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-10: samplingMaxPixelSize (CellSampling.swift) is the one size rule; ASCIIConverter.thumbnailMaxPixelSize and TileGridConverter.thumbnailMaxPixelSize both call it. The cap is max(columns, rows) x oversample, raised for a portrait to ceil(columns x oversample x H/W) and never lowered: the ASCII portrait branch used to replace the base cap, which for the .tall sampling shape halved the cell height of portraits and gave an empty ASCII grid at oversample 1. Sharing ASCII's rule unchanged would have carried that into the tile converter, which had no such failure before.

The 975x1280 portrait at 60 columns now prepares 120x158 at oversample 2 (was 119x156, cell width 1) and 60x79 at oversample 1 (was 59x78, an empty grid). SamplingMaxPixelSizeTests pins the tile cell width at oversample 1 to 4, sweeps real tile lattices and the shared rule for all three sampling shapes, and pins square and landscape at the base cap. Mutation check: restoring the tile's base-only cap fails the tile portrait tests, and restoring ASCII's replace-the-base branch fails the .tall tests.

ImageIO undershoot on the library path: none. Since ASKI-1 a direct CGImage is resampled to the lattice without ImageIO, and preparedSize rounds the short side, so a portrait's prepared width is at least columns x oversample. The undershoot only reaches the converter through an image the caller already decoded with ImageIO, which is the CLI loader's case (ASKI-104 retries for it).

No golden moved: the tile snapshots use square sources, and the frozen Vesper preset uses .wide, where the shared rule equals the old ASCII rule. No census applies. AskiTileMatrix portraits keep the old decode size until the CLI loader takes its size from TileGridConverter (ASKI-104, PR 24).

Known gap, not fixed here: for a landscape source with the .tall sampling shape, both converters still prepare cells under oversample pixels high (a 4:3 landscape at oversample 2 gets 1-pixel cell rows), because the base cap does not account for rows x oversample x W/H.

2026-11-10, after merging main (PR 24, ASKI-104, merged as c84199d): the earlier note that AskiTileMatrix portraits keep the old decode size no longer holds. The CLI loader now takes its size from TileGridConverter.preparationMaxPixelSize, which goes through samplingMaxPixelSize with max(1, oversample) via the tile converter's width/height thumbnailMaxPixelSize, so tile-matrix portraits decode at the portrait size and are sampled at cellWidth == oversample. ConversionThumbnailLoaderTests.tileLoaderGivesPortraitsTheIntendedCellWidth pins that for 975x1280 at 60 columns, oversample 1 to 3. The landscape .tall gap is filed as ASKI-106.
<!-- SECTION:NOTES:END -->
