import CoreGraphics
import os

internal enum MaskLogger {
    static let log = OSLog(subsystem: "com.bigcactuslabs.aski", category: "Masking")

    private static let samplingWarning = OSAllocatedUnfairLock<Bool>(initialState: false)
    private static let tileCharacterWarning = OSAllocatedUnfairLock<Bool>(initialState: false)
    private static let fallbackColorWarning = OSAllocatedUnfairLock<Bool>(initialState: false)

    static func warnOnceSamplingFailed(_ reason: StaticString) {
        samplingWarning.withLock { warned in
            guard !warned else { return }
            os_log(reason, log: log, type: .info)
            warned = true
        }
    }

    static func warnOnceTileCharacterFallbackIgnored() {
        tileCharacterWarning.withLock { warned in
            guard !warned else { return }
            os_log(
                "MaskFallback.character is only supported by ASCII renderers; tile renderer treats it as transparent",
                log: log,
                type: .info
            )
            warned = true
        }
    }

    static func warnOnceFallbackColorConversionFailed() {
        fallbackColorWarning.withLock { warned in
            guard !warned else { return }
            os_log(
                "MaskFallback.character color conversion failed; using opaque white fallback glyphs",
                log: log,
                type: .info
            )
            warned = true
        }
    }
}

// Pixel-buffer rule for every `CGContext` in the masking pipeline:
// `CGContext` stores the `data` pointer and dereferences it long after the
// initializer returns, so a Swift `inout`-to-pointer conversion
// (`CGContext(data: &bytes, ...)`) is undefined behaviour — that pointer is
// only valid for the duration of the initializer call. Either keep the whole
// context lifetime inside `withUnsafeMutableBytes` (reference pattern:
// `readRGBA8` in Sources/Aski/CellSampling.swift) or pass `data: nil` and let
// CoreGraphics own the buffer (reference pattern: `CellRasterBuilder`).

internal enum MaskSampler {
    static func sample(_ options: MaskOptions, columns: Int, rows: Int) -> [Float]? {
        guard columns > 0, rows > 0 else {
            MaskLogger.warnOnceSamplingFailed("MaskSampler: invalid target dimensions")
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: columns * rows * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let didDraw = bytes.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard
                let context = CGContext(
                    data: rawBuffer.baseAddress,
                    width: columns,
                    height: rows,
                    bitsPerComponent: 8,
                    bytesPerRow: columns * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                )
            else {
                return false
            }

            context.interpolationQuality = .high
            context.draw(
                options.image,
                in: CGRect(x: 0, y: 0, width: columns, height: rows)
            )
            return true
        }

        guard didDraw else {
            MaskLogger.warnOnceSamplingFailed("MaskSampler: could not allocate bitmap context")
            return nil
        }

        var coverage = [Float](repeating: 0, count: columns * rows)
        for (index, offset) in stride(from: 0, to: bytes.count, by: 4).enumerated() {
            let red = Float(bytes[offset])
            let green = Float(bytes[offset + 1])
            let blue = Float(bytes[offset + 2])
            var value = max(0, min(1, (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255.0))
            if !options.softEdges {
                value = value >= 0.5 ? 1.0 : 0.0
            }
            if options.invert {
                value = 1.0 - value
            }
            coverage[index] = value
        }

        return coverage
    }
}
