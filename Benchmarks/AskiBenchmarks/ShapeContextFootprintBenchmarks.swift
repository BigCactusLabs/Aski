@_spi(AskiResearch) import Aski
import Benchmark
import CoreGraphics

/// ASKI-87 instruments, not new regression thresholds. Preparation stays inside
/// measurement. Compare identical instruments on the scalar and candidate builds.
func addShapeContextFootprintBenchmarks() {
    let configuration = Benchmark.Configuration(
        metrics: [.wallClock, .cpuTotal, .mallocCountTotal],
        units: [.mallocCountTotal: .count],
        warmupIterations: 1, scalingFactor: .one, maxDuration: .seconds(3), maxIterations: 10
    )
    for (width, height) in [(2, 3), (3, 3), (8, 12), (16, 24)] {
        for cells in [1, 2400] {
            for prepared in [false, true] {
                let arm = prepared ? "prepared" : "scalar"
                Benchmark("aski87-histogram-\(arm)-\(width)x\(height)-\(cells)cells", configuration: configuration) { benchmark in
                    let pixels = (0..<(width * height)).map { Float(($0 * 37 + 19) % 256) / 255 }
                    benchmark.startMeasurement()
                    for _ in benchmark.scaledIterations {
                        if prepared {
                            let footprint = ShapeContext.Footprint(width: width, height: height)
                            for _ in 0..<cells { blackHole(footprint.histogram60(pixels)) }
                        } else {
                            for _ in 0..<cells { blackHole(ShapeContext.histogram60(pixels, width: width, height: height)) }
                        }
                    }
                    benchmark.stopMeasurement()
                }
            }
        }
    }
    for columns in [1, 8, 80, 120] {
        for oversample in [2, 4, 8] {
            for (name, mode) in [("serial", GridRowWalk.Mode.forcedSerial), ("parallel", .forcedParallel)] {
                Benchmark("aski87-convert-\(columns)cols-os\(oversample)-\(name)", configuration: configuration) { benchmark in
                    let image = makeGradient(width: 800, height: 600)
                    var converter = DefaultConverter()
                    converter.oversample = oversample
                    converter.rowWalkMode = mode
                    benchmark.startMeasurement()
                    for _ in benchmark.scaledIterations { blackHole(converter.convert(image, columns: columns)) }
                    benchmark.stopMeasurement()
                }
            }
        }
        // ConversionContext is also used by dotMatrix: measure the new setup
        // cost even though dotMatrix never consumes the descriptor map.
        Benchmark("aski87-dotmatrix-control-\(columns)cols", configuration: configuration) { benchmark in
            let image = makeGradient(width: 800, height: 600)
            var converter = DefaultConverter()
            converter.algorithm = .dotMatrix
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations { blackHole(converter.convert(image, columns: columns)) }
            benchmark.stopMeasurement()
        }
    }
    for (name, mode) in [("serial", GridRowWalk.Mode.forcedSerial), ("parallel", .forcedParallel)] {
        for oversample in [2, 4, 8] {
            Benchmark("aski87-repeated-80cols-os\(oversample)-\(name)", configuration: configuration) { benchmark in
                let image = makeGradient(width: 800, height: 600)
                var converter = DefaultConverter()
                converter.oversample = oversample
                converter.rowWalkMode = mode
                benchmark.startMeasurement()
                for _ in benchmark.scaledIterations {
                    for _ in 0..<10 { blackHole(converter.convert(image, columns: 80)) }
                }
                benchmark.stopMeasurement()
            }
        }
        Benchmark("aski87-ranked-80cols-\(name)", configuration: configuration) { benchmark in
            let image = makeGradient(width: 800, height: 600)
            var converter = DefaultConverter()
            converter.rowWalkMode = mode
            let options = AnimationOptions(duration: 5, seed: 1, cycling: CyclingOptions(k: 6, speed: 1, intensity: 0.6, randomness: 0.5))
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations { blackHole(converter.animate(image, columns: 80, options: options)) }
            benchmark.stopMeasurement()
        }
    }
    addScopedHistogramBenchmarks()
}

private func addScopedHistogramBenchmarks() {
    // Raw count units apply to both arms and leave existing thresholds intact.
    let configuration = Benchmark.Configuration(
        metrics: [.wallClock, .cpuTotal, .mallocCountTotal, .peakMemoryResident],
        units: [.mallocCountTotal: .count, .peakMemoryResident: .count],
        warmupIterations: 1, scalingFactor: .one, maxDuration: .seconds(3), maxIterations: 6
    )
    let regimes: [(columns: Int, oversample: Int, edge: Int)] = [(80, 2, 0), (120, 2, 0), (240, 2, 0), (120, 8, 50)]
    let modes: [(String, GridRowWalk.Mode)] = [("serial", .forcedSerial), ("parallel", .forcedParallel)]
    for (columns, oversample, edge) in regimes {
        for (modeName, mode) in modes {
            for path in ["convert", "ranked", "residual", "temporal"] {
                let name = "aski89-\(path)-\(columns)cols-os\(oversample)-e\(edge)-\(modeName)"
                Benchmark(name, configuration: configuration) { benchmark in
                    let image = makeGradient(width: 2400, height: 1800)
                    let next = path == "temporal" ? reversedGradient(image) : image
                    var converter = DefaultConverter()
                    converter.oversample = oversample
                    converter.options.edgeEmphasis = Float(edge) / 100
                    converter.rowWalkMode = mode
                    let animation = AnimationOptions(duration: 5, seed: 1, cycling: CyclingOptions(k: 6, speed: 1, intensity: 0.6, randomness: 0.5))
                    benchmark.startMeasurement()
                    for _ in benchmark.scaledIterations {
                        switch path {
                        case "convert":
                            blackHole(converter.convert(image, columns: columns))
                        case "ranked":
                            blackHole(converter.animate(image, columns: columns, options: animation))
                        case "residual":
                            blackHole(converter.convertWithResidual(image, columns: columns))
                        case "temporal":
                            let first = converter.convertTemporalFrame(
                                image, columns: columns, prior: nil, alpha: 0.5, tau: 0.1, sourceTetherRho: 0.2)
                            let second = converter.convertTemporalFrame(
                                next, columns: columns, prior: first.state, alpha: 0.5, tau: 0.1, sourceTetherRho: 0.2)
                            blackHole(first)
                            blackHole(second)
                        default:
                            preconditionFailure("Unregistered ASKI-89 path")
                        }
                    }
                    benchmark.stopMeasurement()
                }
            }
        }
    }
    for (name, columns, algorithm) in [
        ("aski89-convert-1cols-os2-e0-serial", 1, ASCIIAlgorithm.logPolar),
        ("aski89-convert-8cols-os2-e0-serial", 8, .logPolar),
        ("aski89-dotmatrix-control-8cols", 8, .dotMatrix),
        ("aski89-dotmatrix-control-120cols", 120, .dotMatrix),
    ] {
        Benchmark(name, configuration: configuration) { benchmark in
            let image = makeGradient(width: 2400, height: 1800)
            var converter = DefaultConverter()
            converter.algorithm = algorithm
            converter.oversample = 2
            converter.rowWalkMode = .forcedSerial
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations { blackHole(converter.convert(image, columns: columns)) }
            benchmark.stopMeasurement()
        }
    }
}

private func reversedGradient(_ source: CGImage) -> CGImage {
    let context = CGContext(
        data: nil, width: source.width, height: source.height, bitsPerComponent: 8, bytesPerRow: source.width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .none
    context.translateBy(x: CGFloat(source.width), y: 0)
    context.scaleBy(x: -1, y: 1)
    context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
    return context.makeImage()!
}
