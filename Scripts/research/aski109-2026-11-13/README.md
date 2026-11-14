# ASKI-109 allocator lifecycle correction

The pinned malloc-interposer 1.4.0 dependency has a reproduced thread-cleanup defect. Its counter destructor frees a block but leaves the thread-local cached pointer set. A later pthread-key destructor that allocates can then write through that stale pointer. Clearing the cache after the null-argument guard fixes this native reproduction.

This does **not** establish the cause of the original ASKI-92 reset crashes at address `0x20c8`. The old failed studies remain invalid and are never pooled into fresh measurements. The original benchmark-process FD-protocol causal replay was not completed. A direct no-workload startup check of the original candidate passed three times; it is not equivalent to that protocol.

## Native evidence

The [lifecycle matrix](lifecycle-matrix.json) contains 36 separate processes. The later-destructor allocation case crashes 3/3 with pristine source and passes 3/3 with the one-line correction. Five negative-control modes pass on both variants. The [probe](lifecycle-probe.c) contains no Aski registration or benchmark-observation code.

The [count regression](count-regression.c) and [raw results](count-results.json) cover 28 starts at O1 and O3. All 12 pristine lifecycle cases crash; all 12 corrected cases pass. Comparing 1 versus 41 explicit 4096-byte allocations per destructor pass gives exact marginal malloc/free deltas 40,80 and160 for 1,2 and 4 passes, and matching byte deltas. All 4 warmed main-thread cases report exactly 17 malloc/free operations and 69,632 bytes. Reset clears every counter checked by the program. See the [summary and source hashes](regression-summary.json).

The evidence is specific to this arm64 host and toolchain. It does not establish long-lived repeated create/join behavior, universal destructor ordering, or every allocation in an Aski workload. Debugger/trace variants changed the failure form and are supporting evidence only. The public JSON retains native exits/stdout/stderr; `$EVIDENCE` and `$UPSTREAM` replace local path prefixes in commands.

## Reproduce the count comparison

Run on the selected Apple toolchain. Use a new scratch directory outside the repository and compile both O1 and O3 variants. For each optimization, link the program normally against each library:

```bash
capture=$(mktemp -d)
xcrun clang -g -O1 -dynamiclib Scripts/research/aski109-2026-11-13/upstream-interposer-darwin.c \
  -I Vendor/malloc-interposer/Sources/MallocInterposerC/include -o "$capture/lib-pristine-O1.dylib"
xcrun clang -g -O1 -dynamiclib Vendor/malloc-interposer/Sources/MallocInterposerC/src/interposer-darwin.c \
  -I Vendor/malloc-interposer/Sources/MallocInterposerC/include -o "$capture/lib-corrected-O1.dylib"
xcrun clang -g -O1 Scripts/research/aski109-2026-11-13/count-regression.c \
  -I Vendor/malloc-interposer/Sources/MallocInterposerC/include "$capture/lib-corrected-O1.dylib" \
  -o "$capture/count-corrected-O1"
"$capture/count-corrected-O1" 0 17
"$capture/count-corrected-O1" 1 1
"$capture/count-corrected-O1" 1 41
```

Link the same program against the pristine library for the control. Repeat the 1/41 comparison with 2 and 4 destructor passes, then compile/run the same matrix at O3. Preserve nonzero exits and full logs. A successful corrected process also checks that reset cleared its counters and that the requested destructor passes occurred; compare the printed count/byte deltas separately. The lifecycle-probe program accepts modes 0–5; each matrix arm used three independent starts.

## Packaging and qualification boundary

`Vendor/malloc-interposer` preserves upstream 1.4.0 source, tests, Apache 2.0 LICENSE and NOTICE, with one attributed Darwin correction. The Unix backend is unchanged. The [capture guide](../../../docs/benchmark-validation.md) describes the supported SwiftPM edit, exact source/routing checks, explicit setup lock transition, stable effective lock during measurement, and guarded original-lock restoration. Real process-local allocator observations, missing-metric rejection and nonzero-exit validation remain required.

Fresh qualification passed: six smoke workloads, all 237 benchmark workloads, all 11 unchanged absolute budgets, 942 fast tests, and the full local gate (1,539 core tests, 178 media tests, two isolated sentinels and DocC). The [qualification record](native-qualification.json) binds the tested source patch, dependency pins, lock states and active allocator observations. The [budget log](absolute-budgets.log) retains the native result with private path prefixes normalized. No ASKI-92 performance result is implied.

The gate ran on the recorded base plus the exact reviewed source patch. Integration adds this public evidence packet, task/ledger records, changelog and discovery links; it does not change the tested runtime or capture code. The lead reviewed the source and regression controls. Independent cross-family review was unavailable.
