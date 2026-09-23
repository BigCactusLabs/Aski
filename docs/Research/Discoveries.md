# Research Discoveries — Triage Queue

Append-only log of cross-cutting insights and out-of-scope discoveries that surfaced during other work. Agents add entries when they hit something worth revisiting but not in scope of the current task. Triage promotes winners into planned work.

**When to add an entry.** While working on task A, you notice something that would help task B, would invalidate an assumption in research area C, or is a genuinely surprising finding worth retesting. Add it here before finishing the session.

**Entry format.**

    ## YYYY-MM-DD — <short headline>

    <Body paragraph: what you noticed and the surrounding context.>

    Found in: <which task / branch / research run>
    Touches: <relevant files or research areas>
    Revisit if: <a falsifiable test or trigger>

The `Revisit if:` line is the killer feature — it forces the writer to commit to a falsifiable criterion, which makes later triage easy.

**Triage workflow.**

Periodically (cadence TBD by user — weekly review, before each minor release, or on demand):

1. Read entries in `docs/Research/Discoveries.md`.
2. For each entry, check whether its `Revisit if:` criterion can be evaluated now.
3. If yes and the criterion fires: open a tracked task for it, then strike through the discovery entry with `~~`-wrap markdown and append `→ promoted to <task-id>`.
4. If the entry is obsolete or won't pan out: strike through and append `→ dropped: <reason>`.
5. Otherwise leave the entry for the next triage pass.

Entries are never deleted, only struck through. The historical log stays readable.

---

<!-- entries below -->

## 2026-06-02 — SDK-26 `AVAssetWriterInput.PixelBufferReceiver.append` deadlocks under spaced appends — ✅ RESOLVED 2026-06-03

While implementing C2a (video MP4 loop), the new SDK-26 async pixel-buffer receiver
(`AVAssetWriter.inputPixelBufferReceiver(for:pixelBufferAttributes:)` →
`receiver.append(_:with:) async`) deadlocked once the writer's input buffer filled (~38 frames) **when
appends are spaced out by slow upstream work** (per-frame shape-matching conversion). The suspended
`append` never resumes — its readiness wakeup appears lost. Reproduced in both the executable and the
Swift-testing harness; an instrumented trace localized the hang to *inside* `append` (decode side idle,
pipeline serial, so not concurrent cooperative-pool starvation). Feeding the same encoder back-to-back
from an in-memory array does **not** deadlock, so the plan's encoder-only test missed it. The legacy
`AVAssetWriterInputPixelBufferAdaptor` path encoded 300 frames with zero issues in the same process.
The API has near-zero public usage guidance (brand new in 2025). This is the kind of finding that
should gate *any* future adoption of the async receiver elsewhere in Aski.

