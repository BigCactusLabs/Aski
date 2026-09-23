import CoreGraphics
import Foundation

/// Deterministic synthetic input for MotionLab. A diagonal brightness ramp
/// (0...255) tinted by quadrant for chroma variety, fully opaque so animated
/// cells inherit base alpha 1.0. Reproducibility-correct default per the spec
/// (synthetic geometric image; real photos via `--image` for validation only).
public enum SyntheticImage {
    /// RGBA8 (premultiplied-last, opaque) pixel buffer, row-major.
    static func pixels(width: Int, height: Int) -> [UInt8] {
        precondition(width > 0 && height > 0, "SyntheticImage requires positive dimensions")
        var out = [UInt8](repeating: 0, count: width * height * 4)
        let span = Double(max(1, width + height - 2))
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let level = UInt8(min(255, max(0, Int((Double(x + y) / span) * 255))))
                let half = level / 2
                let (r, g, b): (UInt8, UInt8, UInt8)
                switch (y < height / 2, x < width / 2) {
                case (true, true): (r, g, b) = (level, half, half)
                case (true, false): (r, g, b) = (half, level, half)
                case (false, true): (r, g, b) = (half, half, level)
                case (false, false): (r, g, b) = (level, level, level)
                }
                out[i] = r
                out[i + 1] = g
                out[i + 2] = b
                out[i + 3] = 255
            }
        }
        return out
    }

    /// Builds an sRGB `CGImage` from the deterministic pixel buffer.
    public static func make(width: Int = 128, height: Int = 128) -> CGImage {
        let buffer = pixels(width: width, height: height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data(buffer) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}
