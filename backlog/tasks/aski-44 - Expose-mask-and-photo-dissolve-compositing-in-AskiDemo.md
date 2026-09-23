---
id: ASKI-44
title: Expose mask and photo-dissolve compositing on the aski CLI
status: Done
assignee: []
created_date: '2026-08-20 23:59'
updated_date: '2026-08-27 12:32'
labels:
  - cli
  - masking
  - docs
dependencies:
  - ASKI-43
references:
  - 'Source tracker issue #6 (not migrated)'
  - 'Source tracker issue #7 (not migrated)'
documentation:
  - Sources/Aski/Aski.docc/Masking.md
  - docs/README.md
modified_files:
  - Tools/AskiToolSupport/DemoMaskArguments.swift
  - Tools/AskiToolSupport/AskiDemoCommand.swift
  - Tools/AskiToolSupport/ImageFileIO.swift
  - Tools/AskiToolSupport/DemoOutputTransaction.swift
  - Tests/AskiTests/AskiDemoTests.swift
  - Tests/AskiTests/DemoOutputTransactionTests.swift
  - Tests/AskiTests/Goldens/command-surface.json
  - Sources/Aski/Aski.docc/Masking.md
  - docs/README.md
  - AGENTS.md
  - CHANGELOG.md
priority: medium
type: enhancement
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub issue #6 identifies a discoverability and product-workflow gap: the library can combine raster masks, soft coverage, and image fallbacks, but the aski CLI cannot exercise that pipeline. Expose a complete single-pass photo-dissolve workflow on `aski render` through `MaskOptions` and normal Aski renderers; do not add a tool-local compositor.

The command surface is:

```bash
swift run aski render photo.jpg \
  --columns 256 \
  --render-png dissolve.png \
  --mask mask.png \
  --mask-fallback original \
  --mask-fallback-sizing stretch \
  --mask-ground "#080808"
```

Implement mask options as an `@OptionGroup` nested inside `RenderArguments` — the option surface shared by `AskiRenderCommand` and the source-compatible `AskiDemoCommand` wrapper — so both entry points gain the flags and presence, resolution, and validation stay isolated from the commands. `--mask-fallback` and `--mask-fallback-sizing` are parser-optionals rather than stored defaults: this preserves whether the user supplied them, allowing `--mask-fallback transparent` without `--mask` and contradictory sizing/color combinations to be rejected. When a mask exists, the resolved fallback defaults to `transparent`; original-image sizing defaults to `stretch`.

`--mask <path>` is the only mask option usable without `--render-png`. In that text-only case, the existing 0.5 coverage threshold controls spaces. `solid`, `original`, and `--mask-ground` are raster-only and require `--render-png`. `clear`/`transparent` are rejected for solid fallback colors and grounds: use `--mask-fallback transparent` or omit `--mask-ground` instead.

Decode the source once through `loadThumbnailForConversion`. Decode the mask through `DemoImageIO.loadThumbnail` with `maxPixelSize = max(source.width, source.height)`, then let the library stretch it to the grid. Use that exact orientation-normalized source `CGImage` as `MaskFallback.originalImage`; never decode the source a second time.

Validation, source/mask decode, conversion, PNG rendering, and PNG encoding must complete before any output file is replaced or stdout is emitted. Requested file artifacts are staged in their destination directories and committed through a small tool-local output transaction with rollback, so a validation/input/render/encode failure leaves prior outputs intact and no new partial file. Cross-filesystem atomicity is not promised; each stage and replacement occurs in the destination directory.

