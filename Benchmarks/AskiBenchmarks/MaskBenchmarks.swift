import Aski
import Benchmark
import CoreGraphics

internal func addMaskBenchmarks() {
    Benchmark("masked-ascii-convert-80cols-transparent-fallback", configuration: maskBenchmarkConfiguration()) { benchmark in
        let image = makeGradient(width: 800, height: 600)
        let mask = makeCircularMask(width: 800, height: 600)
        let converter = DefaultConverter()

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(
                converter.convert(
                    image,
                    columns: 80,
                    mask: MaskOptions(image: mask, fallback: .transparent)
                ))
        }
        benchmark.stopMeasurement()
    }

    Benchmark("masked-ascii-convert-render-80cols", configuration: maskBenchmarkConfiguration()) { benchmark in
        let image = makeGradient(width: 800, height: 600)
        let mask = makeCircularMask(width: 800, height: 600)
        let converter = DefaultConverter()
        let font = ASCIIFont.system(size: 10)
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let grid = converter.convert(
                image,
                columns: 80,
                mask: MaskOptions(
                    image: mask,
                    fallback: .solid(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
                )
            )
            blackHole(grid.renderImage(font: font, backgroundColor: background, scale: 1))
        }
        benchmark.stopMeasurement()
    }

    Benchmark("masked-effects-render-solid-fallback", configuration: maskBenchmarkConfiguration()) { benchmark in
        let image = makeGradient(width: 800, height: 600)
        let mask = makeCircularMask(width: 800, height: 600)
        let grid = DefaultConverter().convert(
            image,
            columns: 80,
            mask: MaskOptions(
                image: mask,
                fallback: .solid(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            )
        )
        let font = ASCIIFont.system(size: 10)
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let composition = CompositionOptions(background: .solid(background))

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(
                grid.renderImage(
                    font: font,
                    backgroundColor: background,
                    scale: 1,
                    composition: composition,
                    effects: EffectChain([.vignette(intensity: 0.2)])
                ))
        }
        benchmark.stopMeasurement()
    }
}

private func maskBenchmarkConfiguration() -> Benchmark.Configuration {
    Benchmark.Configuration(
        metrics: [.wallClock, .mallocCountTotal, .allocatedResidentMemory],
        warmupIterations: 2,
        scalingFactor: .one,
        maxDuration: .seconds(3),
        maxIterations: 8
    )
}

func makeCircularMask(width: Int, height: Int) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceGray()
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    context.setFillColor(gray: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(gray: 1, alpha: 1)
    let insetX = width / 5
    let insetY = height / 5
    context.fillEllipse(
        in: CGRect(
            x: insetX,
            y: insetY,
            width: width - insetX * 2,
            height: height - insetY * 2
        ))
    return context.makeImage()!
}
