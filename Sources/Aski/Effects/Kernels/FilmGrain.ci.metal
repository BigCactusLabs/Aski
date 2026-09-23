#include <CoreImage/CoreImage.h>
#include "_Seed64.h"

extern "C" {
    namespace coreimage {
        float4 ascii_b_filmGrain(sampler src, float intensity, float4 seedParts, destination dest) {
            float2 dpx = dest.coord();
            float4 base = src.sample(src.coord());
            float noise = (pixelNoise(seedParts, dpx) - 0.5) * 2.0 * intensity * 0.15;
            return float4(base.rgb + float3(noise), base.a);
        }
    }
}
