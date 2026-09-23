import Aski
import Benchmark
import CoreGraphics

func addHelmlabBenchmarks() {
    // Opt-in Helmlab matching path on `convert(800x600, 80col)` with
    // .helmlabCompressed. Its own threshold — NOT folded into the default-path
    // budgets. Like the default static-convert, this grid is above
    // parallelCellThreshold=1200 and takes the parallel row walk (ASTSK-51),
    // which fans total CPU out to ~2.4x wall — so wallClock and cpuTotal carry
    // SEPARATE budgets (ASTSK-58) instead of one shared, now-stale knob.
    // Post-parallel matrix (2026-07-13, `just bench` x3 isolated + full-suite,
    // worst p90): wall 5.31 ms (was ~8.2 ms serial), cpuTotal 16 ms, malloc 29K
    // (contention-dependent — 24K isolated, 29K under full-suite load). Wall
    // tightened 12->8 ms (extra headroom for this path's documented wall/CPU
    // noise-sensitivity); cpuTotal 20 ms and malloc 36K re-baselined to the
    // fan-out cost (~25% over the worst observed peak). A real regression in the
    // per-cell Double MetricSpace transform still blows well past these.
    Benchmark(
        "helmlab-compressed-convert-80cols",
        configuration: helmlabBenchmarkConfiguration(wallBudgetMilliseconds: 8, cpuBudgetMilliseconds: 20, mallocCountBudget: 36_000)
    ) { benchmark in
        let image = makeGradient(width: 800, height: 600)
        let converter = ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.ansi16,
            paletteMatching: .helmlabCompressed
        )
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(converter.convert(image, columns: 80))
        }
        benchmark.stopMeasurement()
    }
}

// wallClock and cpuTotal carry separate budgets because this convert takes the
// parallel row walk (cpuTotal ~= 2.4x wallClock). Serial callers may leave
// `cpuBudgetMilliseconds` nil to reuse the wall budget. See ASTSK-58.
private func helmlabBenchmarkConfiguration(
    wallBudgetMilliseconds: Int,
    cpuBudgetMilliseconds: Int? = nil,
    mallocCountBudget: Int
) -> Benchmark.Configuration {
    let resolvedCPUBudget = cpuBudgetMilliseconds ?? wallBudgetMilliseconds
    return Benchmark.Configuration(
        metrics: [.wallClock, .cpuTotal, .mallocCountTotal],
        warmupIterations: 1,
        scalingFactor: .one,
        maxDuration: .seconds(3),
        maxIterations: 6,
        thresholds: [
            .wallClock: BenchmarkThresholds(absolute: [
                .p50: .milliseconds(wallBudgetMilliseconds),
                .p90: .milliseconds(wallBudgetMilliseconds),
            ]),
            .cpuTotal: BenchmarkThresholds(absolute: [
                .p50: .milliseconds(resolvedCPUBudget),
                .p90: .milliseconds(resolvedCPUBudget),
            ]),
            .mallocCountTotal: BenchmarkThresholds(absolute: [
                .p50: .count(mallocCountBudget),
                .p90: .count(mallocCountBudget),
            ]),
        ]
    )
}
