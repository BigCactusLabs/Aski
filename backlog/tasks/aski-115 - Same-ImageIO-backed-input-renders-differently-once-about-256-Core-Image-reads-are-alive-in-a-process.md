---
id: ASKI-115
title: >-
  Same ImageIO-backed input renders differently once about 256 Core Image reads
  are alive in a process
status: To Do
assignee: []
created_date: '2026-11-25T19:02:28Z'
labels:
  - rendering
  - determinism
  - core-image
dependencies: []
references:
  - Scripts/research/aski112-2026-11-25/README.md
priority: medium
ordinal: 116000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the ASKI-112 investigation on 2026-11-25 (Scripts/research/aski112-2026-11-25/, ASKI-112 notes). Aski hands caller-supplied CGImages to Core Image with CIImage(cgImage:). For a lazily decoded ImageIO image (JPEG confirmed; HEIC untested), Core Image reads the image through its own decode until about 256 such reads are alive in one process. After that, new reads get a software decode, and the same input renders differently across the whole image: 86,477 of 386,946 bytes differ, up to 22 levels, on the 288x336 MaskSnapshotTests background. The state is process-global (a new CIContext switches at the same point), and bitmap-backed images never switch. Reads released one at a time did not switch in 300 iterations, so the trigger is many live reads. A long-running app that keeps CIImages or renders alive, such as a gallery or batch export, can change output mid-session. The pre-switch output, which the committed mask-ground goldens record, also matches no bitmap-backed render, so the Core Image background and the converter (Core Graphics/vImage) can read different pixels from the same file.

Unverified hypothesis: if the pre-switch path is a hardware decoder, its output may differ by device or host, which would bear on ASKI-78's host-dependent goldens.

Affected entry points (caller-supplied images reaching CIImage(cgImage:)): Sources/Aski/Effects/Internal/BackgroundResolver.swift:20 (.original) and :22 (.blurred), reached from renderImage/renderCIImage composition backgrounds, TileGrid effects, AskiRenderEngine, and MaskFallback.originalImage through Sources/Aski/Masking/MaskFallbackImageFactory.swift:27-28 and :50-51. To check: Sources/Aski/Masking/CoverageImageBuilder.swift:20 (only if a caller's mask reaches it unconverted) and Sources/Aski/Video/ASCIIVideoDecoder.swift:334 (AVFoundation frames, probably not ImageIO-lazy). Not affected: Aski's own bitmaps and the conversion path.

Fix options (ASKI-112 r2 report): materialize caller images into an owned bitmap before Core Image, costing width x height x 4 bytes per source per render (5 MB for the 975x1280 corpus JPEG, about 48 MB for 12 MP) plus a decode and copy; or a test-only decode, which leaves the product defect. Either moves MaskSnapshotTests docc-mask-ground-before/after and the DocC images mask-ground-before.png and mask-ground-after.png. FrozenRenderReference renders without a Core Image background and is not expected to move (unverified).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A regression test (autoreleasepool per iteration, footprint guard) renders one ImageIO-backed JPEG source before and after holding at least 256 live Core Image reads and requires identical bytes
- [ ] #2 Every entry point that hands caller-supplied CGImages to CIImage(cgImage:) gives the same output for an ImageIO-backed input regardless of process state, and the canonical decode is chosen and documented (recommended: the decode Core Graphics and the converter already read, so the background and glyph colours come from the same pixels)
- [ ] #3 Moved goldens are listed, re-recorded only with owner approval and explained in CHANGELOG; the frozen-reference no-harm census runs if any FrozenRenderReference golden moves
- [ ] #4 Per-render time and peak memory are measured on the 975x1280 corpus JPEG and on a 12 MP JPEG and recorded with the decision; no benchmark threshold is loosened
<!-- AC:END -->
