# Changelog

All notable changes to Aski are documented in this file.

Development before v0.7.0 happened in a private repository; this repository's history begins at a
single root commit shortly before v0.7.0, and entries up to and including v0.7.0 are summarized from
the private history. Commit SHAs, issue and pull-request numbers, and tags before v0.7.0 cited in this
file and under `docs/` refer to that repository and do not resolve here.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/) for tagged releases. Aski is pre-1.0; per SemVer 2.0.0 § 4, "anything may change at any time" while the major version is `0`. Minor version bumps within the `0.y.z` range may carry source-breaking changes; consumers should pin to exact versions if they depend on a stable API surface.

## Unreleased

### Added

- `aski metadata` emits deterministic, versioned JSON for CLI discovery (ASKI-49).
  It reports command paths, aliases, visible arguments, parser defaults, research
  classification, replay product mappings, and the current checkout revision.

### Changed

- **Benchmark instrumentation corrects a reproduced allocator cleanup defect (ASKI-109).**
  Canonical captures use a reviewed local edit of malloc-interposer 1.4.0 that
  clears a stale thread-local counter pointer during teardown. Source and routing
  checks preserve allocator observations and reject invalid samples. Setup records
  SwiftPM's effective lock and restores the original lock from verified bytes.
  The native regression does not establish the cause of earlier ASKI-92 reset
  crashes. Evidence: `Scripts/research/aski109-2026-11-13/README.md`.

- **Pulse math is reused once per frame (ASKI-91).** Pulse overlays and animated
  frames preserve the existing arithmetic and exact cell values. Five paired
  runs of synthetic overlays at 80/192/288 columns on one Mac measured 34.56%,
  43.65% and 47.77% lower median wall time; all 93 regression guards passed.
  Animated pulse has exact parity coverage, not a direct timing result in this
  matrix. Evidence and limits: `Scripts/research/aski91-2026-11-13/README.md`.

- **Benchmark captures record the active allocator (ASKI-86).** A native probe
  verifies the loaded malloc interposer and live counters. Process-specific probe
  details stay separate from stable comparison identity. Real setup/execution
  failures and missing required metrics were verified to fail the canonical command.

- **Log-polar conversions reuse footprint geometry (ASKI-87).** An immutable
  pixel-to-bin map is prepared once per conversion context, with exact scalar
  descriptor and final-grid parity. Five paired runs of the synthetic gradient
  on one Mac measured 6.85–15.71% lower wall time in seven primary cases and 2.10%
  in the eighth; all 108 regression guards passed. Adoption was explicitly approved
  with that eighth case below the registered 5% bar. Evidence and limits:
  `docs/benchmark-validation.md#native-replay-result--2026-11-12`.

- **Lower-rate video exports convert only selected frames (ASKI-93).**
  `convertVideo(targetFPS:)` selects decoded frames before ASCII conversion and
  reuses a converted grid for duplicate output slots. Exact rendered-pixel,
  timestamp and report parity passed against the old ordering. Five paired runs
  on one Mac measured median wall-time reductions of 30%, 56% and 73% for the
  synthetic 720p/80-column 30/60/120-to-12 fps cases, with no reproducible control
  or resource regression under the predeclared rule. Codec decoding still occurs;
  no-resampling exports and public decoder callbacks keep their existing paths.
  Evidence and limits: `Scripts/research/video-frame-selection.md`.

- **A decoded `CGImage` is prepared directly at the conversion size (ASKI-1).** A `CGImage` whose
  longest side exceeds the conversion budget is no longer PNG-encoded and decoded through an
  ImageIO thumbnail before conversion. The converter, the temporal (video-frame) path and the tile
  converter convert it to the target color space and resample it once with vImage Lanczos straight
  to the sampling lattice. On the ASKI-1 benchmarks (median, one Mac), preparing a 4032×3024 photo
  for the Vesper preset drops from 677 ms to 28 ms and a 1920×1080 frame from 21.9 ms to 4.7 ms,
  and the 720p video benchmarks run 33–85% faster end to end. Peak resident memory rises by 5–8 MB
  on the two rotated-video end-to-end benchmarks. The likely cause is the full-size RGBA8 copy the
  converter now makes of each oriented frame before resampling; ASKI-2, which moves orientation
  into frame preparation, would remove that full-size frame. Rendered output changes for these
  inputs: cell colors and some glyph picks move, and grid dimensions stay the same. One change is
  visible. ImageIO's thumbnail could land a decoded portrait one pixel below the width budget, and
  the cell pitch is that width divided by the column count and floored, so such a source was
  sampled at `oversample − 1` working pixels per cell: 1 instead of 2 at the default. A cell one
  pixel wide is too narrow for the shape descriptor, so those cells were matched on tone alone.
  The prepared size now rounds to the nearest pixel and meets the budget. This is why the DocC
  mask-ground figure changes visibly: its 975×1280 source now gets 2-pixel cells, and its picks
  inside the mask move from varied letters to the shape matcher's runs of one glyph per tone band
  (ASKI-80). The rounding and resampler changes were not measured separately. On the frozen Vesper
  preset the change passes the pre-registered no-harm census: production-arm MAE moves by ×1.0000
  and ×0.9991 on the two naturals corpora. A source already within the budget renders byte for
  byte as before, and so does anything loaded through
  `ImageIOThumbnail.decode(data:maxPixelSize:)` or `decode(source:maxPixelSize:)`, including `aski
  render` and `aski inspect`. Resampler choice and census:
  `docs/Research/2026-11-10-aski-1-direct-cgimage-preparation.md`.

### Removed

- **`ImageIOThumbnail.decode(image:maxPixelSize:)` (ASKI-1, source-breaking).** It shrank a
  decoded image by PNG-encoding it and decoding an ImageIO thumbnail. Pass the `CGImage` to
  `convert` directly; the converter now resamples it itself. For encoded input, keep using
  `ImageIOThumbnail.decode(data:maxPixelSize:)` or `decode(source:maxPixelSize:)`, which avoid
  materializing the full raster and apply EXIF orientation.

### Fixed

