---
title: "C1 algorithmic animation — design research notes"
slug: 2026-05-10-c1-animation-design-decisions
date: 2026-05-10
status: complete
subsystem: [animation]
summary: "Thirteen frontier surveys (three deep-tier dispatches) behind C1's algorithmic-animation choices: a hybrid lazy synthesizer, a top-K visually-similar candidate pool, an entrance-versus-ongoing pattern split, a pure-data SoA schedule for Swift 6 strict concurrency, a match-to-CellMatchResult kernel API, a method on ASCIIConverter over a separate type, an optional-fields struct over a fluent builder, and a stateless SplitMix64 keyed on seed, row, col, and salt."
---

# C1 algorithmic animation — design research notes

> Companion to the C1 animation design spec (not published). Captures the field surveys that informed each load-bearing C1 decision before the spec was hardened. Eleven frontier-search threads (three of them deep-tier subagent dispatches) over the course of the brainstorming session.

## Question

C1 adds time-based algorithmic animation to Aski: per-cell character cycling among visually similar candidates, plus optional `entrance` (cascade, reveal) and `ongoing` (wave, pulse) motion patterns. The output is a `Sendable` `AnimatedASCIIGrid` whose `grid(at: TimeInterval)` synthesizes per-frame `ASCIIGrid` values for SwiftUI `TimelineView` and (future) GIF/MP4 export. Before locking the data shape, the candidate-selection model, the API surface, and the implementation contract, we ran frontier-search across the Swift / animation ecosystem in 2026 to ground the choices in current practice. This file records what the field says, what Aski picked, and where the field signal pushed against the initial intuition.

---

## 1. Animated-value data shape — lazy synthesizer vs. materialized array vs. hybrid

**What the field says.** The dominant 2026 pattern across SwiftUI, Lottie iOS, and Rive iOS is **separate the animated value from the renderer; synthesize frames on demand**:

