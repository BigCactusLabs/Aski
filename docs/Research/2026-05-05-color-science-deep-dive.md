---
title: "ASCII color science deep dive"
slug: 2026-05-05-color-science-deep-dive
date: 2026-05-05
status: living
subsystem: [color-science]
summary: "Three-pass survey over OKLAB matching, gamut mapping, palette construction, output color spaces, alpha compositing, and display-surface differences. Pass 3 surfaces Krasilnikov 2024's CAM16-UCS-beats-OKLab psychophysics finding, corrects pass 2's binary-search-versus-Halley framing (Aski's binary search is the CSSWG default), names cross-cutting load-bearing assumptions, proposes seven Aski-runnable experiments, and ends with five original conjectures (the ASCII-regime thesis)."
runners: [AskiColorLab]
datasets: []
next_action: "Run the proposed Aski color experiments; validate the HyAB-for-matching and CAM16-UCS conjectures."
---

# ASCII color science deep dive

**Date:** 2026-05-05 (started); pass 3 added 2026-05-06
**Triggered by:** No specific bug — a wide-angle pass to (a) validate Aski's current color-pipeline choices against 2025–2026 practice, (b) survey alternatives Aski hasn't picked, (c) leave a state-of-the-art reference so future-us doesn't have to re-derive it. **Three research passes**: pass 1 mapped the field; pass 2 contested pass-1 claims and plumbed edges; pass 3 oriented the doc against published experimental protocols, surfaced genuine field gaps, and corrected pass-2 numerical and Aski-side claims.

## Question

Aski's pipeline makes six load-bearing color decisions:

1. **Color space + distance metric** for matching — OKLAB + Euclidean (`ColorConversion.swift`, `ASCIIPalette.swift`).
2. **Gamut mapping** for output — Ottosson adaptive L₀ with α=0.05, 16-iteration binary search (`GamutMapping.swift`).
3. **Palette construction** — static built-in palettes only (`BuiltInPalette.fullColor` / `.monochrome` / `.ansi16`); no image-derived palette today.
4. **Output color spaces** — `sRGB | displayP3` (`RenderColorSpace.swift`).
5. **Alpha compositing** — `ASCIICell` carries FG color + alpha; renderers blend over a caller-supplied background.
6. **Display surface** — `AttributedStringRenderer` (SwiftUI/AppKit/UIKit), `ImageRenderer` (CGImage), `PlainTextRenderer` (no color).

Each was picked at some point with at-the-time reasoning. Where has the field moved since? What's still right? What divergences are real bugs vs academic curiosities? What experimental protocols would settle the open questions, and what does the field genuinely not know?

## What the field says

### 1. Color space + distance metric

