#include <CoreImage/CoreImage.h>

extern "C" {
    namespace coreimage {
        float4 ascii_b_halftone(sampler src, float scale, destination dest) {
            float2 dpx = dest.coord();
            float2 cell = floor(dpx / scale);
            float2 cellCenter = (cell + float2(0.5)) * scale;
            float2 cellOffset = dpx - cellCenter;
            float dist = length(cellOffset) / (scale * 0.5);

            float4 sampleColor = src.sample(src.transform(cellCenter));
            float lum = dot(sampleColor.rgb, float3(0.2126, 0.7152, 0.0722));
            float radiusFactor = 1.0 - lum;
            float dot_ = step(dist, radiusFactor);

            return float4(float3(dot_) * sampleColor.rgb, sampleColor.a);
        }
    }
}
