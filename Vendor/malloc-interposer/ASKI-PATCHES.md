# Local modifications

This copy comes from [ordo-one/malloc-interposer 1.4.0](https://github.com/ordo-one/malloc-interposer/tree/9221411ac2e845a93ce65b9ca2ab84f8c1084b0d), revision `9221411ac2e845a93ce65b9ca2ab84f8c1084b0d`.

ASKI-109 modifies `Sources/MallocInterposerC/src/interposer-darwin.c`.
`block_destructor` sets `t_block = NULL` after its null-argument guard so
subsequent thread teardown allocations cannot access the freed counter block
through the stale TLS pointer. The ASKI-109 regression covers post-destructor
allocation/free counts and repeated destructor passes at O1 and O3.
