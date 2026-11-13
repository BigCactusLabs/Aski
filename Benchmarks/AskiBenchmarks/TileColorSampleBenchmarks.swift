import Aski
import Benchmark
import CoreGraphics
import Foundation

/// ASKI-92 instruments, not budgets. Resolve/convert timing includes sample
/// preparation. Stage timing excludes upstream stages; RSS still describes the
/// whole child process, including fixture and setup. Use a quiet host.
func addTileColorSampleBenchmarks() {
    let spaces: [(String, RenderColorSpace)] = [("srgb", .sRGB), ("p3", .displayP3)]
    for (spaceName, space) in spaces {
        for alphaMode in ["opaque", "mixed"] {
            for columns in [8, 80, 256] {
                let side = columns * 2
                let key = "\(side)x\(side)-\(spaceName)-\(alphaMode)"

                for count in [8, 16, 64, 256] {

                    Benchmark("aski92-convert-\(key)-\(columns)cols-k\(count)", configuration: tileSampleConfiguration()) { benchmark in
                        let image = tileSampleImage(side: side, alphaMode: alphaMode, space: space)
                        let converter = TileGridConverter(palette: .adaptive(maxColors: count), colorSpace: space)
                        benchmark.startMeasurement()
                        for _ in benchmark.scaledIterations { blackHole(converter.convert(image, columns: columns)) }
                        benchmark.stopMeasurement()
                    }
                }
                Benchmark("aski92-fixed-\(key)-\(columns)cols", configuration: tileSampleConfiguration()) { benchmark in
                    let image = tileSampleImage(side: side, alphaMode: alphaMode, space: space)
                    let converter = TileGridConverter(palette: .brick, colorSpace: space)
                    benchmark.startMeasurement()
                    for _ in benchmark.scaledIterations { blackHole(converter.convert(image, columns: columns)) }
                    benchmark.stopMeasurement()
                }
            }
        }
        for columns in [8, 80, 256] {
            let side = columns * 2
            Benchmark("aski92-transparent-\(side)x\(side)-\(spaceName)-\(columns)cols", configuration: tileSampleConfiguration()) { benchmark in
                let image = tileSampleImage(side: side, alphaMode: "transparent", space: space)
                let converter = TileGridConverter(palette: .adaptive(maxColors: 16), colorSpace: space)
                benchmark.startMeasurement()
                for _ in benchmark.scaledIterations { blackHole(converter.convert(image, columns: columns)) }
                benchmark.stopMeasurement()
            }
        }
    }
}

func tileSampleConfiguration() -> Benchmark.Configuration {
    .init(
        metrics: [.wallClock, .cpuTotal, .mallocCountTotal, .peakMemoryResident],
        warmupIterations: 1,
        scalingFactor: .one,
        maxDuration: .seconds(3),
        maxIterations: 6
    )
}

func tileSamplePixels(side: Int, alphaMode: String) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    for y in 0..<side {
        for x in 0..<side {
            let index = y * side + x
            let offset = index * 4
            let alpha = alphaMode == "transparent" ? 0 : (alphaMode == "opaque" ? 255 : (index * 37) & 255)
            pixels[offset] = UInt8(((x * 13 + y * 7) & 255) * alpha / 255)
            pixels[offset + 1] = UInt8(((x * 3 + y * 19) & 255) * alpha / 255)
            pixels[offset + 2] = UInt8((((x ^ y) * 11) & 255) * alpha / 255)
            pixels[offset + 3] = UInt8(alpha)
        }
    }
    return pixels
}

private func tileSampleImage(side: Int, alphaMode: String, space: RenderColorSpace) -> CGImage {
    let pixels = tileSamplePixels(side: side, alphaMode: alphaMode)
    let cgSpace = CGColorSpace(name: space == .sRGB ? CGColorSpace.sRGB : CGColorSpace.displayP3)!
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(
        width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
        space: cgSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    )!
}
