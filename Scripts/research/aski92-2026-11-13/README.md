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

## November 14 warmup diagnostic

A later fresh control preparation failed in `objc_msgSend` through CFPreferences
and CoreGraphics during the fixed-palette workload
`aski92-fixed-512x512-srgb-opaque-256cols`. Matching native image UUIDs and symbols
place this failure in warmup, before measurement. It is a different observed
fault site from the reset failures above; the cause is still unproved.

The [bounded diagnostic rule](diagnostic-2026-11-14.json) was committed before
three independent starts of the same saved binary and workload. All three
completed with active allocator observations and no matching crash. Source,
lock, binaries and the original crash report remained unchanged. The result is
**not reproduced**, as recorded in the [diagnostic receipts](diagnostic-2026-11-14-result.json).
These direct-tool outputs are diagnostic only. They do not repair the failed
study, replace a sample, establish instrumentation reliability or authorize
adoption. The paired comparison and allocation-lifetime profiles remain open.

## November 14 allocation-profile pilot

The single registered 160-pixel control pilot failed under Instruments
Allocations. The [pilot receipt](allocation-pilot-2026-11-14.json) records
SIGBUS in `malloc_interposer_is_ours` through `replacement_malloc_size`,
Instruments `liboainject`, and benchmark cleanup. The supplied pointer was not
page-aligned; the classifier read unreadable memory immediately before it.
Matching crash UUIDs and 1,302 unchanged file hashes bind this observation to
the frozen control. This is a confirmed classifier read fault, with the pointer's
origin still unknown. It does not explain the earlier CoreGraphics or reset
failures. At the time of that pilot, no correction had been verified.

The retained trace exports 4,186 allocation rows with source stacks through the
CLI's Allocations List track detail. All exported rows are marked live, and
the table supplies no free timestamps. This does not prove that the raw trace
contains no free events; it leaves allocation/free lifetimes and overlap
unproved. Six paired measurement signposts do not cure the crashed target.
That pilot ran no second profile or replacement study capture. AC3 and AC4 remain open.

The [upstream page-aligned-pointer correction](https://github.com/ordo-one/malloc-interposer/commit/4d5c09d92394ad4a04426cca812ced8d9b15d2dd)
is relevant background, but its alignment condition does not cover this
observed pointer. The later correction below follows that failed pilot and does
not replace it.

## November 14 classifier correction

The Darwin classifier now verifies that the complete header starts at a native
allocation before it reads the tag and magic. A standalone O1/O3 regression
reproduced faults for unreadable pages, unreadable offsets and a small address
in the old classifier; the native allocator returned zero for all seven
non-owned pointer cases. All 30 corrected pointer cases and 16 original
valid-allocation controls passed. The existing count/lifecycle matrix also
passed in all 52 processes, preserving exact marginal counts and reset behavior.
See [the manifest and raw results](classifier-correction/manifest.json). The
first foreign-allocation harness attempt is retained separately: its `dlsym`
call was still interposed, so the corrected harness uses the public malloc-zone
callback to obtain an unwrapped allocation. This was a harness setup failure.

The same frozen benchmark executable, copied byte-for-byte and linked to the
corrected scratch allocator, completed one Allocations validation run with
exit zero. The trace records 109,020 freed allocations; its default CLI list
exports 4,111 persistent rows. Those rows alone still do not establish free
timestamps or sample-buffer overlap. This is instrumentation validation, not
a replacement study sample or proof that the earlier reset/CoreGraphics
failures have the same cause. A fresh study must use identical corrected
instrumentation in both arms because the additional ownership lookup affects
the measurement path.

The [integrated qualification](classifier-correction/qualification.json) passed
the native vendor suite, 122 portable validator tests (one documented expected
failure), the full local gate, all 237 benchmark workloads with required malloc
counts, and all 11 unchanged absolute budgets. The native gate ran 1,549 core
tests, 178 media tests, two sentinels and DocC. The lead reviewed the source;
independent cross-family review was unavailable.

A separate command-line capability capture uses `MallocStackLoggingNoCompact=1`
and pauses the unchanged executable at normal exit to read `malloc_history
-allEvents -fullStacks -noContent`. It retains ordered allocation/free records
and source stacks, but no clock timestamps. All 49 Wu tables and all seven
control sample buffers have matching frees in this diagnostic. A fresh protocol
uses event ordinals for overlap and peak-live calculations; it cannot report
lifetime durations. The diagnostic is excluded from the fresh study.
