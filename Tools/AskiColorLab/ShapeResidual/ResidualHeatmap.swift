import CoreGraphics
import Foundation

// MARK: - Heatmap

enum ResidualHeatmap {
    /// One 8×8 block per cell, row-major. Residual is min–max normalized over
    /// finite values to a grayscale ramp; NaN/empty cells map to 0 (black).
    static func image(
        residual: [Float],
        rows: Int,
        cols: Int,
        finiteMin: Float,
        finiteMax: Float
    ) -> CGImage {
        let scale = 8
        let w = max(1, cols * scale)
        let h = max(1, rows * scale)
        let span = finiteMax - finiteMin
        var pixels = [UInt8](repeating: 0, count: w * h)
        for r in 0..<rows {
            for c in 0..<cols {
                let value = residual[r * cols + c]
                let gray: UInt8
                if value.isFinite, span > 0 {
                    let t = (value - finiteMin) / span
                    gray = UInt8(max(0, min(255, (t * 255).rounded())))
                } else if value.isFinite {
                    gray = 128  // all-equal finite residuals -> mid-gray
                } else {
                    gray = 0
                }
                for dy in 0..<scale {
                    let y = r * scale + dy
                    for dx in 0..<scale {
                        pixels[y * w + (c * scale + dx)] = gray
                    }
                }
            }
        }
        let cs = CGColorSpaceCreateDeviceGray()
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: w, height: h,
            bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
            space: cs, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }
}