- **Point lights no longer over-brighten (ASKI-102).** The light field summed opaque layers
  with `CIAdditionCompositing`, which adds alpha along with color, so the field reached
  alpha 3 with one light and one more per added light. Converting the lit image to the output
  color space then divided its color by that alpha, encoded it and multiplied the alpha back
  in, which brightened every lit pixel and made semi-transparent pixels opaque. The field is
  now opaque before it multiplies the image. Over white, an sRGB (0.8, 0.2, 0.1) light at
  intensity 1 with ambient 0 renders (204, 51, 25) at its center, the light's own color,
  instead of (255, 81, 33); with ambient 0.5 it renders (233, 136, 130) instead of
  (255, 243, 232). Lit renders are darker than before; raise `ambient` or the light's
  `intensity` to brighten them. Lighting now keeps the image's alpha. Intensity scaling,
  lighting with no lights, and renders without lighting are unchanged.
- **Landscape `.tall` sampling keeps the requested sample size (ASKI-106).** Both
  `ASCIIConverter` and `TileGridConverter` now prepare enough source pixels for
  `oversample` on both cell axes when downscaling landscape images with `.tall`.
  This changes colors and glyph choices for affected inputs and prevents empty
  grids at `oversample: 1`. Small sources are not upscaled. `.square`, `.wide`,
  portrait sampling, and the frozen Vesper preset keep their previous behavior.
- **Ragged ASCII grids use their widest row (ASKI-7).** Longer later rows are no
  longer clipped, and an empty first row no longer hides later content. Text keeps
  the supplied row lengths. Missing cells retain the canvas background during mask
  composition instead of receiving mask ground or fallback paint; lighting and
  whole-image effects still apply afterward. Rectangular grids are unchanged.
- **Mask paint is color-matched on every render path (ASKI-98).** `MaskFallback.solid(_:)` and
  `MaskOptions.groundColor` colors are interpreted in the color space their `CGColor` declares
  and color-matched into the grid's render color space on every raster path, including effects,
  async, `renderCIImage` and `AskiRenderEngine` gamut adaptation. Before, those Core Image paths
  (and tile renders with a ground or a partly covered mosaic) read Generic RGB and unnamed-RGB
  components as values in the grid's gamut, while direct ASCII rendering color-matched them.
  Generic RGB (0.9, 0, 0) now renders as sRGB (237, 34, 0) on those paths instead of
  (229, 0, 0), and Generic `#080808` as `#060606`. To keep the old numbers, tag the components
  with the grid's space: `CGColor(srgbRed:green:blue:alpha:)` for sRGB grids, or
  `CGColor(colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!, components: [r, g, b, a])`
  for Display P3 grids. The CLI's `--mask-fallback-color` and `--mask-ground` are already sRGB
  and do not change.
- **Color overlays and point lights honor their color space (ASKI-99).** `ColorOverlay` and
  `PointLight` colors are interpreted in their `CGColor`'s declared color space, as
  `Background.solid` already was. Their components were previously read as sRGB numbers: a
  Display P3 (0.8, 0.2, 0.1) overlay rendered (204, 51, 25) in sRGB output instead of about
  (222, 24, 0). `CGColor(red:green:blue:alpha:)` creates a Generic RGB color, so overlays and
  lights built with it now render slightly differently; use `CGColor(srgbRed:green:blue:alpha:)`
  to keep the previous result. sRGB-tagged colors, overlay opacity, blend modes and light
  intensity are unchanged: intensity still scales encoded sRGB components, and intensity above 1
  still saturates each channel at 1. A Display P3 light outside the sRGB gamut keeps its color
  instead of being read as sRGB numbers.
- **MP4 export keeps its colors (ASKI-100).** Frames are drawn in the grid's encoded gamut (sRGB
  or Display P3) instead of an untagged device RGB space, and the H.264 or HEVC track is tagged
  with its color primaries (BT.709 or P3 D65), the sRGB transfer function and the BT.709 Y'CbCr
  matrix, at video range. Untagged files let decoders guess the matrix from the frame size, which
  shifted colors in small exports, and Display P3 frames were clipped to sRGB before encoding.
  Exported MP4 bytes change.
- **Soft mask edges use the same coverage weight on every path (ASKI-101).** Mask coverage is a
  linear weight: a cell with coverage `c` shows `c` of the active branch (glyphs or tiles, and
  the ground) and `1 - c` of the fallback. Effects, async, `renderCIImage` and `AskiRenderEngine`
  renders, renders with a `groundColor`, and partly covered tile mosaics read coverage through the
  sRGB transfer function in Core Image's linear working space, so at coverage 0.5 they showed
  the fallback at about 0.78 of its alpha and the ground at about 0.22. Direct ASCII,
  target-width, and direct pixel-art and brick tile renders already used 0.5, and
  `renderCIImage` results now carry the same weight whatever working space reads them. Soft-edged
  masks on those Core Image paths render differently at partly covered cells: the active branch
  is stronger and the fallback weaker. Hard-edged masks, unmasked renders, and direct renders
  without a ground do not change. Where both branches are opaque, Core Image paths still mix in
  linear light and Core Graphics paths in encoded values (see the Masking guide).
- **The CLI samples portraits at the intended cell width (ASKI-104).** `aski render`,
  `aski inspect`, `aski lab motion --image` and `AskiTileMatrix` decode the input file at the
  size the converter prepares it at. The loader kept its own copy of that size rule, and the copy
  capped the longest side at `max(columns, rows) × oversample`, which in a portrait is the
  height. A 975×1280 photo at 60 columns decoded 91 pixels wide, so each cell was one pixel wide
  instead of two, and a one-pixel cell has no shape descriptor: the log-polar matcher picked
  glyphs by tone alone. The loader now asks the converter for the size, so that photo decodes 120
  wide and is shape-matched. It also sizes from the displayed shape after EXIF orientation, which
  catches portrait phone photos stored as landscape rasters, and it retries one pixel larger when
  ImageIO decodes a portrait one pixel narrower than that size implies. CLI portrait output
  changes. The row count comes from the decoded aspect ratio, which the larger decode keeps
  closer to the source's, so a portrait can gain or lose one row. Landscape and square inputs
  decode exactly as before. Library callers that pass a `CGImage` are unaffected.
