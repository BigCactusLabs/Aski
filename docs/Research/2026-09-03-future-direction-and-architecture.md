---
title: "Future Direction and Architecture - validated decisions from the three-arm and simplification reviews"
slug: 2026-09-03-future-direction-and-architecture
date: 2026-09-03
status: complete
subsystem: [meta, shape-context, frontier]
summary: "Decision record for the 2026-09-03 future-direction and architecture reviews, checked against commit 6083c40, the live backlog, current research notes, independent architecture review, and a frontier scan. ACCEPT the direction of production-surface compression, a research-only render-space matcher challenger, an internal glyph-data owner after raster and matcher decisions, consolidation of the three ordinary converter loops, and an authored Vesper product probe. MODIFY the three-arm thesis to one active arm plus two evidence-gated parking lots: research supplies differentiated capabilities but is not itself a moat. ASKI-70 subsequently measured and KILLED the nested research-package split: the Aski library target was already isolated, while the split duplicated artifacts or weakened the one-build gate. ASKI-41 subsequently HOLDs Swift Build and Swift 6.4 adoption: native Swift 6.3.2 has a repeated baseline, but the current backend cannot compile the full graph, including its documented case-insensitive Aski library / aski executable-product limitation. Upstream fixed that class for Swift 6.4, but no final Swift 6.4/Xcode 27 lane is installed. REJECT moving dotMatrix after glyph selection because its Floyd-Steinberg state changes selection, and DEFER canonical mask assets, Swift 6.4-only code, a learned runtime matcher, and public visual-primitive abstractions until named gates pass. The implementation sequence is captured in ASKI-16 and ASKI-68 through ASKI-74."
related_specs: [docs/architecture.md, docs/agents/research-methodology.md, docs/Research/2026-08-19-sampling-lattice-support-collapse.md, docs/Research/2026-08-19-selection-optimality-gap.md]
next_action: "The implementation sequence through ASKI-72 is complete. Finish the bounded ASKI-73 human product probe and the ASKI-62 human/VLM validation. When a genuine final side-by-side Xcode 27 / Swift 6.4 toolchain exists, run ASKI-74 on the unchanged one-package graph before ASKI-41 repeats the backend lane."
---

# Future direction and architecture

**Status:** SETTLED AS A PROJECT DECISION, NOT AS AN ALGORITHM VERDICT.

**Baseline:** `6083c40394597430c1f3b1b4d38f3cb490869bf5` on `main`, clean and equal to
`origin/main` when the review started.

## 1. Question

Two external reviews dated 2026-09-03 proposed a three-arm direction and a large architecture
simplification. This note folds their useful claims into the project after checking them against the live
source, package graph, tests, backlog, prior measurements, current primary sources, and independent
technical and product reviews. The reviews are evidence inputs. Their proposed instructions and sequence
are not project instructions.

The decision rule for this review was:

1. A local claim must match the named baseline and current task graph.
2. An external claim must be supported by a primary source or clearly labeled practitioner evidence.
3. Published adjacency can justify an experiment, but cannot decide an Aski result.
4. New production architecture must replace measured complexity or serve a concrete product use.

## 2. Local facts that control the decision

- The shipping log-polar query reaches only **2-3 of 60 bins** at the default sampling regime, while
  candidate glyph descriptors average about 28 live bins. This is a support mismatch, not proof that every
  log-polar design is obsolete. See [Sampling-lattice support collapse](2026-08-19-sampling-lattice-support-collapse.md).
- On the frozen `blocks` preset, a tone-only floor beats production under MAE, GMSD, and HaarPSI. On dense
  `standard` and `braille` sets, production remains close to the tone floor. The preset and dense-character
  regimes must therefore be reported separately. See [Selection optimality gap](2026-08-19-selection-optimality-gap.md).
- `occupancyMatching`, `shapeStructureAssist`, `steerableShapeAssist`, and `inkPreCompensation` remain in
  the production surface after KILL verdicts. The former `chromaShapeAssist` PASS was retracted because its
  sampling lattice was invalid; ASKI-66 owns the corrected-lattice decision.
- `.edgeMap` still fails 9 of 20 honest orientation cases after its two local defects were fixed. Vesper
  uses `.logPolar`, and no in-repo product requires `.edgeMap`.
- `.dotMatrix` applies and diffuses error before each glyph choice. It is a stateful serial converter, not
  a renderer that can be moved after selection without changing the algorithm.
