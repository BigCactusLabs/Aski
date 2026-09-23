@_spi(AskiResearch) import Aski
import Benchmark
import Foundation

/// Measurement-only workloads retained from ASTSK-55's gamut-path audit.
func addASTSK55Benchmarks() {
    addGamutMappingBenchmarks()
}

private func addGamutMappingBenchmarks() {
    let cases: [(name: String, mapper: (SIMD3<Float>) -> SIMD3<Float>)] = [
        ("gamut-adaptiveL0-srgb-out-of-gamut-256", GamutMapping.adaptiveL0ToSRGB),
        ("gamut-adaptiveL0-displayp3-out-of-gamut-256", GamutMapping.adaptiveL0ToDisplayP3),
        ("gamut-raytrace-srgb-out-of-gamut-256", GamutMapping.rayTraceToSRGB),
        ("gamut-raytrace-displayp3-out-of-gamut-256", GamutMapping.rayTraceToDisplayP3),
    ]

    for benchmarkCase in cases {
        Benchmark(benchmarkCase.name) { benchmark in
            let samples = makeOutOfGamutOKLABSamples(count: 256)

            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                for sample in samples {
                    blackHole(benchmarkCase.mapper(sample))
                }
            }
            benchmark.stopMeasurement()
        }
    }
}

private func makeOutOfGamutOKLABSamples(count: Int) -> [SIMD3<Float>] {
    (0..<count).map { index in
        let hue = Float(index) * .pi * 2 / Float(count)
        let lightness = 0.25 + Float(index % 11) * 0.055
        let chroma = 0.42 + Float(index % 7) * 0.035
        return SIMD3(lightness, chroma * cos(hue), chroma * sin(hue))
    }
}
