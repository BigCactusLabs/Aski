# ASKI-15 hero provenance results

Evidence for [the ASKI-15 note](../../2026-11-07-aski15-hero-provenance.md).

- `bisect.csv`: one row per rendered build plus the old README hero. Pre-public builds
  are labeled by date because their commits are not in this repository. Columns:
  glyph difference against the 2026-06-29 anchor, median same-glyph OKLab ink-chroma
  ratio against the anchor, black-floor fraction (cells whose ink max channel is
  ≤ 5/255), and HSV S/V of the PNG box-downsampled to the 512 × 134 cell grid.
- `hero-stats.csv`: the same cell-grid statistics for the old and regenerated heroes.

Host: Apple M3 Max, macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Swift 6.4.
