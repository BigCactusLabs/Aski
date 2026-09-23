import CoreGraphics
import Foundation

/// Which deterministic moving stimulus to drive the temporal-prior gate with.
public enum TemporalStimulus: String, CaseIterable, Sendable {
    /// Translating high-contrast disc over a fixed linear gradient.
    case s1
    /// Rotating high-contrast bar through the center.
    case s2
}

/// Deterministic synthetic moving sources for the ASTSK-41 temporal-prior gate.
public enum SyntheticMotion {
    /// Frames per stimulus.
    public static let frameCount = 48
    /// Square native render size of the conversion input.
    public static let renderSize = 512

    private static let discStartX = 0.32
    private static let discStartY = 0.40
    private static let discRadius = 0.18
    private static let discVelX = 0.7
    private static let discVelY = 0.4

    private static let barHalfWidth = 0.06
    private static let barDegPerFrame = 2.0

    /// Scene luma in `[0,1]` at normalized `(u,v)` for `stimulus` at `frame`.
    public static func sceneLuma(_ stimulus: TemporalStimulus, frame: Int, u: Double, v: Double) -> Float {
        switch stimulus {
        case .s1:
            let cx = discStartX + Double(frame) * discVelX / Double(renderSize)
            let cy = discStartY + Double(frame) * discVelY / Double(renderSize)
            let dx = u - cx
            let dy = v - cy
            if dx * dx + dy * dy <= discRadius * discRadius {
                return 1.0
            }
            return Float(0.10 + 0.50 * u)

        case .s2:
            let angle = Double(frame) * barDegPerFrame * Double.pi / 180.0
            let px = u - 0.5
            let py = v - 0.5
            let perp = abs(-sin(angle) * px + cos(angle) * py)
            return perp <= barHalfWidth ? 1.0 : 0.15
        }
    }

    /// The conversion input frame, rendered as opaque sRGB RGBA8 gray.
    public static func inputImage(_ stimulus: TemporalStimulus, frame: Int) -> CGImage {
        let size = renderSize
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let u = (Double(x) + 0.5) / Double(size)
                let v = (Double(y) + 0.5) / Double(size)
                let luma = sceneLuma(stimulus, frame: frame, u: u, v: v)
                let byte = UInt8(min(255, max(0, Int((luma * 255).rounded()))))
                let offset = (y * size + x) * 4
                pixels[offset] = byte
                pixels[offset + 1] = byte
                pixels[offset + 2] = byte
                pixels[offset + 3] = 255
            }
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    /// Ground-truth scene luma at arbitrary output dimensions, sampled analytically at pixel centers.
    public static func groundTruthLuma(
        _ stimulus: TemporalStimulus,
        frame: Int,
        width: Int,
        height: Int
    ) -> [Float] {
        guard width > 0, height > 0 else { return [] }

        var out = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let u = (Double(x) + 0.5) / Double(width)
                let v = (Double(y) + 0.5) / Double(height)
                out[y * width + x] = sceneLuma(stimulus, frame: frame, u: u, v: v)
            }
        }
        return out
    }
}