- **SwiftUI `TimelineView` + `Canvas`** is the canonical per-frame-animation idiom; effectively replaces `CADisplayLink` for SwiftUI consumers. The `.animation` schedule hands a `Date` to the view body and you draw what's needed at that time — no pre-buffered frames ([Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-custom-animated-drawings-with-timelineview-and-canvas), [Swift with Majid](https://swiftwithmajid.com/2022/05/18/mastering-timelineview-in-swiftui/)).
- **Lottie iOS 4.0+** explicitly splits `LottieAnimation` (immutable model deserialized once) from `LottieAnimationView` (renderer); time exposed as Frame/Progress/Seconds, frames synthesized at render time. Their Core Animation engine win came from getting per-frame work *out* of the JS-style "do work in a closure on the main thread" pattern ([airbnb/lottie-ios](https://github.com/airbnb/lottie-ios)).
- **Rive iOS** mirrors the split via MVVM (`RiveViewModel` ↔ `RiveView`); declarative state machines + runtime that synthesizes per-frame ([rive-app/rive-ios](https://github.com/rive-app/rive-ios), recent commits 2026-05).
- **AVAssetWriter** (future C2) is agnostic — it pulls frames in presentation-time order, so a lazy synthesizer iterated at target fps works as well as a frame array ([img.ly tutorial](https://img.ly/blog/how-to-make-videos-from-still-images-with-avfoundation-and-swift/)).

Memory math: 80×40 cells × 60fps × 5s ≈ 5.4M `ASCIICell` values pre-rendered; ~36 bytes/cell → ~190MB worst case. Lazy synthesis is constant memory.

**What we picked.** **Hybrid** — `AnimatedASCIIGrid` is a lazy synthesizer (`grid(at: TimeInterval)`) by default, with an opt-in `materialize(frameRate:) -> [ASCIIGrid]` for callers that need a frame array (snapshot tests, future GIF/MP4 export). The schedule is pure data (no captured closures) so the value type is trivially `Sendable` under Swift 6 strict concurrency. Native fit for `TimelineView`, constant memory, no API churn when C2 lands.

---

## 2. Cycling candidate pool — top-K visually similar vs. uniform random

**What the field says.** Three reinforcing signals all point to similarity-aware substitution:

- **Xu / Zhang / Wong (CUHK 2010)** — Aski's algorithmic ancestor — explicitly identifies *temporal consistency* as the open problem in animated ASCII. Top-K candidates from the same shape neighborhood produce that consistency by construction. Random substitution does the opposite.
- **Glitch-text effects** (the closest production analog to per-cell cycling) are unanimous: "character replacement prioritizes visual similarity, ensuring that corrupted text maintains recognizable shapes and proportions of original characters through predefined character mapping tables" ([glitchtexteffect.com](https://glitchtexteffect.com/content/glitch-text-translator)). Multiple substitution generators ship Cyrillic / Greek look-alike tables. Uniform random isn't the standard; it's the lazy fallback.
- **Practical animated-ASCII tools** report flicker as the central engineering problem. GitHub Copilot CLI's banner uses semantic role-based color mapping with frame-by-frame *content* changes over ~20 frames at 75-80ms per frame; ASCII Motion (Feb 2026, actively maintained) and DurDraw track object movements to *avoid* flicker — the very problem uniform random produces.

**A second look at the surveyed browser tools' UI** showed candidate-pool selection exposed as a discrete checkbox under a Characters section, separate from the animation panel. That UX treats pool selection as a discrete choice and reserves `randomness` for *timing jitter*.

**What we picked.** **Top-K visually similar only** in v1 — extends `ShapeMatching.findRanked(...)` to expose the existing log-polar prefilter results (today only the winner is returned). K defaults to 6, clamped to charset size. A `.uniform` pool can be added later if a caller asks; the optional-pool was rejected because it conflated two orthogonal axes and made `randomness` ambiguous.

The original second-question framing offered a continuous `randomness` blend between top-K and uniform. The research showed that's a documentation tax with no clear win, and no surveyed tool does it that way.

---

## 3. Motion pattern API shape — split `entrance` + `ongoing` vs. flat enum

**What the field says.** Every major animation library splits *intro / once* from *loop / ongoing* at the API level:

- **Framer Motion** — `initial` (entrance) vs. `animate` (ongoing) is its flagship API choice ([motion.dev](https://motion.dev/), [Semaphore comparison](https://semaphore.io/blog/react-framer-motion-gsap)).
- **SwiftUI** itself splits these: `AnyTransition` for entrance/exit, `Animation` for ongoing. `AnyTransition.asymmetric(insertion:removal:)` exists precisely because the phases differ ([SwiftUI Lab](https://swiftui-lab.com/advanced-transitions/), [objc.io transitions](https://www.objc.io/blog/2022/04/14/transitions/)).
- **Rive state machines** — `Entry → Idle` is architecturally distinct: Entry is "lifecycle marker, initialization"; Idle is "holding state where animation waits" ([Rive State Machine guide](https://rive.app/blog/how-state-machines-work-in-rive)).
- **CSS** supports comma-separated multiple animations exactly so entrance + idle can compose; **After Effects** treats "idle / breathing" as a distinct conceptual class.

The prevailing browser-tool convention is a single flat enum (Wave / Cascade L→R / Cascade R→L / Cascade T→B / Reveal / Pulse) that lumps both kinds together. Consumers learn per-case semantics; invalid combinations are representable (no way to express that "reveal" doesn't loop while "pulse" does).

**What we picked.** **Two-slot split**: `entrance: EntrancePattern?` + `ongoing: OngoingPattern?` on `AnimationOptions`. Either, both, or neither. Cycling runs underneath both. Honest semantics; documentation simplifies; future patterns slot into the right axis. Goes against the flat-enum UI convention but matches every comparable Swift-native library.

---

## 4. Schedule storage — pure-data SoA vs. closures-per-cell

**What the field says.** Three reinforcing signals push hard toward pure-data, struct-of-arrays layout:

- **Swift 6 strict concurrency** explicitly prefers value types for cross-isolation safety ([Apple Sendable docs](https://developer.apple.com/documentation/Swift/Sendable), [Hacking with Swift Sendable](https://www.hackingwithswift.com/swift/5.5/sendable)). Closures-per-cell is *the exact* shape Swift 6 wants you to avoid where pure-data is available.
- **Closures hit a heap-allocation cliff.** [SwiftRocks: "Memory Management and Performance of Value Types"](https://swiftrocks.com/memory-management-and-performance-of-value-types) — "if your value type recursively contains a reference type (remember that closures are also reference types), then it will require heap allocation." A 100×60 grid with closures-per-cell = 6,000 heap allocations on construction.
- **ECS / SoA particle-system literature** is unequivocal. Components storing animation state in contiguous arrays with batch-processed evaluation deliver "12× faster animation processing time vs. per-character object-oriented approaches" ([Number Analytics ECS deep dive](https://www.numberanalytics.com/blog/ecs-in-game-development-deep-dive), [Generalist Programmer DOD guide](https://generalistprogrammer.com/tutorials/data-oriented-design-games-complete-architecture-guide)). Particle systems specifically — the W·H "particles, each evaluated per-frame" analog — universally use SoA.

Lottie 4.0's perf gains came from a comparable shift away from main-thread-closure-per-frame work toward a declarative model evaluated by a dedicated runtime.

**What we picked.** Per-cell record array of pure data, **physically struct-of-arrays** for cache locality:

```swift
struct AnimationSchedule: Sendable {
    let candidates: ContiguousArray<UInt16>  // length W·H·candidateStride, K-strided
    let candidateStride: Int                  // resolved K
    let phases: ContiguousArray<Float>       // length W·H
    let periods: ContiguousArray<Float>      // length W·H
    let participates: BitSet                 // length W·H bits
    // + global pattern / duration / seed metadata
}
```

`UInt16` candidate index ceiling supports rasterized custom charsets up to 65,535 entries; precondition'd at `animate()` entry. K-stride is winner-padded when the kernel returns fewer than K candidates (non-`.logPolar` algorithms always return one), so `candidates[i * K]` is always a valid winner index.

---

## 5. Per-cell color behavior during cycling — fixed vs. variable

**What the field says.** Color stays constant; only the character cycles. This is the dominant pattern across:

- **GitHub Copilot CLI banner** ([engineering blog](https://github.blog/engineering/from-pixels-to-characters-the-engineering-behind-github-copilot-clis-animated-ascii-banner/)) — semantic role-based ANSI colors fixed per character role; frame-by-frame *content* changes only.
- **ASCII Motion / DurDraw** — both support per-frame color independently via timeline keyframes, but the default workflow treats color as a stable property of a cell while character candidates cycle.
- **Glitch-text effects** — base color held constant; only the glyph substitutes.
- **Academic pattern** — color is derived once from source-pixel chroma; the cell's character set cycles through brightness-matched glyphs.

The browser tools' color modes (color dodge, screen) are *post-processing effects* on static colorization, not per-frame character-color pairs.

**What we picked.** Color is fixed at cell initialization (from the matched winner / source pixel); only the *character* cycles per frame. Per-frame color variation is out of scope for v1.

---

## 6. Alpha composition combinator — multiplicative vs. min/screen/additive

**What the field says.** **Multiplicative composition (`final = base × entrance × ongoing × coverage`) is the canonical standard** across production systems:

- **Alpha-compositing literature** — [Bartosz Ciechanowski "Alpha Compositing" (2023)](https://ciechanow.ski/alpha-compositing/), [W3C Compositing and Blending Level 1](https://www.w3.org/TR/compositing-1/) — confirms transparency values compose multiplicatively; multiple sequential transparent layers multiply, mirroring physics of light transmission.
- **CSS `animation-composition`** ([MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/animation-composition)) offers `replace`, `add`, `accumulate` for property animations. For opacity specifically, the relevant modes implement the same multiplicative semantics.
- **SwiftUI Core Animation** uses `CompositingGroup` + "Group Opacity" flag to apply a single opacity to all descendants before rendering — premultiplied alpha by default.
- **Lottie / Rive / After Effects** all handle opacity per-layer with multiplicative composition at the layer boundary ([Lottie blend modes wiki](https://github.com/airbnb/lottie-web/wiki/Blend-Modes), [Rive animation mixing](https://help.rive.app/editor/animate-mode/animation-mixing)).

Hardware-efficient (single multiply per channel), predictable, no surprising non-linear behavior at boundaries.

**What we picked.** Multiplicative: `final_alpha = base_alpha × entrance_alpha × ongoing_alpha`. Mask `coverage` is **not** baked into `cellAlpha` — it is carried unchanged on the synthesized cell because the renderer (`Sources/Aski/Renderers/ImageRenderer.swift:66`) already does `cell.alpha * cell.coverage` at draw time. Baking it in here would multiply twice. Pattern alphas are clamped to `[0, 1]` after evaluation as defense-in-depth. (This was the bug a code review caught after the first spec draft.)

---

## 7. Cycle progress model — continuous fract vs. discrete steps with hold

**What the field says.** Evidence splits by domain:

- **Particle / sprite flipbook systems** (Unity, Unreal, Defold) use discrete step timing (`animation-timing-function: steps(K)`) with explicit per-frame hold durations. No cross-fade between glyphs; the "pop" is the expected aesthetic ([Unity Texture Sheet Animation](https://docs.unity3d.com/Manual/PartSysTexSheetAnimModule.html)).
- **Professional animation** (After Effects, Rive, Lottie) uses keyframe-based explicit timing per candidate.
- **Real-time procedural** (glitch-text, Claude's spinner) is frame-based with deterministic phase offsets per cell, advancing at a fixed tick rate (~75-80ms).
- **CSS `steps()`** ([MDN animation-timing-function](https://developer.mozilla.org/en-US/docs/Web/CSS/animation-timing-function)) and Unity flipbook docs both confirm: discrete hold per frame is the baseline; cross-fading between character glyphs is rare (would require intermediate glyphs, defeating the "sharp ASCII" aesthetic).

**What we picked.** **Continuous progress, discrete display**:

```
cycleProgress  = ((t + phase) / period).truncatingRemainder(dividingBy: 1.0)
candidateIdx   = floor(cycleProgress * K) clamped to [0, K-1]
```

Each candidate visible for `period / K` seconds. Stateless per cell, smooth time axis, deterministic from `(seed, row, col)`. Phase offset blends position-correlated (`(row + col) * 0.05` at randomness=0) and uniform random (at randomness=1) so users get coordinated shimmer at one extreme and independent flicker at the other. No easing between glyphs — the pop is the style.

---

## 8. API entry point — method on `ASCIIConverter` vs. separate `AnimatedASCIIConverter`

**What the field says.** A deep-tier subagent recommended a separate `AnimatedASCIIConverter` peer type, citing swift-collections (Deque / OrderedSet / OrderedDictionary as separate root types) and Lottie iOS (UIKit vs. SwiftUI views as separate types). The Swift API Design Guidelines were also referenced.

**Why we pushed back.** The agent's analogies don't fit:

- swift-collections types aren't "static vs. animated" *versions* of the same operation — they're entirely different data structures.
- Lottie's split is *renderer per UI framework*, not converter per output mode.

Closer Apple-framework analogs when one configured pipeline produces multiple output modes:

- `URLSession.dataTask` vs. `downloadTask` — methods on the same configured object.
- `CIFilter` — one type, many parameter sets and output methods.
- `AVAssetExportSession` — one configured object with multiple output methods.

`ASCIIConverter` is the configured shape-matching pipeline (charset, palette, algorithm, tile shape, rendering options). Animation is a temporal layer over the same matched cells — same charset, same palette, same brightness/contrast. Forcing callers to duplicate configuration across two converter types just to add a duration parameter is poor ergonomics.

**What we picked.** **Method on `ASCIIConverter`**: `animate(_:columns:options:mask:) -> AnimatedASCIIGrid`. Mirrors the existing `convert(_:columns:mask:)` shape.

---

## 9. Configuration combinator — optional-fields struct vs. fluent builder

**What the field says.** A deep-tier subagent recommended fluent `.withCycling().withEntrance().withOngoing()` chaining, citing SwiftUI Charts modifier chains, ViewModifier composition, and Vapor's Fluent ORM.

**Why we pushed back.** Those are *view composition* and *query composition* APIs that build AST nodes. We're configuring a one-shot computational operation; the Apple-framework analog isn't view trees. Apple's pattern for *configuration of an immutable operation* is struct/class with properties:

- `URLSessionConfiguration` — properties.
- `URLComponents` — properties.
- SwiftUI's own `Animation` enum — associated values, not fluent.
- `AVPlayerItem` configuration — properties.
- `CIRAWFilter` parameters — properties.

A `withCycling()` method exists *only to set one field*. There's no chain to compose — each axis is one assignment. Fluent builders earn their keep when chains build something hierarchical (View, Query, AST). They don't here.

The optional-fields struct also matches every other configuration type in Aski (`RenderingOptions`, `CompositionOptions`, `MaskOptions`, `LightingOptions`, `EffectChain`). Switching styles for animation alone would be a discontinuity.

**What we picked.** **Optional-fields struct** — `AnimationOptions { duration; seed; cycling: CyclingOptions?; entrance: EntrancePattern?; ongoing: OngoingPattern? }`.

---

## 10. SwiftUI dependency stance — owned `UnitPoint` vs. `SwiftUI.UnitPoint`

**What the field says.** **SE-0409 (Access Levels on Imports, Swift 6.0+, 2024)** is the defining ecosystem shift. Best practice is to mark utility-package SwiftUI imports `internal import SwiftUI` to prevent accidental public-API creep. Swift Forums consensus (2025): "For utility packages, avoid exposing SwiftUI as part of your public API unless it's the core product."

Verified across the leading utility packages:

- **swift-collections, swift-algorithms, swift-dependencies** — all avoid SwiftUI in public API, even with iOS 16+ targets.
- **Lottie iOS, rive-ios, swift-dependencies** — define their own configuration types; do not re-use `SwiftUI.UnitPoint` publicly.

Compile/link cost is minimal (SwiftUI is linked anyway on iOS 13+ apps). The real cost is API surface pollution — once SwiftUI is in the public API, future SwiftUI changes can break consumers.

**What we picked.** **Owned `UnitPoint`** (Sendable, `x: Double`, `y: Double`, [0, 1]², ~10 lines of code). Used for `EntrancePattern.reveal(origin:)`. No SwiftUI import in the public surface.

---

## 11. Deterministic per-cell randomness — stateless hash vs. stateful RNG

**What the field says.** Strong consensus across communities favors **stateless hash functions** for per-cell / per-entity deterministic generation, especially in graphics and animation:

- **Swift stdlib has no built-in seedable PRNG** ([Swift Forums consensus](https://forums.swift.org/t/deterministic-randomness-in-swift/20835)). Community solutions (Xoroshiro256, PCG, [SwiftWyhash by lemire](https://github.com/lemire/SwiftWyhash)) implement custom `RandomNumberGenerator` or stateless hash.
- **GPU / shader practice** is universal: Metal shader implementations use stateless hash (`fract(sin(dot(...)))`, lowbias32) for per-pixel noise, not stateful generators ([The Book of Shaders, Chapter 10](https://thebookofshaders.com/10/), [Inferno Metal library](https://github.com/twostraws/Inferno)).
- **GameplayKit** (Apple) provides `GKRandomSource` subclasses for game RNG — but the Swift Forums thread above flags this as "overkill" for non-game contexts.
- **Order-independence**: stateless `(seed, row, col) → value` is trivially parallelizable across cells; useful if schedule build ever moves off the calling thread.

**What we picked.** **SplitMix64 keyed on `(seed, row, col, salt)`**. SplitMix64 is well-known, patent-free, and ~5 lines. A salt enum (`.phaseSalt`, `.periodSalt`, `.intensitySalt`) keeps the three independent random streams uncorrelated. Pure function, order-independent, schedule-build parallelizable in the future without API change.

---

## 12. Validation strategy — precondition vs. throws vs. clamp

**What the field says.** Swift API practice **splits on intent**, not uniformly:

- **Swift API Design Guidelines** ([swift.org](https://www.swift.org/documentation/api-design-guidelines/)), **Swift Forums Parameter Validation** ([forums.swift.org](https://forums.swift.org/t/parameter-validation/236)) — precondition for invariants ("must always be true"), throws for "valid runtime error conditions" from untrusted sources, assertions for bugs.
- **Apple Foundation idiom** — assertions/preconditions for invalid parameter combos. One Swift Forums expert: "passing an invalid parameter value is a bug."
- **Animation framework silence** — SwiftUI `Animation` and `TimelineView` do not publicly validate frame-rate or duration out-of-range; they silently clamp or default. Lottie and Rive handle out-of-range gracefully without throwing.

**What we picked.** Mixed strategy:

- **Precondition** for programmer-invariant inputs that must be finite and positive: `duration`, `cycling.speed`, `wave.frequency`, `pulse.period`. NaN and `±∞` both fail. Precondition for `cycling.k > 0`, `materialize.frameRate > 0`, `1 ≤ characterSet.count ≤ UInt16.max`.
- **Clamp** for soft user knobs: `cycling.intensity` and `randomness` to `[0, 1]`, `wave.amplitude` to `[0, 0.5]`, `pulse.depth` to `[0, 1]`. NaN soft-knob values map to the parameter's default.
- **Clamp** for temporal coordinates: non-finite `t` (NaN, +∞, -∞) clamped to `0`; finite `t > duration` continues (entrance completed, ongoing loops, cycling continues).
- **Empty grid**: `columns ≤ 0` matches `convert()` behavior (returns empty `AnimatedASCIIGrid`), not a precondition.

This split matches Apple animation frameworks and avoids `try`/`catch` overhead at every `TimelineView` tick.

---

## 13. Synchronous vs. async schedule construction

**What the field says.** 2024-2026 Apple framework practice **defaults to sync for bounded CPU work**, async only where I/O, blocking, or user-cancellation matters:

- **Vision Framework modernization** ([WWDC 2024 session 10163](https://developer.apple.com/videos/play/wwdc2024/10163/)) migrated request handlers to async/await for expensive ML; Core Image filters remain synchronous.
- **Metal / GPU filter packages** — [Harbeth (200+ filters, MIT, actively maintained)](https://github.com/yangKJ/Harbeth) and [BBMetalImage](https://github.com/Silence-GitHub/BBMetalImage) both offer sync as the primary path; async overloads where backpressure matters.
- **Swift 6.2 isolation model** ([newsletter.mobileengineer.io 2025](https://newsletter.mobileengineer.io/p/swift-62-default-concurrency-isolation-and-concurrent)) introduced single-threaded-by-default; async became a deliberate opt-in.

Aski's schedule construction is O(W·H·K) ≈ 60K SIMD operations for typical grids — same magnitude as the existing synchronous `convert()`, smaller than Vision ML tasks.

**What we picked.** `animate()` is **synchronous**. Schedule construction matches the existing `convert()` magnitude. `materialize(frameRate:)` is also sync in v1 (typical case is ~100 frames; for very long animations callers wrap in `Task`). Cancellation surfaces on the consumer side, not in the API. CLAUDE.md's "introduce async/cancellable seams where cheap" is satisfied — sync is exactly what "cheap" looks like at this scale.

---

## Where we disagreed with the deep-tier subagent

Two of the seven deep-tier recommendations did not survive the analogy check. Recording them here so the disagreement and reasoning are preserved:

- **Q8 (entry point)** — agent recommended a separate `AnimatedASCIIConverter` type. We kept the method on `ASCIIConverter`. Agent's analogy (swift-collections, Lottie split) didn't fit "static vs. animated output mode of one configured pipeline"; closer analogs are `URLSession.dataTask` / `downloadTask` and `CIFilter` parameter-set + multiple output methods.
- **Q9 (configuration combinator)** — agent recommended fluent `.withCycling()` chaining, citing SwiftUI Charts and Vapor Fluent. We kept the optional-fields struct. SwiftUI Charts and ViewModifier are *view composition* APIs that build AST nodes; we're configuring a one-shot computation. Apple's pattern for that (`URLSessionConfiguration`, `URLComponents`, `AVPlayerItem`, `CIRAWFilter`) is struct-with-properties.

The remaining nine recommendations from the agents and the inline standard-tier searches went into the spec as proposed.

---

## What changed in the spec under code review

The spec went through five rounds of review with the user catching real bugs that needed real design fixes — captured here so the failure modes don't recur:

1. **Round 1**: candidates can't be derived from `convert() + findRanked()` because `ASCIIGrid` doesn't retain the per-cell query lanes. Mask coverage was applied twice. `findRanked` conflated brightness-prefilter width with returned count. → Internal `convertWithRankedCandidates` single-pass path; coverage carried unchanged on the synthesized cell; split `findRanked(brightnessLimit:resultLimit:)`.
2. **Round 2**: `AlgorithmKernel.rankedCandidates` default was unimplementable (`score` returns `Character`, no index path; default re-invocation would corrupt `DotMatrixKernel`'s Floyd-Steinberg buffer). Variable-length candidate lists vs. fixed K-stride. → Replace `score` with `match(...) -> CellMatchResult` (one call per cell, returns winner + ranked indices); winner-pad short lists; gate `participates` on effective K ≥ 2.
3. **Round 3**: cycling timing was under-specified (no formula for `period` jitter or phase blending). Candidate lookup pseudocode missed the `i * K` offset and the `CharacterSetSnapshot` resolution. `findRanked` tie-breaker not specified. → Concrete timing formulas (`basePeriod = 1/speed`, ±25% jitter scaled by `randomness`, position+random phase blend); pseudocode rewritten with explicit indices; stable ordering `(shapeDistance, brightnessDelta, index)` matches existing `findBest` first-seen-wins.
4. **Round 4**: schedule didn't store the resolved K stride. NaN / `±∞` slipped past `≤ 0` checks. `UInt16` ceiling lacked an explicit precondition. Spec wrongly claimed `columns ≤ 0` was preconditioned in `convert()`. → Added `candidateStride: Int` field; `value.isFinite && value > 0` for invariants; explicit `1 ≤ count ≤ UInt16.max` precondition; matched `convert()`'s empty-grid behavior.
5. **Round 5**: `findRanked` missing `brightnessLimit > 0` / `resultLimit > 0` preconditions. `grid(at: .infinity)` undefined (`truncatingRemainder` of `±∞` produces NaN, then `Int(floor(NaN))` traps). Empty charset deferred to "matcher precondition" but K-stride slot 0 indexes the snapshot directly. → Explicit preconditions on `findRanked`; non-finite `t` clamped to 0 in `grid(at:)`; lower bound of 1 enforced at `animate()` entry.

The pattern: research-backed architectural choices held up; the gaps were always at the integration seams between Aski's existing pipeline (`ASCIIGrid` doesn't retain query lanes; renderer applies coverage; `DotMatrixKernel` mutates state) and the new animation layer. Worth remembering for future subsystems.

---

## Sources

### Animation API patterns

- SwiftUI `TimelineView` — [Apple Developer documentation](https://developer.apple.com/documentation/swiftui/timelineview), [Hacking with Swift tutorial](https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-custom-animated-drawings-with-timelineview-and-canvas), [Swift with Majid](https://swiftwithmajid.com/2022/05/18/mastering-timelineview-in-swiftui/), [SwiftUI Lab Part 4](https://swiftui-lab.com/swiftui-animations-part4/).
- airbnb / lottie-ios — [GitHub](https://github.com/airbnb/lottie-ios), [Lottie blend modes wiki](https://github.com/airbnb/lottie-web/wiki/Blend-Modes). Active in 2026.
- rive-app / rive-ios — [GitHub](https://github.com/rive-app/rive-ios), [State Machine guide](https://rive.app/blog/how-state-machines-work-in-rive), [Animation Mixing](https://help.rive.app/editor/animate-mode/animation-mixing). Active in 2026.
- Framer Motion — [motion.dev](https://motion.dev/), [Semaphore comparison](https://semaphore.io/blog/react-framer-motion-gsap), [GSAP vs Motion](https://motion.dev/docs/gsap-vs-motion).
- W3C Compositing and Blending Level 1 — [w3.org/TR/compositing-1](https://www.w3.org/TR/compositing-1/).
- CSS `animation-composition` — [MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/animation-composition).
- CSS `animation-timing-function: steps()` — [MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/animation-timing-function).
- Bartosz Ciechanowski, "Alpha Compositing" — [ciechanow.ski](https://ciechanow.ski/alpha-compositing/).

### Algorithmic foundations

- Xu, Zhang, Wong (CUHK 2010), "Structure-based ASCII Art" — [PDF](https://ttwong12.github.io/papers/asciiart/asciiart.pdf). Foundational log-polar shape-context paper.
- Coumar & Kingston (arXiv 2503.14375, March 2025) — "Evaluating Machine Learning Approaches for ASCII Art Generation" — [arXiv](https://arxiv.org/html/2503.14375v1).
- ASCII Motion — [ascii-motion.app](https://ascii-motion.app/), [GitHub CameronFoxly/Ascii-Motion](https://github.com/CameronFoxly/Ascii-Motion). Active 2026.
- DurDraw — [GitHub cmang/durdraw](https://github.com/cmang/durdraw). Active 2025.
- GitHub Copilot CLI ASCII banner engineering — [github.blog](https://github.blog/engineering/from-pixels-to-characters-the-engineering-behind-github-copilot-clis-animated-ascii-banner/).
- Glitch text generators (similarity-aware substitution) — [glitchtexteffect.com](https://glitchtexteffect.com/content/glitch-text-translator).

### Swift / API design

- Swift API Design Guidelines — [swift.org](https://www.swift.org/documentation/api-design-guidelines/).
- SE-0409 Access Levels on Imports — [swift-evolution](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md).
- SE-0023 API Design Guidelines — [swift-evolution](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0023-api-guidelines.md).
- Swift Forums "Deterministic randomness in Swift" — [forums.swift.org](https://forums.swift.org/t/deterministic-randomness-in-swift/20835).
- Swift Forums "Parameter Validation" — [forums.swift.org](https://forums.swift.org/t/parameter-validation/236).
- SwiftRocks "Memory Management and Performance of Value Types" — [swiftrocks.com](https://swiftrocks.com/memory-management-and-performance-of-value-types).
- Apple `Sendable` documentation — [Apple Developer](https://developer.apple.com/documentation/swift/sendable).
- Hacking with Swift `Sendable` — [hackingwithswift.com](https://www.hackingwithswift.com/swift/5.5/sendable).
- Adopting strict concurrency in Swift 6 apps — [Apple Developer](https://developer.apple.com/documentation/swift/adoptingswift6).
- Swift 6.2 default concurrency isolation — [newsletter.mobileengineer.io](https://newsletter.mobileengineer.io/p/swift-62-default-concurrency-isolation-and-concurrent).
- swift-collections — [GitHub apple/swift-collections](https://github.com/apple/swift-collections). Active 2025-2026.
- swift-algorithms — [GitHub apple/swift-algorithms](https://github.com/apple/swift-algorithms). Active 2025.
- PointFree Composable Architecture — [GitHub](https://github.com/pointfreeco/swift-composable-architecture).

### Performance / data layout

- ECS deep dive — [Number Analytics ECS in Game Development](https://www.numberanalytics.com/blog/ecs-in-game-development-deep-dive).
- Data-Oriented Design for Games — [Generalist Programmer guide](https://generalistprogrammer.com/tutorials/data-oriented-design-games-complete-architecture-guide).
- The Book of Shaders, Chapter 10 — [thebookofshaders.com](https://thebookofshaders.com/10/).
- Inferno Metal shader library — [GitHub twostraws/Inferno](https://github.com/twostraws/Inferno).
- SwiftWyhash — [GitHub lemire/SwiftWyhash](https://github.com/lemire/SwiftWyhash).
- GameplayKit Programming Guide (per-entity seeds) — [Apple Developer](https://developer.apple.com/library/archive/documentation/General/Conceptual/GameplayKit_Guide/RandomSources.html).
- Unity Texture Sheet Animation — [Unity Manual](https://docs.unity3d.com/Manual/PartSysTexSheetAnimModule.html).

### Sync vs. async / image-pipeline practice

- WWDC 2024 Vision Framework enhancements — [Apple Developer](https://developer.apple.com/videos/play/wwdc2024/10163/).
- Harbeth Metal filter library — [GitHub yangKJ/Harbeth](https://github.com/yangKJ/Harbeth). Active 2025.
- BBMetalImage — [GitHub Silence-GitHub/BBMetalImage](https://github.com/Silence-GitHub/BBMetalImage).
- Cloudinary Swift Image Processing guide — [cloudinary.com](https://cloudinary.com/guides/image-effects/swift-image-processing).
- AVFoundation video frame creation — [img.ly tutorial](https://img.ly/blog/how-to-make-videos-from-still-images-with-avfoundation-and-swift/).
