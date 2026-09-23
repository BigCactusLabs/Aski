---
title: "Issue #33 - Exact Target-Size Rendering and Lossless Animated WebP, Grounded Before Filing"
slug: 2026-09-01-issue33-target-size-render-and-lossless-webp
date: 2026-09-01
status: complete
subsystem: [frontier, animation]
summary: "Research spike behind source tracker issue #33 (not migrated), which asks for three things a retina web consumer had to do outside the API: an exact target-pixel-width render, a documented relationship between font size, scale and downscaling, and a lossless animated WebP encoder beside ASCIIGIFEncoder. Two of the three asks collapse under measurement. Font size and the CG scale transform are pixel-identical for Aski's fonts: rendering at size S with scale k and at size S times k with scale 1 gave zero differing bytes on the bundled Courier Prime and on Menlo at every ratio tried, including the 0.38 a direct 1166 px render needs, so scale is the one knob and an exact width is a closed-form scale, not a resize. The remaining quality question is direct render at the derived fractional cell advance versus supersample-then-area-average, and that is a measurement the follow-up task pre-registers rather than a decision this note makes. The third ask cannot be met with ImageIO on any current Apple OS: CGImageDestination has no WebP writer on macOS 26.6.2 or the iOS 26.5 simulator, the kCGImagePropertyWebP keys are decode-side only, multi-frame AVIF is refused, and ImageIO's own APNG writer produced a 14.3 MB file where the consumer's libwebp lossless WebP is 2.49 MB and the GIF 3.04 MB. A lossless animated WebP encoder therefore means the package's first C dependency, libwebp through its WebPAnimEncoder, and that is an owner decision the task carries as its first acceptance criterion. Two follow-up tasks are filed, ASKI-63 for the target-size path and ASKI-64 for the encoder."
related_specs: [docs/architecture.md]
datasets: []
runners: []
next_action: "ASKI-63 (exact target-size render, measurement-gated interpolation choice) and ASKI-64 (lossless animated WebP via libwebp, dependency decision first) are filed from this note. Neither changes a default. ASKI-63 should run before ASKI-64 because the consumer's byte numbers depend on the frames the render path produces."
---

# Issue #33 — exact target-size rendering and lossless animated WebP

Origin: source tracker issue #33 (not migrated), filed 2026-09-01. The consumer is
a downstream website's canyon strip: a 384-column animated grid rendered at 13.33 pt, native
width 3072 px, resized per frame to 1166 px (@1x) and 2332 px (@2x), then repackaged from
GIF frames into lossless animated WebP with `img2webp -lossless -m 6`.

Method: a Claude research spine with two read-only research workers, a Codex cross-model
sweep on the ImageIO question, and local measurements on this machine (macOS 26.6.2, Xcode
SDK 26.5). Every number below that is not linked is a local measurement from this run; the
scripts are not committed because they are throwaway probes against private consumer assets.

## 1. Ask 2 is settled: font size and `scale` are the same knob

