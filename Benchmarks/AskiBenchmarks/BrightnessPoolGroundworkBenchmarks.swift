@_spi(AskiResearch) import Aski
import Benchmark
import CoreGraphics

/// ASKI-88 instruments only. No new budgets and no lab arm in production.
func addBrightnessPoolGroundworkBenchmarks() {
    for count in [8, 95, 256] {
        for limit in [1, 12, 24, 36, count, count + 1] {
            Benchmark("aski88-pool-n\(count)-k\(limit)-batch64", configuration: brightnessPoolConfiguration()) { benchmark in
                // Shuffled finite inputs with duplicates; fixture setup excluded.
                let brightness = (0..<count).map { Float(($0 * 37) % 129) / 128 }
                let queries = (0..<64).map { Float($0) / 64 }
                benchmark.startMeasurement()
                for _ in benchmark.scaledIterations {
                    for query in queries {
                        blackHole(ShapeMatching.poolIndices(queryBrightness: query, candidateBrightness: brightness, topK: limit))
                    }
                }
                benchmark.stopMeasurement()
            }
        }
    }
    for (name, set) in [("standard", StandardCharacterSet.standard), ("braille", .braille)] {
        for columns in [80, 120] {
            for parallel in [false, true] {
                for ranked in [false, true] {
                    addBrightnessConversion(name: name, set: set, columns: columns, density: 0, parallel: parallel, ranked: ranked)
                }
            }
        }
        // A wider pool on each dense bank, without multiplying the full matrix.
        for ranked in [false, true] {
            addBrightnessConversion(name: name, set: set, columns: 120, density: 1, parallel: false, ranked: ranked)
        }
    }
    for columns in [80, 120] {
        for ranked in [false, true] {
            addBrightnessConversion(name: "blocks", set: .blocks, columns: columns, density: 0, parallel: false, ranked: ranked)
        }
    }
}

private func brightnessPoolConfiguration() -> Benchmark.Configuration {
    Benchmark.Configuration(
        metrics: [.wallClock, .cpuTotal, .mallocCountTotal, .peakMemoryResident],
        warmupIterations: 1, scalingFactor: .one, maxDuration: .seconds(3), maxIterations: 5
    )
}

private func addBrightnessConversion(
    name: String, set: StandardCharacterSet, columns: Int, density: Float, parallel: Bool, ranked: Bool
) {
    let path = ranked ? "ranked" : "convert"
    let mode = parallel ? "parallel" : "serial"
    let pool = density == 0 ? 12 : 36
    Benchmark("aski88-\(path)-\(name)-\(columns)cols-k\(pool)-\(mode)", configuration: brightnessPoolConfiguration()) { benchmark in
        let image = makeGradient(width: 800, height: 600)
        var converter = ASCIIConverter(
            characterSet: set, palette: BuiltInPalette.monochrome,
            options: RenderingOptions(density: density)
        )
        converter.rowWalkMode = parallel ? .forcedParallel : .forcedSerial
        let options = AnimationOptions(duration: 2, seed: 88, cycling: CyclingOptions(k: 6, speed: 1, intensity: 1, randomness: 0.5))
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            if ranked {
                blackHole(converter.animate(image, columns: columns, options: options))
            } else {
                blackHole(converter.convert(image, columns: columns))
            }
        }
        benchmark.stopMeasurement()
    }
}