**Resolution (2026-06-03):** Fixed — `ASCIIVideoEncoder` rewritten to the legacy
`AVAssetWriterInputPixelBufferAdaptor` + an `isReadyForMoreMediaData` **poll** (`try await Task.sleep`,
re-reading the real flag each tick so it can't lose a wakeup; the poll also checks
`Task.checkCancellation()` and `writer.status` and throws on `.failed`/`.cancelled` so a writer failure
can't spin it forever). A 64-frame scale + spaced-append regression test now guards it; full suite green
(667 tests) and a real `AskiVideoLab` 60-frame run completes. Fix plan:
the C2a video-loop encoder-fix plan. Apple Feedback for the
lost-wakeup has Apple Feedback **FB22925320** filed (no prior art).

**Related availability findings (fix's frontier-search + local `swiftc -typecheck`, 2026-06-03):**
- **`next(isolation:)` is iOS 18 / macOS 15 / visionOS 2 (SE-0421)** — *this*, not the receiver, pins the
  C2a floor at iOS 18. The decode→render bridge advances its non-Sendable iterator with
  `next(isolation: #isolation)` (`Sources/Aski/Video/ASCIIVideoConverter.swift`,
  `Tools/AskiVideoLab/CappedRenderDriver.swift`); iOS 16 / macOS 14 / visionOS 1 all fail to typecheck.
  A lower floor would require redesigning that iterator advance.
- **iOS-17 custom-executor trap (informational, moot at the iOS 18 floor):** a `requestMediaDataWhenReady`
  + `assumeIsolated` continuation bridge traps on back-deployment and fails at runtime on iOS 17 under a
  custom `SerialExecutor` (SE-0424 isolation checking absent pre-iOS-18). Another reason the poll (no
  continuation, no `assumeIsolated`) beats a bridge.

Found in: ASTSK-3 / C2a, branch `worktree-astsk-3-c2a-video-loop` (Task 8). Full write-up:
the C2a video-loop encoder-deadlock findings note.
Touches: `Sources/Aski/Video/ASCIIVideoEncoder.swift`; any future AVAssetWriter-based encode path; the
iOS-26 floor-bump rationale.
Revisit if: a future Aski feature wants `AVAssetWriterInput.PixelBufferReceiver` again, OR a
later SDK (≥ 26.6) is available to retest whether Apple fixed the lost-wakeup (minimal repro: ≥60
spaced-out appends through a real decode→encode chain).

## 2026-06-03 — C2a decoder ignores `preferredTransform` (portrait clips decode rotated)

`ASCIIVideoDecoder` reads raw track pixel buffers via `AVAssetReaderTrackOutput` +
`VTCreateCGImageFromCVPixelBuffer` and never applies the source track's `preferredTransform`. Video
authored as landscape-plus-rotation (the standard portrait iPhone capture) therefore converts to ASCII
sideways/upside-down, and the re-encoded MP4 inherits the wrong orientation. Surfaced by Codex on PR #21
(P2). Decided 2026-06-03 to track rather than fix inside the encoder-deadlock PR: it is pre-existing,
separable, needs a video-composition decode path (or per-frame rotation) plus rotation AND mirror
(front-camera) fixtures, and the repo has zero current consumers. A KNOWN-LIMITATION note was added to
the decoder doc comment.

Found in: ASTSK-3 / C2a, branch `worktree-astsk-3-c2a-video-loop`, PR #21 (Codex review).
Touches: `Sources/Aski/Video/ASCIIVideoDecoder.swift`; `convertVideo`; AskiVideoLab output orientation.
Revisit if: C2a/C2b ingests real device footage (any portrait clip) — fixed once a
`preferredTransform`-applying decode path lands with a rotated round-trip test (decoded dimensions match
the oriented size) and a front-camera mirror case.

**RESOLVED 2026-06-03 (ASTSK-12).** Decoder now loads `preferredTransform` once and reorients each
decoded `CGImage` via `CIImage(cgImage:).transformed(by:)` (identity short-circuits to the prior fast
path). Chose per-frame Core Image over `AVAssetReaderVideoCompositionOutput`: the composition path
resamples to a fixed `frameDuration` (breaking the decoder's source-PTS/no-resample contract and
exact-count tests) and `copyNextSampleBuffer` is reported to stall with a composition attached. Covered
by a 90° dimension-swap test and a front-camera mirror test (full suite 670 green).

## 2026-06-03 — ImageIO composites animated-GIF frames (placement + disposal); old web sources say otherwise

While implementing C2b (animated-GIF loop), an on-device probe on the target SDK (`arm64-apple-macosx26.0`)
showed `CGImageSourceCreateImageAtIndex` returns **fully-composed, full-canvas** GIF frames — sub-rect
placement AND disposal (restore-to-background) are already applied. A 3-frame fixture (full red →
2×2 green at (1,1), restore-to-bg → 1×1 blue) decodes frame 2 with the green region **cleared**, proving
ImageIO disposed it before composing. This **inverts** the iOS-11-era sources (Cloudinary ghosting thread,
YYImage #99) that the addendum cites — they describe non-compositing behavior that no longer holds. Net:
the decoder must **not** build a manual compositor (it would double-composite and corrupt output), so C2b's
`ASCIIGIFDecoder` is strictly simpler than the prior design draft assumed. Two related read-quirks: per-frame
delay must come from `kCGImagePropertyGIFUnclampedDelayTime` (the clamped key silently floors fast GIFs to
0.1s), and container `LoopCount` semantics are non-obvious (absent = 1/play-once, 0 = infinite, raw Netscape
N reads back as N+1) — so loop count is **preserved**, never defaulted to 0.

Found in: ASTSK-13 / C2b, branch `worktree-aski-c2b-gif-loop`, PR #23. Full write-up + probe:
the C2b GIF-loop design addendum, §Verification.
Touches: `Sources/Aski/Video/ASCIIGIFDecoder.swift`; any future GIF/APNG/HEIC-sequence ingest; the
"no manual compositor" assumption shared with image-sequence decoding.
Revisit if: the composed-frame disposal sentinel
(`AskiGIFDecoderTests.decoderYieldsComposedFullCanvasFramesWithDisposalApplied`) ever fails on a newer SDK —
i.e. ImageIO stops compositing — at which point a manual placement+disposal compositor becomes required.

## 2026-06-07 — Helmlab palette-matching win, if any, lives in dense palettes — not the built-in 16-color sets

Porting Helmlab MetricSpace (ASTSK-2) produced **no measured palette-matching win** over OKLab: the
perturbation-recovery oracle ties at 100% (23/23) for all three policies, and the predicted
`helmlabCompressed` saturation collapse never appears (on the Carina Nebula corpus image it selects *more*
distinct ANSI16 entries than OKLab — 10 vs 7). The theory (research note §5): coarse palettes decide the
nearest-entry argmin on gross geometry every ΔE agrees on, so a trained ΔE's calibration is wasted
precision above the JND threshold quantization already discards. MetricSpace's real COMBVD edge is
sub-threshold. Two falsifiable predictions fall out: (a) divergence-from-OKLab rate should grow
monotonically with palette density, and (b) a hybrid metric (`helmlabCompressed` for near candidates,
monotonic Euclidean for distant ranking) only pays off once a dense-palette oracle shows the two pure
variants split by distance regime.

Found in: ASTSK-2 Helmlab MetricSpace port, branch `astsk-2-helmlab-spec`, this plan (Task 15).
Touches: `Sources/Aski/HelmlabMetric.swift`, `Sources/Aski/CellSampling.swift`,
`Tools/AskiColorLab/PaletteMatching/`; the `palette-match-ablation` + `helmlab-recovery-oracle` harnesses.
Revisit if: a dense-palette (≥256-entry / gradient-LUT) recovery oracle shows
`helmlabCompressed` wins small-ΔE recovery AND loses large-ΔE ranking on the same palette — the regime
split the hybrid targets — OR the divergence-vs-density prediction (a) is confirmed and a real
photographic-palette use case appears.

## ~~2026-06-10 — Core Text raster output drifts across macOS updates; committed .bin bytes are OS-version-bound~~ → promoted to ASKI-51

While regenerating `ShapeData/*.bin` for the v2 format bump (ASTSK-28), the Step-0 determinism
pre-check failed: 6/10 committed v1 bins (standard, dots, cross, diamond, diagonal, mixed) could
not be byte-reproduced on the current macOS — Core Text anti-aliasing shifted some glyph coverage
by ≤1e-4 in brightness (single gray-levels on a few pixels) since the bins were built (2026-05-06).
Scalar sort order survived; the full snapshot suite stayed green, so matching was unaffected at this
magnitude. Frontier-search confirmed this is a known platform behavior: image-snapshot communities
hit it on minor OS updates, and no CoreGraphics/CTFont API pins rasterizer output across releases.
The four clean sets include `braille` — generated by our own vendored `BrailleRasterizer`, which is
immune by construction. Glyph-level drift was also non-uniform: `minimal` (ASCII) was clean while
`diagonal` (`/\X`, also ASCII) drifted, so it is per-glyph, not per-font-fallback.

Found in: ASTSK-28 `.bin` v2 regen, branch `astsk-28-30-color-theory-phase1`.
Touches: `Tools/BuildStandardVectors/`, `Sources/Aski/Resources/ShapeData/*.bin`,
`Sources/Aski/CharacterSets/RasterizedCharacterSet.swift` (Core Text rasterization path).
Revisit if: a future regen on a newer macOS shows drift > 1e-3, flips any snapshot test,
or changes the brightness sort permutation — that is the trigger to vendor a deterministic glyph
rasterizer (or commit per-OS golden rasters) instead of relying on Core Text stability.

## 2026-06-10 — Saturated colors are always "inky" to the inverted-luma shape field; channel injections must be mass-normalized, not peak-normalized

> See also the [ASKI-65 addendum](2026-06-11-isoluminant-dose-response.md#addendum-2026-09-02-aski-65-the-pass-above-was-measured-on-a-truncated-lattice) (2026-09-02), which retracts the later competition-ramp dose-response PASS; its exact-lattice re-measurement does not cover the step-edge result quoted here.

While locking ASTSK-30's injection arithmetic, the dilution algebra showed the design sketch
(`g += λ·peak1(∇chroma)`) could never work — and the reason generalizes. The logPolar query field is
*inverted* Rec.601 luma, and saturated primaries have luma well below 1, so any strongly-colored cell
arrives pre-flooded (g ≈ 0.7–1.0 on every pixel). `ShapeContext.histogram60` then L1-normalizes, so
what matters is a channel's *share of total field mass*, not its amplitude: a peak-1 additive bump on
a ~2px edge band tops out near 9% of descriptor mass at λ=1, while flipping a flat descriptor to a
line-like one needs ~40% (‖U‖² ≈ 0.018, ‖U−E‖² ≈ 0.13). Any auxiliary channel injected into the
shape query (chroma gradient today; depth, saliency, or flow fields tomorrow) therefore needs
**mass normalization** — `g′ = (1−λ)·g + λ·(Σg/Σc)·c` makes λ the channel's exact descriptor-mass
fraction (and needs an absolute noise floor, since it amplifies arbitrarily faint fields). With that
fix Thread D PASSed cleanly (melt H=0 → step to 0.72 bits at every λ>0); with the sketched
arithmetic the same lab would have returned a KILL that measured the injection arithmetic, not the
chroma signal — the ASTSK-27 instrument-artifact trap, avoided this time by pre-run algebra instead
of a post-run autopsy. Secondary find (frontier-grounded): for the gradient itself, scalar
chroma-magnitude `|∇√(a²+b²)|` is near-blind to red/green hue edges (C constant, `a` flips sign);
the Di Zenzo vector gradient `√(|∇a|²+|∇b|²)` is the correct operator.

Found in: ASTSK-30 isoluminant-rescue, branch `astsk-30-isoluminant-rescue`
(docs/Research/2026-06-10-isoluminant-rescue.md).
Touches: `Sources/Aski/Algorithms/LogPolarKernel.swift` (`extractShapeVector`,
`chromaGradientFloor`), `ShapeContext.histogram60` L1 normalization, `edgeEmphasis` (peak-normalized
*blend* — exempt because it replaces rather than augments the field), ASTSK-7 (pool diversity caps
any query-side rescue).
Revisit if: any new per-pixel channel is proposed for the shape query, or `edgeEmphasis`
is ever revisited — both should start from the mass-share framing, not amplitude.

## 2026-06-10 — Area-tone color compensation is gamut-bound, not algorithm-bound; only luminance is recoverable

While scoring Thread C (ASTSK-29), the linear back-solve `FG' = (target − (1−k)·BG)/k` failed in an
unexpectedly *total* way: on every one of the 4,114 compensated fullColor cells, the out-of-gamut FG'
projected to the achromatic boundary — mean compensated FG chroma was exactly 0.0000. The display
ceiling means a glyph covering ~25% of a cell can never composite to the source chroma (that needs
FG chroma ÷ k, unreachable), but it *can* recover much of the luminance by going toward white
(fullColor mean l_fidelity 0.185 → 0.102). The constraint is the gamut geometry, not the back-solve
math — so a *chroma-preserving, L-only* correction (back-solve L in OKLab, hold a/b) or a gamut-aware
partial back-solve (scale toward FG' only as far as the cell's gamut ray allows) should bank the
luminance win without the chroma annihilation. The `compensation-ab` harness scores either variant
as-is (it pairs arms cell-by-cell and verdicts mechanically). Secondary instrument lesson: the
`cancellationRate` guard watched for FG snapping *back* (fgHex unchanged) while the actual failure
changed FG everywhere — to white; paired-delta criteria caught what the targeted guard missed.

Found in: ASTSK-29 compensation-ab run, branch `astsk-29-ink-precompensation`
(docs/Research/2026-06-10-thread-c-ink-precompensation.md).
Touches: `Sources/Aski/InkPreCompensation.swift`, `Tools/AskiDecolorLab/DecolorCompensationAB.swift`,
gamut mapping (`mapToDisplayColor`/rayTrace), ASTSK-7 (occupancy-weighted k raises effective k and
shrinks the infeasible region).
Revisit if: muddy sparse-glyph color is prioritized again — the falsifiable test is an
L-only compensation arm through `compensation-ab` with fullColor Δl < 0 AND Δchroma ≤ 0; or ASTSK-7
ships occupancy-weighted k and the re-run flips any palette's verdict.

## 2026-06-11 — Mass-normalized injection cancels its own contrast ramp; ~~competition, not isolation, gives a dose-response~~ → second clause RETRACTED (ASKI-66)

> **Partially retracted 2026-09-02 (ASKI-65), closed 2026-09-04 (ASKI-66).** The cancellation theorem below still
> stands — it is algebraic, not measured. What is withdrawn is the second half: the claim that the
> luma-vs-chroma *competition* ramp DID produce a graded dose-response. That reading was an artifact
> of the truncating sampling lattice (the bottom band rows were never sampled). Re-measured on an
> exact lattice the competition instrument does not grade on any geometry probed, so the flipped-
> fraction figures quoted below are invalid. ASKI-66 then ran one preregistered 64-candidate
> exact-lattice redesign; all candidates were valid and every axis remained invariant over 21 lambda
> arms, so no candidate qualified and the question closed INCONCLUSIVE. The two corollaries split the
> same way the main claim does: corollary (1), the non-white
> ground, is the same algebraic cancellation argument in another guise and still stands; corollary (2),
> flipped-fraction over entropy, quotes flip percentages from the invalid run and is unproven as
> stated — the underlying point that entropy cannot read a relabeling is sound, the numbers are not. See
> [the retracted verdict](2026-06-11-isoluminant-dose-response.md).

ASTSK-36 set out to calibrate `chromaShapeAssist` λ with a constant-OKLab-L fixture that grades
*chroma contrast* per row — and the fixture is mathematically degenerate. The kernel's injection is
mass-normalized (`scale = λ·lumaMass/chromaMass`), so a row of chroma contrast `c` has both
`chromaGradient ∝ c` and `chromaMass ∝ c`; the `c` cancels and every ramp row becomes identical after
normalization. **Any single-channel signal whose mass scales with its own contrast cannot produce a
graded response under a mass-normalized blend** — the grading must come from *competition* between
two channels whose mass ratio λ tunes. The working instrument was a graded vertical luma grating
crossed by a horizontal isoluminant chroma edge: there the inverted-luma pedestal keeps `lumaMass`
constant, the graded luma enters the blend uncancelled, and the per-column flip point sweeps with the
luma contrast. Two transferable corollaries: (1) the fixture background must be non-white — on a white
ground `1−Y → 0`, `lumaMass ∝ g`, and the luma grading cancels exactly like the chroma did; (2) band
*entropy* is the wrong dose readout when the dose is a relabeling — at λ=1, 56–58% of band cells had
flipped yet entropy returned to its λ=0 value; flipped-fraction-vs-baseline is the right metric.

Also surfaced: the kernel's luma field is **Rec.601** but the isoluminant fixtures are **OKLab**-L —
and they disagree. An OKLab-L-equal red/green edge can carry a real Rec.601 luma step, so a corpus
classifier files it as luminance-structured, not isoluminant. Any real-corpus round must decide whether
"isoluminant" means Rec.601-isoluminant (what the kernel sees) or perceptually isoluminant.

Frontier grounding: there is no published portable multiplier for chromatic-vs-luminance dominance of
form (Kingdom/Bell/Gheorghiu/Malkoc 2010 call their equating contrasts "essentially arbitrary";
Switkes/De Valois 1988 normalize to each observer's threshold) — exactly parallel to there being no
portable a*/b* chroma-noise floor constant (Imatest: CIELAB noise "is not a standard measurement").
Both the override threshold and the floor must be *measured per instrument*, not looked up; and the
masking literature keeps luminance dominating spatial form, so a low/opt-in λ stays the principled
default.

Found in: ASTSK-36, branch `astsk-36-dose-response`
(docs/Research/2026-06-11-isoluminant-dose-response.md).
Touches: `Sources/Aski/Algorithms/LogPolarKernel.swift` (`extractShapeVector` mass-normalized blend),
`Tools/AskiColorLab/IsoluminantRescue/`, any future fixture that grades a single injected channel.
Revisit only if a different mechanism is proposed and its rule is committed before measurement. The
existing competition-ramp family exhausted its bounded exact-lattice search in ASKI-66. A real-corpus
review can still settle Rec.601-vs-OKLab classification, but it cannot restore the invalid dose curve.

## 2026-06-14 — A confidence-signal ρ lift is NOT a pick-quality result; rank-mix-at-selection discards the magnitude that picks need

ASTSK-31's AC#4 "lift" measured ρ(augmented score, pixel-oracle consensus) over a POPULATION of cells —
the augmented score rank-mixes the 60D residual with orientation/radial channels at w=0.25, and on
radial/diagonal it flipped that population correlation from strongly negative to positive (radial
−0.61 → +0.23). ASTSK-35 wired exactly that rank-mix into per-cell selection and measured the thing we
actually care about — GMSD between the *chosen glyph* and the source at native footprint — and the
picks did **not** clear the +3% bar on radial/diagonal and regressed the naturals. The ρ lift
reproduced bit-for-bit, yet the picks did not improve past the bar. (A PR #42 fidelity fix later made
the channel rasterization + shrink resampler faithful to the lab and the gate was RE-MEASURED 2026-06-15:
radial/diagonal stop *regressing* but still miss the bar at +0.1%/+0.7%, while `checker` −35% and the
naturals −12%…−30% regress harder — and the ρ lift still reproduces bit-for-bit. Making the signal *more*
faithful did not turn it into better picks; the lesson is reinforced.) Two distinct lessons: (1) a population rank-correlation
between a score and an oracle says nothing about whether *argmin of that score per cell* selects better
items — the same trap as the ASTSK-27 instrument lesson (a confidence-correlation ρ is not a falsifiable
pick-quality gate; see `docs/Research/2026-06-09-shape-residual.md`); always close the loop with a direct
chosen-item-vs-source measurement before productizing. (2) Rank-mix-at-pool is dimensionless (that's why it needs no fitted
normalization constants), but the price is that it **discards magnitude** — over a brightness-homogeneous
near-tie pool it arbitrates by ordering alone, and that ordering does not align with the pixel oracle.

Found in: ASTSK-35, branch `worktree-astsk-35-basis-augmentation`
(the 2026-06-15 fidelity-fix re-measurement, which supersedes the
pre-fix shape-residual-astsk35-2026-06-14/).
Touches: `Sources/Aski/ShapeMatching.swift` (`findBestStructure` rank-mix), `Sources/Aski/RenderingOptions.swift`
(`shapeStructureAssist`, default-off), `Tools/AskiColorLab/ShapeResidual/{BasisAugmentation,ProductionPathArm}.swift`,
and any future "the lab signal correlates, ship it" proposal.
Revisit if: a NORMALIZED-DISTANCE blend (keeps per-channel magnitude via stated Ko/Kr scale
bounds instead of ranks) is specified with its own pre-registered pass/fail — the one avenue ASTSK-35's
frozen decision tree left open for the augmented basis (and as part of that work, audit full lab/prod
resample fidelity: production `LumaResample`'s grow path uses endpoint/align-corners mapping while the lab
copy uses center mapping — inert today only because the off-by-default structure query runs almost entirely
through the shrink path at canonical geometry); or if any other lab ρ-lift is proposed for a
selection path without first measuring chosen-item-vs-source pick quality.

## 2026-06-24 — NCA-fork frontier-bolster: log-polar is an *orientation low-pass*; ASTSK-42's honest design is a steerable channel — not a Fourier swap, and NOT the killed ASTSK-35 histogram

A frontier-search bolster (6 briefs + 2 adversarial fact-check passes, workflow `wf_fd0a0e5a-0f3`)
of the three 2026-06-18 NCA-brief follow-ups redirected two of them and surfaced one cross-cutting lever.

**Fork ASTSK-42 (sub-cell basis).** The task as written ("evaluate a Fourier-feature descriptor
alongside log-polar") is neither the cheapest nor the most defensible test. Verbatim-confirmed
(Tancik et al. 2020, Fig 11): an isotropic basis "performs well across all angles, while the positional
encoding mapping performs worse for frequencies that are not axis-aligned" — log-polar's radial/diagonal
degeneracy is the *generic* failure of an axis-aligned/centered basis, not a 60D implementation bug.
Steerable filters (Freeman–Adelson) give continuous, analytically-exact orientation from a tiny fixed
basis — the property the existing **discrete 8-bin** orientation histogram (`BasisAugmentation`,
GLOH-style π/8 ≈ 22.5° bins) structurally lacks; angular quantization, not the gradient, is the bottleneck
that lets population ρ rise while per-cell picks stay wrong. **Sharp theory:** log-polar acts as a
*low-pass filter on orientation* — it orders glyphs by gross shape (ρ up) while collapsing the fine angular
distinctions that decide the single best pick; the prior "ρ rose, picks didn't" KILLs (ASTSK-31/35) are
diagnostic of this, not anomalous.

**CRITICAL — Fork A is attempt #3 on a wall that held twice.** A steerable oriented-energy channel is NOT
automatically distinct from the KILLED `shapeStructureAssist` (ASTSK-35). It is a valid new test ONLY if it
differs in the two ways that actually mattered: (1) **continuous angular resolution** (steerable energy at
exact angles) vs the discrete 8-bin histogram that already failed; AND (2) a **magnitude-preserving
normalized-distance blend** (the open avenue ASTSK-35's frozen decision tree explicitly left — stated
Ko/Kr scale bounds), NOT rank-mix-at-pool (which discards the magnitude picks need — see 2026-06-14). Built
as another rank-mixed discrete channel, it is ASTSK-35 relabeled and will KILL the same way. The +3% GMSD
pick bar (native footprint, no rank-ρ credit, no constant tuned on the battery) is unchanged.

**Fork ASTSK-43 (inter-cell smoothing).** Strong convergence on a **guided filter** (He–Sun–Tang),
r=1 / 3×3 / single pass over the *continuous pre-quantization* OKLab/luma field: O(N) independent of radius
and a per-window proof of *no gradient reversal* in the self-guided case (aₖ = σ²/(σ²+ε) < 1) — the flaw
that makes bilateral "inherent and cannot be safely avoided by tuning parameters." Perona–Malik is
iterative/ill-posed/staircasing — wrong for a cheap fixed pass. Caveat: the box window is "rotationally
asymmetric and slightly biases to the x/y-axis" (verbatim), which intersects Aski's known radial/diagonal
weakness — use a Gaussian-weighted window if diagonal seams stair-step. Gate: native-resolution M1
(cross-seam stroke-orientation continuity) + M2 (GMSD) cross-checked by an AGREEING HaarPSI; PASS iff M1
improves AND neither line-art nor naturals GMSD regresses AND HaarPSI agrees on sign; KILL on naturals
washout or oracle disagreement.

**Cross-fork lever (the synthesis worth testing).** Both forks reduce to one primitive: a single DoG/Sobel
**orientation/coherence field** computed once over the grid can feed *both* Fork A's steerable descriptor
channel AND Fork B's edge-gated coupling. Unified theory (Fork B verifier): a **cross-guided** guided filter
— high-res continuous luma as guidance I, discrete cell state as input p — lets real luma edges *veto*
smoothing across genuine boundaries while smoothing only intra-region cross-cell jitter, using the free
pre-quantization continuous field already in the pipeline. (Loses the self-guided no-reversal guarantee →
gate empirically.) Deliberately NOT building this unified primitive first: it is an unproven bet; build the
two arms independently, share the orientation field only where genuinely identical, and let the gates say
whether the synthesis is real.

Two fact-check corrections to carry forward: "σ=6 for NeRF" is a misattribution (it is the positional-encoding
scale on the *Natural* dataset, not a NeRF value); and Xu et al. SIGGRAPH'10 built an alignment-tolerant
metric but never names log-polar — do not cite it as anti-log-polar precedent.

Found in: frontier-search design bolster ahead of building ASTSK-42/43 (the 2026-06-18 NCA brief follow-ups).
Touches: `Tools/AskiColorLab/ShapeResidual/` (BasisAugmentation, GMSD, HaarPSI, OracleConsensus, GlyphRaster,
ProductionPathArm); `Sources/Aski/Algorithms/{LogPolarKernel,ShapeStructureChannels,EdgeMap}.swift`;
`Sources/Aski/CellSampling.swift`; `Tools/AskiMotionLab/FlickerMetrics.swift` (ASTSK-41 flicker readout).
Revisit if: already tracked — ASTSK-42 (steerable channel, gate above), ASTSK-43 (guided-filter
coupling, gate above), ASTSK-41 (NCA temporal prior). New trigger: if Fork A's steerable channel clears +3%
picks, split the production basis change into its own task; if the cross-guided unified pass clears BOTH
gates, promote the shared orientation field as a first-class pre-pass primitive.

**VERDICT (2026-06-27, decisive) — KILL.** Fork A built and run exactly as frozen above: continuous 24-bin
(7.5°) phase-invariant steerable signature + magnitude-preserving Ko/Kr=0.5 blend (`shapeL2 + Kr·scale·
sigDist/2`, NOT rank-mix), off-by-default `steerableShapeAssist`, real converter, native-footprint
GMSD(chosen glyph, source). Full sweep {48,64,80,96,120} × {spokes, diagonals 15/30/60/75°, arcs, ≥3072px
NASA naturals (`nasa-steerable-v1`)}; **147,168 cells, 0 upsampled**. Aggregate Δ = **−0.19%** (bar +3.0%);
naturals Δ = **−0.92%** (regression). Fails clauses (a) and (c). The channel is **inert** where it was meant
to help — diagonals +0.0%, arcs +0.0%: the per-cell dominant-orientation signature is near-degenerate at the
24px footprint, so `sigDist ≈ 0` collapses the blend to argmin-shape — and net-harmful on naturals (the one
non-trivial move, spokes +0.32%, is an order of magnitude short of the bar). **The wall has now held three
times (ASTSK-31 / 35 / 42):** a reconstruction-side orientation/structure signal does not transfer to glyph
pick-quality, by three mechanically distinct routes. Do **not** attempt a 4th orientation-channel variant
without either a *perceptual* (not reconstruction-GMSD) oracle or a rendering-model change. The "+3% → split
production basis" trigger for Fork A is **extinguished**. Verdict doc:
`docs/Research/2026-06-27-astsk42-steerable-channel.md`.

### 2026-06-24 (sub-entry) — ASTSK-43 M1 must be *source-conditioned*: self-referential blockiness rewards the washout it's meant to KILL

Frozen before building the M1 instrument (frontier-search `--effort=med`, 1 probe + 1 expand round). The open
fork was the exact operationalization of M1 ("cross-seam stroke-orientation continuity" — the pre-registration
offered two forms: *fraction of source edges unbroken* vs *gradient angular coherence across seams*). The
**decisive** finding: the no-reference blockiness lineage that the second form resembles — GBIM (Wu & Yuen, IEEE
1997) "intensity changes along adjacent block boundaries"; Wang–Sheikh–Bovik (ICIP 2002) block-edge impairment at
fixed 8-px boundaries — is **self-referential** (penalizes *any* seam-aligned edge, no reference) and is
**documented to be gamed by low-pass/over-smoothing**: verbatim "in order to reduce blockiness, images are
low-pass filtered which leads to more blurriness," which is why PSNR-B and the DBIQ metric had to *add a blur
term* (Signal Processing 2016, *No-reference quality assessment of deblocked images*). A self-referential M1
would therefore score this gate's **naturals-washout KILL case as a win** — strictly backwards. So M1 is
**source-conditioned**: structure-tensor orientation coherence `C = (λ₁−λ₂)/(λ₁+λ₂) ∈ [0,1]` over a window
straddling each interior seam on the *rendered* field, **weighted by source edge strength crossing that seam**;
`M1 = Σ(w·C_rendered)/Σ(w)`. Source-conditioning *is* the anti-washout property (wash strokes out → real seam
edges vanish → M1 drops). The structure tensor (built from `∇I∇Iᵀ`) handles `[0,π)` orientation folding for free
and sidesteps the Di Zenzo direction-indetermination bug; `cos²(Δθ)` is its degenerate 2-pixel reduction. M2 =
GMSD (Xue/Zhang/Mou/Bovik, arXiv 1308.3052, gradient-*magnitude* deviation, global) cross-checked by HaarPSI —
complementary to M1 (orientation-at-seams vs magnitude-global), so the dual-oracle independence holds. Field
resolution (Explore map): the guided-filter pre-pass runs on the **per-cell grid** of continuous cell-state
(`CellSourceStats.oklab/adjustedL`, rows×cols, 3×3 r=1 = the 8 grid-neighbors); M1 is measured on the rendered
grid at **native pixel resolution** — different resolutions by design.

Found in: design bolster ahead of ASTSK-43 Unit 2 (the M1 instrument). Touches:
`Tools/AskiColorLab/ShapeResidual/` (new `SeamContinuity.swift`; existing `GMSD`/`HaarPSI`/`GlyphRaster`/
`LumaResample`). Revisit if: already tracked (ASTSK-43, gate above). Primary sources: GBIM —
Wu & Yuen, IEEE T-CSVT 1997; NR blockiness — Wang, Sheikh & Bovik, ICIP 2002; deblock blur-tradeoff — *No-reference
quality assessment of deblocked images*, Signal Processing 2016; structure-tensor coherence — OpenCV GST tutorial;
Di Zenzo multichannel gradient (direction-indetermination caveat); GMSD — arXiv 1308.3052.

## 2026-06-29 — ASTSK-41 KILL: smoothing the continuous state can't move a discrete argmax; + the band-relative equivalence-bound (SESOI) deadband pattern for noise-floor oracle splits

ASTSK-41 (NCA temporal prior) settled **KILL (non-robust)** — and the *why* is two cross-cutting findings.

**(1) NCA's "bounded local change" stabilizes the wrong variable.** EMA leaky-integration on the continuous
pre-quantization cell-state reduced glyph churn **nowhere** (at fixed τ, churn is flat-or-worse as α
strengthens; on S2 it strictly worsens). All measured churn reduction came from the hysteresis deadband (a
debounce on the discrete pick), already achieved at α=1 (no EMA). Mechanism: glyph identity is an **argmax over
the quantized 60D log-polar basis** — smoothing upstream can't move the pick unless it crosses a Voronoi
boundary, which a slow source never does (no-op) and a fast source does the *wrong* way (EMA lag → locks a
wrong-but-stable glyph = freeze-trap, GMSD-vs-source +1.9–10.7%). Same log-polar-degeneracy family as ASTSK-31
/ ASTSK-35: operations upstream of the argmax don't transfer to the pick. Corollary already promoted: a
coherence prior must act on the **discrete decision with a source tether** (motion-adaptive hysteresis), not
the continuous state — filed as ASTSK-45.

**(2) Reusable instrument lesson — band-relative equivalence-bound (SESOI) deadband.** The gate's cross-oracle
agreement check (GMSD vs HaarPSI fidelity sign) used an *absolute* float-dust deadband (`1e-4`) and fired a
spurious `RERUN (instrument)` on a noise-floor sign split (0.09% / 0.26%, an order of magnitude under the
gate's own ±2% / −1% qualify bands). Fix (a NEW pre-registration committed before re-measuring): make the
deadband a per-oracle **equivalence bound = the gate's own decision tolerance** (the SESOI), so a sub-band
disagreement reads as "fidelity held," not instrument failure. Zero new free parameters; grounded in
equivalence-testing (Lakens 2017/2018; Bland–Altman LOA is the wrong tool — it needs a common scale, GMSD and
HaarPSI don't share one). The re-run reproduced every number byte-for-byte with only the verdict line changing
`RERUN → KILL` — proof the re-instrument changed the *instrument*, not the *measurement*.

Found in: ASTSK-41 settle (branch `astsk-41-nca-temporal-prior`, merged PR #56, merge `0091d7c`). Touches:
`Tools/AskiMotionLab/TemporalGate.swift` (oracle-sign check); spec §7.1
(the ASTSK-41 NCA-temporal-prior design spec); verdict note
`docs/Research/2026-06-29-astsk41-nca-temporal-prior.md`; the LogPolar descriptor argmax in `Sources/Aski/`.
Revisit if: (1) already promoted → **ASTSK-45** (motion-adaptive hysteresis). (2) if any other
dual-oracle gate (ASTSK-31 regime oracle; ASTSK-43 M1 + GMSD/HaarPSI) ever fires a noise-floor disagreement at
the float-dust floor, retrofit the band-relative SESOI deadband there.

## 2026-07-01 — ASTSK-45 KILL: fixed-tolerance glyph hysteresis is falsified BOTH ways; the slow/fast regime split, not the tolerance's reference, is the invariant killer

ASTSK-45 (source-tethered hysteresis) settled **KILL (non-robust)**. It tethered the hold to the **source**
(release when the held glyph's fit degrades past a fraction ρ of its first-appearance commit fit) — the
opposite of ASTSK-41's EMA and of its own τ predecessor (which tethered to the *challenger*). Three
cross-cutting findings:

**(1) The regime split is the invariant, not the reference.** ASTSK-41 (`τ`, relative-to-challenger) and
ASTSK-45 (`ρ`, source-tethered) hit the **same 2/4 non-robust wall**: any *scalar* tolerance that suppresses
S1 (slow) idle flicker at held fidelity washes out S2 (fast). Changing *what* the tolerance is measured
against (challenger → source) did not change the outcome — so fixed-tolerance glyph hysteresis is now
falsified both ways. The killer is the slow/fast motion split a single scalar can't span, exactly the
frontier-predicted risk (TAA scene-dependence).

**(2) "Real but non-generalizing" ≠ "inert".** Unlike ASTSK-41's EMA (which reduced churn *nowhere*), the
source-tether reduces churn **monotonically in ρ on both stimuli** (S1/64 0.0120→0.0014; S2/64 0.0630→0.0064).
It is a genuine mechanism that simply doesn't transfer across regimes: a clean win on S1 (all ρ qualify), a
washout on S2 (no ρ qualifies — GMSD +6–8% past band, HaarPSI −10–14% past band, drift ~0.27, the freeze-trap
triple). Even ρ=0 (release on any degradation) busts S2 fidelity: on a fast source the per-frame argmax is
already the best fit and the medium can't track the bar (baseline GMSD ~0.35), so *any* hold strictly worsens
the source match.

**(3) The commit-fit tolerance and the luma oracles decouple under large motion.** The spec disclosed that
B2's tether metric (`distance(held, source)`, 60D log-polar) and GMSD both measure held-vs-source, so a
GMSD-pass is "partly mechanical" — yet on S2 **GMSD busted anyway** (+7.7%), and HaarPSI busted with it,
*agreeing in sign* (no oracle-sign RERUN → clean KILL). Log-polar descriptor distance staying within ρ of
commit does **not** bound composited-luma fidelity once the source has moved substantially. Corollary
instrument: `meanDriftVsBaseline` alone separates coherence from washout before the fidelity oracles are
consulted (S2 drift ~0.27 vs S1 ~0.07 the instant the tether engages) — a cheap first-pass screen.

Found in: ASTSK-45 settle (branch `astsk-45-source-tethered-hysteresis`). Touches:
`Sources/Aski/Animation/ASCIIConverter+Temporal.swift` (`sourceTetherRho` / `lockDistance`, off-by-default);
`Tools/AskiMotionLab/SourceTetherGate.swift` + `SourceTetherExperiment.swift`; spec
the ASTSK-45 source-tethered-hysteresis design spec; verdict note
`docs/Research/2026-07-01-astsk45-source-tethered-hysteresis.md`. Revisit if: temporal coherence is
reopened — the only untried lever is an **explicit motion-adaptive ρ(v)** (per-cell velocity scaling the
tolerance, the TAA confidence-factor analog), which needs a motion estimator the pipeline lacks and carries
low post-1.0 ROI. NCA temporal line is now **0-for-3** (ASTSK-41 EMA / ASTSK-43 inter-cell / ASTSK-45
source-tether); ASTSK-42 (steerable channel) remains the one queued sibling and is a spatial/basis fork, not
temporal.

## 2026-07-06 — The descriptor line is dead, but differentiable joint optimization is the one evidence-backed rendering-model door left (parked post-M4)

A frontier-search sweep (workflow `wf_9a247d89-b64`, 2 frontier threads + adversarial verify) revisited the
fork the descriptor kills (ASTSK-31/35/41/42/43/45) left open: the team's frozen rule was "do not attempt
another orientation-channel variant without either a PERCEPTUAL (not reconstruction-GMSD) oracle OR a
rendering-model change." The sweep splits that fork cleanly.

**The one door that is genuinely open — a rendering-model change, NOT a descriptor channel.** `stong/gradscii-art`
(Jan 2026, ~253★) beats classical structure-ASCII by changing the *rendering model itself*: a soft-blend over
the whole glyph codebook (softmax weights + einsum compositing), temperature/Gumbel annealing to force
discreteness, a **learnable affine subpixel warp** that aligns content to the character grid and exploits
inter-row gaps for clean edges, and **joint whole-grid optimization** — degrees of freedom the
per-cell-independent nearest-neighbor argmax structurally cannot express. Critically it optimizes plain
MSE + multiscale + diversity, **not** a perceptual metric — which reframes the whole frozen fork: the ceiling
the kills hit is the *per-cell nearest-neighbor rendering model*, not GMSD-the-metric. That is why every
upstream channel/temporal knob failed to transfer to picks.

**Evidence is existence-proof grade, not quantitative** — compelling galleries + a principled mechanism, but NO
controlled benchmark vs classical and NO human-preference study. Cost is per-image gradient descent (default
~10k AdamW iters on GPU/MPS): a Metal/MPSGraph port is plausible for the STILL path (seconds/image, no trained
model or dataset to ship — fits no-SDK-ceremony / on-device), but heavy/questionable for video even with
temporal regularization. (Honesty note: this door-open claim is also the one whose adversarial-verify agent
returned a degenerate placeholder in the sweep, so it is the least-checked finding — non-blocking because it is
parked, but re-verify before any build.)

**The perceptual-oracle half of the fork is a cheap instrument, not the unlock.** LPIPS/DISTS are VGG/texture
metrics validated on natural-image restoration patches, unvalidated at the ~24px binary-glyph-vs-tone cell
scale; swapping GMSD→LPIPS as a *per-cell selection objective* is not expected to move picks. The cheap,
durable win is a human-preference / offline A-B *adjudication* instrument (break GMSD tunnel vision, score any
future rendering-model prototype against classical) — which is exactly the preset A/B lab now being
built for ASTSK-47.

Two verify corrections carried forward: the "neural classifiers are a closed door" reading of Coumar & Kingston
2025 (arXiv 2503.14375) is over-general (the paper shows *parity*, is about tile classification not Aski's
signal-processing hooks, and declines the dead-end framing); and "VLMs can't judge ASCII" (arXiv 2504.01589) is
scoped to *adversarial* semantic-visual-conflict recognition — current work (arXiv 2604.25235; 2602.06013)
shows VLM *pairwise* selection is reliable EXCEPT on fine-grained near-ties, which is exactly Aski's knob
regime. So a VLM A-B judge is usable for clearly-separated calls, untrustworthy for near-ties.

Found in: needle-mover frontier sweep, ahead of the preset freeze (ASTSK-47).
Touches: `Sources/Aski/ShapeMatching.swift`, `Sources/Aski/Algorithms/LogPolarKernel.swift` (the per-cell argmax
rendering model this would replace); `Tools/AskiColorLab/ShapeResidual/` (the battery any prototype scores
against); a future Metal/MPSGraph differentiable-render lab tool.
Revisit if: post-M4 signal reopens quality investment AND a still-path differentiable-joint-optimization
prototype (soft-blend + temperature anneal + learnable subpixel warp) clears the frozen shape-residual GMSD
battery AND a human-preference A-B on real portraits — the two-gate bar the descriptor line could never pass.
Reference impl: https://github.com/stong/gradscii-art.

## 2026-07-29 — Optimality-gap instrument: measure the selection ceiling before any more selection work

The 2026-07-29 frontier sweep (four parallel agents; product-expansion synthesis in session) surfaced a cheap
way to settle the *entire* selection-improvement family at once: use DiffVG-style differentiable optimization
(or exhaustive search at small grids) to find the loss-optimal glyph per cell under GMSD/MILO, then measure the
gap between the 60D descriptor's picks and the optimal picks, stratified by structure class (radial/diagonal
vs naturals vs line-art). This is a ceiling-*measurement* instrument, not a shipping path — distinct from (and
complementary to) the differentiable-joint-optimization rendering-model entry above: that one proposes a
replacement, this one asks whether any replacement could pay. Context: Coumar & Kingston (arXiv 2503.14375,
Mar 2025) found classical methods match CNNs at glyph selection, so the frontier already suspects selection is
near-ceiling; ASTSK-35's ρ-lift-that-didn't-transfer is consistent with a small gap.

Found in: 2026-07-29 frontier sweep (rendering-research agent), main-session synthesis.
Touches: `ShapeMatching.swift` (the argmax being measured); `Tools/AskiColorLab/ShapeResidual/` battery; lab-only.
Revisit if: any new selection-improvement idea (descriptor channel, rank-mix, learned scorer) is
proposed — run this instrument FIRST; if gap < ~3% aggregate, the proposal is dead on arrival and the whole
family is permanently deprioritized. Also promotable standalone as a one-session lab probe.

## 2026-07-29 — VLM subject-recognition oracle for semantic preservation (what GMSD can't see)

ASCIIEval (arXiv 2410.01733, v2 Sep 2025; 3K+ samples) shows machine recognition of ASCII art is measurable
and that proprietary models exceed 70% on some categories. Proposal: a lab-only oracle asking "does a VLM still
identify the subject/expression in the rendered output?" — measuring *semantic* preservation, which
GMSD/HaarPSI structurally cannot. Caveats from the record: feed rendered PNGs, not text (text-priority bias,
arXiv 2606.29649 — VLMs attend to character semantics over macro shape), and per the entry above, VLM judges
are untrustworthy on fine-grained near-ties — so adopt only where it discriminates pairs that GMSD ties AND
agrees with human eyeball ranking (the ASTSK-27 agreeing-oracles lesson).

Found in: 2026-07-29 frontier sweep (rendering-research agent) + cross-domain synthesis.
Touches: ASTSK-47 preset A/B corpus (first test bed); `Tools/` lab harness.
Revisit if: run over the ASTSK-47 corpus discriminates ≥1 GMSD-tied pair in agreement with human
ranking.

## 2026-07-29 — Lexical-interference hypothesis: letterforms may fight shape perception

Theory seed from the sweep: VLM text-priority bias (arXiv 2606.29649) may mirror a human effect — letterform
glyphs trigger a *reading* channel that competes with shape perception, while non-lexical glyphs (blocks,
braille) leave the shape channel unopposed. Prediction: at matched structural fidelity (matched GMSD), block
charsets beat letterform charsets on human/VLM subject-recognition. If true, it retroactively explains why the
ASTSK-47 preset freeze landed on blocks, and it makes charset choice a measured perceptual variable rather
than pure taste (with product consequences for charset packs).

Found in: 2026-07-29 frontier sweep (rendering-research agent theory seed T1).
Touches: `CharacterSets/`; ASTSK-47 corpus; the VLM oracle entry above (its natural instrument).
Revisit if: the VLM subject-recognition oracle is adopted (entry above) — this becomes its first
pre-registered hypothesis: recognition A/B across charsets at matched GMSD.

## 2026-07-29 — Detail-budget conservation: background glyph *poverty* may raise perceived subject quality

Theory seed: perceived portrait quality may be set by the *allocation* of glyph entropy, not total fidelity —
throttling charset richness in non-salient cells (flat backgrounds restricted to a 2–3 glyph subset) should
*increase* perceived subject quality even as aggregate GMSD worsens, because background glyph noise
perceptually masks the figure (the masking mechanism MILO models explicitly — arXiv 2509.01411, Sep 2025; same
structure/tone split as contrast-weighted-SSIM halftoning, arXiv 2304.12152). Nota bene: this predicts
preference and GMSD *disagree*, so the decisive run must be forced-choice human preference with the
GMSD-divergence pre-registered as expected, not a failure.

Found in: 2026-07-29 frontier sweep (rendering-research agent theory seed T2).
Touches: ASTSK-62 (saliency-budgeted grids — same mask, opposite lever: 62 adds detail inside, this removes
entropy outside; they compose); `CharacterSets/`; MILO audition below.
Revisit if: ASTSK-62's decisive run PASSES (the mask infrastructure then exists and this becomes a
cheap rider experiment); or MILO is auditioned and its masking term proves discriminative on Aski output.

## ~~2026-07-29 — Metric refresh audition: MILO + contrast-weighted SSIM as confidence check on the kill record~~ → promoted to ASKI-50

MILO (arXiv 2509.01411, Sep 2025): lightweight full-reference metric with an explicit visual-masking model,
usable as a differentiable loss. Cheap audition: re-run ONE archived decisive run (steerable channel,
ASTSK-42) under MILO and contrast-weighted SSIM. If verdicts hold, confidence in the kill record rises for the
cost of a re-score; if one flips, the oracle-agreement protocol fires (ASTSK-27 lesson: agreeing oracles or no
verdict). Instrument only — never a shipping dependency.

Found in: 2026-07-29 frontier sweep (rendering-research agent D6).
Touches: archived ASTSK-42 run artifacts; `Tools/AskiColorLab/ShapeResidual/` scoring battery.
Revisit if: any new decisive run is being designed (audition rides along free), or a spare
lab session wants a one-shot confidence check.

Executed 2026-09-04 under ASKI-50. The absent June pair artifacts were not
invented; a current exact-lattice ASTSK-42-style comparison was regenerated at
shipping 3/60 support and at a separate 48/60 comparator. MILO, CSSIM, MAE,
GMSD, and 1-HaarPSI all held the archived KILL in both regimes. Full record:
`docs/Research/2026-09-04-aski29-50-steerable-metric-replay.md`.

## ~~2026-08-19 — The shipped log-polar descriptor carries 2–3 of 60 bins, and every kill was measured at 48~~ → promoted to ASKI-26, ASKI-29

`ASCIIConverter.thumbnailMaxPixelSize` caps the thumbnail's longest side at `columns * oversample` and
`prepareConversion` takes an **integer** cell pitch, so for landscape and square sources
`cellWidth == oversample` *identically* — at the default (which is also the frozen canonical preset's value) `oversample: 2`,
every cell is exactly **2 source pixels wide**, on every image, at every column count.
`ShapeContext.histogram60` then admits a pixel only when `0.5 <= r <= min(w,h)/2`, which for a 2-px-wide
cell is `maxRadius == 1.0` and admits **2–3 pixels of 8**, reaching **2–3 of the 60 bins**. Since the
histogram L1-normalizes, the shipped "60D log-polar shape context" is a **1-to-2 parameter
vertical-asymmetry statistic**. A source-aspect sweep from 3:1 to 1:3, read back from the converter's own
resolved geometry, lands on the same **2×4** footprint for every aspect at `columns: 80` — the collapse is
not an artifact of one image shape. Cell-height parity flips *which* bins are reachable (even → radial
bin 4, angular {3,6,9}; odd → radial bin 0, angular {3,9}), making output quality a **discontinuous
function of the requested column count** — but measured, that flip is dense below 16 columns (5, 8, 10, 11,
13, 15) and **absent at 16 and above**, so it never fires at the frozen preset's 76. The candidate side
does not collapse: glyph descriptors are built on a **square 64×64** raster and average **27.94** non-zero
bins, so the matcher compares a 2–3-sparse query against dense candidates whose support the query is a
measure-zero subset of. Measured consequence: only **4–8 of 95** glyphs are ever emitted at default
settings.

The widest-blast-radius part is a **regime split**. `ShapeResidualCommand.noDownscaleOversample` raises
oversample until the converter stops thumbnailing (correct, so the oracle stays pixel-aligned) — which put
ASTSK-31 at `oversample 26` (25×56 cell, **48/60 bins**) and ASTSK-42 at `oversample 39` (38×85,
**48/60**). **Every decisive descriptor experiment characterized a 48-bin descriptor; the product ships a
2–3-bin one.** This does not reverse any verdict — a fully-supported baseline is the *harder* test for a
proposed channel — but it means the record contains no measurement of the configuration users get, and any
claim that "the log-polar basis is the bottleneck for Aski output" is unevidenced for the shipping path.

Two riders. (a) The anisotropy is a **divergence from the cited baseline**, not just a resolution issue:
`maxRadius` inscribes a disc in the *shorter* axis, admitting ~79% of the square glyph raster but ~39% of
a 1:2 cell and excluding the top and bottom quarters of every cell *entirely*. `ASCIICharacterSet.swift:8`
claims parity with Xu/Zhang/Wong SIGGRAPH 2010; the dimensionality matches but the sampling does not —
they tile **N** isotropic windows over a non-square cell (72 windows → 4320-D for 12×24) and pre-blur 7×7;
Aski uses **N = 1** and no pre-blur. (b) Sub-cell **lattice phase**, the other never-studied lattice
parameter, was swept (16 arms, full-pitch null arm derived from the converter's own cell pitch, identical
resample path per arm) and is a **KILL**: spread 0.38–1.24% against an 18.7–51.7% optimality gap on the
same corpus, i.e. 20–50× too small.

Found in: branch `research/selection-ceiling-and-grid-phase`, 2026-08-19.
Full write-up: `docs/Research/2026-08-19-sampling-lattice-support-collapse.md`.
Touches: `Sources/Aski/Algorithms/ShapeContext.swift`, `Sources/Aski/ASCIIConverter.swift`
(`thumbnailMaxPixelSize`, `prepareConversion`), `Sources/Aski/CharacterSets/RasterizedCharacterSet.swift`,
`Tools/AskiColorLab/ShapeResidual/ShapeResidualCommand.swift`; ASKI-25/26/29.
Revisit if: any new descriptor work is proposed — it must state which sampling regime it
measures, and a channel validated only at no-downscale oversample must be re-measured at
`oversample: 2` before any default change. Also fires if the column-parity discontinuity is ever seen as
a user-visible quality jump between adjacent column counts.

Executed 2026-09-04 under ASKI-29. At C80 the current exact shipping lattice is
2x4 with 3/60 bins, and all five registered metrics held ASTSK-42's KILL. The
current 3072-square 4...80 census finds parity transitions at 5, 6, 8, 9, 10,
12, 13, 14, 15, and 16, with none above 16. This replaces the old boundary
claim after ASKI-65; it does not rewrite the old lattice's measurements.

## ~~2026-08-19 — The selection optimality gap is large, and which term dominates INVERTS by charset~~ → promoted to ASKI-28, ASKI-30

The optimality-gap instrument proposed here on 2026-07-29 was finally built and run. Its pre-registered
rule — *"if gap < ~3% aggregate, the proposal is dead on arrival and the whole family is permanently
deprioritized"* — is **not triggered, but only narrowly on the dense sets**. Exhaustive per-cell census
over the full charset, scored by the record's own GMSD oracle and cross-checked by HaarPSI and MAE on the
`nasa-steerable-v1` naturals (columns 80, **8640 cells**, every cell): total gap **3.6–19%** on the dense
charsets and **52–327%** on the sparse shipping preset. What keeps selection open is the sparse preset the
product ships, **not** the dense sets the entire kill record was measured on — where, under the
luminance-aware oracle, the pre-registered rule very nearly fires.

The decomposition into *pool exclusion* (the optimum never entered the brightness pre-filter's candidate
pool) versus *ranking* (it was in the pool and the descriptor mis-ranked it) is the useful part, and it
**inverts by charset**, because `topK = 12 + round(density*24)` is **12** at the default density while
built-in glyph counts are diagonal 4, diamond 4, cross 5, blocks 8, dots 8, minimal 10, lines 12, mixed
12, standard 95, braille 256:

- **Dense sets — the pre-filter binds.** standard: gap 18.7% GMSD, of which **16.5 pts is pool
  exclusion**; the optimum is outside the pool in **58.5%** of cells. braille: gap 19.0%, **16.5 pts**
  pool, optimum in pool **37.3%** of the time. Under MAE both totals fall to **3.6–4.7%**.
- **Sparse sets — the pre-filter is a literal no-op**, `optInPool == 100%`, and the gap is **100%
  ranking**. This includes the ASTSK-47-frozen `blocks` preset, whose gap is the **largest measured** by an
  order of magnitude (51.7% GMSD / 327.4% HaarPSI / 61.8% MAE).

So the shipped configuration's entire gap sits in a ranker that — per the companion entry above — carries
2–3 descriptor bins. The two findings lock together. It also explains ASTSK-35's
"ρ-lift-that-didn't-transfer": a ranking signal can be genuinely informative and still fail to move picks
on a dense charset whose pool excludes the optimum three times in four.

**The sharpest consequence is a head-to-head, not a gap.** `findBestScored` prunes by brightness and then
takes `argmin` of shape distance *inside* the pool, with brightness surviving only as a tie-break in the
`(distance, brightnessDelta, index)` ordering — so when `topK >= glyphCount` the prune is a no-op and
**tone information is discarded at selection time**. Measured on the frozen `blocks` preset, a shape-free
floor picking purely by ink coverage (in the matcher's own polarity convention) **beats the real matcher
under all three oracles**: GMSD 0.20278 vs 0.33993 (40% better), MAE 0.24637 vs 0.56329 (2.3×), HaarPSI
0.38673 vs 0.09480 (4.1×, higher better). Under MAE the production pick averages rank **7.22 of 8** —
second worst available. Production wins on `standard` and `braille` by a *narrow* 0.6–3.2%, where the
pre-filter is still doing the tone work. This is a comparison of **two realizable selectors**, not a
selector against a metric's argmin, so it survives the oracle impeachment below. A third oracle also
splits the regimes: MAE cuts the dense-charset gap ~4× (standard 18.71% → 4.68%) but leaves the shipped
preset's at 62%, so most of the dense-set "headroom" is structure-metric luminance blindness and the
shipped-preset finding is not. Filed as ASKI-30 — the fix is a tone-weighted score, and the machinery
already exists (`occupancyMatching` applies `toneWeight = occupancyMatching * 50`).

Found in: branch `research/selection-ceiling-and-grid-phase`, 2026-08-19.
Full write-up: `docs/Research/2026-08-19-selection-optimality-gap.md`.
Touches: `Sources/Aski/ShapeMatching.swift` (`poolIndices`, `findBestScored`, `findBestOccupancyScored`),
`Sources/Aski/Algorithms/LogPolarKernel.swift` (`topK`), the canonical-preset type; ASKI-28, ASKI-30.
Revisit if: any selection-improvement idea is proposed — run `AskiColorLab selection-ceiling`
FIRST and read the charset-specific decomposition, because a pool-side fix is provably worthless on the
eight sparse built-ins and a ranking-side fix on the dense ones is competing for **2.26% GMSD, below the
+3.0% promotion bar** — i.e. unwinnable before it starts.

**Instrument correction, same day.** Every number above is a re-measurement. The first version of this
entry scored each glyph against an equal `rows × cols` partition of the native image rather than the
rectangle the converter actually sampled (the integer cell pitch leaves a bottom remainder unread; at the
shipping arm 10% of image height), and subsampled cells at one fixed lattice phase while calling the
aggregate a population mean. Both were caught by an automated code review of this branch, 2026-08-19. Correcting them cut the
dense-charset gaps 2–6×, grew the sparse-preset gap and the tone-only margin, and flipped §4's reading of
the kill record from "the gates were competing for two-thirds of the headroom" to "the gates were
unwinnable on their own terms." *Instrument lesson: a misregistration that accumulates with index is not
bounded by its per-step size — bound it at the last index, not the first. The first version listed this
very mechanism under "other limits," sized it at "≤ one cell row, ≈2.8%, does not affect comparability,"
and was wrong on both counts.*

## ~~2026-08-19 — The oracle that decided the descriptor kill record is ranked last of 11 as an objective~~ → promoted to ASKI-27

Every archived descriptor verdict (ASTSK-31/35/42) was decided by **per-cell GMSD** between the chosen
glyph raster and the source block, cross-checked by HaarPSI. A frontier sweep run alongside the
optimality-gap work found two primary results that impeach that instrument, and neither was in the record.
(1) **Ding, Ma, Wang & Simoncelli (IJCV 2021)** rank **GMSD last of 11** full-reference metrics used as an
*optimization objective* in a four-task human study, diagnosing it as **luminance-blind**; they find plain
**MAE** competitive and MS-SSIM's advantage over MAE statistically insignificant. Mechanistically, GMSD
pools by the **standard deviation** of the gradient-magnitude-similarity map, so a per-cell argmin rewards
*uniform mediocrity* over a glyph that is right across most of a cell and wrong in one corner — the wrong
preference for a medium where per-cell tone is half the signal. (2) **Xu, Zhang & Wong (SIGGRAPH 2010,
Fig. 7)** already demonstrated, for glyph selection specifically, that the loss-optimal pick under
alignment-sensitive full-reference metrics is *perceptually wrong* (SSIM and blurred-RMSE pick `=` for a
centred horizontal line where `-` is right). Two further cautions: **GMSD + HaarPSI is not a disjoint
pair** — both are gradient/wavelet structure metrics — and HaarPSI's pooling uses a **global denominator**,
so a per-cell argmax under it is not cleanly well-posed; and Aski's GMSD deliberately omits the canonical
2×2 mean filter and dyadic subsample, so the published correlation numbers do not transfer to this variant.

This does not retract any verdict. It does mean the kill record's central instrument has never been
validated for the job it was used for, and that the measured optimality gap should be read as *metric*
headroom until a luminance-aware oracle agrees. `AskiColorLab selection-ceiling` now runs MAE as a third,
separable, luminance-aware oracle for exactly this reason.

Found in: frontier sweep `wf_a94fb778-b6a`, branch `research/selection-ceiling-and-grid-phase`, 2026-08-19.
Touches: `Tools/AskiToolSupport/GMSD.swift`, `Tools/AskiToolSupport/HaarPSI.swift`,
`Tools/AskiColorLab/ShapeResidual/ProductionPathArm.swift`, `IsoluminantNoHarmGuard`; ASKI-27.
Revisit if: any new decisive run is designed — adopt the audited oracle first; and run the
reference-recovery disqualifier (when the source cell IS a rendered glyph, the oracle must make that glyph
the unique argmin at the scoring footprint) before trusting any metric as a per-cell objective.

## ~~2026-08-19 — The reference-recovery screen settles the oracle, and finds a rasterizer bottleneck under all of them~~ → promoted to ASKI-32

ASKI-27 ran the disqualifier the entry above asked for, and it separated the panel — but not where the
argument predicted. At the **scoring footprint itself**, with the resample an identity, **all five**
candidate oracles (GMSD, HaarPSI, MAE, RMSE, single-scale SSIM) recover every reference glyph on `blocks`,
`standard` and `braille`. Nothing is blind in the trivial sense. The split appears the moment the source
takes a trip through the converter's **own anisotropic cell block** with the rasterizer held fixed: MAE,
RMSE and SSIM stay perfect (8/8, 95/95, 256/256), while **GMSD loses the half-block pair `▄→▀`** — a pure
vertical position swap at identical ink, the textbook luminance-blind confusion — and 51 of 256 braille
glyphs, and HaarPSI loses 20 of 256. **MAE is now the house oracle; GMSD and HaarPSI are disqualified from
defining an optimum** (argmin/ceiling), though *not* from the A/B comparison of two realizable renderings
the archived kills actually made — which is why no verdict flips.

Three things worth carrying forward. **(a) The cost of luminance awareness is calibration sensitivity.**
On an arm whose source ink fraction is *not* calibrated against the candidate, MAE collapses to 7 of 256
(its worst confusion is `⣿→⠀`, a full braille cell read as blank) while the structure oracles are
near-invariant. So the house oracle carries a standing precondition: both sides in the matcher's ink-high
convention, rendered through the same path. **(b) `GlyphRaster` centres every glyph by its image bounds**
(`CTLineGetImageBounds`), which erases position-only distinctions before any oracle sees them — `▄` and `▀`
become the same centred bar, single-dot braille glyphs collapse together. All five oracles lose *the same*
~70 of 256 braille references on the fixed-aspect downscale arm, within a spread of 3. That is one
bottleneck upstream of the whole panel, and it bounds every lab result about position-sensitive charsets.
**(c) The default corpus is not the reported corpus.** `selection-ceiling` defaults to the 2048px
`nasa-structure-v1`, while the 2026-08-19 notes report the 3072px `nasa-steerable-v1`; the two disagree by
up to 10 gap points, and the dense-charset ranking headroom under the house oracle is 1.8–2.4% on one and
2.9–3.9% on the other — **straddling the +3.0% promotion bar**. The margin that re-read the kill record as
unwinnable is thinner than the difference between two corpora.

Found in: ASKI-27, branch `aski-27-house-oracle`, 2026-08-19 —
[house-oracle audit](2026-08-19-house-oracle-audit.md).
Touches: `Tools/AskiColorLab/SamplingLattice/ReferenceRecovery.swift`,
`Tools/AskiColorLab/SamplingLattice/SelectionCeiling.swift`, `Tools/AskiToolSupport/GlyphRaster.swift`.
Revisit if: a glyph-position-sensitive result is measured through `GlyphRaster` (bound it by (b) first);
or any gap figure is quoted without naming its corpus.

## 2026-08-27 — The house bar sits inside the perceptual ambiguity interval, and the rater sided with SSIM on the one recorded disagreement

The ASKI-56 arbiter's first validated run grounds MAE's *direction* (32/37 blinded
trials prefer the lower-MAE side, p ≈ 0) but not the 3.0% *bar*: the JND75 band in
the bar's own units (relative MAE margin) spans −0.345 to +0.072 — the bar sits
well inside the ambiguity interval, exactly the Cheon-et-al. shape the protocol
pre-registered. Separately, on the only oracle-disagreement case yet measured (the
ASKI-30 T-vs-F near-tie), the blinded owner's decided picks went 3-to-1 *against*
MAE, toward the side single-scale SSIM preferred by 0.09% — and the VLM judge
order-flipped on half those pairs. Small-n and non-gating, but it is the first
observation in this repo of a human tracking an SSIM disagreement that MAE calls
decisively the other way.

Found in: `docs/Research/2026-08-27-aski56-arbiter-verdict.md` (result store
`docs/Research/Results/2026-08-27-aski56-arbiter/`).
Touches: the §5.1 bar in `2026-08-24-aski-30-28-decisive-rule.md` (retained, arbiter
now required for promotion); ASKI-30 (still INCONCLUSIVE); ASKI-50 (metric refresh —
a D-focused arbiter run would give it a human anchor); ASKI-57 (exploratory-arm lift
must clear the arbiter, not just the bar).
Revisit if: a dedicated D-family run reaches decided n ≥ 30, or a future calibration
fit produces a positive JND75 lower edge (which re-arms the §5.3 near-tie clamp).

## 2026-08-28 — Engineering line-art is a distinct descriptor-collapse stratum, an order of magnitude below photographs

The ASKI-52/26 census geometry table, run over the newly reachable `nasa-occupancy-v1` corpus (unlocked by the JPEG loader fix in PR #32), shows the four engineering-diagram fixtures carrying 0.33–0.69 live bins of 60 at the shipping regime — versus ~3/60 for photographic content, which is already the ASKI-55 support-collapse regime. Sparse strokes on flat ground leave the 2×4 thumbnail cell almost entirely empty, so the shape term is effectively absent on exactly the content class ASCII art is classically best at. No Tools-side battery could see this stratum before the loader fix, so no archived verdict accounts for it.

Found in: ASKI-52/26 unit, PR #32, `docs/Research/Results/2026-08-28-aski52-26-convention-ablation/geometry.csv`
Touches: ASKI-55 (support collapse), ASKI-29 (kill records measured at 48/60 bins), corpus stratification for any future decisive run
Revisit if: ASKI-55's root-cause work lands a support fix — re-census the diagram fixtures; if live bins stay below 1/60 there while photographs recover, line art needs its own regime split rather than inheriting the photographic verdict.

## 2026-09-01 — The shape query is the only ink-low stage in an ink-high pipeline, and flipping it is the largest selection effect measured

Production's logPolar query has histogrammed 1 − luma since the first commit, so it treats dark source regions as ink, while the tone pre-filter, the candidate rasters and the renderer all treat bright as ink. Flipping only the query on the real converter moves blocks MAE 0.667 → 0.353 (+47%) on steerable and 0.657 → 0.396 (+40%) on occupancy, GMSD agreeing in sign — and it still died on the pre-registered collateral clause: occupancy braille −3.26% MAE / −17.5% GMSD, past the 3.0% veto. The charset dependence is mechanical: the tone pre-filter admits topK 12 and blocks carries 8 glyphs, so blocks is the only charset whose prune excludes nothing and whose shape term ranks the whole set. `shapeQueryPolarity` ships SPI-only, `.inverted`; no default moved.

Found in: ASKI-60, PR #34, `docs/Research/2026-09-01-aski60-shape-query-polarity.md`
Touches: ASKI-61 (per-charset polarity), ASKI-62 (arbiter v2 converter-level arms), ASKI-55 (support collapse — the blocks gain is bounded by the same 2–3 live bins)
Revisit if: ASKI-61 finds the braille regression is a root-causable defect rather than a real convention preference — then a per-charset map (direct on blocks, inverted elsewhere) becomes a promotion candidate that needs an ASKI-62 sitting.