- **`TileGridConverter` samples portraits at the intended cell width (ASKI-105).** The tile
  converter capped its sampling lattice's longest side at `max(columns, rows) × oversample`, which
  in a portrait is the height, so the width came out below `columns × oversample`. A 975×1280
  portrait at 60 columns was sampled 119 pixels wide at the default oversample 2, one source
  pixel per cell instead of two, and 59 pixels wide at oversample 1, where the cell width floored
  to zero and `convert` returned an empty grid. `TileGridConverter` now uses `ASCIIConverter`'s
  size rule, which raises a portrait's cap to the height that puts the width on
  `columns × oversample`; the two converters share one implementation. Portrait tile output
  changes: cell colors and the adaptive palette move, and grid dimensions stay the same. Square
  and landscape tile output is unchanged. Sharing the rule also fixes `ASCIIConverter` with the
  `.tall` sampling shape, which gives a portrait more rows than columns × height/width. Its
  portrait branch replaced the base cap even where the base was larger, which halved the cell
  height of `.tall` portraits and returned an empty grid at oversample 1; the shared rule keeps
  the larger cap. All other `ASCIIConverter` output, including the frozen Vesper preset, is
  unchanged. `AskiTileMatrix` takes its decode size from `TileGridConverter` (ASKI-104), so its
  portraits now decode at this portrait size and are sampled at the intended cell width too.

## v0.8.0 — 2026-11-10

### Fixed

- **Raster output honors cell color spaces (ASKI-3).** ASCII, tile, and effects
  rendering interpret encoded cell colors in their declared sRGB or Display P3
  gamut. `AskiRenderEngine` converts colors across gamuts and preserves masked
  background colorimetry. Raster colors, including mid-gray neutrals, change; glyph selection and
  attributed-string output do not. Review saved renders and remove compensation
  for the previous Generic RGB interpretation; see the rendering guide. The CLI
  now builds `--background`, `--mask-fallback-color`, and `--mask-ground` colors in
  sRGB, so `aski render --background "#808080"` writes `#808080` pixels (it wrote
  `#929292` before) and gray or colored values now match the manifest's
  `#RRGGBBAA` record. `aski lab hdr --background-hex` also builds its color in sRGB.
- **GIF loop counts round-trip through ImageIO (ASKI-8).** Encoding accepts `0...32767`
  (`0` means infinite; `1` means once), rejects unsupported values before opening the
  destination, and reports the loop metadata read from the finalized file. Out-of-range
  values throw the new `GIFEncodeError.invalidLoopCount(_:)` case; an exhaustive `switch`
  over `GIFEncodeError` needs a branch for it.
- **CLI text output supports `/dev/null` and `/dev/stdout` (ASKI-83).** Text streams are
  written directly after regular outputs are ready. Other special destinations are
  rejected with an explicit reason; device nodes are never staged or replaced.

### Added

- **`aski render` selects the algorithm, dither strength and palette (ASKI-82).** New flags
  `--algorithm logPolar|dotMatrix`, `--coverage 0...1` and `--palette fullColor|monochrome`;
  defaults (`logPolar`, `0`, `fullColor`) keep existing output. `--write-manifest` records all three
  as additive, optional fields in the v1 render manifest schema.
- **CLI distribution candidates and Swift Package Index docs config.** `just package-cli <new-dir>`
  (or `make package-cli ASKI_PACKAGE_OUTPUT=<new-dir>`) builds an arm64-only, relocatable `aski`
  candidate from a clean checkout, checks its bundled resources, smoke-tests a relocated copy, and
  writes a `.tar.gz` archive (including `release-info.txt`) with `SHA256SUMS`. It does not run the
  acceptance gates or publish assets.
  `.spi.yml` declares `Aski` as the documentation target for Swift Package Index. See the
  [distribution guide](docs/guides/distribution.md).
- **`just test-infra` (contributors).** Portable regression tests for the doctor, DocC, and Metal
  restoration scripts, using Python 3's standard library, disposable Git repositories, and fake
  Apple tools. They do not build Swift or replace `just check`.

### Changed

- **Glyph cycling works with `dotMatrix` (ASKI-81).** Cycling previously filled every candidate slot
  with the one dotMatrix pick, so animation never changed glyphs. Candidates after the base pick are
  now the other glyphs nearest in ink density. The base frame is unchanged and matches `convert()`.