`ASCIIGrid.renderImage(font:backgroundColor:scale:preserveSourceAspect:)` builds its
geometry as `glyphWidth = pointSize × 0.6`, `pixelWidth = ceil(columns × glyphWidth × scale)`,
then applies `scale` as a CG transform and draws glyphs at `pointSize`
(`Sources/Aski/Renderers/ImageRenderer.swift`, `renderGeometry`). Whether Core Text
rasterizes the same pixels for (size S, transform k) and (size S·k, transform 1) is not
documented by Apple; Skia's Core Text backend deliberately folds device scale into the
requested text size because color glyphs and optical-size tables (`trak`) key on it
([SkScalerContext_mac_ct.cpp](https://raw.githubusercontent.com/google/skia/main/src/ports/SkScalerContext_mac_ct.cpp)).

Measured here, for the fonts Aski actually ships or falls back to:

| font | size × scale | vs size·scale × 1 | differing bytes |
|---|---|---|---|
| Courier Prime (bundled) | 13.333 × 0.38 | 5.067 × 1 | 0 / 19200 |
| Courier Prime (bundled) | 13.333 × 0.76 | 10.133 × 1 | 0 / 19200 |
| Courier Prime (bundled) | 13.333 × 2.0 | 26.667 × 1 | 0 / 19200 |
| Courier Prime (bundled) | 6.0 × 3.1 | 18.6 × 1 | 0 / 19200 |
| Menlo (`ASCIIFont.system` fallback) | 13.33 × 2 | 26.66 × 1 | 0 / 48000 |
| Menlo | 13.33 × 1.5 | 19.995 × 1 | 0 / 48000 |

Byte-identical with subpixel positioning on and off, with the text origin matched in device
space. So for monochrome monospaced fonts the effective pixel size is `pointSize × scale`
and nothing else. The consumer's "double the font size for @2x" and "double `scale`" are
the same operation. This is the sentence the DocC page should carry, with the caveat that
color fonts or fonts with optical-size axes are out of scope (Skia's reason, untested here).

Consequence for ask 1: an exact target width is a closed-form scale,
`scale = targetWidth / (columns × pointSize × 0.6)`, and the render lands at the target
resolution with no resample at all. The current `ceil` in `RenderPixelBounds.pixelExtent`
can round a float-noisy product up by one pixel, so a target-width entry point must set the
pixel width directly and derive the scale, not the reverse.

## 2. The open quality question, and why it is a measurement

Direct render at the derived scale means a fractional cell advance (1166 / 384 = 3.036 px)
and glyphs rasterized by Core Text at about 5 px. The alternative the consumer uses today is
render large, then downscale. Which gives better glyph edges is not settled by any source
found:

- `CGInterpolationQuality.high` names no algorithm in Apple's documentation
  ([CGInterpolationQuality](https://developer.apple.com/documentation/coregraphics/cginterpolationquality)),
  so the consumer's current resize is an unspecified, version-unstable step.
- vImage documents its resampler as "Lanczos3, probably" by default and "typically Lanczos5"
  under `kvImageHighQualityResampling` (`vImage_Types.h`, SDK 26.5), and requires
  non-premultiplied data to avoid high-frequency artifacts (`Geometry.h`). Aski renders into
  a premultiplied context. Lanczos rings on hard edges; box and Catmull-Rom are the line-art
  recommendations ([ImageMagick filter guide](https://usage.imagemagick.org/filter/)).
- Terminal emulators refuse fractional cells and pad the remainder (Alacritty floors the
  advance: [display/mod.rs](https://raw.githubusercontent.com/alacritty/alacritty/master/alacritty/src/display/mod.rs));
  browsers go fractional with subpixel positioning and accept the cost
  ([Esfahbod, 2012](https://docs.google.com/document/d/1wpzgGMqXgit6FBVaO76epnnFC_rQPdVKswrDQWyqO1M/mobilebasic)),
  whose named failure mode is low-frequency banding from accumulated rounding. An ASCII grid
  is periodic, so that failure mode maps onto this case exactly. Padding is wrong for the
  consumer (centre-anchored `object-cover` crops), so the choice is fractional advance versus
  supersample-and-average, both of which honour the exact width.
- Downscaling in sRGB rather than linear light changes glyph weight; for light-on-dark output
  it thins the glyphs ([Summers, ImageWorsener](https://entropymine.com/imageworsener/gamma/)).

Core Graphics gates subpixel placement on two flags at once (`allowsFontSubpixelPositioning`
and `shouldSubpixelPositionFonts`) plus a separate quantization pair (`CGContext.h`, SDK
26.5); Skia's recipe sets all four explicitly. The direct-render arm must do the same or it
is measuring the defaults.

ASKI-63 therefore pre-registers a two-arm measurement on the consumer's own grid rather than
picking: (A) direct render at the derived scale with the four CG flags set; (B) integer-factor
supersample followed by area average in linear light. Reference and oracles are fixed in the
task before the run. Aski ships whichever wins and documents the other.

## 3. Ask 3 cannot be met with ImageIO

Measured on macOS 26.6.2 and, by the second worker, on the iOS 26.5 simulator runtime:

| capability | result |
|---|---|
| `CGImageDestinationCopyTypeIdentifiers()` contains `org.webmproject.webp` | no (22 UTIs; PNG, GIF, HEIC, HEICS, AVIF present) |
| `CGImageDestinationCreateWithURL(…, "org.webmproject.webp", n, nil)` | nil |
| `CGImageSourceCopyTypeIdentifiers()` contains WebP | yes (decode only) |
| `kCGImagePropertyWebPDictionary/DelayTime/LoopCount` in `CGImageProperties.h` | yes, `IMAGEIO_AVAILABLE_STARTING(11.0, 14.0)`, populated on decode only |
| `public.avif` multi-frame destination | refused (n=1 works, n>1 nil); `public.avis` not a destination type |
| lossless request key in `CGImageDestination.h` | none; `kCGImageDestinationLossyCompressionQuality = 1.0` on HEICS is not lossless (max channel delta 2/255) |

The 2021 forum report of `unsupported file format 'org.webmproject.webp'` is still the state
of the world ([Apple Developer Forums thread 688001](https://developer.apple.com/forums/thread/688001),
re-reported November 2024, no Apple reply); SDWebImage's maintainer confirmed the same at
the iOS 14 beta ([SDWebImage#3041](https://github.com/SDWebImage/SDWebImage/issues/3041)).

What ImageIO can write, on the consumer's real 17-frame 1166×777 corpus decoded from its GIF:

| container | encoder | bytes |
|---|---|---|
| GIF (shipped) | ImageIO via `ASCIIGIFEncoder` | 3,035,750 |
| lossless animated WebP (shipped) | `img2webp -lossless -m 6` | 2,493,752 |
| APNG | ImageIO `public.png` + APNG delay/loop keys | 14,268,917 |
| HEICS, quality 1.0 | ImageIO `public.heics` | 8,978,062 (not lossless) |

ImageIO's APNG writer is lossless (byte-identical decode, second worker's corpus) but does no
useful inter-frame reduction; on this corpus it is 4.7× the GIF and 5.7× the WebP. AVIF is
not writable as a sequence. So the only route to the consumer's numbers is libwebp itself.

Two independent corpora agree on direction: the second worker's synthetic 12-frame ASCII
grid gave WebP 118 KB vs GIF 446 KB vs APNG 483 KB, and `WebPAnimEncoder` beat a
keyframe-only mux of the same frames by about 40% (118 KB vs roughly 196 KB). The encoder
API matters, not just the format.

Dependency landscape (GitHub, retrieved this run):

- [SDWebImage/libwebp-Xcode](https://github.com/SDWebImage/libwebp-Xcode): SwiftPM, single C
  target over upstream libwebp, ships `mux.h` and `demux.h`, release 1.6.0 on 2026-07-31,
  BSD-3. Thinnest viable dependency; `WebPAnimEncoder` is reachable.
- [SDWebImage/SDWebImageWebPCoder](https://github.com/SDWebImage/SDWebImageWebPCoder): active,
  but drags the whole SDWebImage stack and its animated path pushes keyframes through
  `WebPMux`, not `WebPAnimEncoder`. Rejected.
- [awxkee/webp.swift](https://github.com/awxkee/webp.swift): last push 2025-04-01. Stale.
- [ainame/Swift-WebP](https://github.com/ainame/Swift-WebP): 0.6.1 on 2026-02-19, static
  WebP only, no animated encode documented. Not sufficient alone.
- Upstream API: `WebPAnimEncoderNew/Add/Assemble` in
  [mux.h](https://github.com/webmproject/libwebp/blob/main/src/webp/mux.h); losslessness is
  the `lossless` config flag, not `quality = 100`
  ([encode.h](https://github.com/webmproject/libwebp/blob/main/src/webp/encode.h)), and RGB
  under alpha-zero pixels survives only with `exact = 1`
  ([WebP FAQ](https://developers.google.com/speed/webp/faq)). Aski's `--background clear`
  output makes that flag load-bearing for a byte-identical oracle.
- Format limits that Aski's own bounds do not enforce: 16383 px per side (Google's FAQ; the
  bitstream spec says 16384, so take the smaller) against `RenderPixelBounds.maxPixelExtent`
  of 1,048,576, and a 4 GiB RIFF container
  ([container spec](https://developers.google.com/speed/webp/docs/riff_container)).
- None of the three wrapper manifests declares a visionOS platform (`libwebp-Xcode`
  `Package.swift` lists macOS, iOS, tvOS, watchOS); the visionOS build is proof by doing.

The `Aski` library target has no third-party dependencies today (`Package.swift`; the five
packages listed are test, benchmark and tool dependencies). Adding libwebp to it is a
policy change. The recommendation is a separate product (`AskiWebP` or similar) so the core
stays dependency-free and app consumers opt in; the "no SDK ceremony" rule argues for a
thin encoder type over the C target, mirroring `ASCIIGIFEncoder`, not a codec abstraction.

Browser support does not discriminate: caniuse-db gives WebP 96.1%, APNG 95.9%, AVIF 94.7%
global support, with animation included in every fully-supporting version
([caniuse-db webp.json](https://github.com/Fyrd/caniuse/blob/main/features-json/webp.json)).

## 4. Two incidental findings

- **GIF cannot hold 1/12 s.** ImageIO stores 0.08 s in both the clamped and unclamped delay
  fields for a requested 0.0833 s (second worker, measured); APNG and WebP keep 0.083.
  `ASCIIGIFEncoder` documentation should say so; 12 fps and 24 fps exports drift about 4%.
  A related doc-versus-measurement disagreement: Apple's reference for
  [kCGImagePropertyWebPDelayTime](https://developer.apple.com/documentation/imageio/kcgimagepropertywebpdelaytime)
  says the value "is never less than 100 milliseconds", yet the worker read 0.083 back from
  a libwebp file through ImageIO on macOS 26.6.2. ASKI-64's round-trip test should read the
  unclamped key and treat the clamped one as advisory.
- **The consumer's `.high` resize runs in sRGB on premultiplied pixels**, which is the
  documented artifact regime for vImage and the gamma regime that thins light-on-dark glyphs.
  Whatever ASKI-63 ships, it should state the resample space in the manifest.

## 5. What was not resolved

- Whether a physical iOS device exposes a WebP writer the simulator does not. Unlikely, and
  closable with a six-line probe on a device.
- No published text-specific downscale benchmark exists; ASKI-63's measurement is the first
  for this repo.
- Whether Core Graphics still switches glyph dilation on foreground luminance (a 2015 Mozilla
  finding, [bug 1230366](https://bugzilla.mozilla.org/show_bug.cgi?id=1230366)) on macOS 26.
  Relevant to bone-on-oxblood, untested.
- The Codex cross-model sweep (gpt-5.6-terra, live web search, read-only) landed after the
  draft and agreed on every headline: no ImageIO WebP destination on the tested runtime, the
  WebP keys are metadata only, quality 1.0 is conditional, APNG is the ImageIO-native path,
  `libwebp-Xcode` 1.6.0 is the foundation. It added the `exact` flag, the 16383 px cap, the
  visionOS manifest gap and the 100 ms clamp above, and its own synthetic text render put
  lossless WebP 11% under q75 and 31% under q90 with zero changed channels, corroborating the
  consumer's lossy-is-worse finding on a second corpus.