Manifest interaction: `aski render` now emits an opt-in deterministic manifest (`--write-manifest`, schema v1). This task must decide explicitly whether resolved mask/ground state joins the manifest (likely as a v1-additive optional block) or is documented as excluded; either answer is acceptable, silence is not.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `AskiDemo` exposes an `@OptionGroup DemoMaskArguments` with `--mask`, optional fallback mode/color/sizing, ground, hard-edge, and inversion fields; help states the white/black/intermediate mask convention.
- [x] #2 `--mask-fallback` resolves to `transparent` only after validation, and original-image sizing resolves to `stretch` only when the fallback is `original`.
- [x] #3 Any supplied mask-specific option without `--mask` fails validation, including an explicit `--mask-fallback transparent` or `--mask-fallback-sizing stretch`.
- [x] #4 `solid` requires a nontransparent fallback color and `--render-png`; colors supplied for non-solid modes are rejected.
- [x] #5 `original` requires `--render-png`; sizing supplied for non-original modes is rejected.
- [x] #6 `--mask-ground` requires `--render-png` and rejects `clear`/`transparent`; omitting it remains the no-ground behavior from ASKI-43.
- [x] #7 `--mask-hard-edges` and `--mask-invert` map exactly to `MaskOptions.softEdges == false` and `invert == true`.
- [x] #8 The source is decoded once, and the exact orientation-normalized conversion image is reused for `MaskFallback.originalImage`.
- [x] #9 Mask decoding is bounded to the normalized source thumbnail long side and the library remains the only component that stretches/samples mask coverage.
- [x] #10 Validation, source/mask decode, conversion, raster rendering, and PNG encoding occur before stdout or final output replacement; staged file commits roll back prior destinations on failure.
- [x] #11 Missing/unreadable source or mask paths use `DemoExitCode.inputUnavailable` and name the failing path; output staging/commit failures use the existing failure exit class with deterministic text.
- [x] #12 Existing no-mask invocations remain byte-identical, including text output, transparent PNG backgrounds, and preserve-aspect behavior.
- [x] #13 Tests cover parser defaults and presence, exact validation precedence/messages, text-only transparent masks, every fallback, clear-color rejection, bounded mask decode, source identity/alignment, hard/inverted masks, transaction rollback, no-mask regression, and command-surface golden regeneration.
- [x] #14 `Masking.md` includes equivalent CLI/library recipes and generated before/after assets; `docs/README.md`, `AGENTS.md`, `CHANGELOG.md`, and the command-surface golden reflect the new flags.
- [x] #15 Resolved mask, fallback, sizing, ground, hard-edge, and invert state is either recorded in the render manifest (schema-versioned, additive) or its exclusion is documented in the schema doc and DocC; the choice is stated in the PR.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Parser, transaction, integration, and command-surface tests pass.
- [ ] #2 `just check` passes on the final implementation tree.
- [ ] #3 CLI help, Masking DocC, tool inventory, agent example, changelog, and issue/PR linkage are committed.
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
### File map and interfaces

- Create `Tools/AskiToolSupport/DemoMaskArguments.swift` (Demo* prefix kept for consistency with `DemoImageIO`/`DemoExitCode`):
  - `MaskFallbackArgument: String, CaseIterable, ExpressibleByArgument, Sendable` with `transparent`, `solid`, `original`.
  - `MaskFallbackSizingArgument: String, CaseIterable, ExpressibleByArgument, Sendable` with `fill`, `fit`, `stretch` and `var backgroundSizing: BackgroundSizing`.
  - `DemoMaskArguments: ParsableArguments, Sendable` containing parser-optional mode/sizing values, optional colors, and the two flags.
  - `func validate(renderPNGPath: String?) throws` and `func makeMaskOptions(maskImage: CGImage, sourceImage: CGImage) -> MaskOptions?`.
- Modify `Tools/AskiToolSupport/AskiDemoCommand.swift`: add `@OptionGroup public var mask: DemoMaskArguments` to `RenderArguments` (NOT to `AskiDemoCommand` — `RenderArguments` is the shared option surface consumed by both `AskiRenderCommand` and the compatibility wrapper). Call `mask.validate(renderPNGPath:)` after existing numeric validation in the shared run path; decode source, then mask, then build one `MaskOptions`; pass it to conversion.
- Modify `Tools/AskiToolSupport/ImageFileIO.swift`: add `encodePNG(_:) throws -> Data`; make `writePNG` delegate to it so encoding failures are separable from destination commits.
- Create `Tools/AskiToolSupport/DemoOutputTransaction.swift`: stage UTF-8 text/PNG data beside each destination, back up existing destinations, replace all staged outputs, restore backups and remove newly committed destinations if any replacement fails, and clean stage/backup files in all paths.
- Manifest (`Tools/AskiToolSupport/AskiRenderManifest.swift`, `docs/assets/schemas/aski-render-manifest-v1.schema.json`): implement the AC#15 decision — add an optional additive mask block, or document exclusion. Do not fork a v2 schema for this.