- The `Aski` library target has no third-party target dependency. The repository burden comes from one
  test target coupled to most labs and generators, plus a full gate designed to build once and reuse
  artifacts with `--skip-build`. A package split cannot claim consumer build savings without measurement.
- `ASCIICharacterSet` exposes several parallel arrays. ASKI-53 added a central validator, but ASKI-51 must
  settle Core Text raster drift before a committed canonical-mask format is chosen.
- Ordinary, ranked, and residual conversion repeat preparation, kernel construction, row walking, ink
  handling, and cell construction. Temporal conversion has different cross-frame state and is not part of
  that consolidation.

## 3. Claim decisions

| Proposal | Decision | Project consequence |
| --- | --- | --- |
| Research -> authored aesthetic product -> later visual primitives | **MODIFY** | Keep the order, but operate one active arm at a time. The other two are named parking lots with entry gates, not a 55/35/10 concurrent allocation. Research supplies differentiated capabilities. |
| Delete failed experimental controls from production | **ACCEPT DIRECTION, CHANGE SEQUENCE** | Preserve the minimum replay surface required by ASKI-29, ASKI-50, and ASKI-66, demote pending work to research SPI, then delete settled production branches. Notes, results, and Git history are the durable archive. ASKI-68 owns the cut. |
| Replace log-polar with fixed-footprint render-space matching | **PROMOTE TO SPIKE, NOT TO PRODUCTION** | ASKI-69 compares aligned reconstruction, a soft-edge or bounded-shift variant, and a tone-plus-fill baseline against the current matcher. It must use exact lattices, unchanged raster conventions, separate sparse and dense regimes, the MAE/GMSD protocol, the arbiter, and a performance budget. |
| Remove `.edgeMap` | **ACCEPT WITH CONSUMER GATE** | ASKI-16 now defaults to removal unless a named product use justifies an edgeMap-local matcher and that matcher passes the full orientation and no-harm gates. |
| Move `.dotMatrix` into rendering or post-processing | **REJECT** | Its Floyd-Steinberg state changes later glyph choices. Keep it as a specialized converter until a product probe decides whether it earns its production cost. |
| Move research into `Research/Package.swift` now | **KILL (ASKI-70)** | The measured child package duplicated `Aski` artifacts in direct use or pulled lab modules back into the root graph, could not consume unpublished `AskiToolSupport`, and required a second test-package invocation. Keep ASKI-48, shipping generators, governance, and labs in the root package. See [ASKI-70 package-boundary measurement](2026-09-04-aski70-package-boundary-measurement.md). |
| Add one canonical `GlyphBank` with committed masks now | **MODIFY AND DEFER** | ASKI-71 introduces an internal validated owner only after ASKI-51, ASKI-68, and ASKI-69. Start as an adapter over the surviving structure-of-arrays data. Add mask assets or a format bump only if the matcher and drift evidence require them. One bank means one rasterized bank per font with subset selection, not one charset. |
| Collapse all converter paths | **ACCEPT FOR THE THREE ORDINARY PATHS** | ASKI-72 shares preparation and traversal with specialized capture policies. The plain hot path must not allocate ranked results. Stateful temporal conversion stays separate; retained dot-matrix behavior remains serial and explicit. |
| Prefer Accelerate, Swift 6.4, `UniqueArray`, and Swift Build | **HOLD (ASKI-41)** | ASKI-69 measured the matcher arms separately. ASKI-41 recorded a repeated native Swift 6.3.2 baseline. A later feasibility run removed the initially observed demo and lab diagnostics but reached Swift Build's documented unsupported case-insensitive overlap between the required `Aski` library and `aski` executable product. [swift-package-manager#9184](https://github.com/swiftlang/swift-package-manager/issues/9184) tracks that class; [PR #10067](https://github.com/swiftlang/swift-package-manager/pull/10067) adds the fix to `release/6.4.x`. ASKI-74 validates it when a genuine final Swift 6.4/Xcode 27 lane is installed. See [ASKI-41 Swift Build migration gate](2026-09-04-aski41-swift-build-migration-gate.md). |
| Train a small learned matcher | **DEFER** | No teacher exists until a deterministic challenger wins. A student is eligible only if that teacher materially improves quality and exhaustive matching misses its runtime budget. |
| Publish vocabulary-neutral visual primitives | **DEFER** | No public framework until two genuinely different vocabularies use the same internal substrate unchanged and at least one shows repeat real-world use. |

