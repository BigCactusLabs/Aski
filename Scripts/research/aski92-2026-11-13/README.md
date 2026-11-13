# ASKI-92: paired study remains inconclusive

The shared tile-color sample buffer is **not adopted**. The original five-pair
study and its one fresh, unchanged recovery both stopped before a complete valid
pair. No speed, allocation or RSS comparison can be made from these attempts.
The task stays open.

Both failures were SIGSEGV / EXC_BAD_ACCESS at address `0x20c8`. Their first two
frames were `malloc_interposer_reset` (`interposer-darwin.c:201`) and
`BenchmarkRunner.run()` (`BenchmarkRunner.swift:133`). The pinned interposer was
1.4.0. This supports an instrumentation-startup failure; the root cause remains
unproved. It does not establish or exclude an Aski defect. No dependency,
instrumentation, threshold or failed sample was replaced to obtain a result.

## Evidence retained

- [Failed attempts](failed-attempts.json) records both capture failures, process
  exits, commands, frozen revisions and crash excerpts. The original attempt
  stopped in pair 1's candidate; recovery stopped in candidate preparation.
  Excluded preparation observations were never pooled into paired results.
- [Diagnostic phase](diagnostic-phase.json) contains all 480 raw histogram exports
  from a separate successful candidate-only run: 120 workloads, four metrics,
  six observations per cell. It separates preparation, Wu accumulation/split
  and k-means over the registered sizes, spaces, alpha cases and palette counts.
  [The table](diagnostic-phase-cells.csv) is descriptive attribution, not a
  control comparison. Run `python3 -B verify-phase.py` in this directory to
  verify hashes and statistics from the raw samples.
- [Readout](readout.json) binds the passing candidate/control full gates and
  existing 27-workload tile/color capture to evidence hashes. The unchanged
  Helmlab absolute budget passed. Completeness of other captures does not imply
  numeric budgets where none are configured.
- [Pre-registration](pre-registration.json) retains the original rule. Native
  allocation-lifetime profiles at 160 and 512 pixels in both arms remain unrun.
  In particular, overlap between the shared samples and Wu/k-means storage is
  not established by a packed-stride calculation or candidate-only sampled RSS.
- [Source replay](source-replay.json) and the two patches preserve the measured
  source experiment. Apply the control support patch to its stated base, then
  the treatment patch for the candidate. Local study SHAs identify provenance;
  they are not assumed available from the public remote. The patches reconstruct
  source and instrumentation, not the original commit metadata.

Exact palette/tile parity and full native gates passed on the prepared source.
They are prerequisites, not proof of a performance benefit. All measurements
used one M3 Max on macOS 27.0.1 / Xcode 27 / Swift 6.4. Desktop and system CPU
activity continued; there was no competing batch native job or recorded thermal
warning. This was not a quiet-host study. Histogram samples remain quantized.

The complete original and recovery captures remain in the local study archive.
The draft PR and isolated branches are preserved. No production option is added
for this inconclusive arm. A future study needs a resolved instrumentation
failure, fresh frozen identities and a complete unchanged comparison protocol.

ASKI-109 owns diagnosis of the allocator-reset failure. A [bounded upstream source
check](upstream-source-check.json) found the four inspected bookkeeping/reset
function bodies unchanged in 1.6.1; this does not establish the cause or exclude
an indirect fix elsewhere. No dependency update was attempted.
