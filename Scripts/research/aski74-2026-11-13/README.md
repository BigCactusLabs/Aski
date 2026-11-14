# ASKI-74 native replay, 2026-11-13

The unchanged package at `e9ac79bd48ab0d387d85cedf15f5bab244fc0aad` builds and tests on final Xcode 27 / Swift 6.4. The previous case-only product collision did not reproduce. Product names and package layout were preserved.

[readout.json](readout.json) retains command exits, parsed comparisons, resource hashes, HDR bounds, and raw-log hashes. Local paths are replaced with role placeholders. Full local captures, generated media, and machine paths are not bundled. This is a compact evidence record, not a standalone replay archive.

The [research note](../../../docs/Research/2026-09-04-aski41-swift-build-migration-gate.md#aski-74-unchanged-graph-replay--2026-11-13-partial) records passing checks and limits. At this checkpoint ASKI-74 remained open: one same-native repeat could not clear decoded HEIC cross-backend differences. All existing HDR gates and lossless TIFF outputs agree. The canonical local `just check` passed with the installed Swift Build default; it is not a legacy-native-backend gate.

Both backend tools produce identical fresh Metal libraries and identical vector-audit results, but those differ from checked-in baselines. They are retained failures of freshness checks, separate from passing resource-copy parity. No kernels, vectors, snapshots or thresholds were changed. The vector drift is already owned by ASKI-78.

Evidence limitations: the benchmark wrapper replaced its initial command-metadata filename, so its complete raw logs/exports were replayed into the retained smoke readout. One early generator wrapper overwrote its inner command-record filename. Raw logs and outputs survived; exact commands are in the local scripts, and subsequent explicit native-repeat/Swift-Build records are retained here. Missing inner durations are not inferred from wrapper durations.

The later [registered HDR boundary comparison](../aski74-hdr-boundary-2026-11-13/README.md#registered-result--2026-11-14)
and explicit legacy-native full gate complete the scoped qualification. Exact
encoder inputs and existing gates pass; compressed outputs retain the documented
variability limits. The historical measurements above are unchanged.
