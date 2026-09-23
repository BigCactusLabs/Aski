# ASTSK-54 TileGrid profiling record

Measured 2026-07-23 on an otherwise idle `arm64` Darwin 25.5.0 host. Every
timed run used the serial `just bench` matrix; results below are wall-clock
`p50 / p99`.

## Matrix

- `tile-quantize-rich-512x512-256cols-adaptive{8,16,64}` converts a
  deterministic rich 512x512 RGBA image to 256 columns. The 16-colour case
  also has a soft circular-mask variant.
- `tile-render-finite16-128x128-pixelart-{square,circle}-scale8-{unmasked,masked}`
  renders a 128x128 `TileGrid` with a repeating finite 16-colour palette;
  masked variants cycle coverage through `1, .75, .5, .25`.
- The same finite palette fixture also covers brick square/circle and the full
  64x64 mode-by-shape matrix. The focused rows below are the fixtures that
  isolate findings 17 through 21.

No benchmark threshold changed.

## Decisions

| Finding | Decision | Before p50/p99 | After p50/p99 | Evidence |
| --- | --- | --- | --- | --- |
| 17: k-means invariant OKLAB conversion | Adopt | adaptive8 `77/78 ms`; adaptive16 `98/98 ms`; masked16 `100/101 ms`; adaptive64 `156/160 ms` | `35/36 ms`; `41/41 ms`; `42/42 ms`; `97/98 ms` | Convert source pixels once before refinement; centroid order and strict `<` nearest-centroid tie behavior remain unchanged. |
| 18: incremental Wu split scoring | Adopt, only at 64+ colours | adaptive64 `97/98 ms` | `90/90 ms` | Cache the selected split for boxes only when `target >= 64`; 8/16-colour calls retain direct scoring because cache bookkeeping was not a demonstrated win there. Strict box traversal and `>` split selection are unchanged. |
| 19: parent-minus-left Wu moments | Reject | adaptive64 `90/90 ms` | `90/90 ms` | The prototype only reassociated floating-point moment arithmetic and had no measured gain. It was removed; no production abstraction and no golden rebaseline. |
| 20: primitive cell drawing | Adopt square only; reject circle | square unmasked `13/14 ms`, masked `14/15 ms`; circle unmasked `29/30 ms`, masked `35/36 ms` | square `8.135/8.602 ms`, `9.134/9.593 ms`; circle `29/29 ms`, `36/37 ms` | Square fills draw the rectangle directly. Circle `fillEllipse` was removed: no p50 win and a masked-tail regression. |
| 21: finite-palette `CGColor` reuse | Adopt | square unmasked `8.286/9.306 ms`, masked `9.527/14.254 ms`; circle unmasked `31/33 ms`, masked `36/38 ms` | `4.473/4.964 ms`, `5.583/6.537 ms`; `27/28 ms`, `34/35 ms` | Exact `Float.bitPattern` RGB plus clamped-alpha keys reuse only equal `CGColor` inputs. The control was rerun from the final square-only state to isolate this result. |

## Output review and golden status

- Findings 17, 18, 20, and 21: `just test-snapshots` passed (38 tests in 6
  suites, including `TileGridRenderingSnapshotTests` and mask cases). No
  snapshot or golden file changed. The rendering changes keep the same color
  components and alpha; findings 17 and 18 preserve the old ordering and
  strict tie comparisons.
- Finding 19: before removing the prototype,
  `AskiTileMatrix earth-night-iss-091208.jpg --columns 128 --scale 8` produced
  15 of 15 matching PNG SHA-256 digests for the default 16-colour path.
  Parent-minus-left moments inherently permit floating-point reassociation,
  but that code was rejected, so no such change ships and no rebaseline was
  made.

Validation during each trial included `just format-check`, `just check-fast`,
and `just test-snapshots`. The final repository gate is recorded in the task
handoff after `just check` completes.
