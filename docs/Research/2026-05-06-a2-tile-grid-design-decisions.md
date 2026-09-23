---
title: "A2 tile-grid modes — design research notes"
slug: 2026-05-06-a2-tile-grid-design-decisions
date: 2026-05-06
status: complete
subsystem: [tile-grid]
summary: "Fourteen narrowly-scoped frontier surveys behind A2's load-bearing choices: a factored mode-by-shape API, Wu plus kmeans-in-OKLAB quantization, brick symbol naming for LEGO Fair Play compliance, struct-with-static-factories palettes, pointy-top hex packing, no shared GridConverter protocol, a sync-only API matching A1, and a lift-internals refactor over a new shared-core abstraction."
runners: [AskiTileMatrix]
---

# A2 tile-grid modes — design research notes

> Companion to the A2 tile-grid design spec (not published). Captures the field surveys that informed each load-bearing A2 decision before the spec was hardened and the implementation plan was written.

## Question

A2 adds a parallel image-conversion pipeline producing colored cell grids (pixel-art / brick / mosaic, in five cell shapes) alongside Aski's ASCII output. Before locking the API surface, color quantization algorithm, file organization, and naming, the spec ran a frontier-search session over 14 narrowly-scoped questions. This file records what the field says, what Aski picked, and why — so future work doesn't re-derive these from chat scrollback.

---

## 1. Mode space — flat enum vs. factored geometry × shape?

**What the field says.** Modern image-mosaic tools have moved away from flat mode enums toward orthogonal axes:

