---
title: "ASKI-78 - ShapeData rasterizer options and golden policy inputs"
slug: 2026-11-24-aski78-rasterizer-options
date: 2026-11-24
status: active
subsystem: [shape-context, meta]
summary: "Decision inputs for ASKI-78; the owner decision is pending. The macOS 27 ShapeData trigger is real for loaded channels (largest delta 0.0059, brightness), but the 0.0452 headline comes from the retired v3 structure block that production reads and discards. On one macOS 27.2.1 host Core Text draws 24 block, box-drawing and geometric glyphs from Menlo, not Courier, and braille (Core Graphics ellipse fills) stayed byte-identical from macOS 26.6.2 to 27. The note costs the per-OS route, compares rasterizer routes (Core Text per OS, Core Text outlines plus CG fill, FreeType, stb_truetype, fontations, a fixed-point rasterizer of Aski's own, programmatic geometric glyphs), adds a freeze-the-rasters alternative, lists AC#4 golden-policy options with precedents, and proposes a staged hash experiment. Recommendation (medium-low confidence): run the experiment first. The AC#1 selection-effect census has not been run."
related_specs: [docs/Research/2026-09-04-aski51-core-text-drift-policy.md, Tools/BuildStandardVectors/BuildStandardVectors.swift, Tools/BuildStandardVectors/VectorDriftAudit.swift, Sources/Aski/CharacterSets/StandardCharacterSet.swift, Tools/AskiToolSupport/FrozenRenderReference.swift]
results: [docs/Research/Results/2026-11-05-aski97-render-drift]
runners: [BuildStandardVectors]
next_action: "Owner decides ASKI-78 AC#2 and AC#4. Before that, run the AC#1 selection-ceiling MAE and GMSD census (in-memory regenerated vectors versus committed) on the frozen reference, and, if wanted, pre-register and run the staged hash experiment below."
---

# ASKI-78 - ShapeData rasterizer options and golden policy inputs

**Decision: pending owner.** This note records evidence for the owner's decision on ASKI-78
(acceptance criteria 2 and 4). It does not make that decision. The research was done read-only
at `f3f7663a` on 2026-11-24. No build, test, render, or benchmark was run for it. The local
probes ran on one Apple M5 Max host with macOS 27.2.1 (26B8132).

## What ASKI-78 must decide

