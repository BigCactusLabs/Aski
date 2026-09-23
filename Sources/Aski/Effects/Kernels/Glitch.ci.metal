#include <CoreImage/CoreImage.h>
#include "_Seed64.h"

extern "C" {
    namespace coreimage {
        float4 ascii_b_glitch(sampler src, float intensity, float4 seedParts, destination dest) {
            float4 ext = src.extent();
            float2 uv = (dest.coord() - ext.xy) / ext.zw;
            float bandIndex = floor(uv.y * 16.0);
            float h = pixelNoise(seedParts, float2(bandIndex, 0.0));
            float shift = (h - 0.5) * intensity * 0.05;
            float2 shiftedUV = float2(clamp(uv.x + shift, 0.0, 1.0), uv.y);
            float2 workingPx = ext.xy + shiftedUV * ext.zw;
            return src.sample(src.transform(workingPx));
        }
    }
}
