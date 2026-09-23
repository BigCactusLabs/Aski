#include <CoreImage/CoreImage.h>

extern "C" {
    namespace coreimage {
        float4 ascii_b_rgbSplit(sampler src, float intensity, destination dest) {
            float4 ext = src.extent();
            float2 dpx = dest.coord();
            float pxShift = intensity * 0.01 * ext.z;
            float2 lpx = dpx - float2(pxShift, 0);
            float2 rpx = dpx + float2(pxShift, 0);
            float r = src.sample(src.transform(lpx)).r;
            float g = src.sample(src.transform(dpx)).g;
            float b = src.sample(src.transform(rpx)).b;
            float a = src.sample(src.transform(dpx)).a;
            return float4(r, g, b, a);
        }
    }
}