### Validation order and exact behavior

1. Run existing column/font validation.
2. If `maskPath == nil` and any other mask field was explicitly supplied or either flag is true, throw `ValidationError("--mask is required when using mask-specific options")`.
3. Resolve `fallback = fallbackArgument ?? .transparent` only when `maskPath != nil`.
4. Reject `fallbackColor` unless fallback is `solid`; require it for `solid`; reject alpha `<= 0` with guidance to use `transparent`.
5. Reject sizing unless fallback is `original`; for `original`, resolve absent sizing to `.stretch`.
6. Require `--render-png` for `solid`, `original`, and a ground.
7. Reject a ground with alpha `<= 0` and tell the caller to omit `--mask-ground`.

Tests assert this precedence so a command with several contradictions returns the first rule above consistently.

### Execution sequence

1. Decode the source once with `loadThumbnailForConversion`.
2. If `--mask` exists, decode it with `loadThumbnail(at:maxPixelSize:)`, using `max(sourceImage.width, sourceImage.height)`.
3. Build `MaskOptions`; an original fallback captures the same `sourceImage` object passed to `converter.convert`.
4. Convert once and prepare plain text.
5. If PNG output is requested, render and call `encodePNG` before emitting stdout or touching final paths.
6. Build a list of file artifacts (`--output` text and/or `--render-png` data) and commit them through `DemoOutputTransaction`.
7. Emit stdout only after file commit succeeds. Preserve the existing trailing-newline rule.

### Tests and documentation

- Extend `Tests/AskiTests/AskiDemoTests.swift` for parsing, validation, path-specific errors, integration, orientation/alignment, and no-mask parity — asserting the flags surface through BOTH `aski render` and the `AskiDemo` compatibility spelling.
- Add `Tests/AskiTests/DemoOutputTransactionTests.swift` with: successful two-file replacement, existing-file preservation, failure before commit, and rollback after the first replacement. Use a deterministic test-only failure hook on the transaction after N replacements rather than relying on filesystem permissions.
- Re-record `Tests/AskiTests/Goldens/command-surface.json` only after docs are updated (extend, never replace — ASTSK-61 golden covers the command surface).
- Generate the CLI and library DocC examples from the same source/mask as ASKI-43.

### Verification

```bash
xcrun swift test --filter AskiDemoTests
xcrun swift test --filter DemoOutputTransactionTests
ASKI_RECORD_COMMAND_SURFACE=1 xcrun swift test --filter CommandSurfaceGoldenTests
xcrun swift test --filter CommandSurfaceGoldenTests
just check-fast
just check
```

Do not change `MaskSampler`, add a second compositor, or decode the source twice.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Salvaged 2026-08-23 from branch issue-7-mask-ground (full design). The design text predates the first-class aski CLI (PR #19/#20): AskiDemo no longer exists — every reference to AskiDemo in the description/plan maps to the aski product command (swift run aski). End-to-end recipe requirement from the later re-migration still applies.

Board audit 2026-08-24 (deep pass): STALE — needs rewrite before pickup: worked example targets removed AskiDemo product; plan attaches @OptionGroup mask to AskiDemoCommand but the real option surface is RenderArguments (shared by AskiRenderCommand) — following it literally leaves aski render without the flags; plan predates --write-manifest, and whether mask/ground state belongs in the manifest is an unasked question.

Board audit 2026-08-24: rewritten against the first-class aski CLI per owner instruction — command example now aski render, @OptionGroup re-anchored from AskiDemoCommand to RenderArguments (shared surface), manifest interaction added as AC#15 and a plan step. Design content (validation precedence, decode-once, output transaction) preserved from the issue-7-mask-ground salvage.

Shipped in the four-task mask batch, PR #31 (merge f761952, 2026-08-27). aski render gained the DemoMaskArguments @OptionGroup (--mask, fallback mode/color/sizing, --mask-ground, --mask-hard-edges, --mask-invert) with strict validation precedence; single source decode reused for originalImage fallback; staged output transaction with rollback (DemoOutputTransaction); resolved mask state joined the render manifest as a v1-additive optional block; command-surface golden, Masking.md recipes, AGENTS.md and CHANGELOG updated.
<!-- SECTION:NOTES:END -->
