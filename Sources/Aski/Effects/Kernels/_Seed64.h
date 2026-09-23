// Shared 64-bit seeded noise utilities for filmGrain, glitch, filmDust.
// Spec contract: xorshift64 PRNG seeded from full UInt64 + per-pixel coords.

#ifndef ASCII_B_SEED64_H
#define ASCII_B_SEED64_H

namespace coreimage {

struct Seed64 { uint hi; uint lo; };

// Reconstruct a 64-bit seed from 4 x 16-bit halves carried losslessly in
// floats. Each parts component is an integer in [0, 65535], which is within
// float's exact-integer range, so uint(parts.x) round-trips bit for bit.
static inline Seed64 seed64FromParts(float4 parts) {
    uint p0 = uint(parts.x);  // bits  0..15
    uint p1 = uint(parts.y);  // bits 16..31
    uint p2 = uint(parts.z);  // bits 32..47
    uint p3 = uint(parts.w);  // bits 48..63
    Seed64 s;
    s.lo = p0 | (p1 << 16);
    s.hi = p2 | (p3 << 16);
    return s;
}

// One Marsaglia xorshift64 step using the standard (13, 7, 17) triple,
// emulated as paired uint32s to avoid 64-bit integer edge cases in CIKernel.
static inline Seed64 xorshift64Step(Seed64 s) {
    // s ^= s << 13
    uint h = s.hi ^ ((s.hi << 13) | (s.lo >> 19));
    uint l = s.lo ^ (s.lo << 13);
    s.hi = h; s.lo = l;
    // s ^= s >> 7
    l = s.lo ^ ((s.lo >> 7) | (s.hi << 25));
    h = s.hi ^ (s.hi >> 7);
    s.hi = h; s.lo = l;
    // s ^= s << 17
    h = s.hi ^ ((s.hi << 17) | (s.lo >> 15));
    l = s.lo ^ (s.lo << 17);
    s.hi = h; s.lo = l;
    return s;
}

// Mix per-pixel coords into the seed and run two xorshift rounds. The constants
// prevent the seed=0, pixel=0 trap where xorshift would produce a zero stream.
static inline float pixelNoise(float4 seedParts, float2 pixel) {
    Seed64 s = seed64FromParts(seedParts);
    uint px = uint(pixel.x);
    uint py = uint(pixel.y);
    s.lo ^= px ^ 0x9E3779B9u;
    s.hi ^= py ^ 0x85EBCA6Bu;
    s = xorshift64Step(s);
    s = xorshift64Step(s);
    // Fold high bits into the low lane before truncating to 24 bits, otherwise
    // seeds that differ only above bit 32 can still collapse to the same output.
    uint mixed = s.lo ^ s.hi ^ (s.hi >> 8) ^ (s.hi << 16);
    return float(mixed & 0x00FFFFFFu) / 16777216.0;
}

}  // namespace coreimage

#endif
