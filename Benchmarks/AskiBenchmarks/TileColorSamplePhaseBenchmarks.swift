import Aski
import Benchmark

// Candidate-only phase attribution. The E2E instruments live in a separate
// file so a scalar-control worktree can build them without these new helpers.
func addTileColorSamplePhaseBenchmarks() {
    let spaces: [(String, RenderColorSpace)] = [("srgb", .sRGB), ("p3", .displayP3)]
    for (spaceName, space) in spaces {
        for alphaMode in ["opaque", "mixed"] {
            for columns in [8, 80, 256] {
                let side = columns * 2
                let key = "\(side)x\(side)-\(spaceName)-\(alphaMode)"
                Benchmark("aski92-prepare-\(key)", configuration: tileSampleConfiguration()) { benchmark in
                    let pixels = tileSamplePixels(side: side, alphaMode: alphaMode)
                    benchmark.startMeasurement()
                    for _ in benchmark.scaledIterations {
                        blackHole(TilePalette.makeColorSamples(pixels: pixels, width: side, height: side, colorSpace: space))
                    }
                    benchmark.stopMeasurement()
                }
                Benchmark("aski92-wu-accumulate-\(key)", configuration: tileSampleConfiguration()) { benchmark in
                    let samples = TilePalette.makeColorSamples(pixels: tileSamplePixels(side: side, alphaMode: alphaMode), width: side, height: side, colorSpace: space)
                    benchmark.startMeasurement()
                    for _ in benchmark.scaledIterations { blackHole(WuQuantizer(samples: samples)) }
                    benchmark.stopMeasurement()
                }
                for count in [8, 16, 64, 256] {
                    Benchmark("aski92-wu-split-\(key)-k\(count)", configuration: tileSampleConfiguration()) { benchmark in
                        let samples = TilePalette.makeColorSamples(pixels: tileSamplePixels(side: side, alphaMode: alphaMode), width: side, height: side, colorSpace: space)
                        let wu = WuQuantizer(samples: samples)
                        benchmark.startMeasurement()
                        for _ in benchmark.scaledIterations { blackHole(wu.palette(maxColors: count)) }
                        benchmark.stopMeasurement()
                    }
                    Benchmark("aski92-kmeans-\(key)-k\(count)", configuration: tileSampleConfiguration()) { benchmark in
                        let samples = TilePalette.makeColorSamples(pixels: tileSamplePixels(side: side, alphaMode: alphaMode), width: side, height: side, colorSpace: space)
                        let palette = WuQuantizer(samples: samples).palette(maxColors: count)
                        benchmark.startMeasurement()
                        for _ in benchmark.scaledIterations { blackHole(KMeansRefinement.refine(palette: palette, samples: samples)) }
                        benchmark.stopMeasurement()
                    }
                }
            }
        }
    }
}
