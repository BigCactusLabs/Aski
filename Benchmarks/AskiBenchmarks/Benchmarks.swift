import Aski
import Benchmark
import CoreGraphics

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .mallocCountTotal, .allocatedResidentMemory],
        warmupIterations: 3,
        scalingFactor: .one
    )

    Benchmark("convert-gradient-800x600-80cols") { benchmark in
        let image = makeGradient(width: 800, height: 600)
        let converter = DefaultConverter()

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(converter.convert(image, columns: 80))
        }
        benchmark.stopMeasurement()
    }

    Benchmark("convert-gradient-2400x1800-120cols") { benchmark in
        let image = makeGradient(width: 2400, height: 1800)
        let converter = DefaultConverter()

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(converter.convert(image, columns: 120))
        }
        benchmark.stopMeasurement()
    }

    Benchmark("render-image-gradient-80cols") { benchmark in
        let image = makeGradient(width: 800, height: 600)
        let grid = DefaultConverter().convert(image, columns: 80)
        let font = ASCIIFont.system(size: 10)
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(grid.renderImage(font: font, backgroundColor: background, scale: 1))
        }
        benchmark.stopMeasurement()
    }

    addTileGridBenchmarks()
    addEffectChainBenchmarks()
    addMaskBenchmarks()
    addAnimationBenchmarks()
    addHelmlabBenchmarks()
    addParallelismCrossoverBenchmarks()
    addVideoPipelineBenchmarks()
    addGIFMetadataBenchmarks()
    addASTSK55Benchmarks()
}

internal func makeGradient(width: Int, height: Int) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    )!

    for x in 0..<width {
        let t = CGFloat(x) / CGFloat(width - 1)
        context.setFillColor(red: t, green: t, blue: t, alpha: 1)
        context.fill(CGRect(x: x, y: 0, width: 1, height: height))
    }

    return context.makeImage()!
}