- **DocC Markdown export no longer writes to `/tmp/aski-docc-markdown` (contributors).**
  `./Scripts/validate-docc.sh --emit-markdown` writes to a new directory and prints it as
  `DocC Markdown output: ...`; pass `--output-dir <new-dir>` for a fixed location. Packaging scripts
  that read the old shared path need updating. The doctor and DocC scripts now use private
  temporary space per run, fail explicitly when another run holds the same checkout's lock, and stop
  an interrupted Metal regeneration before restoring the checked-in library; see
  [CONTRIBUTING.md](CONTRIBUTING.md#pull-requests-and-releases).

### Documentation

- **Character-art recipes guide.** [docs/guides/character-art-recipes.md](docs/guides/character-art-recipes.md)
  shows the Carina source beside rendered output and gives three recipes (color ASCII, monochrome
  dithered, braille on a transparent ground) with their exact commands and committed output PNGs.
  The README links to it.
- **Color examples use sRGB.** README and DocC snippets build example colors with
  `CGColor(srgbRed:green:blue:alpha:)` instead of the Generic RGB initializer.
- **README hero regenerated from the current build (ASKI-15).** The previous Carina hero
  could not be reproduced by any converter build: it had about 1.9× the source's
  per-cell chroma and a 17% pure-black floor, while every build since June 2026 matches
  the source's color. The new hero is a default-settings render, and its caption gives
  the command and the correct 134-row grid size. Converter output is unchanged; see the
  [ASKI-15 note](docs/Research/2026-11-07-aski15-hero-provenance.md).
- **logPolar pairings match measured behavior (ASKI-79).** `logPolar` is now recommended with
  `standard` and `braille` only. At the default `oversample`, `minimal`, `dots`, `diagonal`, `cross`
  and `diamond` render every cell as a space under `logPolar`, and `blocks`, `lines` and `mixed`
  settle on a few glyphs per image; `Algorithms.md`, the `ASCIIAlgorithm.logPolar` and
  `RasterizedCharacterSet` doc comments, and a new "Custom sets and logPolar" section in
  `CharacterSets.md` say so and point to `dotMatrix`. The custom-set examples in `CharacterSets.md`
  and `GettingStarted.md` now pass `algorithm: .dotMatrix`, because under `logPolar` they rendered
  all blank or one repeated glyph, and `CommandLine.md` notes that `aski render` renders those five sets
  blank under the default `--algorithm logPolar`. Output is unchanged: a pre-registered fallback to the
  tone-nearest glyph was measured and rejected
  (`docs/Research/2026-09-27-aski-79-80-orthogonality-fallback.md`).

## v0.7.0 — 2026-09-23

### Added

- **Unified research-lab command tree (ASKI-48, #23).** The first-class `aski` product now owns
  `aski lab {color,motion,video,accessibility,decolor,hdr,preset}`, generates Bash, Zsh, and Fish
  completions for the full tree, and launches through an async-correct root. The seven lab
  implementations are importable package modules; the historical `Aski*Lab` products remain as
  byte-thin replay shims with byte-identical help, usage, and exit behavior. Built-binary launch,
  canonical/replay parity, complete command-surface golden, and package-manifest tests guard the
  boundary.
- **CLI mask and photo-dissolve compositing (ASKI-44, #6).** `aski render` now accepts raster
  masks with transparent, solid-color, or original-photo fallbacks; original sizing; active-region
  grounds; hard-edge thresholding; and inversion. It decodes the source once, stages text/PNG/
  manifest outputs as one rollback-capable transaction, and records resolved mask state in the
  additive v1 render-manifest `mask` block when a mask is supplied. Closes issues #6 and #7.
- **Active-region mask grounds (ASKI-43, #7).** `MaskOptions.groundColor` can place an opaque or
  translucent caller-selected color behind active ASCII glyphs and tiles. ASCII and tile grids
  retain the resolved ground, and soft masks interpolate once between completed active and
  inactive branches. The default and effective no-ground paths remain byte-identical; text output
  ignores raster grounds, and the extended-range renderer rejects positive-alpha grounds rather
  than changing its opaque/full-coverage contract.
- **Exact target-width rendering (ASKI-63, #35).** New public
  `ASCIIGrid.renderImage(font:backgroundColor:targetPixelWidth:preserveSourceAspect:)` renders to an
  exact output pixel width instead of a font-size-derived scale, and `aski render --width` exposes it
  on the command line, so PNG pixel size no longer depends on `--font-size`. The shipped arm draws at
  4x the target and area-averages down in linear light — selected over direct rendering by the
  pre-registered ASKI-63 gate (SHIP-B, run 2). `ASCIIGrid.maxTargetPixelWidth` bounds the request at a
  quarter of the renderer's pixel-extent ceiling because the supersampled bitmap must itself fit it;
  out-of-range geometry returns the 1x1 fallback image, matching the scale renderer. The CLI never
  writes one: an out-of-range `--width` is refused up front as a validation error, and a width whose
  *derived height* exceeds the ceiling is caught after the render and refused as a runtime error, so no
  fallback image and no manifest describing one reaches disk. `--width` requires `--render-png`. The
  direct arm remains reachable through the `@_spi(AskiResearch)` `TargetWidthResample` overload for
  research comparison. Addresses issue #33 asks 1 and 2; ask 3 (a lossless animated WebP encoder) stays
  open as ASKI-64, so #33 is not yet closed.
- **Transparent PNG backgrounds (#8).** `aski render --background` now accepts `clear` and
  `transparent` alongside `#RRGGBB` and the existing named colors, producing an alpha-zero ground
  for `--render-png`. The opaque-black default is unchanged. Closes issue #5.

### Changed

- **Custom character sets use one validated glyph snapshot (ASKI-71).** `ASCIIConverter` now
  adapts the four public per-glyph arrays into one internal `GlyphBank` at initialization and whenever
  `characterSet` is assigned. Reference-type conformers that mutate their arrays in place must assign
  the character set again before conversion to refresh the snapshot.
- **`swift-argument-parser` upgraded to 1.8.x (ASKI-47, #26).** Requirement raised from 1.5.1 to
  `from: "1.8.0"` (resolves 1.8.2); the ASTSK-61 command-surface golden was regenerated for the
  richer 1.8 `_dumpHelp` serialization with no semantic surface change. `package-benchmark` is
  held at `"1.31.0"..<"1.36.0"` because 1.36.x removes the Jemalloc trait the benchmark target
  requires. Closes issue #22.
- **DocC Markdown sidecars are opt-in (#12).** `Scripts/validate-docc.sh` now defaults to the
  single warnings-as-errors validation conversion; `--emit-markdown` requests the second
  conversion and fails loudly if the toolchain lacks the flag. The release build passes it, so the
  published Markdown manifest and sidecar assets are unchanged — only local gates stop compiling
  the catalog twice.
- **One build per `just check` (#11).** The gate builds the full test graph once with
  `swift build --build-tests`; the drift tools and every test phase consume it via `--skip-build`.
  Registry assertions the pre-test tools already cover are no longer re-run in-process, while
  `docsRootMatchesAllowlist` stays in the broad run.
- **Media tests run as a bounded serial partition (#13).** `GIF|Video|MotionLab` cases leave the
  parallel core phase and run with `--no-parallel` from the same prebuilt bundle, ahead of the two
  deadlock sentinels. Swift Testing's default concurrency had these competing for the media
  engine, I/O, and temp files with every other suite — the contention behind ASKI-39. Ad-hoc
  `just test-media` keeps its previous parallel scope.
- **`repo-doctor` no longer pins an Xcode version.** `just doctor` and `just release-preflight`
  report the active Xcode and read the Swift minimum from `swift-tools-version` in `Package.swift`;
  `ASKI_REQUIRED_SWIFT_VERSION` remains an override.
- **Render goldens re-recorded on macOS 27 / Xcode 27 (ASKI-77).** Core Text, Core Graphics, Metal
  and Core Image output drifted on unchanged source, so the PNG snapshots and the G0 byte golden were
  re-recorded and `default.metallib` was regenerated with the Xcode 27 Metal toolchain. Glyph
  selection is unchanged: text, selection and `VesperPreset` goldens pass as before. Committed
  `ShapeData` is not regenerated because the ASKI-51 drift audit fired on macOS 27; ASKI-78 owns
  that decision. The goldens now fail on macOS 26.

### Removed

- **Settled experiment surface (ASKI-68).** Removed five failed or inconclusive
  default-off treatments from the public and production matcher surface: occupancy matching,
  shape-structure assist, steerable-shape assist, ink pre-compensation, and chroma-shape assist.
  `RenderingOptions` now has five public controls instead of twelve. `rawDensityValues`, the base
  residual map, selection-ceiling analysis, ASKI-69's lab-only matcher challenger, frozen research
  notes/results, and Git history remain. `.bin` v3 files stay readable, but their obsolete structure
  channels are skipped and the byte-compatible encoder is local to the generator.
- **The failed `edgeMap` algorithm (ASKI-16).** No product or accepted
  probe used it, and its template matcher selected the wrong orientation in 9
  of 20 honest bucket-by-charset cases even after two local fixes (ASKI-16.1
  and ASKI-16.2, #9 and #10), which are superseded by the removal. The public
  `ASCIIAlgorithm.edgeMap` case, its kernels, canonical templates, misleading
  tests, and baked all-X golden are gone. This is a deliberate source-breaking
  change; `logPolar` and `dotMatrix` output are unchanged.

### Fixed

- **Converters dropped the bottom source rows (ASKI-65, #36).** All three converter paths took a
  floored integer cell pitch and sampled the decoded thumbnail from the origin, so the bottom
  `height % rows` rows and right `width % columns` columns were never read — up to 10% of image
  height — while the renderer still drew the grid over the full source aspect, producing a
  vertically stretched, downward-drifting result. The pitch is unchanged and still uniform, but
  the thumbnail is now drawn into a sampling lattice of exactly `columns * cellWidth ×
  rows * cellHeight`, so the origin-anchored walk tiles the raster exactly and
  `SamplingGeometry.droppedX`/`droppedY` are zero. Every rendered-grid golden and snapshot was
  re-recorded against the corrected sampling; no tolerance was loosened. Before the ASKI-68 cleanup,
  the `isoluminant-rescue` lab refused fixtures that were not exact sampling lattices for their resolved
  grids. Re-measured there, the ASTSK-36 competition-ramp instrument no longer graded. ASKI-66 later
  closed its exact-lattice redesign INCONCLUSIVE, and ASKI-68 removed the chroma-shape treatment and
  dedicated runner. The surviving shape-residual and decolor labs map their native oracle blocks
  through the lattice instead.

## v0.6.0 — 2026-08-17

First public release, under the Apache-2.0 license. Code is identical to the
final private-repo state. Changes since v0.5.0:

### Added

- **Canonical Vesper render preset (ASTSK-47).** New public `VesperPreset` —
  `VesperPreset.canonical` is the built-in frozen duotone share preset (blocks charset,
  76 columns, bone `#E8E2D2` sRGB figure on oxblood `#5E1B18` Display P3 ground, `.wide` +
  aspect-faithful render, bundled Courier Prime, contrast `+0.15`, `#161616` charcoal ground, SDR),
  bundling the converter recipe and render parameters as one drift-proof source of truth with
  `render(_:)` as its single entry point. Every knob carries a one-line rationale; knobs were
  settled on `AskiPresetLab` A/B evidence over real faces. Purely additive — existing API output is
  byte-identical. Locked by a golden byte-snapshot plus a guard test that fails if the golden ever
  renders blank, uses non-blocks glyphs, or drops either duotone color.
- **`AskiPresetLab` charset × columns A/B tooling (ASTSK-47).** New research lab: `ab` renders one
  portrait across charset/column candidates through the draft Vesper preset, writing labeled
  candidate PNGs, a contact sheet (thumbnails double as the phone-glance legibility test), and a
  provenance manifest. `--font-size`/`--scale` are bounds-validated at parse time like the other
  labs.
- **Video tooling fidelity + animated-overlay levers (ASTSK-39).** `AskiVideoLab` exposes the
  per-frame quality levers — `--charset`, `--oversample`, `--brightness`, `--contrast`, `--density`,
  `--edge-emphasis` (defaults reproduce `DefaultConverter()` byte-for-byte) — and a time-modulated
  overlay, `--pattern none|wave|pulse`, with `--pattern-amplitude`/`--pattern-frequency` (wave) and
  `--pattern-period`/`--pattern-depth` (pulse). The overlay's global phase is driven by each frame's
  presentation time, so it stays coherent across frames (GIF uses accumulated post-resample
  presentation time). `--pattern-frequency` and `--pattern-period` are validated finite and positive
  at parse time. New public `ASCIIGrid.applyingOngoingPattern(_:at:)` and
  `ASCIIVideoFrame.applyingOngoingPattern(_:)`; `convertVideo(...)` gained an optional `pattern:`
  parameter. The default (`--pattern none` plus the historical lever defaults) is byte-identical to
  prior output.
- **Cosmetic post-render effects for video (ASTSK-44, ASTSK-39 step b).** `AskiVideoLab` exposes
  opt-in `--bloom`/`--scanlines`/`--vignette` (with `--bloom-radius` and `--scanline-frequency`) that
  apply a time-invariant cosmetic `EffectChain` to every rendered frame across all four paths
  (uncapped/capped/resampled MP4, GIF). Effects compose in a fixed bloom → scanlines → vignette order
  (bloom softens glyph edges first, the CRT-style composite lands last). Intensities clamp to `0...1`;
  radius/frequency are validated finite and positive at parse time. Effects are deliberately
  time-invariant — per-frame stochastic effects (glitch/film grain) are not exposed because per-frame
  noise flickers. Each intensity defaults to `0` (off), so omitting every flag is byte-identical to
  prior output. Reuses the existing `ASCIIGrid.renderImage(…, effects:)` overload (no new kernels);
  `convertVideo(...)` gained an optional `effects:` parameter.

### Changed

- **Temporal portrait parity and descriptor reuse (ASTSK-53).** The research-only
  `convertTemporalFrame` path now shares production conversion's portrait-aware thumbnail bound, so portrait
  frames keep the intended per-cell width instead of collapsing to blank one-pixel-cell grids. Each temporal
  cell also extracts its 60-D log-polar descriptor once and reuses those lanes for matching, held-glyph checks,
  and source-tether lock maintenance. Square and landscape output, held/unheld decisions, state arrays, and
  floating-point distance accumulation remain byte-identical; no public or new SPI surface was added.
- **Bounded video export pipeline (ASTSK-52).** The one-shot `convertVideo` path now overlaps ordered
  decode + conversion of the next frame with render + encode of the current frame through a one-frame
  prefetch (two frames in flight total). The original pull semantics remain available unchanged through
  `ASCIIVideoDecoder.grids(...)`; the new sibling `pipelinedGrids(...)` is additive. On deterministic
  12-frame 720p fixtures, wall p50 improved 393 -> 326 ms for identity input and 593 -> 400 ms for rotated
  input, with flat CPU and a structurally bounded resident peak. Exact PTS order, cancellation/failure,
  early termination, and rotated cell-for-cell parity are covered. Adjacent GIF metadata reuse and fused
  orientation-thumbnail prototypes were measured and rejected; the latter failed its color-fidelity gate.
  No benchmark threshold was loosened.
- **Parallel per-cell conversion walk (ASTSK-51).** The per-cell grid loop now walks rows in parallel via
  `DispatchQueue.concurrentPerform` behind a grid-size gate (`GridRowWalk`, default crossover at 1200
  cells), across all four conversion entry points (`convert`, `convertWithRankedCandidates`,
  `convertWithResidual`, and the research-only `convertTemporalFrame`). Writes target pre-sized storage at
  proven-disjoint per-row indices, so output is **byte-identical** to the previous serial walk (guarded by a
  serial↔parallel parity suite and a frozen pre-change golden). `dotMatrix` always walks serially — its
  Floyd–Steinberg error diffusion is cell-order-dependent. Video/animation parallelism stays *within* each
  frame; no nested frame-level fan-out is introduced. Default single-still converts run ~18–40% faster at
  and above the threshold; small grids stay serial where parallelism would lose. Three adjacent
  micro-optimizations from the same audit (existential→generic kernel dispatch, per-cell scratch reuse, and
  a per-conversion log-polar bin table) were each implemented, measured, and **rejected** as non-wins — the
  60-D descriptor compute dominates per-cell cost. No benchmark threshold was loosened.
- **Bit-identical conversion and render cleanup (ASTSK-50).** The default linear-light sampler now uses a
  raw-alpha-gated 256-entry sRGB decode table for opaque pixels and tighter unsafe-buffer traversal while
  preserving the existing partial-alpha path. Helmlab reuses its preserved hue angle; mask fallback scans and
  per-character mask construction are gated behind their constant-time prerequisites; matching, TileGrid
  drawing, palette/color-space setup, and the three production conversion prologues shed verified duplication.
  The research-only temporal conversion path remains separate and unchanged. Default goldens and render
  snapshots remain byte-identical; `just bench` passed unchanged thresholds, with mixed/noisy timings rather
  than a claimed aggregate speedup.

### Fixed

- **Portrait-aspect images rendered blank under `.logPolar` (found during ASTSK-47).** The
  thumbnail decode cap bounded the image's longest side at `max(columns, rows) × oversample`, so a
  portrait input's width fell below `columns × 2`, cells truncated to 1 px wide, the log-polar
  histogram's radius gate excluded every pixel, and the zero descriptor exact-matched the space
  glyph — every cell rendered blank (a 1000×1000 face filled 2493/2584 cells; the same face at
  750×1000 filled 0/3496). The cap is now derived from the width budget
  (`columns × oversample × height/width`) for portrait inputs; square and landscape outputs are
  byte-identical.
- **Rotated video orientation follow-up (ASTSK-38).** Fixed the vertical-flip bug that remained in the
  `v0.5.0` rotated/portrait decode path by applying `preferredTransform` through the Core Image/Core
  Graphics coordinate-space conversion and verifying decoded frames against
  `AVAssetImageGenerator(appliesPreferredTrackTransform: true)`.
- **Full-gate reliability (ASTSK-40).** `just check` now keeps the video deadlock sentinels in the
  comprehensive gate by running the complementary suite first, then the two load-sensitive video
  sentinels in an isolated shard.

### Documentation

- **Video/GIF DocC coverage.** Added a `Video` DocC article (`<doc:Video>`) and a "Video & GIF" Topics
  group to the catalog so the public streaming-video API — `convertVideo`/`convertGIF`, the
  decoder/encoder halves, and the frame/report types — is discoverable. Corrected the `architecture.md`
  `ShapeData` note to describe the `.bin` v1/v2/v3 format (v3 = structure channels, ASTSK-35), and added a
  quality/effects lever hint to the `AskiVideoLab` example in `AGENTS.md`.

## [0.5.0] — 2026-06-16

Pre-1.0 additive roll-up of every change merged to `main` between `v0.4.0` and `v0.5.0`. Default rendered
output is unchanged: every new color/shape capability ships as an opt-in knob or research SPI that is
off by default, and the PNG/snapshot baselines are byte-identical to `v0.4.0`.

### Added

- **HDR/EDR emissive render path (ASTSK-10).** New `@_spi(AskiResearch)` `ASCIIGrid.renderExtendedRangeImage(...)`
  renders an SDR base plus a linear-domain per-cell emission gain in a 16-bit half-float extended-linear
  context and authors a gain-map Adaptive HDR HEIC (system SDR fallback by delegation). The default render
  path is byte-identical; this is opt-in research surface.
- **Video pipeline.** Streaming MP4 → ASCII → MP4 loop (ASTSK-3); animated-GIF ingest and GIF export with
  per-frame delays and loop count, promoting `ASCIIGIFEncoder` and adding `ASCIIGIFDecoder` to the library
  (ASTSK-13); target-FPS resampling for both MP4 and GIF (ASTSK-19); one-shot `convertVideo`/`convertGIF`
  carriers.
- **Faithful aspect-ratio image rendering.** New `preserveSourceAspect` parameter on the image renderer
  reproduces the source image's aspect ratio (`glyphWidth * 2.2`). Default `false` keeps the historical
  2.0 glyph aspect — all existing PNG snapshot baselines are unchanged. `AskiDemo` defaults to the faithful
  ratio via `--preserve-aspect`.
- **Helmlab palette-matching policies (ASTSK-2).** `PaletteMatchingPolicy.helmlabEuclidean` and
  `.helmlabCompressed`, backed by a full Helmlab MetricSpace transform + inverse ported from Helmlab v21.
  Opt-in; the default remains `.oklabEuclidean`.
- **Per-cell shape residual.** The discarded 60D log-polar match distance is surfaced via a
  `convertWithResidual` SPI plus shape-structure channels on the descriptor.
- **Character-set `.bin` format updates.** `.bin` v2 adds a raw ink-density block exposed as
  `rawDensityValues` (ASTSK-28); `.bin` v3 adds shape-structure channels (ASTSK-35). Both stay
  backward-compatible with prior versions.
- **Default-off research knobs.** Ink-fraction color pre-compensation (ASTSK-29); `chromaShapeAssist`
  isoluminant rescue via mass-normalized chroma-gradient shape assist (ASTSK-30); `occupancyMatching`
  composited-tone glyph matching (ASTSK-7); `shapeStructureAssist` basis augmentation (ASTSK-35). Each
  defaults to off. `shapeStructureAssist` ships as a **documented negative result** and is not recommended
  for production use.

### Changed

- **All CLI tools migrated to swift-argument-parser (ASTSK-21/22).** `--help` and `--version` (build SHA)
  now work uniformly across every tool.
- **`AskiDemoSupport` renamed to `AskiToolSupport` (ASTSK-24).** Internal tool-support target; no library
  API change.

### Fixed

- **Video decode orientation (ASTSK-12).** Decoding now applies the source `preferredTransform`, so
  rotated/portrait sources are no longer mis-oriented.
- **DocC validation gate (ASTSK-25).** Repaired the warm-cache symbol-graph footgun: `validate-docc.sh`
  now regenerates the Aski symbol graph via `swift package dump-symbol-graph` on every run, ending the
  spurious "unresolved reference" failures on a warm `.build`.

### Documentation

- **Research infrastructure.** NASA isoluminant corpus validation (ASTSK-37); λ dose-response via a
  luma-vs-chroma competition ramp (ASTSK-36); regime-appropriate structure oracle re-settling the
  shape-residual verdict (ASTSK-31); Color-Theory Phase 0 composited-cell oracle gate + glyph
  shape-residual field; CAM16/HCT and Color.js gamut reference cross-checks (gamut-mapping doc-comments
  now cite the pinned Color.js reference port); research data/results-store conventions (ASTSK-11);
  generated repo-map source index + orientation docs; tooling/CI preflight hardening.
- **New research harnesses (`swift run` targets, not library API).** `AskiMotionLab`, `AskiVideoLab`,
  `AskiAccessLab`, `AskiDecolorLab`, and `AskiHDRLab`, plus new `AskiColorLab` subcommands.

## [0.4.0] — 2026-05-29

Pre-1.0 default-output release.

### Added

- **`GamutMappingPolicy.rayTrace`** — public gamut-mapping policy for CSS Ray Trace mapping into sRGB or Display P3. `.adaptiveL0` remains public for legacy comparison and A/B testing.

### Changed

- **Ray Trace gamut mapping is now the default.** `ASCIIConverter.gamutMapping` defaults to `.rayTrace` instead of `.adaptiveL0`. The change improves lightness and hue preservation on out-of-gamut OkLCh stress cases, while reducing chroma more aggressively on some boundary colors.
- **`gamut-sweep` now measures shipped Ray Trace behavior.** The lab `rayTrace` policy delegates to production wrappers, and `adaptiveL0` remains the CSV `baseline_policy` for this release.
- **Snapshot baselines regenerated where default-output bytes changed.** See the visual sign-off note for the exact snapshot scope.

### Documentation

- Release notes call out the ColorAide #400 yellow-desaturation caveat and the Color.js counter-signal so the release does not claim ecosystem consensus.
- **Research registry + front-matter discoverability (ASTSK-9).** Every `docs/Research/` note now carries YAML front-matter, a new `BuildResearchIndex` tool generates the README index and a machine-readable `docs/Research/index.json`, and `ResearchRegistryTests` enforces front-matter validity and index sync in `swift test`. No library or rendered-output change.

## [0.3.1] — 2026-05-27

Correctness release after `v0.3.0`.

### Changed

- **Linear-light sampling is now the default.** `ASCIIConverter.colorSampling` defaults to `.linearLightAverage` instead of `.encodedAverageLegacy`. This changes default rendered output for fixtures where encoded-space averaging previously darkened or skewed per-cell color. Callers that need `v0.3.0`-style encoded averaging can pass `colorSampling: .encodedAverageLegacy` explicitly.
- **Snapshot baselines regenerated for the new default.** The actual changed baseline scope was four image snapshots: one mixed-charset render, two circle-mask fallbacks, and one soft-edge mask fixture. Other regenerated snapshot candidates were byte-identical.

### Documentation

- **`PaletteMatchingPolicy.helmlabMetric` promotion paused.** Helmlab is a separate color space with a MetricSpace pipeline, not a one-line distance function on OKLab inputs. A fresh spec is required before any Helmlab implementation is promoted again.

## [0.3.0] — 2026-05-27

Additive color-pipeline release after `v0.2.0`. Defaults remain unchanged and no snapshots were regenerated.

### Added

- **`PaletteMatchingPolicy.oklabHyAB`** — experimental palette-matching policy using city-block lightness plus Euclidean chroma. The default remains `.oklabEuclidean`.
- **`RenderCompositionPolicy`** — public renderer composition policy with `.encodedDisplay8Bit` as the default and `.extendedLinearPerGamut` as an opt-in target-gamut linear-light composition path.
- **Palette matching DocC article** registered under the Aski documentation catalog.

### Fixed

- **Renderer composition propagation.** Animation frame materialization and the effects raster path now preserve `ASCIIGrid.composition` instead of falling back to encoded-display compositing.

### Documentation

- **`cbrtf` production switch reconciled as shipped.** The OKLab cube-root correction already landed before `v0.2.0`; this release updates the deferred-work review docs so the tracked color-pipeline queue matches repo reality.

## [0.2.0] — 2026-05-27

First tagged release after the initial `v0.1.0` (2026-04). Cumulative roll-up of every change merged to `main` between `v0.1.0` and `v0.2.0`.

### Added

- **A1 — Character-mode expansion.** New algorithms (`ASCIIAlgorithm.logPolar`, `.edgeMap`, `.dotMatrix`), seven new built-in character sets, Courier Prime factory, Braille rasterizer, edge-map + dot-matrix kernels, `RenderingOptions` API. The pre-A1 default-output golden is preserved.
- **A2 — Sample-grid aspect + render-time tile modes.** `ASCIITileShape` (sampling-only: `.square`, `.wide`, `.tall`) replaces the earlier `widthRatio` parameter; `.wide` reproduces the historical `widthRatio: 2.2` default bit-identically. Render-time `TileGrid` adds `TileCellShape` (`.square`, `.hex`, `.triangle`, `.diamond`, `.circle`) and `TileGridMode` (`.pixelArt`, `.brick`, `.mosaic(grout:, groutThickness:, cornerRadius:)`).
- **B Phase 1 — Stock effects + `EffectChain`.** Compose renders with backgrounds, lighting, and effect chains.
- **B Phase 2 — Metal effects, actor, async rendering.** Metal-backed effect execution behind an actor; async rendering APIs.
- **D — Raster mask input support.** Source images accept an optional mask raster to constrain conversion.
- **C1 — Algorithmic animation support.** Frame sequences from a single source.
- **Color Pipeline v2 Phase 1.** `PaletteContent` + `PaletteColor(_:colorSpace:)` API. Palette sources declare colors in sRGB or Display P3; Aski resolves into its internal matching space.
- **`AskiColorLab` research harness** with five lab commands: `sampling-ablation`, `palette-match-ablation`, `gamut-sweep`, `linear-composite-ab`, `cuberoot-accuracy`.
- **`ColorSamplingPolicy.linearLightAverage`** — additive opt-in for physically-correct linear-light averaging during per-cell color sampling. The default remains `.encodedAverageLegacy` in v0.2.0; the flip is deferred to a later release.
- **DocC Markdown sidecar emission in CI.** `Scripts/validate-docc.sh` emits per-symbol Markdown and a manifest JSON; CI uploads them as build artifacts. Surfaced at the GitHub Release level as downloadable assets (see § Migration for the manifest URL).
- **`DESIGN.md`** at repo root — algorithm overview + patent-lineage section.
- **`llms.txt`** at repo root — agent-discoverable pointer file pointing at the DocC Markdown manifest.

### Changed

- **Palette source API.** `colorsOKLAB` removed in favor of ``PaletteContent`` + ``PaletteColor(_:colorSpace:)`` with sRGB / Display P3 declared components. See the Color Pipeline v2 section of `Sources/Aski/Aski.docc/Migrating-to-A1.md` for the full migration.
- **OKLab conversion uses `cbrt` instead of `sign · pow(·, 1/3)`** in `linearSRGBToOKLAB` and `linearP3ToOKLAB`. Canonical round-trip tolerances unchanged. ANSI16 and Display P3 primaries pinned-OKLab regressions installed as silent-drift gates.
- **OKLab matrices `FUSED_LINEAR_SRGB_TO_LMS`, `FUSED_LINEAR_P3_TO_LMS`, `LMS_PRIME_TO_OKLAB`** lifted from `private` to module-internal access for tests and the lab harness.

### Removed

- **`ASCIIConverter.widthRatio`** — replaced by ``ASCIITileShape``. The old `widthRatio: 2.2` default maps to `.wide` (bit-identical).
- **Dead `sign(_:)` helper** in `ColorConversion.swift` — eliminated as part of the cbrt swap.

### Migration

For step-by-step migration from `v0.1.0`, see [`Sources/Aski/Aski.docc/Migrating-to-A1.md`](Sources/Aski/Aski.docc/Migrating-to-A1.md) — specifically the *Migrating from v0.1.0 → v0.2.0* section.

### Deferred (not in v0.2.0)

- `PaletteMatchingPolicy.oklabHyAB` (experimental HyAB metric)
- `PaletteMatchingPolicy.helmlabMetric` (experimental Helmlab metric)
- `RenderColorSpacePolicy.extendedLinear` (per-gamut working space)
- Linear-light sampling as the default (the flip)
- Ray Trace gamut policy as the default

## [0.1.0] — 2026-05-04

Initial release. The conversion pipeline with the original character-mode set, OKLab color pipeline v1, DocC catalog, shape-vector resource layer (`Resources/ShapeData/standard_vectors.bin`, Courier Prime font), and benchmark harness. (Tag commit: `4f61348`, *"Initial commit: Aski v0.1.0"*, tagged 2026-05-04.) The A1 character-mode expansion (algorithms, charsets, kernels) landed in `v0.2.0` and brought the Metal kernel resource layer (`Resources/Kernels/default.metallib`) with it; do not back-attribute either to v0.1.0.
