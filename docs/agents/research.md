# Find and extend research

Start with the task and its recorded decision, then open the relevant source.
This page routes investigations; [Backlog](backlog.md) remains the task-status
authority. The decision map below was checked against `main` on 2026-11-22.
Re-read the task before starting work: **Done can mean rejected**, and a research
note marked `complete` does not mean its treatment ships.

## Find the right record

| Question | Read first | Source of truth |
| --- | --- | --- |
| What work is open, and what counts as complete? | [Backlog workflow](backlog.md) | The current branch's `backlog/tasks/`; use `backlog task view ASKI-NN --plain` |
| Where is the implementation? | [Code navigation](navigation.md), then [architecture](../architecture.md) | `Sources/Aski/`, `Tools/`, `Tests/`, and `Package.swift` |
| Why was a choice made? | [Research index](../Research/README.md), or search the topic below | The dated note and its frozen rule, including retractions and later decisions |
| Where are the measurements? | The note's result links | `docs/Research/Results/` manifests and the study's `Scripts/research/` packet |
| How do I run a new quality experiment? | [Research methodology](research-methodology.md) | The pre-registered rule, exact lattice, independent oracles, and frozen control |
| How do I establish a performance benefit? | [Capture validation](../benchmark-validation.md), then [paired comparisons](paired-benchmarks.md) | Complete native captures and the experiment's rule; a successful capture is not a budget verdict |
| How do I add or maintain a note? | [Research entry conventions](../Research/README.md#when-to-add-an-entry) | Note front matter; regenerate the index with `xcrun swift run BuildResearchIndex` |

Use narrow searches before opening the whole research corpus:

```bash
backlog task list --plain --status "To Do"
backlog task list --plain --status "In Progress"
backlog task view ASKI-95 --plain
rg -n -i 'near.white|orthogonality' docs/Research --glob '*.md' --glob '!**/Results/**'
rg --files Scripts/research | rg 'aski9[0-5]|video-frame-selection'
```

[`index.json`](../Research/index.json) is the generated machine-readable index.
It records notes, corpora, and result manifests; it is not a live task queue.
Keep research provenance and result bytes intact. To change a conclusion, update
the owning note and its front matter, then regenerate the index as required by
the [closing rules](research-methodology.md#closing-the-task).

## Performance groundwork: decisions already made

The ASKI-86–95 batch is no longer an unexecuted roadmap. Use these records before
proposing a repeat. Preserve each study's scope and native-host limitations;
the results do not establish a universal speedup or a general ban on a mechanism.

| Task | Recorded disposition | Evidence / implementation boundary |
| --- | --- | --- |
| ASKI-86 — capture validity | Complete | [Native failure/allocator evidence](../../Scripts/research/aski86-2026-11-13/README.md); `just bench` validates complete exports. ASKI-5 separately owns representative budgets. |
| ASKI-87 — prepared footprint | Adopted with an explicit maintainer exception | [Decision and full replay](../benchmark-validation.md#aski-87-prepared-footprint-candidate). One primary improved 2.10% against its registered 5% bar; the original unmet rule remains recorded. |
| ASKI-88 — brightness pool | Rejected | [Native heap study](../../Scripts/research/aski88-2026-11-13/README.md). Shipping selection keeps full sorting. [Groundwork](brightness-pool-groundwork.md) preserves exact Float-distance and tie contracts. |
| ASKI-89 — histogram storage | Rejected | [Study and source replay](../../Scripts/research/aski89-2026-11-15/README.md). Reduced allocations did not meet every primary speed-benefit bar. |
| ASKI-90 — fixed-palette color reuse | Rejected | [Study](../../Scripts/research/aski90-2026-11-13/README.md). Production retains scalar display-color conversion. |
| ASKI-91 — frame-wide pattern work | Pulse arm adopted | [Study](../../Scripts/research/aski91-2026-11-13/README.md). Overlay primaries passed; animated-pulse parity is established, but the matrix does not directly measure animated-pulse speed. |
| ASKI-92 — shared tile samples | Rejected | [Fresh, decisive study](../../Scripts/research/aski92-2026-11-14/README.md). The shared-sample candidate is absent from production; the independently qualified allocator classifier correction is retained. |
| ASKI-93 — early video selection | Adopted | [Study and contracts](../../Scripts/research/video-frame-selection.md). Explicit `targetFPS` selects before ASCII conversion and reuses grids for duplicate slots. |
| ASKI-94 — one fallback-image draw | Rejected | [Parity veto and control baseline](../../Scripts/research/aski94-2026-11-15/README.md). The candidate changed pixels in 239 of 1,161 cases; no candidate timing verdict followed. |
| ASKI-95 — fallback-noise reuse | Open; contract groundwork only | [Remaining harness and memory work](rendering-groundwork.md#aski-95-prove-reachability-then-consider-render-local-reuse). Establish product fallback frequency and measured cost before choosing a reuse lifetime. |

Closed candidates require a materially new hypothesis and a new frozen rule to
reopen. The reusable comparison tool does not promote a candidate or rewrite the
recorded result.

## Other decision routes

| Area | Current boundary and useful starting points |
| --- | --- |
| Matcher quality and sparse glyph sets | Log-polar remains the default. The [fixed-footprint challenger](../Research/2026-09-04-aski69-render-space-matcher-rule.md) was KILL; the [orthogonality study](../Research/2026-09-27-aski-79-80-orthogonality-fallback.md) records why blank collapse cannot be adjudicated by those per-cell oracles alone. Read tasks ASKI-55, 57, 61, 62, and 85 before defining an arm. |
| Human/VLM arbiter | [Protocol v2](../Research/2026-09-04-aski62-arbiter-v2-protocol.md) and [validation record](../Research/2026-09-04-aski62-arbiter-v2-validation.md). ASKI-62 is To Do. On 2026-11-24 the owner retired its private-archive stimuli and the unopened VLM decisions; the next step re-freezes the stimuli at a public commit, collects the pinned VLM leg once, then runs the blinded owner sitting. Never mix stimuli, keys or decisions from the two freezes. ASKI-85 waits on v2 validation and registers its own A1 fallback arm; dotMatrix is no longer a scored arm there. |
| Glyph assets and raster drift | [Core Text policy](../Research/2026-09-04-aski51-core-text-drift-policy.md), [contributor snapshot baseline](../../CONTRIBUTING.md#toolchain-and-snapshot-baseline), and ASKI-78. Committed ShapeData stays the selection control; the unresolved raster policy blocks changes requiring its regeneration. Render-snapshot behavior is host-dependent, not only OS-dependent. |
| Charset extension API | [ASKI-76 decision](../Research/2026-11-15-aski76-charset-boundary.md) and [Character Sets](../../Sources/Aski/Aski.docc/CharacterSets.md). Expert precomputed-array conformances remain supported; `GlyphBank` validates the converter's snapshot. |
| Color, glyph coverage, and compositing | [ASKI-103 composition decision](../Research/2026-11-15-aski103-composition-spaces.md), [ASKI-68 removals](../Research/2026-09-04-aski68-production-experiment-cleanup.md), and ASKI-107. Current source-color rendering does not promise coverage-compensated cell appearance. The [old color plan](../research-plan.md) is historical rationale, not an implementation queue. |
| Near-white cutoff | [ASKI-108 inspection](../Research/2026-11-14-aski108-near-white-inspection.md) records a visible cliff on the named portrait. That diagnostic did not change the shipping threshold; its proposed opacity-taper arm is filed as ASKI-111, lab work rather than an accepted fix. |
| Media preparation and GIF lifetime | ASKI-2 and ASKI-4 are back in To Do after rejected arms: [orientation fidelity experiment](../../Scripts/research/aski2-2026-11-13/README.md), [GIF ownership/RSS experiment](../../Scripts/research/aski4-2026-11-13/README.md). Removing an application array did not establish bounded ImageIO lifetime. |
| Animation, reveal, and tone experiments | Read ASKI-10, 11, 12, 45/45.1/45.2, 58, 59, and 96 through [Backlog](backlog.md). [Rendering groundwork](rendering-groundwork.md) supplies exact pattern/mask contracts. These tasks are separate from the adopted pulse reuse. |

## Preserve the boundaries

- `ASKI-NN` is the current task sequence. Historical `ASTSK-NN` identifiers refer
  to a different private tracker; the numbers are unrelated.
- History before v0.7.0 may refer to unavailable private commits and PRs. Later
  public study links are usable. Check the recorded source revision before replay.
- `VesperPreset` and `aski lab preset` were retired. New experiments use the
  package-only [frozen render reference](research-methodology.md#frozen-render-reference)
  or an explicit recipe; dated Vesper evidence is retained without relabeling it.
- A passing synthetic, portable, or parsing check does not validate native
  rendering, media behavior, allocation lifetime, or `just check`. Record what
  actually ran and the exact revision; see [validation](validation.md).
- Preserve rejected source patches and measured artifacts in their study packet.
  Do not restore removed production options merely to make an old plan executable.

For runnable products and the lab/replay boundary, use the
[tool inventory](tooling.md). For standing experimental rules, use
[research methodology](research-methodology.md).
