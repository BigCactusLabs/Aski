# Local modifications

This copy comes from [ordo-one/malloc-interposer 1.4.0](https://github.com/ordo-one/malloc-interposer/tree/9221411ac2e845a93ce65b9ca2ab84f8c1084b0d), revision `9221411ac2e845a93ce65b9ca2ab84f8c1084b0d`.

ASKI-109 modifies `Sources/MallocInterposerC/src/interposer-darwin.c`.
`block_destructor` sets `t_block = NULL` after its null-argument guard so
subsequent thread teardown allocations cannot access the freed counter block
through the stale TLS pointer. The ASKI-109 regression covers post-destructor
allocation/free counts and repeated destructor passes at O1 and O3.

ASKI-92 modifies `Sources/MallocInterposerC/include/interposer.h` and the native
pointer-safety tests. Before reading the prefix, the Darwin classifier now
requires that the complete header starts at an allocation recognized by
`malloc_zone_from_ptr`. The previous page-alignment guard still read before
unreadable non-page-aligned pointers supplied during an Instruments size query.
The tag and magic checks remain required. Child-process regressions cover an
unreadable page, an unreadable offset, and a small address. Standalone O1/O3
checks cover owned and foreign allocation lifecycles and unchanged counts.
This adds a native ownership lookup to the Darwin path; studies must use the
same corrected instrument in both arms. It does not explain the separate
historical reset or CoreGraphics failures.