1. How committed ShapeData survives Core Text drift: vendor a deterministic glyph rasterizer, or
   define explicit per-OS rasters, so that the
   [ASKI-51 audit](2026-09-04-aski51-core-text-drift-policy.md) either stops depending on the OS
   rasterizer or is keyed per OS (AC#2). Until this lands, any change that needs ShapeData
   regeneration (schema, raster construction, glyph inventory, accepted matching change) is
   blocked by the ASKI-51 policy.
2. How rendered goldens (88 PNG snapshots and the G0 byte golden) handle more than one OS and more
   than one host (AC#4).

AC#1 asks for the selection effect of the macOS 27 drift on the frozen reference
([FrozenRenderReference.swift](../../Tools/AskiToolSupport/FrozenRenderReference.swift)):
selection-ceiling MAE and GMSD with in-memory regenerated vectors versus committed vectors.
**That census has not been run.** The maintenance cost of per-OS rasters is estimated below from
the repository, without a build.

## The macOS 27 trigger, read by channel

The ASKI-51 audit fired on macOS 27.0 (ASKI-77) and again on macOS 27.0.1 (ASKI-97): 9 of 10 sets
drift, the standard set's brightness order changes, and braille is byte-identical. The reported
maximum component delta, 0.0452, is real but comes from a channel production does not use.

ShapeData v3 stores brightness, a 60D shape descriptor (15 SIMD4 lanes), raw density, and a
retired structure block (8 orientation bins and a radial peak).
`Sources/Aski/CharacterSets/StandardCharacterSet.swift:100-106` reads the retired block only to
validate the file length and then discards it. The audit's maximum mixes both kinds of channel.

Maxima recomputed from
[vector-glyph-drift.csv](Results/2026-11-05-aski97-render-drift/vector-glyph-drift.csv)
(macOS 27.0.1, 26A434; 414 glyph rows, 158 of them outside braille):

| Channel | Loaded by production | Largest delta |
| --- | --- | ---: |
| Brightness | yes | 0.00594 |
| Raw density | yes | 0.00591 |
| 60D shape lanes | yes | 0.00560 |
| Orientation histogram | no (retired v3 block) | 0.04518 |
| Radial peak | no (retired v3 block) | 0.01757 |

- 91 of the 158 non-braille glyph rows exceed the 0.001 tolerance in a loaded channel (127 in
  any channel). All 256 braille rows are zero.
- On loaded channels alone, 8 of 10 sets exceed the tolerance. The lines set's largest loaded
  delta is 0.00041; it fires only through the retired block. Braille does not fire.
- The standard-set sort change is driven by brightness, a loaded channel, so trigger condition 2
  holds independently of the retired block.

The trigger therefore still fires on loaded channels, at about one eighth of the headline delta.
Whether that drift changes selection on the frozen reference is the AC#1 census question.

## Cost of the per-OS route

Committed ShapeData is ten files, 119,534 bytes, of which braille.bin is 73,759 bytes.
`Package.swift:31` copies `Resources/ShapeData` into the Aski bundle, so every file there ships
to every app that links Aski.

- **Selection is already bound to committed bytes.** `Sources/Aski/CharacterSets/GlyphBank.swift:50-53`
  marks built-in sets as `.committedAsset`. No runtime path regenerates ShapeData. Per-OS keys are
  needed only by the audit and by regeneration, not by the shipped library.
- **The audit has no key today.** `Tools/BuildStandardVectors/VectorDriftAudit.swift:199-215`
  compares fresh in-memory bins with the committed bins; the tolerance test is at `:144` and
  `:150-151`, the sort comparison at `:187`. It records OS, Xcode, and Swift provenance
  (`:258-259`) but never keys a comparison on them, and records no host hardware.
- **Cheapest form.** Store a per-key digest file (one SHA-256 per set, or per glyph for
  diagnosis) under `Tools/` or `Tests/`, keyed by macOS build and the hashes of the system font
  files used (Courier and, because of fallback, Menlo). Add the host chip only if same-OS host
  dependence is shown. Nothing reaches an app bundle. Storing full per-key `.bin` sets instead
  costs about 46 KiB per key for the nine Core Text sets.
- **Recurring cost.** One audit run and one digest commit per new OS build per maintainer host.
- **What it does not buy.** Regeneration stays non-reproducible: bytes made on OS N cannot be
  reproduced on OS N+1, so every authorized regeneration mixes the intended change with OS drift
  and needs the AGENTS.md no-harm census.
- **Inputs it would key.** `justfile:75-79` defines `regen-vectors` and `audit-vectors`.
  `Tools/BuildStandardVectors/BuildStandardVectors.swift:69` uses system Courier
  (`CTFontCreateWithName("Courier", 32, nil)`), not the bundled Courier Prime. `:182` rasterizes
  through `RasterizedCharacterSet` (64×64, CTLineDraw). `:186-198` and
  `Tools/BuildStandardVectors/LegacyShapeChannels.swift:15-40` build the retired block at 24×24.
  `:151-180` route braille through `BrailleRasterizer` with no font.
- **Out of scope.** Runtime Core Text use in `RasterizedCharacterSet` (caller fonts) and in
  `Sources/Aski/Renderers/ImageRenderer.swift:784` and `:1157` stays OS-dependent under every
  option, so no ShapeData decision makes rendered PNG goldens OS-independent.

## Font fallback: 24 glyphs come from Menlo

A read-only probe called `CTFontCreateForString` on each glyph on the macOS 27.2.1 host. The probe
script was a scratch file and is not committed. Results:

- System Courier and bundled Courier Prime both fall back to Menlo-Regular for 24 of the 123
  unique non-braille glyphs: `░▒▓█▄▀■ ◦○● ─│┌┐└┘├┤┬┴┼ ◇◈◆`.
- System Courier covers `∙` (U+2219); Courier Prime does not.
- The committed blocks, lines, dots, diamond, and mixed vectors therefore depend on an Apple
  system font chosen by the OS cascade list. A bundled-font route needs a second redistributable
  font with these glyphs, or programmatic drawing of them.
- Drift appears in both Courier-sourced glyphs (overall maximum 0.0235) and Menlo-sourced glyphs
  (overall maximum 0.0452), so fallback alone does not explain the drift.
- Not checked: the cascade on macOS 26, and any other host.

## Braille evidence

Braille is drawn by `BrailleRasterizer` with Core Graphics `fillEllipse` into an 8-bit gray
bitmap (`Sources/Aski/CharacterSets/Braille/BrailleRasterizer.swift:67-86`) and runs through the
same descriptor maths (`Sources/Aski/Algorithms/ShapeContext.swift`, `atan2f` at `:41` and
`:99`). All 256 braille glyphs were byte-identical between macOS 26.6.2 and 27.0.1. On that
evidence the drift lies in the Core Text text path or in the system fonts, not in CG path filling
or in the descriptor maths. This is one host and one OS pair.

## Rasterizer routes

Tiers follow the research guide: T1 primary source or vendor documentation, T2 issue trackers and
registry data, T4 practitioner code, T5 forums. Maintenance dates were checked on 2026-11-24.

| Route | Determinism evidence | Integration | Licence | Maintenance | Main risks |
| --- | --- | --- | --- | --- | --- |
| Core Text keyed per OS (status quo plus keys) | Drifts 26.6.2 to 27 in 9 of 10 sets (Aski). Same-OS host dependence for ShapeData untested | Digest files and a key lookup in the audit | n/a | Apple | Non-reproducible regeneration; Menlo fallback is OS-controlled; re-key on every OS update |
| Core Text outlines (`CTFontCreatePathForGlyph`, bundled font) plus CG fill on a CPU 8-bit bitmap | No Apple stability statement found. Braille (CG fill, same bitmap kind) byte-identical 26.6.2 to 27 (Aski, one host) | Small tool change, no dependency | n/a | Apple | CG anti-aliasing could change in any OS; needs a solution for the 24 Menlo glyphs |
| FreeType 2.15.0 smooth rasterizer, `FT_LOAD_NO_HINTING \| FT_LOAD_NO_BITMAP`, `FT_RENDER_MODE_NORMAL` | [ftgrays.c](https://gitlab.freedesktop.org/freetype/freetype/-/raw/master/src/smooth/ftgrays.c) states it computes exact coverage and "doesn't use floating point values" (T1). Output changes between versions: [CHANGES](https://gitlab.freedesktop.org/freetype/freetype/-/raw/master/docs/CHANGES) 2.11.0 (T1), [py-sdl2 #286](https://github.com/py-sdl/py-sdl2/issues/286) at 2.14.0/2.14.1 (T2). No same-version cross-platform counterexample found | Vendored C target in a tool only (precedent: [freetype-spm Package.swift](https://raw.githubusercontent.com/tomasf/freetype-spm/main/Package.swift)) | [FTL](https://freetype.org/license.html), BSD-style with a credit clause, or GPLv2 | 2.15.0 released 2026-10-12 ([freetype.org](https://freetype.org/)) | Version drift unless pinned; overlap oversampling (2.10.3) changes coverage; unhinted rasters change selection, so the census applies |
| [stb_truetype](https://raw.githubusercontent.com/nothings/stb/master/stb_truetype.h) v1.28 | Accumulates coverage in `float` scanlines (T1). Clang contracts floating-point expressions by default ([clang manual](https://clang.llvm.org/docs/UsersManual.html)); Go's [x/image/vector](https://raw.githubusercontent.com/golang/image/master/vector/raster_floating.go) disables FMA for bit-exact output | Single header; `#pragma STDC FP_CONTRACT OFF` | MIT or public domain | v1.28 dated 2026-11-12 | Float results may move with compiler changes (untested); header warns of no security guarantee |
| fontations ([skrifa](https://raw.githubusercontent.com/googlefonts/fontations/main/skrifa/README.md)) plus zeno, [vello_cpu](https://docs.rs/crate/vello_cpu/latest/source/README.md), or tiny-skia | skrifa is tested against FreeType ([fauntlet](https://raw.githubusercontent.com/googlefonts/fontations/main/fauntlet/README.md), T1); rasterizers are float-based, no determinism claim | Rust static library behind a C ABI; Rust toolchain for maintainers | MIT or Apache-2.0; tiny-skia BSD-3-Clause | skrifa 0.50.0 (2026-11-10), vello_cpu 0.4.0 (2026-11-11) | Heaviest toolchain change; determinism unproven |
| fontdue 0.9.5 ([README](https://raw.githubusercontent.com/mooman219/fontdue/master/README.md)) | No determinism statement found | Rust to C ABI | MIT, Apache-2.0, or Zlib | 0.9.5 (2026-10-19) | As fontations |
| HarfBuzz hb-raster | Fixed-point edges plus a float flattening threshold and SIMD paths ([hb-raster-draw.cc](https://raw.githubusercontent.com/harfbuzz/harfbuzz/main/src/hb-raster-draw.cc), T1) | New C++ library | Old-MIT-style | Experimental since 13.0.0; 15.2.0 on 2026-11-20 ([NEWS](https://raw.githubusercontent.com/harfbuzz/harfbuzz/main/NEWS)) | Experimental API; mixed integer and float |
| Fixed-point coverage rasterizer written in Aski, fed by outlines (`CTFontCreatePathForGlyph` or the bundled TTF `glyf` table) | Integer accumulation is deterministic if its outline input is | About 300-500 lines in `Tools/` | Aski's own | Aski | Own bugs; outline input stability; still needs the 24-glyph solution |
| Programmatic geometric glyphs (complements any route) | `BrailleRasterizer` precedent (Aski); [Alacritty](https://raw.githubusercontent.com/alacritty/alacritty/master/extra/man/alacritty.5.scd) draws U+2500 to U+259F itself by default | Extend the braille pattern | Aski's own | Aski | These glyphs stop looking like Menlo (design choice) |

The rasterizer only needs to run in `Tools/BuildStandardVectors` on macOS. It does not need to
ship in the library or run on iOS or visionOS. Whether SwiftPM builds or fetches a tool-only C
target for consumers who use only the Aski library product was not verified.

## Alternative: freeze the rasters, not the rasterizer

Commit the canonical 8-bit coverage rasters as tool or test data and derive descriptors from
them. For the 123 non-braille glyphs at 64×64 plus 24×24 that is 574,656 bytes before PNG
compression. Schema changes, descriptor changes, and accepted matching changes (most of what the
ASKI-51 policy now blocks) would then need no rasterizer at all. Only glyph-inventory changes
would need new rasters, made by whichever route is chosen. The risk is that the descriptor maths
(`atan2f`, `Float`) must itself be stable; the braille result above is evidence that it was,
on one host across one OS pair.

## AC#4 golden-policy options

All 92 snapshot files (88 PNG, 4 `.txt`) compare with swift-snapshot-testing's `as: .image`
defaults, which in 1.18.9 means any byte difference fails. The G0 byte golden
(`Tests/AskiTests/ImageRendererGoldenTests.swift:68`) is an exact byte comparison. On one
macOS 27.0.1 host, 16 PNGs differed by one 8-bit step from goldens that pass on an M3 Max with
the same OS and Xcode builds ([ASKI-97 evidence](Results/2026-11-05-aski97-render-drift/README.md)).
All 16 are in the Composition, Effect, and Mask suites, which route through Core Image.

| Option | Mechanism | Precedent | Cost and risk |
| --- | --- | --- | --- |
| A. macOS-27, host-pinned exact (status quo) | Name a reference host in CONTRIBUTING | [Playwright](https://playwright.dev/docs/test-snapshots): run tests where baselines were made | No tooling; other hosts fail; ASKI-112 stays open |
| B. Several accepted exact digests per snapshot | Pass if the image hash equals any committed digest, each annotated with OS build and chip | [Chromium GPU tests with Skia Gold](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/gpu/gpu_pixel_testing_with_gold.md): exact matching with several baselines by default; [Flutter Gold](https://raw.githubusercontent.com/flutter/flutter/master/docs/contributing/testing/Writing-a-golden-file-test-for-package-flutter.md) | Small helper; re-triage per new host or OS; the 16 variants were stable across four captures, so one extra digest each would cover them |
| C. Per-channel tolerance of 1 | Custom Diffing, opt-in per snapshot | [Typst](https://raw.githubusercontent.com/typst/typst/main/tests/src/output.rs) defaults to 1 | Hides real one-step regressions; ASKI-112 AC#3 forbids tolerance until the cause is shown inherent |
| D. Split by path | Exact for CPU-only outputs (`.txt` goldens, ShapeData, braille-only images); B for Core Image suites; C only where ASKI-112 proves inherent nondeterminism | Chromium chooses per test | Needs a per-suite classification; G0 placement unknown until its host stability is known |
| E. Per-OS directories with fallback | Snapshot directory keyed by OS (and chip) | [Chromium baseline fallback](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/testing/web_test_baseline_fallback.md) | About 2.3 MB of PNG per key; custom fallback logic |

swift-snapshot-testing 1.18.9 offers no maximum per-channel delta mode; its `perceptualPrecision`
runs through Core Image, the stack suspected of the variance
([NSImage.swift](https://raw.githubusercontent.com/pointfreeco/swift-snapshot-testing/1.18.9/Sources/SnapshotTesting/Snapshotting/NSImage.swift)).
No Apple document was found stating that Core Graphics or Core Image output varies by one step
between Apple-silicon hosts on the same OS build. An Apple DTS reply in an
[Apple Developer Forums thread](https://developer.apple.com/forums/thread/844598) (September 2026, T5)
quotes the Metal Shading Language allowing either of two rounding modes and denormal flushing, so
bit-identical GPU output across GPU families is not promised.

## Proposed staged experiment (not a frozen rule)

This is a proposal. A decision rule must be pre-registered before any run.

- **Stage 0, no code.** Run `just audit-vectors --output-dir <scratch dir>` on the M3 Max (27.0.1)
  and the recording host (27.0.1) and byte-compare the two `glyph-drift.csv` files. Identical
  files mean Core Text ShapeData generation is host-independent at a fixed OS build; different
  files mean per-OS keys must also be per-host. Repeat once under parallel load. Record chip, OS
  build, Xcode build, and the SHA-256 of the Courier and Menlo font files.
- **Stage 1, scratch tool outside the repository.** Rasterize the 123 non-braille scalars from
  bundled Courier Prime (record its SHA-256) at 64×64 and 24×24, placed from integer outline
  bounds rather than Core Text image bounds. Arms: (a) current CTLineDraw construction, the
  negative control; (b) `CTFontCreatePathForGlyph` plus CG fill into an 8-bit gray bitmap;
  (c) FreeType 2.15.0 from the release tarball (record its SHA-256 and compiler flags, add
  `-ffp-contract=off`); (d) the 24 geometric glyphs drawn programmatically. Output one SHA-256
  per glyph raster per arm. Hosts: M3 Max 27.0.1, recording host 27.0.1, M5 Max 27.2.1, and one
  macOS 26.x install (whether a VM is an acceptable stand-in is unverified). An arm qualifies only
  if every per-glyph hash matches on every host and OS. If arm (a) never varies, the instrument
  is not sensitive.
- **Stage 2, only for a qualifying arm.** Regenerate ShapeData in memory from that arm and run the
  selection-ceiling MAE and GMSD census against committed ShapeData on the frozen reference
  before any regeneration is proposed. In parallel, cost the per-key digest route from Stage 0.

## What remains unverified

1. Whether Core Text ShapeData generation is host-dependent at a fixed OS build.
2. Whether `CTFontCreatePathForGlyph` plus CG fill gives the same bytes across hosts and across
   macOS 26 and 27 for a bundled font.
3. Whether a pinned FreeType build gives the same bytes across hosts, OS versions, and Xcode
   versions. No maintainer statement or counterexample was found either way.
4. A redistributable font covering the 24 Menlo glyphs, or the programmatic alternative (an owner
   design choice).
5. The SwiftPM consumer cost of a tool-only vendored C target.
6. The cause of the 16-pixel host variance and of ASKI-112.
7. The AC#1 selection-effect census.

## Recommendation (not a decision)

Recommendation from the research leg, **medium-low confidence**: run the staged experiment before
choosing. The prior favours a tool-only vendored FreeType smooth rasterizer (pinned 2.15.0 source)
for Courier Prime text glyphs, plus programmatic drawing for the 24 geometric glyphs in the style
of `BrailleRasterizer`, with the shipped library keeping one committed ShapeData set. If arm (b)
proves byte-identical across hosts and across a macOS 26 to 27 pair, it needs no new dependency and
should be preferred. If even FreeType differs across hosts, adopt per-key audit digests and stop
pursuing determinism.

For AC#4 the recommendation, **medium confidence**, is option D: exact comparison for CPU-only
outputs and several accepted digests per snapshot for the Core Image suites, with a per-channel
tolerance only after ASKI-112 identifies the cause.

**Decision: pending owner.**
