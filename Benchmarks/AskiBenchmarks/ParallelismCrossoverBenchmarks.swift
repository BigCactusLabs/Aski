import Aski
import Benchmark
import CoreGraphics

/// ASTSK-51 Task 6 crossover instruments — measurement only, no thresholds (these
/// are gates' inputs, not gates). One benchmark per (mode × shape) so serial vs
/// parallel can be read from paired names in a single run: the walk schedules by
/// *rows*, so aspect is varied as well as size (equal cell counts at different
/// aspects dispatch differently). Threshold-selection protocol and the full
/// matrix are recorded in the private development archive.
func addParallelismCrossoverBenchmarks() {
    // width × height chosen so rows (≈ columns · height/width / 2 for the ~2:1
    // char aspect) span squat→tall at comparable cell counts.
    let shapes: [(name: String, width: Int, height: Int, columns: [Int])] = [
        ("landscape", 800, 600, [24, 40, 64, 80, 120, 200]),
        ("portrait", 600, 800, [40, 76]),  // tall: many rows, Vesper preset shape
        ("wide", 1200, 400, [120]),  // squat: few rows, many columns
    ]
    let modes: [(name: String, mode: GridRowWalk.Mode)] = [
        ("serial", .forcedSerial),
        ("parallel", .forcedParallel),
    ]

    for (modeName, mode) in modes {
        for shape in shapes {
            for columns in shape.columns {
                Benchmark("crossover-\(modeName)-\(shape.name)-\(columns)cols") { benchmark in
                    let image = makeGradient(width: shape.width, height: shape.height)
                    var converter = DefaultConverter()
                    converter.rowWalkMode = mode

                    benchmark.startMeasurement()
                    for _ in benchmark.scaledIterations {
                        blackHole(converter.convert(image, columns: columns))
                    }
                    benchmark.stopMeasurement()
                }
            }
        }

        // Repeated-frame workload (AC#4): 10 consecutive converts of one image —
        // proves the parallel path holds up under a video/animation-style loop and
        // that the GCD pool is re-entered cleanly frame after frame.
        Benchmark("crossover-\(modeName)-repeated-80cols") { benchmark in
            let image = makeGradient(width: 800, height: 600)
            var converter = DefaultConverter()
            converter.rowWalkMode = mode

            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                for _ in 0..<10 {
                    blackHole(converter.convert(image, columns: 80))
                }
            }
            benchmark.stopMeasurement()
        }
    }
}
