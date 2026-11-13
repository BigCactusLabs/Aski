import Aski
import Benchmark

/// ASKI-87 instruments, not new regression thresholds. Preparation stays inside
/// measurement. Compare identical instruments on the scalar and candidate builds.
func addShapeContextFootprintBenchmarks() {
    let configuration = Benchmark.Configuration(
        metrics: [.wallClock, .cpuTotal, .mallocCountTotal],
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
}