**Consolidation, qualified.** OKLAB has consolidated as the 2025–2026 default for *gradients and perceptual interpolation*. By [March 2025 it was formalized in CSS Color Module Level 4/5](https://www.w3.org/TR/css-color-4/) and ships in Chrome, Safari, and Firefox; `color-mix(in oklab)` has been [Baseline Widely Available since 2024](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/color-interpolation-method) (Chrome 111, Safari 16.2, Firefox 113). Adoption spans Adobe Photoshop, Unity, Godot, Tailwind, Radix, and most new design-system palette generators. Apple has not formally adopted OKLAB — ColorSync remains ICC v4 / CIELAB — but third-party Swift libraries like [importRyan/Oklab](https://github.com/importRyan/Oklab) cover the gap.

**Independent psychophysics now exists, and OKLab is mid-pack.** Pass-2 framed OKLab's perceptual uniformity as established. It isn't, in measured terms. [Krasilnikov et al. (Dec 2024, *MDPI Imaging*)](https://pmc.ncbi.nlm.nih.gov/articles/PMC11676281/) evaluated OKLab against CAM16-UCS-PC, JzAzBz, ICtCp, ICaCb, proLab, ΔE2000, and a fitted ΔEf on COMBVD + a new size-dependent SDCTh dataset + 2,702 new pairs. **Headline STRESS scores (CIE 217:2016 metric, lower is better)**: CAM16-UCS-PC 0.493, **OKLab 0.656** — OKLab is ~30% worse than the current best. The authors' explicit caveat: "root causes of these discrepancies remain unclear." Wang/Li/Melgosa/Xiao (Feb 2025, [*Lighting Res. & Tech.*](https://journals.sagepub.com/doi/abs/10.1177/14771535251318357)) found similar ordering. **OKLab's "perceptually uniform" claim was a fitting exercise (Ottosson optimized against existing equal-hue / equal-chroma datasets), not independent validation.** It now has independent measurement, and CAM16-UCS-PC wins on standard color-difference benchmarks.

**Levien's actual OKLab critique** ([raphlinus 2021](https://raphlinus.github.io/color/2021/01/18/oklab-critique.html)) is mostly *complimentary* — pass 2 misread it. His sole substantive OKLab criticism is **near-black contrast compression**: "I personally would like to see a transfer function with a little more contrast in the near-black region (closer to CIELAB)." A pure cube root has dL/dY → ∞ as Y → 0, which compresses the entire near-black band into a narrow L range. **For Aski this matters concretely**: the brightness-driven shape selection in `logPolar` and `dotMatrix` paths uses OKLab L, and dark cells (where shape-density glyphs `.`, `,`, `:`, `+` differentiate) are exactly the regime Levien flags as compressed. Whether this visibly degrades Aski's shadow-region glyph picks is unmeasured.

**Other OKLab failure modes**:

- **Weber's-law violation above ~200 cd/m²** — OKLab is SDR-only by design. If Aski ever targets HDR matching, it's inadequate.
- **Lightness 0/100% browser discontinuity**: Chrome 120+ diverges from Firefox/Safari at exact endpoints in CSS gradients ([csswg-drafts #10109](https://github.com/w3c/csswg-drafts/issues/10109)).
- **The 1/3 power was rounded from an optimal 0.323** to keep the sRGB blue corner convex — documented compromise ([Lilley W3C 2021](https://www.w3.org/Graphics/Color/Workshop/slides/lilley/lilley.html)).

OKLab specifically *fixed* the blue-purple hue shift around 270–330° that plagued CIELAB (Lilley reports L RMS 0.20 vs Lab's 1.70). **Yellow problems live in Lab/LCh and CSS-GMA's chroma-reduction binary search, not in OKLab itself**.

**The notable holdout is Google's Material You, which deliberately rejected OKLCh in favor of HCT** ([ColorAide HCT docs](https://facelessuser.github.io/coloraide/colors/hct/)). HCT splices CAM16's hue+chroma onto CIE L*'s tone because L* gives more uniform contrast steps for tonal palettes; OKLCh has "sharper transitions at both ends of the spectrum" that hurt accessibility-driven contrast-ratio work. HCT re-inherits Lab's blue-purple shift in H/C — a regression OKLCh had fixed. Takeaway: **OKLab wins for gradients/interpolation; HCT is preferred where tonal-step uniformity matters; CAM16-UCS is the psychophysics winner; HyAB is preferred for quantization** (more on each below).

**Distance-metric alternatives.** **CIELAB + ΔE2000** is fine for SDR sRGB design but [BT.2124-0 (2019)](https://www.itu.int/dms_pubrec/itu-r/rec/bt/R-REC-BT.2124-0-201901-I!!PDF-E.pdf) shows ΔE2000 underpredicts blue-primary error and is unverified above 100 cd/m²; **ICtCp + ΔITP** is the recommended HDR/WCG metric. **JzAzBz** targets HDR but a [2025 *Color Research & Application* study](https://onlinelibrary.wiley.com/doi/abs/10.1002/col.22972) found it the weakest of modern UCSes without parametric tuning. **HyAB** (hue-preserving L1 in CIELAB/OKLAB) beats Euclidean OKLab where you need to control L-vs-C error trade-off independently — exactly the regime for ASCII palette matching ([HN discussion, July 2025](https://news.ycombinator.com/item?id=44514946)).

**ZCAM (Safdar et al. 2021) is not the successor.** [`colour-science/colour`](https://github.com/colour-science/colour) Python is the only production-grade implementation; RawTherapee tried integrating ZCAM in 2021 and reverted because results were "disappointing." No major Rust/Swift/C++ port exists. ZCAM's HDR advantage (built on PQ transfer; bounded lightness for 0–10,000 cd/m²) is real but Aski-irrelevant for SDR. For SDR work, [Lilley's W3C analysis](https://www.w3.org/Graphics/Color/Workshop/slides/talk/lilley) found OKLab beats Jzazbz on most uniformity metrics except hue linearity.

### 2. Gamut mapping

**Pass-2 said Aski's 16-iter binary search diverged from "canonical Halley." That framing was wrong. Correcting.**

The [CSS Color Module Level 4 gamut mapping algorithm](https://www.w3.org/TR/css-color-4/) ("MINDE" / CSS-GMA) is the de facto web standard: binary-search OKLCH chroma reduction with a **ΔEOK floor of 0.02**. The 0.02 is **not a derived OKLab perceptual threshold** — it's CIELAB's JND of ~2.3 divided by 100 because OKLab's L runs 0–1 instead of 0–100 ([svgeesus notes](https://github.com/svgeesus/svgeesus.github.io/blob/master/Color/OKLab-notes.md)). Treat it as a heuristic.

**Aski's 16-iter binary search is the CSSWG default, not a divergence from Ottosson.** [Color.js docs](https://colorjs.io/docs/gamut-mapping) state: "The default method is `css`, which uses the binary search algorithm from CSS Color Module Level 4." Ottosson's adaptive-L₀ Halley method is one of nine options, not the default. The community settled on binary search **precisely because Halley has a singularity** at OKLCh hue ≈ 264°–266° — the sRGB blue primary corner where the gamut surface has a sharp ridge and dS/dh → ∞. From Ottosson's [gamut-clipping post](https://bottosson.github.io/posts/gamutclipping/) source comment: "this gives an error less than 10e-6, *except for some blue hues where the dS/dh is close to infinite*... otherwise do two/three steps." Ottosson **proposes no fallback algorithm** — only "do more Halley steps." Binary search is the community's answer.

So Aski's binary search is correctly aligned with CSSWG practice. **The real implementation finding is overprecision**, not underprecision: 16 iterations gives 1.5×10⁻⁵ t-precision, well beyond CSS Color 4 spec tolerance (ε_OK = 0.02 typically converges in 10–12 iterations). Trimming to 12 iterations would match spec and save ~25% of gamut-mapping CPU with no visible quality loss for 8-bit output.

**The `α=0.05` adaptive-L₀ choice is empirical, not derived.** Ottosson's exact wording: "I think a good default choice would be adaptive L₀ with α=0.05" — visual recommendation, not psychophysical experiment.

**CSS-GMA is genuinely broken for perceptual lightness in some regimes.** [csswg-drafts #9449](https://github.com/w3c/csswg-drafts/issues/9449) documents that channel-clipping fallback after binary-search chroma reduction breaks the fundamental promise: at L=0.25, results come out over-saturated and *too light*; at L=0.85, over-saturated and *too dark*. **LCH chroma reduction via binary search fails catastrophically for yellow** specifically — worse than naive clipping. [csswg-drafts #10579](https://github.com/w3c/csswg-drafts/issues/10579) (open, "Needs Edits" as of May 2026) is evaluating replacements; the leading candidates are projection-along-constant-L (what Aski does) and Rec.2020 YUV-along-constant-Y. **Aski's adaptive-L₀ projection is *ahead* of the CSS spec in the broken-yellow regime**, not behind it.

**No published 2024–2026 head-to-head benchmark** of CSS-GMA vs Ottosson L₀-adaptive vs ICC perceptual intent on a CIE-156-style test set exists. Ottosson himself says "the results here though are not enough to determine how it compares with other algorithms." Aski's "validate against MINDE" follow-up is genuinely unaddressed by the field.

**Negative-LMS handling.** Aski uses `sign(x) * pow(|x|, 1/3)` for real-valued cube root on out-of-gamut blues/magentas — community convention (Color.js, ColorAide), not blessed by Ottosson. [csswg-drafts #9477](https://github.com/w3c/csswg-drafts/issues/9477) shows that even modest colors like `lab(0.01% 35 1)` produce negative LMS, and the thread debates clamp-to-zero vs sign-preserving cube root with no settled answer.

**A code-level tightening that's unambiguous: switch `pow(|x|, 1/3)` → `cbrtf(x)`.** `1.0f / 3.0f` is unrepresentable in binary floating-point — `0.33333334...`, an ~1e-8 relative error in the *exponent itself*. Apple's libsystem_m `cbrtf` reports ~0.55 ULP accuracy; `powf(x, 1/3)` is typically 2–4 ULP. `cbrtf` is mathematically defined for negative arguments and handles sign natively — no separate `sign(x) * ... fabsf(x)` machinery needed. Aski does six cube roots per round-trip (3 forward, 3 inverse), so error compounds.

**ICC perceptual intent** is a different beast: it bakes a smooth full-gamut compression into a profile via [v4 PRMG](https://www.color.org/Design_and_use_of_v4_PI.pdf), preserving overall image relationships rather than the chroma of any single color. Apple ColorSync drives all macOS/iOS rendering through ICC profiles, so any Aski output goes through ColorSync regardless of internal mapping.

### 3. Palette construction / quantization

The classics still rule but the perceptual-space variants are winning. The 2026 retrospective by Celebi and Pérez-Delgado in *JOSA A* ([Median cut color quantization algorithm: retrospective](https://opg.optica.org/josaa/abstract.cfm?uri=josaa-43-2-403)) confirms median cut (Heckbert 1979/82), Wu's 1991 PCA-style splitter, and octree are still the splitting baselines, while k-means and NeuQuant (Kohonen 1994) anchor the clustering camp. Clustering in OKLAB / OKLCH is now standard. [Okolors](https://github.com/Ivordir/Okolors) does Wu-then-k-means-in-OKLAB; the [HN HyAB k-means discussion](https://news.ycombinator.com/item?id=44514946) (July 2025) shows the frontier moved further to **HyAB** distance for better hue separation under tight palettes.

Production tools: Google's [material-color-utilities](https://github.com/material-foundation/material-color-utilities) ships the **Celebi composite** — Wu seed + WSMeans refinement in CAM16/HCT — across TS/Java/Kotlin/Swift/Dart/C++. ImageMagick's `-quantize OKLAB` and Pillow's `MAXCOVERAGE`/`FASTOCTREE` remain the lingua franca. Neural quantization in 2026 is still research toy.

**For very small palettes (N ≤ 16) the algorithm choice matters a lot.** [Bouman/Orchard SP1](https://engineering.purdue.edu/~bouman/publications/pdf/sp1.pdf) and the SPIE 1992 small-palette paper note that statistical methods (k-means, median-cut) collapse below ~32 colors because gamut reduction destroys the variance signal. **Spatial color quantization** (Puzicha/Held 1998) outperforms k-means dramatically at N=4/8/16 because it jointly optimizes the palette and the dither pattern; [`okaneco/rscolorq`](https://github.com/okaneco/rscolorq) is the maintained Rust implementation. For Aski's ANSI16 regime, this is the actual frontier — not Wu+k-means.

**Two more small-palette pitfalls relevant to Aski's "glyph carries L; palette carries C" architecture:**

- **OKLab-median-cut has an L-bias problem**: ([pkh.me/p/39](http://blog.pkh.me/p/39-improving-color-quantization-heuristics.html)) reports heavy desaturation in small palettes because the lightness axis dominates variance. HyAB or chroma-weighted variants directly address this.
- **Floyd–Steinberg in OKLAB vs sRGB** — error diffusion in OKLAB is now table stakes ([demofox, May 2025](https://blog.demofox.org/2025/05/27/thresholding-modern-blue-noise-textures/); [libjxl issue #3926](https://github.com/libjxl/libjxl/issues/3926)). Blue-noise dithering is the preferred ordered alternative under tight palettes.

**No peer-reviewed CVD evaluation of standard ANSI16 / restricted character palettes** has been published as of May 2026 — only craft-knowledge artifacts ([ametameric](https://pippin.gimp.org/ametameric/), [Lunaria](https://lunaria.design/)). This is a real field gap that Aski's CVD audit (see Aski-runnable experiments) could partially fill.

### 4. Output color spaces — sRGB / P3 / Rec.2020 / HDR on Apple platforms

**Display P3** is the default on modern Apple hardware. sRGB still wins for *interop with non-Apple destinations*. For in-app rendering on Apple platforms, P3 is the right floor.

**Rec.2020 / Rec.2100** remain niche outside video in 2026. CES 2026 highlighted SN Display's perovskite film hitting [95% Rec.2020 coverage](https://www.provideocoalition.com/ces-2026-sn-display-technology-delivers-over-95-rec-2020-coverage/), but consumer displays haven't moved meaningfully. Browsers ship `rec2020` in CSS (Safari 15.1+, Chrome 111+); SpriteKit/UIKit don't natively render Rec.2020 stills.

**Apple EDR (Extended Dynamic Range)** is the relevant abstraction. From [WWDC22 session 10113](https://developer.apple.com/videos/play/wwdc2022/10113/) through [WWDC24 session 10177](https://developer.apple.com/videos/play/wwdc2024/10177/), it expanded across platforms. **The Reference White Tone Mapping Operator's exact curve is undocumented** — Apple has never published the formula; the WWDC24 session describes it qualitatively. Anyone repeating numbers is reverse-engineering, not reading a spec.

**Gain-map standard convergence.** [ISO 21496-1 was published July 2025](https://www.iso.org/standard/86775.html); Apple and Google [jointly adopted it](https://www.androidauthority.com/google-apple-hdr-photo-standard-3495035/). Apple brands its implementation "Adaptive HDR." Per [Greg Benz](https://gregbenzphotography.com/hdr-photos/apple-macos-ios-hdr-iso-gain-map-21496-1/) the Apple/Android encodings are "conceptually similar but significantly more different." By 2026 it's effectively one standard with two interop dialects.

**EDR headroom collapses outdoors.** iPhone 15 Pro hits ~8× SDR-white headroom at low brightness and collapses to ~2× at max ambient ([rioogino, 2024](https://rioogino.com/posts/2024/edr_2_metal/)). Any "HDR ASCII" mode would stop looking HDR exactly when the user goes outside.

**The macOS "HDR videos" toggle in System Settings** controls *external* HDR10 displays only ([Apple Support 102205](https://support.apple.com/en-us/102205)). Apple Silicon internal displays use EDR with no toggle — SDR + EDR coexist without a mode switch.

**visionOS Vision Pro.** The widely-cited 5,000 nits is *raw panel* before optics; pancake transmission is ~11%, putting actual ocular brightness around 550 nits ([KGOnTech 2024](https://kguttag.com/2024/04/30/apple-vision-pro-discussion-video-by-karl-guttag-and-jason-mcdowall/)). A November 2025 source pegs delivered peak at ~2,200 nits. The Oct 2025 refresh was **M5**, not M2. visionOS 26 (Sept 2025) inherits the iOS EDR stack.

**The WWDC25 HDR-colors pivot.** iOS 26 / macOS 26 / visionOS 26 promote HDR from "images and video only" to **HDR for arbitrary UI colors**: `UIColor(red:green:blue:alpha:linearExposure:)` and SwiftUI `Color(...linearExposure:)` ([WWDC25 session 243](https://developer.apple.com/videos/play/wwdc2025/243/); [insidegui/CustomHDR](https://github.com/insidegui/CustomHDR)). Trait `UITraitHDRHeadroomUsage` lets custom-drawn HDR content cooperate with system fallback. **For Aski**: today an ASCII grid drawn in `extendedSRGB` clips at 1.0; iOS 26 lets bright glyph FG colors sit at `linearExposure: 1.5–2.0` and bloom on EDR displays. iOS 26 also captures **HDR screenshots in HEIF**, preserving EDR highlights ([MacRumors May 2025](https://www.macrumors.com/how-to/ios-vibrant-screenshots-iphone-hdr/)).

**SDR diffuse white anchor.** Apple's compositor uses 100 nits; BT.2408 broadcast convention is 203 nits.

### 5. Alpha compositing in perceptual / linear space

The classic demo: composite 50%-alpha pure red over pure green. Blended in display-encoded sRGB you get a muddy ~`#806000` brown; blended in linear-light you get ~`#bfa800`, the perceptually correct yellow. The energy loss in sRGB blending comes from interpolating gamma-compressed values. [Bartosz Ciechanowski's *Alpha Compositing*](https://ciechanow.ski/alpha-compositing/) and [Søren Sandmann's *Premultiplied alpha and gamma*](https://ssp.impulsetrain.com/gamma-premult.html) are the canonical interactive demos.

**The "physically wrong" claim is bimodal — and the prior pass had unsourced numbers. Correcting.**

The visible delta concentrates in extreme cases. Computed worst case from γ ≈ 2.2: `(255,0,0) ⊕ (0,255,0)` at α=0.5 produces sRGB-blended `(128,128,0)` vs linear-blended `(186,186,0)`, ΔE2000 ≈ **28** — large and visible. **The pass-2 "5% perceptual error on photographic content" figure had no primary source** (verified — no canonical citation exists). The honest framing: worst-case primary-pair errors are real and computable; mean errors on natural photographic content are unmeasured for this specific axis. Anyone repeating "5% on photos" is propagating a number with no published basis.

Linear is "physically correct"; gamma is "what designers calibrated to decades ago." **Adobe Photoshop ships "Blend RGB Colors Using Gamma 1.0" off by default** — switching mid-stream breaks every existing PSD. The "fix" is a usability call, not just correctness.

**Premultiplied-in-gamma is compounding error, not half-correct.** Premultiplication itself is a linear operation; doing it in gamma space means `0.5 × white` is encoded as ~0.5 sRGB ≈ ~0.21 linear, then composited as if it were linear-0.5 — values land ~0.75 instead of 0.5. Porter-Duff was *defined* assuming linear ([performous bug #32](https://github.com/performous/performous/issues/32)).

**Core Graphics specifics.** A `CGContext` blends in whatever color space you hand it at construction. If that's `CGColorSpace.sRGB` or `.displayP3`, blending happens in display-encoded space. To get gamma-correct blending, construct the context with [`kCGColorSpaceExtendedLinearSRGB`](https://developer.apple.com/documentation/coregraphics/kcgcolorspaceextendedlinearsrgb) or `kCGColorSpaceExtendedLinearDisplayP3` and use `RGBA16Float` (8-bit linear has well-known shadow banding — ~3 stops of usable shadow detail lost vs 8-bit sRGB-encoded). Core Image defaults to extended-linear-sRGB internally and is gamma-correct out of the box. The [JuniperPhoton color-management series](https://juniperphoton.substack.com/p/color-management-across-apple-frameworks-cf7) is the best Apple-side walkthrough.

**SwiftUI / `AttributedString`.** SwiftUI composites in the layer's working space — extended-linear-Display-P3 on capable hardware since iOS 16 / macOS 13, sRGB otherwise. `.opacity()` modifiers apply alpha *after* color-space conversion, so correct linear blending requires the destination layer to be linear-backed.

**CoreText anti-aliases in the CGContext's color space, not forced to linear.** For sRGB-tagged contexts (Aski's `ImageRenderer`) this is gamma-space blending — visually warmer/lighter than linear-correct compositing at glyph edges. Per-cell *solid* colors don't expose this much; high-contrast FG-on-BG glyph anti-aliasing is where the skew shows.

**macOS font rendering history.** Subpixel AA disabled by default in macOS 10.14 Mojave (June 2018), code path *removed* in 10.15 Catalina (Oct 2019). "Font dilation" survived; the System Preferences toggle was removed in Big Sur (Nov 2020). Affects *weight perception only* — no color correctness implications. iOS never had dilation.

### 6. Display surface differences

**SwiftUI Text.** Since iOS 16 / macOS 13, `Text` is composited in the hosting layer's working color space, auto-promoted to extended-linear-Display-P3 on P3-capable hardware. EDR opt-in is per-`UIWindow` / `NSWindow` via `wantsExtendedDynamicRangeContent`.

**AppKit / UIKit `NSAttributedString`.** Same composition path through Core Animation. For wide-gamut fidelity set `CALayer.contentsFormat = .RGBA16Float` (or `.RGBA10XR` for cheaper P3) and tag the window for EDR. **Still recommended in 2026 — no 2025 deprecation.**

**`CGImage` to disk.** ImageIO embeds the `CGColorSpace` as an ICC profile by default for PNG/JPEG/HEIF. Untagged outputs cause downstream apps to assume sRGB ([TN2313](https://developer.apple.com/library/archive/technotes/tn2313/_index.html)), silently desaturating P3 content.

**Accessibility post-render transforms — invisible to the app.** True Tone, Night Shift, Reduce White Point, and Color Filters / Color Accommodations are all post-render, system-compositor-stage adjustments. **Reduce White Point and Color Filters do not affect screenshots, screen recordings, or screen mirroring** ([Apple Support](https://support.apple.com/en-ie/guide/iphone/iph3e2e1fb0/ios), May 2025). There is no public API to query whether True Tone or Night Shift is currently active. The only Aski-relevant hook is `UIAccessibility.shouldDifferentiateWithoutColor`. **Implication for any "color fidelity" claim**: it's true *up to* the framebuffer, not what the user sees.

**Reference Modes have no public detection API** on Pro Display XDR / Liquid Retina XDR. Apps query `NSScreen.colorSpace`, `referenceHeadroom`, `potentialHeadroom`, `headroom` — but the named mode is hidden ([Apple Tech Talk 10023](https://developer.apple.com/videos/play/tech-talks/10023/)).

**`NSScreenColorSpaceDidChangeNotification`** fires when display calibration changes mid-session.

**`CGColor` from dynamic `NSColor`/`UIColor` is frozen at snapshot time** ([Indie Stack 2018](https://indiestack.com/2018/10/supporting-dark-mode-adapting-colors/)). Common Dark Mode bug for layer-backed cell renderers — not currently relevant to Aski (cells use `SIMD3<Float>`).

**visionOS.** Display is wide-P3 with EDR. [visionOS 26](https://www.apple.com/newsroom/2025/06/visionos-26-introduces-powerful-new-spatial-experiences-for-apple-vision-pro/) recommends `.RGBA16Float` for text overlays against passthrough — sRGB-encoded blending shows as muddy fringes on bright real scenes.

**Color font formats.** Apple uses **sbix** (PNG bitmap strikes), not COLR/CPAL or CBDT/CBLC. **sbix glyphs ignore `foregroundColor` by design** — they're pre-rasterized PNG bitmaps drawn via `CGContextDrawImage`, not the path-fill route, so `kCTForegroundColorAttributeName` has no entry point. **COLR v1 has no Apple support as of early 2026** ([WebKit standards-positions #415](https://github.com/WebKit/standards-positions/issues/415)) and is structurally incompatible with sbix's painterly gradient model. iOS 26 / macOS 26 added no new color-glyph public API. **Implication**: rendering colored ASCII via system emoji is impossible to tint; Aski's bundled monochrome Courier Prime is the right architecture.

**Terminal (context only).** 24-bit truecolor escape codes (`\e[38;2;R;G;Bm`) are unmanaged sRGB by convention. iTerm2's "minimum contrast" mutates colors; Terminal.app applies brightness curves; Ghostty/WezTerm pass through raw. No ICC pipeline.

## What we picked, and why

For each topic: **verdict**, then a sentence on the trade-off if it's not a clean validation.

### 1. Color space + distance metric — **validate, with caveats; OKLab's psychophysics standing has changed**

OKLAB + Euclidean is where the *web ecosystem* converged for gradients and interpolation. Aski's `ColorConversion.swift` uses Ottosson's canonical fused matrices and the real-valued cube root. **But independent psychophysics now ranks OKLab mid-pack** (CAM16-UCS-PC scores ~30% better on STRESS per [Krasilnikov 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC11676281/)). Switching color spaces would be a major architectural change — keep OKLab today, but the "OKLab is perceptually uniform" framing in code comments / docs should be softened to "OKLab is the web-platform default for perceptual interpolation."

**Forward-survey items**: (a) **HyAB** is the credible upgrade for palette matching; Aski's "glyph carries L; palette carries C" architecture makes it a natural fit. (b) **CAM16-UCS** wins the psychophysics benchmark — investigate if matching errors actually surface in Aski output. (c) **ΔITP (ICtCp)** is the upgrade if Aski targets HDR. (d) Levien's near-black contrast critique applies to Aski's brightness-driven shape selection in shadow regions — runnable experiment in the next section.

### 2. Gamut mapping — **validate algorithm choice (correcting pass 2); flag overprecision**

`GamutMapping.swift` implements Ottosson adaptive L₀ projection with α=0.05 + 16-iter binary search. **Pass-2 framed the binary search as a divergence from canonical Halley. That was wrong.** [Color.js's default *is* the CSS Color 4 binary search](https://colorjs.io/docs/gamut-mapping); Halley is one of nine options. The CSSWG settled on binary search precisely because Halley has a singularity at OKLCh hue ≈ 264°–266° (sRGB blue primary corner) where dS/dh → ∞. **Aski tracks the CSSWG default exactly.** Ottosson never proposed a fallback algorithm — only "do two/three Halley steps" — so binary search is the community's answer.

**The real implementation finding is overprecision**: 16 iterations gives ~1.5×10⁻⁵ t-precision, well past CSS Color 4 spec tolerance (ε_OK = 0.02 in 10–12 iters). Trimming to 12 iterations would match spec and save ~25% gamut-mapping CPU with no visible quality loss. Tracked as out-of-scope: requires benchmarking before any code change.

**Two corrections to pass-1 framing carry into pass 3**:

- **α=0.05 is empirical, not principled** — document as Ottosson's visual recommendation, not a derived constant.
- **CSS Color 4 MINDE cross-validation is genuinely unaddressed** by published 2024–2026 work; Ottosson himself says "the results here though are not enough to determine how it compares with other algorithms." Aski isn't behind a benchmark — there isn't one.

CSS Color 4 MINDE comparison + iteration-count tightening + `cbrtf` migration are the three runnable experiments for this topic.

### 3. Palette construction — **deferred (not on Aski today); revised future-default**

Aski's `ASCIIPalette` exposes a static `colorsOKLAB` array. **If/when image-derived palettes are added**:

- **For low N (≤16, including ANSI16)**: spatial color quantization (Puzicha/Held; [`okaneco/rscolorq`](https://github.com/okaneco/rscolorq)) jointly optimizes palette and dither and beats flat k-means.
- **For higher N**: Wu seed → k-means refinement with HyAB distance, mirroring Celebi composite.
- **Skip neural quantization**.
- Floyd–Steinberg or blue-noise dithering in OKLAB if dither is wanted.

The **CVD audit** is independently runnable today on the existing static palettes (ANSI16, monochrome) and would partially fill a real field gap — see Aski-runnable experiments.

### 4. Output color spaces — **validate today; HDR is no longer "deferred until use case" after iOS 26**

`sRGB | displayP3` is the right SDR ceiling. The pass-1 verdict ("defer HDR until concrete use case") needs revision: **WWDC25 session 243 ships a concrete API path** — `UIColor(...linearExposure:)` and SwiftUI `Color(...linearExposure:)` on iOS 26 / macOS 26 / visionOS 26, plus `UITraitHDRHeadroomUsage`. iOS 26 HDR screenshots in HEIF preserve the round-trip.

Remaining objections:
- EDR headroom collapses outdoors (~8× → ~2× on iPhone 15 Pro at max ambient).
- Apple's RWTM curve is undocumented; behavior at peak headroom is empirical.
- Aski's deployment targets (iOS 16+, macOS 14+, visionOS 1+) include pre-26 OSes — would need a `#available` gate.

If anything is added, it should be `.extendedLinearDisplayP3` (EDR) with `linearExposure` on per-cell colors, not a `.rec2020` or `.hdr` discrete case.

### 5. Alpha compositing — **divergence is real but its magnitude on Aski-typical inputs is unmeasured**

`ImageRenderer.swift` constructs its `CGContext` with `space: cgColorSpace` (sRGB or displayP3, *not* extended-linear) and `bitsPerComponent: 8`. Cell-over-background alpha compositing happens in display-encoded space at 8-bit precision. The frontier prescription is `kCGColorSpaceExtendedLinearSRGB` / `...DisplayP3` + `RGBA16Float`. **Premultiplying in gamma-encoded space is *compounding* error** — Porter-Duff was defined assuming linear.

**Honest reframing of pass 2's numerical claims**: the worst-case primary-pair ΔE2000 ≈ 28 (computed from γ ≈ 2.2, e.g. red⊕green at α=0.5) is real and verifiable. The **"5% perceptual error on photographic content" figure has no primary source** and shouldn't be cited. The actual mean error on Aski-typical inputs is unmeasured.

With `alpha = 1` cells (the common path), the divergence is irrelevant. The **right next step is the runnable A/B experiment** (see below) — pick saturated FG/BG pairs and a partial alpha, render through both pipelines, decide if the difference clears the "worth fixing" bar.

### 6. Display surface differences — **validate; new caveats from passes 2 and 3**

`AttributedStringRenderer` uses platform-tagged colors correctly. `ImageRenderer` tags its `CGContext` with the right `CGColorSpace`.

**Caveats from passes 2–3:**

- **Color fidelity claims must acknowledge the OS-level post-render layer.** True Tone / Night Shift / Reduce White Point / Color Filters all run after the framebuffer and are invisible to Aski. Reduce White Point and Color Filters even strip out of screenshots/recordings. Any "Aski produces accurate color" claim is true *up to* the framebuffer.
- **`UIAccessibility.shouldDifferentiateWithoutColor`**: when true, palette-only output isn't sufficient.
- **`CGColor` from dynamic `NSColor`/`UIColor` is frozen at snapshot.** Not currently a problem; flag for future "system-color theme" work.
- **sbix emoji bypass `foregroundColor` by design.** Apple's bundled emoji are PNG bitmaps drawn via `CGContextDrawImage`, no fill path. Hard limit for any future "render-to-emoji" mode. Aski's bundled monochrome Courier Prime is the right architecture for tintable cells.

**Watch item**: if Aski ever ships a visionOS-specific renderer or an EDR-aware path, `.RGBA16Float` becomes mandatory.

## Cross-cutting assumptions and load-bearing dependencies

The six topics share a small set of assumptions that, if wrong, cascade. Naming them so they can be tested or relaxed.

1. **OKLab is perceptually uniform enough for Aski's matching task.** Newly contested — CAM16-UCS-PC scores ~30% better on STRESS per Krasilnikov 2024. The matching task here is *which character is closest to this color, given the brightness gradient is already encoded by glyph shape* — that's narrower than industrial color difference, so OKLab's relative weakness on industrial datasets may not transfer. Untested for the specific ASCII-matching regime.

2. **The chromatic CSF cuts off where ASCII glyphs operate, so chromatic precision matters less than luminance precision.** [Mullen 1985](https://pmc.ncbi.nlm.nih.gov/articles/PMC1193381/) and the more recent [castleCSF (Ashraf et al. J. Vision 2024)](https://achapiro.github.io/Ash24/Ashraf2024_castleCSF.pdf): chromatic CSF cuts off near 11–12 cyc/deg, far below luminance acuity. ASCII grids operate at high spatial frequency (a 9-px char at 24" viewing ≈ 12 arcmin ≈ 5 cyc/deg). **Synthesis insight**: this means **Aski's "glyph carries L; palette carries C" architecture is structurally aligned with chromatic CSF cutoff** — the eye has full bandwidth for the luminance signal Aski encodes via shape density and reduced bandwidth for the chroma signal Aski encodes via FG color. That's a positive design rationale that reframes several pass-2 concerns: large color errors at the per-cell scale may be perceptually masked, while shape-density errors (luminance) are not.

3. **The community-convention negative-LMS handling is correct.** Aski's `sign(x) * pow(|x|, 1/3)` is a community pattern (Color.js, ColorAide) — Ottosson never blessed it; CSSWG #9477 is open. The Aski-side improvement is `cbrtf(x)`, which natively handles negatives and is ~0.55 ULP vs `pow(|x|, 1/3)`'s 2–4 ULP.

4. **Float32 is precise enough for the OKLab pipeline.** True for sRGB except very dark regions (Y < 0.001) where the cube root gradient → ∞ amplifies LSB error. Aski's brightness-driven shape selection in dark cells could be affected. Testable.

5. **The 16-iter binary search is the right precision.** Pass-3 finding: it tracks the CSSWG default *algorithm* but exceeds CSSWG default *tolerance* by ~10×. Trimming to 12 iters matches spec and saves CPU.

6. **The compositing in 8-bit display-encoded sRGB/P3 is acceptable for typical Aski output.** Untested. Worst-case ΔE2000 ≈ 28 for primary-pair midpoints; mean ΔE on real Aski outputs is unmeasured.

7. **Aski's deployment-target floor (iOS 16+, macOS 14+, visionOS 1+) auto-promotes to extended-linear-Display-P3 on capable layers.** Trusted per pass 2. Verifiable with a one-time test.

8. **OS-level transforms (True Tone, Night Shift, Reduce White Point, Color Filters) are downstream and shouldn't be modeled.** Correct. Aski's claim is framebuffer-correctness, not end-user-perception correctness — the docs should make this distinction.

9. **The ANSI16 sRGB literals in `BuiltInPalette.ansi16` (e.g. `(0.50, 0.00, 0.00)`) are sRGB-encoded by xterm convention.** Aski applies `sRGBDecode` then `linearSRGBToOKLAB`. This is the correct interpretation if the source is xterm-style; some terminals diverge. Untested for round-trip fidelity.

10. **OKLab's near-black contrast compression doesn't degrade Aski's shape selection in shadow regions.** Levien's only substantive critique. Untested for Aski's specific dark-cell glyph-density gradient.

## Conjectures and predictions

The literature review and Aski-side audit converge on a few claims that aren't in the surveyed sources but follow from synthesis. Each is framed at the epistemic level it deserves: **synthesis** (rearranging known findings), **extension** (claim within reach of existing literature), **novel** (not in the surveyed literature, as best we found). These are conjectures with explicit falsification protocols, not assertions. They're a different epistemic posture from the rest of this document — the literature review reports what others found; this section reports what we'd bet.

### 1. Chromatic-luminance bandwidth split for character-grid rendering *(synthesis)*

Mullen 1985 plus castleCSF: chromatic CSF cuts off at ~11–12 cyc/deg; luminance CSF holds to ~50–60. Aski grids operate at ~5 cyc/deg at typical viewing geometry. Therefore Aski's *luminance channel* (which glyph) is at full perceptual bandwidth while its *chromatic channel* (FG color) is bandwidth-limited by the visual system.

**Prediction**: there exists a palette size **N\*** beyond which adding chroma resolution doesn't visibly improve output. At ~12 arcmin per cell, N\* is plausibly 12–24 colors before perceptual saturation. The fact that ANSI16 looks "fine" for character art is not coincidence — it's at or above N\* for the regime.

**Falsification**: 2AFC observer test at 16/32/64/256 palette sizes on a fixed image at controlled viewing distance. If discrimination accuracy stays at chance above N=16, conjecture holds. (Related to runnable experiment #6 on castleCSF prediction.)

### 2. Joint glyph-occupancy color matching is the correct distance metric *(novel)*

Aski picks glyph (from L) and FG color (from full source pixel) separately. But the *perceived* cell color is `coverage(glyph) × FG + (1 − coverage) × BG` — the eye does sub-cell spatial integration. A `.` covers ~5% of the cell; `+` ~30%; `█` ~100%. So when Aski picks a saturated red FG against a black BG and a low-coverage glyph, the perceived cell is mostly *black*, not red.

The correct matching distance is:

  ΔE_OK( source, coverage(glyph) × FG + (1 − coverage) × BG )

This makes glyph and FG selection *jointly* optimal rather than separable. Predicts Aski **systematically over-saturates dark cells** (low coverage; FG leaks through less than the FG-vs-source match expects) and **under-saturates bright cells** (high coverage; BG barely contributes).

**Falsification**: render a saturated chromatic gradient through current Aski and a joint-optimized variant; measure ΔE between rendered output and source. Predicted gain: visible-but-modest, asymmetric (larger in shadows than highlights). If gain falls below noise, the spatial-integration assumption fails — possibly because the eye doesn't integrate coverage cleanly at typical viewing distances.

This is the gap named in *Deep unknowns* ("no psychophysics of color in glyph-bounded patches") turned into a concrete algorithmic claim. The claim doesn't require new psychophysics — it follows from `coverage` being non-uniform across the glyph set, which is empirically true for any density ramp.

### 3. Near-black shape collapse in OKLab-driven shape selection *(extension)*

Levien's OKLab critique: cube root compresses near-black contrast. Aski uses OKLab L for shape selection. Therefore in shadow regions, the shape-density ramp `.` → `:` → `+` → `█` is being mapped onto a narrowed L range, and adjacent dark cells with perceptually distinct source colors should collapse onto identical glyph picks more often than they do in mid/light tones.

**Prediction**: glyph-pick entropy in low-L cells is measurably lower than in mid-L cells for current Aski, with the gap closing if shape selection uses CIELAB L* (more linear near zero) instead of OKLab L. Color matching should stay in OKLab — only the *selection* axis changes.

**Falsification**: render a dark-dominated test image; measure Shannon entropy of glyph picks within each L-band (low/mid/high). Predicted gap > 0.5 bits between low and mid bands in current Aski; closes after L-axis substitution. If no gap exists, OKLab's near-black compression doesn't matter at the resolutions Aski operates.

### 4. Glyph-set shape diversity has a quantifiable perceptual ceiling *(novel, more speculative)*

Aski's character sets have different shape-vector distributions in 60-D log-polar space. A set with high mean pairwise distance carries more luminance information per cell than a clustered set. There should exist a "shape diversity" metric — e.g., the determinant of the shape-vector covariance matrix, expected nearest-neighbor distance, or covariance-matrix rank — that **rank-orders character sets by perceptual output quality at any fixed palette size**.

**Prediction**: above some diversity threshold, additional set members provide diminishing perceptual return (dual to N\* on the chroma side). The character set is a hyperparameter, not just a stylistic choice — and there's an information-theoretic floor below which a set is "too small" to render perceptually faithfully regardless of palette.

**Falsification**: compute diversity metrics for each `BuiltInCharacterSet`; collect observer preference rankings on a fixed image rendered through each. Spearman correlation > 0.7 supports; near zero falsifies. The mechanism could fail if perceptual quality is dominated by *which* shapes are present (semantic recognizability of glyph silhouettes) rather than how spread they are in shape-vector space.

### 5. HyAB beats Euclidean OKLab for Aski's matching task specifically *(extension)*

The HyAB-for-quantization literature is at low N. Aski's matching is nearest-neighbor in palette. Aski's architecture already factors L into the glyph signal — the *literal motivation* HyAB exists for. So HyAB at the matching step gets the upside (controlled L-vs-C error trade-off) without paying the downside HyAB has in arbitrary clustering tasks (asymmetric weighting hurts variance preservation, but Aski isn't doing variance preservation).

**Prediction**: swapping Euclidean OKLab → HyAB at the matching step changes <5% of glyph picks. The changes concentrate at cells where the prior pipeline traded chroma accuracy for L accuracy. Output has slightly higher chroma fidelity; no perceptible loss elsewhere.

**Falsification**: implement the swap; render the ISO 12640 SCID test set; measure (a) glyph-pick agreement rate, (b) per-cell ΔE2000 to source. Predicted (a) > 95% agreement, (b) lower 95th-percentile ΔE in disagreement cells. If (a) is high *and* (b) is unchanged, HyAB doesn't matter. If (a) is < 90%, the architectural alignment is real but other effects dominate.

### The "ASCII regime" thesis (meta)

Conjectures 1–5 share a premise: ASCII art is not pixel art (uniform pixels), not photography (continuous tone), not typography (text-as-text), not halftone print (random-dot dispersion). It's a unique perceptual regime — joint shape-color encoding at the chromatic CSF cutoff, with discrete glyph vocabulary and sub-cell anti-aliased boundaries. Each conjecture follows from taking this regime seriously instead of treating Aski as "low-resolution image rendering" or "color-text typography."

The thesis isn't itself testable; it's the lens that makes 1–5 sensible. If 2 in particular survives falsification, the thesis earns weight: it predicted a specific algorithmic improvement that the existing field-blind framing didn't.

### Epistemic caveats

- **Conjecture 2 is the riskiest and most consequential.** If it holds, Aski's current matching is provably non-optimal — that's a real result. If it fails, it tells us something about the eye's sub-cell spatial integration that the literature doesn't currently address.
- **Conjecture 1 may be obvious to someone in the color-science-meets-display-systems field**; we haven't found it stated for character grids specifically. If it's been published, we missed it.
- **Conjecture 4 is the most speculative.** Diversity metrics in high-dimensional shape-vector spaces are ill-defined (which norm? which metric?), and the connection to perceptual quality may be mediated by recognizability rather than spread.
- All five conjectures depend on Mullen 1985's chromatic CSF generalizing from disk-stimulus laboratory conditions to character-grid stimuli — plausible but unmeasured.
- These are conjectures, not claims. Future passes that find published prior art should fold the relevant conjecture back into the literature review and demote it.

## Aski-runnable experiments

Concrete protocols Aski could run, ordered by cost-to-information ratio. Each names stimuli, measurement, and a pre-registered threshold for action.

### 1. Iteration-count sweep on `GamutMapping.swift` (lowest cost; clearest payoff)

- **Stimuli**: A representative test set of inputs that exercise the gamut-mapping path (out-of-gamut OKLab colors, e.g., the [ISO 12640-4 SCID](https://www.iso.org/standard/45115.html) palette converted through Aski's `linearSRGBToOKLAB` + a synthetic boundary stress set hitting blue corners at hue 264°–266°).
- **Measurement**: For each input, compare 16-iter and 12-iter outputs in linear RGB. Report max and 95th-percentile per-channel divergence.
- **Threshold**: If 95th percentile < 1/256 (one 8-bit code), trim iteration count. Expected outcome: ~25% gamut-mapping CPU saving on the slow path; quality unchanged.

### 2. `cbrtf` migration (lowest cost; strict accuracy improvement)

- **Stimuli**: 1M random OKLab values uniformly sampled across the OKLab unit cube + a stress set near zero (Y < 1e-6) and near gamut boundaries.
- **Measurement**: Compare `sign(x) * pow(|x|, 1/3)` vs `cbrtf(x)` on each input; quantify ULP error against Float64 reference.
- **Threshold**: If `cbrtf` reduces max ULP error by ≥1, switch. Expected outcome: ~1–2 ULP better accuracy per call, six calls per round-trip.

### 3. Float32-vs-Float64 round-trip in dark regions

- **Stimuli**: A grid of dark sRGB triples with Y ∈ [0, 0.05] sampled densely.
- **Measurement**: Round-trip sRGB → linear → OKLab → linear → sRGB encoded; compare Float32 and Float64 paths. Report max and 95th-percentile per-channel error in the dark band.
- **Threshold**: If Float32 max error in the dark band exceeds 1/256, escalate the LMS' step to Float64 or apply `cbrtf(x + 1e-6)`. Expected outcome: identifies whether Levien's near-black contrast concern affects Aski's actual dark-cell glyph picks.

### 4. Alpha compositing A/B with extended-linear path

- **Stimuli**: Render a fixed test image with two saturated FG/BG color pairs (e.g., red on green, blue on yellow), three alpha values (0.25, 0.5, 0.75).
- **Pipelines**: (a) current `ImageRenderer` path (8-bit display-encoded sRGB/P3); (b) experimental path with `kCGColorSpaceExtendedLinearSRGB` + `RGBA16Float`.
- **Measurement**: Per-pixel ΔE2000 between the two outputs after both are encoded back to sRGB.
- **Threshold**: If max ΔE > 5 *and* mean ΔE > 2 over the test image, the gamma-vs-linear divergence clears the "worth fixing" bar. Otherwise it's an academic concern.

### 5. ANSI16 + monochrome CVD audit (fills a real field gap)

- **Stimuli**: Aski's `BuiltInPalette.ansi16` colors, all 16, simulated through Brettel-Viénot-Mollon (dichromacy: protan, deutan, tritan) and Machado et al. 2009 (anomalous trichromacy at severities 0.5 and 1.0).
- **Measurement**: For each CVD type, report (i) confusion pairs (palette colors landing within 2 JND post-simulation), (ii) gradient monotonicity preservation across the lightness ramp.
- **Threshold**: If any color pair confuses for any CVD type at severity 1.0, document it and consider a CVD-aware palette variant. Expected outcome: a published CVD profile for ANSI16 — currently absent from the literature.

### 6. Spatial chromatic CSF prediction (cheap; informs architecture)

- **Stimuli**: A representative Aski output rendered at the deployed cell sizes (e.g., 9 px, 12 px, 16 px wide) at a typical viewing distance.
- **Measurement**: Use [castleCSF](https://achapiro.github.io/Ash24/Ashraf2024_castleCSF.pdf) (open-source) to predict per-cell chromatic visibility threshold. Compare ΔE_OK between the picked palette color and the source pixel against the predicted threshold.
- **Threshold**: If picked-vs-source ΔE_OK falls below the chromatic CSF threshold for >90% of cells, declare the chromatic precision overprovisioned and document that cheaper distance metrics (or fewer palette colors) wouldn't visibly degrade output.

### 7. OKLab vs CAM16-UCS ablation on Aski's matching path

- **Stimuli**: A diverse 100-image test set (mix of photo, illustration, gradient, dark-dominant, saturated-dominant).
- **Pipelines**: Identical converter, swap matching color space (OKLab → CAM16-UCS via `colour-science` reference values).
- **Measurement**: Per-cell character-pick agreement rate; ΔE2000 between picked palette colors when characters disagree.
- **Threshold**: If agreement rate > 99%, OKLab vs CAM16-UCS doesn't matter for Aski's matching task. If < 95%, the Krasilnikov 2024 finding has bite for Aski and CAM16-UCS migration deserves a real evaluation.

## Deep unknowns the field hasn't answered

Distinct from "open questions" (which are settle-able by reading more sources): these are gaps where the literature genuinely doesn't have an answer.

- **No ΔE calibration for ASCII-cell-sized stimuli.** All canonical color-difference formulas were calibrated at 2°–4° patches. Krasilnikov's SDCTh extends to ~72 arcmin (1.2°); a 9 px char at 24" viewing is ~12 arcmin — still ~5× smaller. Whether ΔE2000 / ΔE_OK / ΔE_HyAB orderings hold at this scale is unknown.
- **No psychophysics of color in glyph-bounded patches.** Color shown through letterform shape, where the chroma signal is fragmented by anti-aliased achromatic edges, has not been studied as a perceptual regime.
- **No published CIE-156-compliant GMA benchmark in 2024–2026.** Ottosson adaptive L₀ vs CSS Color 4 MINDE vs ICC perceptual is genuinely unaddressed.
- **No peer-reviewed CVD evaluation of standard ANSI / character-grid palettes.** Craft work exists (ametameric, Lunaria); no academic baseline.
- **The "5% perceptual error on photographic content" claim for sRGB-vs-linear blending has no primary source.** Pass 2 propagated it; pass 3 found it uncited. Mean errors on natural images haven't been measured against a published protocol.
- **OKLab's near-black contrast compression has no Aski-specific impact study.** Levien flagged it conceptually; nobody has measured whether it affects shape-density picks in the regime where ASCII shadow-region glyphs differentiate.
- **No published ZCAM vs OKLab ΔE comparison on standard datasets.** ZCAM's HDR claims are paper-form only; SDR comparisons exist but aren't head-to-head.
- **Apple's Reference White Tone Mapping Operator curve is undocumented.** Behavior at peak EDR headroom is empirical, not specified.
- **`UITraitHDRHeadroomUsage` for ASCII-grid content has no shipping example.** WWDC25 session 243 demonstrates it for image and color, not character grids.

## Standard experimental protocols (reference)

For posterity — what to use if Aski runs any of the experiments above with the goal of producing publishable findings.

- **Color-difference formula evaluation**: STRESS index ([CIE 217:2016](https://www.cie.co.at)) on COMBVD (BFD-P + Witt + Leeds + RIT-DuPont). Supplement with [Krasilnikov SDCTh dataset](https://pmc.ncbi.nlm.nih.gov/articles/PMC11676281/) for small-patch. Secondary: ΔE2000 mean / 95th percentile, fraction of pairs > 2 JND.
- **Uniform color space**: equal-hue (Ebner-Fairchild), equal-chroma (Hung-Berns), Munsell renotation; report RMS + 95th in ΔE2000 (Ottosson's method).
- **Gamut mapping**: [CIE 156:2004](https://www.cie.co.at/publications/guidelines-evaluation-gamut-mapping-algorithms) protocol on [ISO 12640-2/-4 SCID](https://www.iso.org/standard/45115.html) images; pair-comparison forced choice; metrics ΔE2000 mean/95th, hue-shift Δh, banding visibility on synthetic ramps, CIE Pointer-gamut coverage.
- **Spatial color perception**: Mullen-style chromatic CSF; [castleCSF](https://achapiro.github.io/Ash24/Ashraf2024_castleCSF.pdf) for non-standard stimulus geometry.
- **CVD evaluation**: simulate via Brettel-Viénot-Mollon (dichromacy) + Machado et al. 2009 (anomalous trichromacy); measure ΔE on simulated images and confusion-line distance.
- **Contrast for text**: WCAG 2.2 4.5:1 minimum (compliance). [APCA Lc](https://github.com/Myndex/SAPC-APCA) as second-opinion (no normative status — WCAG 3 [still excludes it](https://yatil.net/blog/wcag-3-is-not-ready-yet) as of August 2025 published draft).

## Open questions and contested points

Places where the field doesn't have a settled answer but a reading of more sources might resolve.

- **Negative-LMS handling**: `sign(x) * pow(|x|, 1/3)` is community convention, not Ottosson-blessed. csswg-drafts [#9477](https://github.com/w3c/csswg-drafts/issues/9477) still open. Aski's right move: switch to `cbrtf(x)`.
- **CSS-GMA replacement**: csswg-drafts [#10579](https://github.com/w3c/csswg-drafts/issues/10579) evaluating successors as of May 2026 ("Needs Edits"). Aski's adaptive-L₀ is one of the projection-along-constant-L candidates being weighed.
- **ΔEOK threshold of 0.02**: dimensional inheritance from CIELAB JND, not OKLab-specific psychophysics.
- **Gamma-space vs linear-space compositing**: physically settled (linear is correct), practically contested (Adobe defaults to gamma; designers calibrated to gamma).
- **OKLab α=0.05 for adaptive gamut mapping**: empirical, not derived. Could be tuned against Aski's input distribution.
- **Krasilnikov's CAM16-UCS-vs-OKLab finding**: independent reproduction would strengthen the case; until then it's a single-paper signal.

## Sources

### Primary — color spaces, distance metrics, psychophysics

- [Björn Ottosson — *A perceptual color space for image processing* (OKLAB, 2020)](https://bottosson.github.io/posts/oklab/)
- [Björn Ottosson — *Two new color spaces for color picker design* (OKLrAB, 2021)](https://bottosson.github.io/posts/colorpicker/)
- [Björn Ottosson — *sRGB gamut clipping* (2021)](https://bottosson.github.io/posts/gamutclipping/)
- [Krasilnikov et al. — Color Difference Models for WCG/HDR (*MDPI Imaging* 2024)](https://pmc.ncbi.nlm.nih.gov/articles/PMC11676281/)
- [Wang/Li/Melgosa/Xiao — LMS color-difference formulas (*Lighting Res. & Tech.* 2025)](https://journals.sagepub.com/doi/abs/10.1177/14771535251318357)
- [Raph Levien — *An interactive review of OKLab* (2021)](https://raphlinus.github.io/color/2021/01/18/oklab-critique.html)
- [CSS Color Module Level 4 — W3C TR](https://www.w3.org/TR/css-color-4/)
- [ITU-R BT.2124-0 — Objective metric for HDR/WCG (2019)](https://www.itu.int/dms_pubrec/itu-r/rec/bt/R-REC-BT.2124-0-201901-I!!PDF-E.pdf)
- [Lilley — *Better than Lab?* (W3C 2021)](https://www.w3.org/Graphics/Color/Workshop/slides/lilley/lilley.html)
- [svgeesus — OKLab implementation notes](https://github.com/svgeesus/svgeesus.github.io/blob/master/Color/OKLab-notes.md)
- [JzAzBz performance evaluation — *Color Research & Application* (2025)](https://onlinelibrary.wiley.com/doi/abs/10.1002/col.22972)
- [Safdar et al. — ZCAM (*Optics Express* 2021)](https://opg.optica.org/oe/fulltext.cfm?uri=oe-29-4-6036)

### Spatial / chromatic vision (the ASCII-relevant regime)

- [Mullen — chromatic CSF (*J. Physiol.* 1985)](https://pmc.ncbi.nlm.nih.gov/articles/PMC1193381/)
- [Ashraf et al. — castleCSF (*J. Vision* 2024)](https://achapiro.github.io/Ash24/Ashraf2024_castleCSF.pdf)
- [Far-periphery chromatic CSF (bioRxiv 2025)](https://www.biorxiv.org/content/10.1101/2025.03.22.644503v1.full)
- [DaltonLens — LMS-based CVD simulation](https://daltonlens.org/understanding-cvd-simulation/)

### Standards and evaluation protocols

- [CIE 156:2004 — GMA evaluation guidelines](https://www.cie.co.at/publications/guidelines-evaluation-gamut-mapping-algorithms)
- [ISO 12640-4:2011 SCID test images](https://www.iso.org/standard/45115.html)
- [ICC — *Design and use of v4 perceptual rendering intent (PRMG)*](https://www.color.org/Design_and_use_of_v4_PI.pdf)
- [ISO 21496-1 (gain-map metadata, July 2025)](https://www.iso.org/standard/86775.html)

### Palette quantization

- [Celebi & Pérez-Delgado — *Median cut color quantization algorithm: retrospective* (JOSA A 2026)](https://opg.optica.org/josaa/abstract.cfm?uri=josaa-43-2-403)
- [Bouman & Orchard — *Color image coding* (SP1)](https://engineering.purdue.edu/~bouman/publications/pdf/sp1.pdf)
- [pkh.me — *Improving color quantization heuristics*](http://blog.pkh.me/p/39-improving-color-quantization-heuristics.html)
- [HyAB k-means for color quantization — HN discussion (Jul 2025)](https://news.ycombinator.com/item?id=44514946)

### Numerical / implementation

- [Intel community — `cbrtf` vs `powf` accuracy](https://community.intel.com/t5/Intel-Fortran-Compiler/Why-does-Version-19-change-how-cube-root-is-calculated/td-p/1180645)
- [Zimmermann — Accuracy of mathematical functions in glibc](https://members.loria.fr/PZimmermann/papers/glibc232-20200917.pdf)
- [cppreference — `std::cbrt`](https://en.cppreference.com/w/cpp/numeric/math/cbrt)

### CSS Color WG — open issues that frame Aski's gamut-mapping context

- [csswg-drafts #9449 — channel clipping breaks perceptual lightness](https://github.com/w3c/csswg-drafts/issues/9449)
- [csswg-drafts #7071 — gamut mapping criticisms](https://github.com/w3c/csswg-drafts/issues/7071)
- [csswg-drafts #9477 — NaN values in conversion](https://github.com/w3c/csswg-drafts/issues/9477)
- [csswg-drafts #10109 — L=0/100 endpoint divergence](https://github.com/w3c/csswg-drafts/issues/10109)
- [csswg-drafts #10579 — Static GMA evaluation](https://github.com/w3c/csswg-drafts/issues/10579)

### Practitioner deep-dives (recency-weighted)

- [Evil Martians — *OKLCH in CSS: why we moved from RGB and HSL*](https://evilmartians.com/chronicles/oklch-in-css-why-quit-rgb-hsl)
- [insights4print — *The web embraces OKLch and OKLab* (May 2025)](https://www.insights4print.ceo/2025/05/the-web-embraces-oklch-oklab/)
- [Smashing — *Interview with Björn Ottosson, creator of OKLAB* (Oct 2024)](https://www.smashingmagazine.com/2024/10/interview-bjorn-ottosson-creator-oklab-color-space/)
- [Color.js — gamut-mapping documentation](https://colorjs.io/docs/gamut-mapping)
- [Chrome — *High-definition CSS color guide*](https://developer.chrome.com/docs/css-ui/high-definition-css-color-guide)
- [Bartosz Ciechanowski — *Alpha Compositing*](https://ciechanow.ski/alpha-compositing/)
- [Søren Sandmann — *Premultiplied alpha and gamma correction*](https://ssp.impulsetrain.com/gamma-premult.html)
- [JuniperPhoton — *Color management across Apple frameworks*](https://juniperphoton.substack.com/p/color-management-across-apple-frameworks-cf7)
- [demofox — *Thresholding modern blue-noise textures* (May 2025)](https://blog.demofox.org/2025/05/27/thresholding-modern-blue-noise-textures/)
- [Coyier — *Two things not great about OKLCh* (2023)](https://chriscoyier.net/2023/05/25/two-things-that-are-not-great-about-oklch/)
- [Indie Stack — *Supporting Dark Mode: adapting colors* (2018)](https://indiestack.com/2018/10/supporting-dark-mode-adapting-colors/)
- [rioogino — *EDR with Metal* (2024)](https://rioogino.com/posts/2024/edr_2_metal/)
- [Greg Benz — *Apple ISO HDR gain map 21496-1*](https://gregbenzphotography.com/hdr-photos/apple-macos-ios-hdr-iso-gain-map-21496-1/)
- [KGOnTech — *Apple Vision Pro discussion* (Apr 2024)](https://kguttag.com/2024/04/30/apple-vision-pro-discussion-video-by-karl-guttag-and-jason-mcdowall/)
- [Skip — *macOS font rendering*](https://skip.house/blog/macos-font-rendering)
- [Glyphs — *Creating an Apple color font (sbix)*](https://glyphsapp.com/learn/creating-an-apple-color-font)

### Apple platform docs and WWDC

- [WWDC22 session 10113 — *Explore EDR on iOS*](https://developer.apple.com/videos/play/wwdc2022/10113/)
- [WWDC23 session 10181 — *Support HDR images in your app*](https://developer.apple.com/videos/play/wwdc2023/10181/)
- [WWDC24 session 10177 — *Use HDR for dynamic image experiences*](https://developer.apple.com/videos/play/wwdc2024/10177/)
- [WWDC25 session 243 — *Use HDR for dynamic image experiences in your app*](https://developer.apple.com/videos/play/wwdc2025/243/)
- [Apple Tech Talk 10023 — Display calibration for pro workflows](https://developer.apple.com/videos/play/tech-talks/10023/)
- [Apple — `kCGColorSpaceExtendedLinearSRGB`](https://developer.apple.com/documentation/coregraphics/kcgcolorspaceextendedlinearsrgb)
- [Apple Tech Note TN2313 — Color management in iOS](https://developer.apple.com/library/archive/technotes/tn2313/_index.html)
- [Apple Support 102205 — HDR videos toggle](https://support.apple.com/en-us/102205)
- [Apple Support — Color Filters do not affect screenshots](https://support.apple.com/en-ie/guide/iphone/iph3e2e1fb0/ios)
- [Apple Newsroom — visionOS 26 (Jun 2025)](https://www.apple.com/newsroom/2025/06/visionos-26-introduces-powerful-new-spatial-experiences-for-apple-vision-pro/)
- [MacRumors — iOS HDR screenshots (May 2025)](https://www.macrumors.com/how-to/ios-vibrant-screenshots-iphone-hdr/)
- [WebKit standards-positions #415 — COLR v1](https://github.com/WebKit/standards-positions/issues/415)

### Tools and libraries (active unless noted)

- [`Evercoder/culori`](https://github.com/Evercoder/culori) — JS color library
- [`colour-science/colour`](https://github.com/colour-science/colour) — Python; OKLAB + CAM16-UCS + ZCAM + JzAzBz
- [`importRyan/Oklab`](https://github.com/importRyan/Oklab) — Swift OKLAB
- [`Ivordir/Okolors`](https://github.com/Ivordir/Okolors) — Rust, Wu+k-means in OKLAB
- [`okaneco/rscolorq`](https://github.com/okaneco/rscolorq) — spatial color quantization (Puzicha/Held)
- [`material-foundation/material-color-utilities`](https://github.com/material-foundation/material-color-utilities) — Celebi composite (Wu+WSMeans in CAM16/HCT)
- [`facelessuser/coloraide` HCT docs](https://facelessuser.github.io/coloraide/colors/hct/)
- [`color-js/apps` gamut-mapping methods.js (binary search default)](https://github.com/color-js/apps/blob/2c7346dd00855f7b82eb4c7527355a09b84beeb3/gamut-mapping/methods.js)
- [`insidegui/CustomHDR`](https://github.com/insidegui/CustomHDR) — iOS 26 `linearExposure` example
- [`Myndex/SAPC-APCA`](https://github.com/Myndex/SAPC-APCA) — APCA reference implementation
- [`pippin.gimp.org/ametameric`](https://pippin.gimp.org/ametameric/) — CGA/ANSI palette for CVD accessibility
- [Lunaria terminal palette](https://lunaria.design/)
- [libjxl issue #3926 — blue-noise dithering](https://github.com/libjxl/libjxl/issues/3926)
- [performous bug #32 — premultiplied alpha in gamma space](https://github.com/performous/performous/issues/32)
