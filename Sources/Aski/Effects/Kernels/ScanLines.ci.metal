#include <CoreImage/CoreImage.h>

extern "C" {
    namespace coreimage {
        float4 ascii_b_scanLines(sampler src, float intensity, float frequency, destination dest) {
            float4 c = src.sample(src.coord());
            float2 dpx = dest.coord();
            float line = sin(dpx.y * 3.14159265 / max(frequency, 1.0));
            float modulator = 1.0 - intensity * 0.5 * (1.0 - line * line);
            return float4(c.rgb * modulator, c.a);
        }
    }
}