- [ImageOnline.io Mosaic Effect](https://imageonline.io/mosaic-effect/) ships **Grid + Voronoi + Scatter as orthogonal *geometry* dimensions**, with cell-shape (square/circle/hex/diamond) as a separate parameter inside Grid mode.
- [TurboMosaic](https://www.turbomosaic.com/) and [Visual Paradigm Mosaic Hexagonal](https://online.visual-paradigm.com/photo-effects-studio/mosaic-hexagonal-effect-tool/) confirm cell-shape as a parameter, not a separate top-level mode.
- Voronoi-style geometry is genuinely structurally different (image-aware feature points, polygon rendering, no row/col indexing). [Du et al. 2009 — A Method for Creating Mosaic Images Using Voronoi Diagrams](https://www.researchgate.net/publication/244449045_A_Method_for_Creating_Mosaic_Images_Using_Voronoi_Diagrams) documents the algorithm.

**What we picked.** Factored API: 3 modes × 5 cell shapes = 15 combinations. All 15 ship. Voronoi is **deferred to a future subsystem** — different output shape (polygons, not row/col cells), different sampling pattern (image-aware feature points), different complexity budget. Belongs in its own subsystem, not A2.

---

## 2. Per-cell data — store brightness, or compute lazily?

**What the field says.** Mainstream tile / pixel-art structures store flat RGBA per cell ([Pixelorama](https://orama-interactive.itch.io/pixelorama), Processing's PImage). Brightness is computed lazily when needed.

**What we picked.** Mirror `ASCIICell` minus `character`: store `displayColor` + `alpha` + `brightness`. Reasoning: A1's `ASCIICell.brightness` exists because palette quantization makes source-L diverge from display-color-L (e.g., `BuiltInPalette.monochrome` produces all-white `displayColor` but distinct source brightness). Same divergence applies in `TileGrid` — e.g., a 16-color adaptive palette doesn't preserve source luminance per cell. The B subsystem (lighting / effects) will need a polymorphic per-cell-brightness contract; either both grid types have it or both don't. Mirroring keeps the contract uniform.

---

## 3. LEGO/mosaic rendering fidelity — flat color, subtle shading, or full 3D?

**What the field says.** Three tiers exist:

- **Flat color + circular stud** — functional, not decorative. Used by [Lego Art Remix](https://lego-art-remix.com/), [Brick.me](https://brick.me/), [LAMG](https://joachim-gassen.github.io/2021/01/meet-lamg/).
- **Subtle CG shading** — bevel highlights/shadows around tile edges, drawn via stock canvas/CG primitives. Shipped by [Vayce](https://vayce.app/tools/mosaic-effect/), [mosaic-tile-designer](https://github.com/simosavonen/mosaic-tile-designer), [BrickPix 3D preview](https://brickjournal.com/?p=4827).
- **Full 3D** — separate visualization product, not the inline render path. Example: [80.lv Substance 3D LEGO mosaic, Jan 2025](https://80.lv/articles/creating-a-realistic-lego-mosaic-generator-with-substance-3d-aseprite).

**What we picked.** Subtle CG shading. Cheap to render (radial gradient overlay on stud, 1px highlight/shadow strokes on mosaic edges), no Core Image dependency. Full 3D is deferred to a hypothetical B subsystem or beyond.

---

## 4. `GridConverter` shared protocol — yes or no?

**What the field says.** Adversarial review against Apple's own libraries:

- [swift-collections](https://github.com/apple/swift-collections) ships `Deque` / `OrderedSet` / `OrderedDictionary` as **independent concrete types**. No shared converter protocol. They conform only to standard protocols (`Collection`, `Sequence`).
- [swift-algorithms](https://github.com/apple/swift-algorithms) uses concrete generic wrappers (`Chain2Sequence`, `Chunked<Base>`) — no intermediate algorithm protocol.
- [SE-0335 Introduce existential `any`](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0335-existential-any.md) explicitly: "The cost of using existential types should not be hidden."
- [Point-Free protocol witnesses series](https://www.pointfree.co/episodes/ep35-advanced-protocol-witnesses-part-1) advice: start with concrete types, add protocols only when ≥2 polymorphic implementations have demonstrated need.

**What we picked.** No `GridConverter` protocol over `ASCIIConverter` and `TileGridConverter`. The roadmap's earlier "probably yes" lean was reversed by this review. We have one concrete consumer of each and no demonstrated polymorphism need. Revisit if/when a third concrete sampling consumer appears (likely in C subsystem — animation/video).

---

## 5. Async / cancellation seams — add `convert(...) async` now?

**What the field says.** A1's `ASCIIConverter.convert` is sync. Adding async to A2 only would create asymmetry. The "cheap async seam" framing is most cheaply satisfied by *not* blocking the strategic move with API plumbing — `Task.detached { ... }` is two lines for the eventual iOS-app substrate. Async wrappers can be added as additive overloads later, on both converters symmetrically.

**What we picked.** Sync only, matching A1. If the iOS-app substrate develops a real consumer pushing on this, retrofit `convert(...) async` and `renderImage(...) async` as additive overloads on both `ASCIIConverter` and `TileGridConverter` together. Pre-1.0, nothing locked.

---

## 6. Sample → quantize → render — convert-once, render-many?

**What the field says.**

- [Core Image](https://www.createwithswift.com/getting-started-with-core-image/) is the canonical Apple example: `CIImage` is "an immutable set of data and instructions that describes how to produce an image when required" — rendering is deferred to `CIContext`.
- [Stebel Feb 2026 — Swift Concurrency + Metal practical architecture for real-time rendering](https://medium.com/@michaelstebel/swift-concurrency-metal-without-stutters-a-practical-architecture-for-real-time-rendering-419d9523ebca) validates Sendable structured intermediates (`FrameRequest`, `FrameResult`) for clean producer/coordinator/renderer separation.
- "Convert once, render many" is named in [graphics pipeline literature](https://en.wikipedia.org/wiki/Graphics_pipeline).

**What we picked.** `TileGrid` is a `Sendable` structural intermediate. The converter holds **no mode or cellShape state** — those are render-time parameters on `TileGrid.renderImage(mode:cellShape:scale:backgroundColor:)`. A single `TileGrid` can be re-rendered with different visual styles (slider drag) without re-running the expensive sampling and quantization stages. Optimizes for the iOS-app substrate's eventual "render this image as tile-grid art" sliders.

---

## 7. Color quantization algorithm — Wu, k-means, or composite?

**What the field says.** Wu's algorithm has a known caveat in OKLAB:

- [ubitux — Improving color quantization heuristics](http://blog.pkh.me/p/39-improving-color-quantization-heuristics.html): "the cuts are limited to an axis... we are not cutting along an arbitrary plane." OKLAB clusters tend to be diagonally elongated relative to L/a/b axes.
- [30fps — Why CIELAB doesn't improve median cut](https://30fps.net/pages/median-cut-lab-problem/): "It seems more important to do pixel mapping in a perceptual space than to change the space in which the [box subdivision] is done in."
- [Material Color Utilities — `QuantizerCelebi`](https://deepwiki.com/material-foundation/material-color-utilities/5.1-quantization-algorithms): production composite is **Wu + WSMeans (k-means)**. Fast Wu init + perceptually-uniform k-means refinement.
- [quantette](https://github.com/Ivordir/quantette) and [Okolors](https://github.com/Ivordir/Okolors) ship the same composite pattern.
- [40-year survey of color image quantization, Springer 2023](https://link.springer.com/article/10.1007/s10462-023-10406-6): "Wu's algorithm can be used as effective deterministic initialization of K-Means."

**What we picked.** Wu + k-means composite for `.adaptive` palettes, not Wu alone. Wu provides a deterministic O(1)-box-sum fast init via 33³ padded summed-area tables; k-means refines centroids based on Euclidean OKLAB distance, which IS perceptually uniform. The combination compensates for Wu's axis-aligned cut limitation. Both stages run in OKLAB on α-weighted unpremultiplied pixels (α=0 skipped, alpha-weighted moments throughout).

---

## 8. LEGO palette licensing — how far do disclaimers carry?

**What the field says.**

- [LEGO Fair Play](https://www.lego.com/legal/legal-notice/fair-play): improper trademark use is **not** cured by a disclaimer alone. Compliance comes from *avoiding* the trademark, not disclaiming after the fact.
- [BrickLink IP Guidance Statement](https://studiohelp.bricklink.com/hc/en-us/articles/6610276581015-IP-Guidance-Statement): color *values* themselves are not copyrightable; the trademark applies to the LEGO® name, minifigure design, and official set designs.
- Fan tools (Lego Art Remix, BrickPix, LAMG) ship brick-style palettes by referencing open data ([BrickLink Color Guide](https://v2.bricklink.com/en-us/catalog/color-guide), [LDraw Colour Definition Reference](https://www.ldraw.org/article/547.html)) with **generic color names** — not by relying on disclaimers.

**What we picked.** API surface uses `.brick` (not `.lego`) — the symbol name is the part most likely to read as a brand identifier (autocomplete shows it everywhere). Renaming is the actual compliance lever per Fair Play. Color names are generic descriptors only (`brightRed`, `darkBluishGray`, `tan`) — never official LEGO color names like "Bright Light Yellow." DocC text mentions LEGO® where context demands it (non-affiliation clarification), as proper-noun usage, not branding. The disclaimer is supplemental clarification of non-affiliation, layered on top of the actual compliance work.

---

## 9. Mosaic configurability — what knobs do field tools expose?

**What the field says.**

- [Vayce mosaic effect](https://vayce.app/tools/mosaic-effect/): adjustable tile size, **grout thickness**, hand-laid irregularity, bevel depth, **custom grout color**.
- [Myaiart mosaic generator](https://www.myaiart.io/features/mosaic-picture-generator/): tile size, **grout thickness**, color palette, pattern density.
- [aolej Mosaic Creator](https://www.aolej.com/tile-mosaic-maker-mosaic-creator): tile size, grout size, custom grout color.
- [OpenAI image API design](https://developers.openai.com/api/reference/resources/images/methods/generate): "configurable parameters with sensible defaults" — `auto` defaults, everything overridable.

**What we picked.** `mosaic` exposes `grout: CGColor`, `groutThickness: Double`, `cornerRadius: Double` (clamped to `0...0.5` at construction). Brick stud size (60% of `min(cellWidth, cellHeight)`) and hex orientation (pointy-top only) remain locked — revisit post-1.0 if consumer demand emerges. Hand-laid irregularity is omitted; add as a `mosaic(...)` parameter post-A2 if asked.

---

## 10. Struct vs. enum for strategy types

**What the field says.**

- [SE-0487 Nonexhaustive Enums](https://forums.swift.org/t/accepted-se-0487-nonexhaustive-enums/81508), accepted 2025-08-05, acknowledges that the additive-evolution problem is real and unsolved at the language level pre-acceptance. SE-0487 lands in a future toolchain; pre-acceptance consumers compiling against Aski with older Swift versions still see the "every new case breaks exhaustive switches" pain.
- Apple's canonical pattern: `Color`, `Font`, `UIColor` ship as struct/class-with-static-factories (not enums) — even with SE-0487 available, the static-factory pattern is what Apple's own libraries use for evolving design tokens.
- `TilePalette` carries heterogeneous associated data (`Int` for adaptive, nothing for brick, `[CGColor]` for fixed) — exactly where enum extensibility friction bites hardest.

**What we picked.** `TilePalette` and `TileGridMode` ship as struct-with-static-factories (with a `private enum Strategy` / `Representation` carrying associated data internally, free to evolve). `TileCellShape` stays an enum — closed geometric set, no associated data, fine for `@frozen` post-1.0.

---

## 11. Hex / triangle tessellation geometry

**What the field says.**

- [Red Blob Games — Hexagonal Grids](https://www.redblobgames.com/grids/hexagons-v1/) is the canonical hex-grid resource. Pointy-top vertical row spacing = `√3/2 × cell_width ≈ 0.866`. Confirmed by [Catlike Coding hex map tutorial](https://catlikecoding.com/unity/tutorials/hex-map/part-1/).
- [BorisTheBrave — Triangle Grids](https://www.boristhebrave.com/2021/05/23/triangle-grids/): equilateral triangles tessellate with horizontal stride = `side/2` (alternating up/down), vertical stride = `side × √3/2`.

**What we picked.** Hex pointy-top with `0.866` vertical packing (even rows shift right by `0.5 × scale`). Triangle: column-parity orientation (even-column up, odd-column down), `0.5` horizontal × `0.866` vertical stride. Brick stud on a triangle cell sits at the geometric centroid — `1/3` of the height from the base, not the bounding-box center.

---

## 12. CGContext bitmap convention

**What the field says.**

- [Apple `CGImageAlphaInfo.premultipliedLast`](https://developer.apple.com/documentation/coregraphics/cgimagealphainfo/premultipliedlast) is the standard iOS / macOS RGBA bitmap convention. Adding `byteOrder32Big` is portability gold-plating — Apple platforms produce the same byte layout either way.
- A1's renderer at `Sources/Aski/Renderers/ImageRenderer.swift:32` already uses only `CGImageAlphaInfo.premultipliedLast.rawValue`.

**What we picked.** The new tile renderer uses **exactly** `CGImageAlphaInfo.premultipliedLast.rawValue` (no `byteOrder32Big`) — matches A1 verbatim. Two renderers shipping identical bitmap setup is the consistency win. Note: the lifted `readRGBA8` *pixel-read* helper retains both flags as A1 had them; that's a different layer (reading pixels back, not writing the final image).

---

## 13. Internal helper sharing — extract a "shared core," or just lift visibility?

**What the field says.**

- [swift-collections precedent](https://github.com/apple/swift-collections/blob/main/Documentation/OrderedDictionary.md): `OrderedSet` and `OrderedDictionary` "share much of the same underlying implementation, so they are provided by a single module" — sharing happens by **direct use of one type by the other** or **co-located internal helpers**, never by manufacturing a third "shared core" abstraction.
- [Rule of Three](https://holdenrehg.com/blog/2021-09-20_rule-of-three) / [Premature Abstractions](https://arpit.substack.com/p/premature-abstractions): wait for the third concrete case before unifying. C subsystem (animation/video) will be the genuine third sampling consumer.
- A1 already factored `ConversionContext` as an internal type passed `borrowing` to algorithm kernels — **most of the work is already done.**

**What we picked.** Lift `ConversionContext`, `cellStats(at:)`, `nearestPaletteOKLAB`, `readRGBA8`, `gridDimensions` from `private` to `internal` in a new `Sources/Aski/CellSampling.swift`. No new abstraction layer; both `ASCIIConverter` and `TileGridConverter` consume the lifted helpers directly. Revisit when a third concrete consumer demonstrates need.

---

## 14. File organization & commit ordering

**What the field says.**

- [Google Swift Style Guide](https://google.github.io/swift/): `Type+Topic.swift` for extensions; one public type per file.
- [Swift Forums "One type per file" thread (2024–2025)](https://forums.swift.org/t/one-type-per-file-helpful-or-harmful/70524): widely-adopted community practice.
- [Kyle Shevlin git workflow for refactoring](https://kyleshevlin.com/my-git-workflow-for-refactoring/), [Jake Goulding — Refactor and make changes in different commits](http://jakegoulding.com/blog/2012/11/04/refactor-and-make-changes-in-different-commits/), [Graphite refactoring PR best practices](https://graphite.com/guides/best-practices-refactoring-prs): refactor commits before feature commits halves reviewer cognitive load.

**What we picked.** Tile public types live in `Sources/Aski/Tiles/` subdirectory, one public type per file, `Type+Topic.swift` for extensions (`TileGrid+Rendering.swift`, `TilePalette+Resolved.swift`). Single PR with refactor-first commit ordering: lift CellSampling helpers (no behavior change) → add Wu/k-means + brick palette → add public type skeleton → add renderer + snapshots → DocC + cleanup. Each commit compiles and tests pass before the next.

---

## Sources (consolidated)

**Field surveys**
- [ImageOnline.io Mosaic Effect](https://imageonline.io/mosaic-effect/)
- [TurboMosaic](https://www.turbomosaic.com/)
- [Visual Paradigm Mosaic Hexagonal](https://online.visual-paradigm.com/photo-effects-studio/mosaic-hexagonal-effect-tool/)
- [Vayce mosaic effect](https://vayce.app/tools/mosaic-effect/)
- [Myaiart mosaic generator](https://www.myaiart.io/features/mosaic-picture-generator/)
- [aolej Mosaic Creator](https://www.aolej.com/tile-mosaic-maker-mosaic-creator)
- [Lego Art Remix](https://lego-art-remix.com/)
- [Brick.me](https://brick.me/)
- [LAMG (Joachim Gassen)](https://joachim-gassen.github.io/2021/01/meet-lamg/)
- [BrickPix 3D preview](https://brickjournal.com/?p=4827)
- [mosaic-tile-designer (simosavonen)](https://github.com/simosavonen/mosaic-tile-designer)
- [80.lv Substance 3D LEGO mosaic, Jan 2025](https://80.lv/articles/creating-a-realistic-lego-mosaic-generator-with-substance-3d-aseprite)
- [Pixelorama](https://orama-interactive.itch.io/pixelorama)

**Color quantization**
- [ubitux — Improving color quantization heuristics](http://blog.pkh.me/p/39-improving-color-quantization-heuristics.html)
- [30fps — Why CIELAB doesn't improve median cut](https://30fps.net/pages/median-cut-lab-problem/)
- [Material Color Utilities `QuantizerCelebi`](https://deepwiki.com/material-foundation/material-color-utilities/5.1-quantization-algorithms)
- [Material Color Utilities GitHub](https://github.com/material-foundation/material-color-utilities)
- [quantette](https://github.com/Ivordir/quantette)
- [Okolors](https://github.com/Ivordir/Okolors)
- [40-year survey of color image quantization, Springer 2023](https://link.springer.com/article/10.1007/s10462-023-10406-6)
- [Björn Ottosson — OKLAB derivation](https://bottosson.github.io/posts/oklab/)

**Trademark / IP**
- [LEGO Fair Play](https://www.lego.com/legal/legal-notice/fair-play)
- [BrickLink IP Guidance](https://studiohelp.bricklink.com/hc/en-us/articles/6610276581015-IP-Guidance-Statement)
- [BrickLink Color Guide](https://v2.bricklink.com/en-us/catalog/color-guide)
- [LDraw Colour Definition Reference](https://www.ldraw.org/article/547.html)

**Swift API design**
- [SE-0487 Nonexhaustive Enums](https://forums.swift.org/t/accepted-se-0487-nonexhaustive-enums/81508)
- [SE-0335 Introduce existential `any`](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0335-existential-any.md)
- [swift-collections](https://github.com/apple/swift-collections)
- [swift-collections OrderedDictionary docs](https://github.com/apple/swift-collections/blob/main/Documentation/OrderedDictionary.md)
- [swift-algorithms](https://github.com/apple/swift-algorithms)
- [Point-Free protocol witnesses series](https://www.pointfree.co/episodes/ep35-advanced-protocol-witnesses-part-1)
- [Google Swift Style Guide](https://google.github.io/swift/)
- [Swift Forums — One type per file](https://forums.swift.org/t/one-type-per-file-helpful-or-harmful/70524)

**Apple platform docs**
- [CGImageAlphaInfo.premultipliedLast](https://developer.apple.com/documentation/coregraphics/cgimagealphainfo/premultipliedlast)
- [Core Image — CIImage / CIContext](https://www.createwithswift.com/getting-started-with-core-image/)
- [Stebel Feb 2026 — Swift Concurrency + Metal real-time rendering architecture](https://medium.com/@michaelstebel/swift-concurrency-metal-without-stutters-a-practical-architecture-for-real-time-rendering-419d9523ebca)
- [Graphics pipeline (Wikipedia)](https://en.wikipedia.org/wiki/Graphics_pipeline)

**Geometry**
- [Red Blob Games — Hexagonal Grids](https://www.redblobgames.com/grids/hexagons-v1/)
- [Catlike Coding — Hex Map tutorial](https://catlikecoding.com/unity/tutorials/hex-map/part-1/)
- [BorisTheBrave — Triangle Grids](https://www.boristhebrave.com/2021/05/23/triangle-grids/)
- [Du et al. 2009 — A Method for Creating Mosaic Images Using Voronoi Diagrams](https://www.researchgate.net/publication/244449045_A_Method_for_Creating_Mosaic_Images_Using_Voronoi_Diagrams)

**Refactoring practice**
- [Rule of Three](https://holdenrehg.com/blog/2021-09-20_rule-of-three)
- [Premature Abstractions](https://arpit.substack.com/p/premature-abstractions)
- [Kyle Shevlin — git workflow for refactoring](https://kyleshevlin.com/my-git-workflow-for-refactoring/)
- [Jake Goulding — Refactor and make changes in different commits](http://jakegoulding.com/blog/2012/11/04/refactor-and-make-changes-in-different-commits/)
- [Graphite — refactoring PR best practices](https://graphite.com/guides/best-practices-refactoring-prs)

**API contract examples**
- [OpenAI image generation API](https://developers.openai.com/api/reference/resources/images/methods/generate)
