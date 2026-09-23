#include <CoreImage/CoreImage.h>

extern "C" {
    namespace coreimage {
        float4 ascii_b_crtCurvature(sampler src, float intensity, destination dest) {
            float4 ext = src.extent();
            float2 dpx = dest.coord();
            float2 uv = (dpx - ext.xy) / ext.zw;
            float2 centered = uv - float2(0.5);
            float r2 = dot(centered, centered);
            float k = intensity * 0.5;
            float2 distorted = centered * (1.0 + k * r2);
            float2 sampleUV = distorted + float2(0.5);
            if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) {
                return float4(0.0, 0.0, 0.0, 1.0);
            }
            float2 workingPx = ext.xy + sampleUV * ext.zw;
            return src.sample(src.transform(workingPx));
        }
    }
}