## 4. What the external research does and does not establish

### Matcher research

[Chafa](https://hpjansson.org/chafa/ref/chafa-ChafaSymbolMap.html) is maintained production evidence for
small bitmap-based glyph matching and separate fill handling. It supports the feasibility of a cheap
render-space arm, not the claim that one uniform metric should select every glyph.

[AISS / Structure-based ASCII Art](https://ttwong12.github.io/papers/asciiart/asciiart.html) exists because
raw aligned reconstruction is sensitive to placement and can favor overlap over shape. Its full tiled
descriptor is also materially richer than Aski's single 60D window. It supports keeping a translation-
tolerant treatment and rejects the claim that local pixel error is automatically perceptual.

[UNICASSO](https://github.com/jakobrees/unicasso) is a useful pre-release comparator. It combines
rendered-glyph reconstruction with structural, multiscale, perceptual, and whole-grid terms, and reports
that reconstruction alone can collapse line art into tone. Its local distilled models lose sub-cell detail
relative to the global optimizer. It has no paper release or tagged software release at this decision date,
so it is a hypothesis source, not a dependency or authority for Aski architecture.

[DiffBMP](https://openaccess.thecvf.com/content/CVPR2026/html/Hong_DiffBMP_Differentiable_Rendering_with_Bitmap_Primitives_CVPR_2026_paper.html)
validates differentiable bitmap primitives as an active graphics frontier. Its CUDA optimizer over position,
rotation, scale, color, and opacity does not validate a local Apple-platform glyph matcher or a public
primitive framework.

[ASCIIEval](https://proceedings.iclr.cc/paper_files/paper/2026/hash/63f5c95b1e6364c42075f913d84ccb73-Abstract-Conference.html)
and the [Lines and Minds workshop](https://lines-and-minds.github.io/) establish ASCII-encoded perception and
computational abstraction as legitimate research subjects. Neither measures image-to-ASCII reconstruction
quality, Aski's novelty, or commercial demand.

### Toolchain and performance research

At this decision date, [Swift.org's macOS install page](https://www.swift.org/install/macos/) lists Swift
6.3.3 as stable and Swift 6.4 only as a development snapshot. SwiftPM documents Swift Build as a
[preview backend](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/SwiftBuildPreview.md)
under Swift 6.3, including a known issue for case-insensitive executable/library product-name overlap that
matches Aski's required `aski` / `Aski` pair. The upstream regression test and fix landed on
`release/6.4.x` in [PR #10067](https://github.com/swiftlang/swift-package-manager/pull/10067).
`UniqueArray` and span-based temporary allocation offer relevant ownership and safety tools, but no source
shows an Aski performance win. ASKI-41 remains HOLD until the final toolchain and unchanged package graph
can pass the whole gate.

[Accelerate](https://developer.apple.com/documentation/accelerate) provides optimized image and vector
operations. That makes bulk vImage/vDSP a benchmark arm. It does not make small per-cell calls preferable
to manual SIMD or one batched Metal dispatch.

## 5. Resulting execution order

1. Finish the evidence blockers: ASKI-29, ASKI-50, ASKI-62, ASKI-66, and ASKI-51.
2. Decide `.edgeMap` in ASKI-16; the ASKI-70 package boundary is settled as one root package.
3. Compress the experiment surface in ASKI-68 without losing required replay evidence.
4. Run the render-space challenger in ASKI-69. A win must replace old machinery; a loss leaves no new
   production option.
5. Build the internal glyph owner in ASKI-71 from the surviving data contract.
6. Collapse the three ordinary converter loops in ASKI-72 around the surviving kernels.
7. When a genuine final side-by-side Swift 6.4/Xcode 27 toolchain is available, use ASKI-74 to validate the
   upstream case-only product fix on the unchanged one-package graph, then repeat ASKI-41's full lane.

## 6. Claims deliberately not made

- The render-space matcher will win.
- A nested package will reduce downstream consumer builds.
- Canonical masks should be committed before the raster-drift decision.
- `.dotMatrix` is valuable enough to retain indefinitely.
- Swift 6.4, `UniqueArray`, Swift Build, compilation caching, Accelerate, or Metal will improve this repo
  without a same-machine measurement.
- A second visual vocabulary or a public primitives layer is needed now.
