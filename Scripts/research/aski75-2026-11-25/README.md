# ASKI-75 - unified `aski` CLI build and binary tax (2026-11-25)

Study packet for [ASKI-75](../../../backlog/tasks/). The result note is
[2026-11-25-aski75-cli-build-tax](../../../docs/Research/2026-11-25-aski75-cli-build-tax.md).

## Arms

Both arms are detached worktrees of the same commit, `99fc4c7c556ceaf947f223da93db4dee1ba94c4d`,
placed side by side under one parent directory with equal-length names (`arm-main`, `arm-ctrl`).

- **main**: the commit as is.
- **control**: the same commit with [lab-free-control.patch](lab-free-control.patch) applied. The patch
  removes the six lab imports (`AskiAccessLab`, `AskiColorLab`, `AskiDecolorLab`, `AskiHDRLab`,
  `AskiMotionLab`, `AskiVideoLab`), the `lab` command group and its six adapters from
  `Tools/AskiCLI/AskiCommand.swift`, and the six lab target dependencies of `AskiCLI` in
  `Package.swift`. It is a measurement control only and is never committed to a branch.

## Pre-registered rule and definitions (written before any timed sample)

Decision rule, frozen in ASKI-75 AC#5 on 2026-11-24: ACCEPT when current main's clean and warm
product-build medians do not exceed the lab-free control's by more than 20% or 15 seconds and no
distribution constraint is exposed; otherwise INVESTIGATE.

Reading applied to "more than 20% or 15 seconds", fixed before measuring: the threshold fires when the
median excess (main minus control) is more than 20% of the control median **or** more than 15 seconds,
for either the clean or the warm class. The alternative reading (fires only when both limits are
exceeded) is reported alongside but does not decide the verdict.

Operational definitions:

- Backend: `--build-system swiftbuild` on every command (the Swift 6.4.2 default, pinned explicitly).
  Debug configuration, `--force-resolved-versions`, `--product aski`.
- Clean sample: a fresh `--scratch-path` inside the arm's checkout that no earlier build used. Dependencies
  are resolved into it from the shared SwiftPM cache by an untimed `swift package resolve` first, so no
  fetch happens inside the timed build. Global caches outside the scratch path are shared by both arms.
- Warm sample: ASKI-70's definition, an immediate repeat of the same build after the clean build
  (a no-op rebuild).
- Link-only sample: after the warm build, delete only the linked `aski` executable in the bin path and
  rebuild. The build log is checked to confirm that no compile step ran.
- Order: one priming pair (`p0`, control then main) is run and excluded from the medians, then three
  samples per arm in the order control, main, main, control, control, main (ids `s1` to `s3`).
- Each sample (clean, warm and link steps) runs inside the machine-wide gate lock; `vm.loadavg` (1-minute)
  is recorded at the start of each timed step.
- Wall time is `/usr/bin/time -lp` `real`. Peak RSS is its `maximum resident set size`, which is the
  largest RSS of a single process in the build's process tree, not the sum across concurrent processes.
- Medians of three samples per arm and class. No sample is discarded after the fact.

## Replay

From a checkout of `99fc4c7` (paths are examples; keep both arms under one parent):

```bash
git worktree add --detach .build/aski75/arm-main 99fc4c7
git worktree add --detach .build/aski75/arm-ctrl 99fc4c7
git -C .build/aski75/arm-ctrl apply "$PWD/Scripts/research/aski75-2026-11-25/lab-free-control.patch"
out=/path/to/aski75-out
S=Scripts/research/aski75-2026-11-25/sample.sh
$S .build/aski75/arm-ctrl control p0 $out; $S .build/aski75/arm-main main p0 $out
$S .build/aski75/arm-ctrl control s1 $out; $S .build/aski75/arm-main main s1 $out
$S .build/aski75/arm-main main s2 $out;    $S .build/aski75/arm-ctrl control s2 $out
$S .build/aski75/arm-ctrl control s3 $out; $S .build/aski75/arm-main main s3 $out
python3 Scripts/research/aski75-2026-11-25/summarize.py $out/samples.tsv
```

On a shared host, wrap each `sample.sh` call in the host's build lock.
