import Aski
import Benchmark
import CoreGraphics

func addAnimationBenchmarks() {
    // animation-regression-static-convert-80cols runs `convert(800x600, 80col)`,
    // whose grid sits above parallelCellThreshold=1200 and takes the parallel
    // row walk (ASTSK-51). That trades ~2.4x total CPU for a -27% wall win, so
    // wallClock and cpuTotal need SEPARATE budgets (ASTSK-58) — one shared knob
    // is cpuTotal-bound and stale. The parallel path's tail inflates under machine
    // load, so budgets are sized ~25% above the worst CONTENDED p90 across 5 runs
    // (2026-07-13, `just bench` x3 isolated + full-suite + contended): contended
    // wall 7.0 ms, cpuTotal 21 ms, malloc 29K (quiet p90s: wall 5.3, cpu 17, malloc
    // 19K). Wall tightened 9->8 ms (real tighten, still above the 7.0 ms peak);
    // cpuTotal 26 ms and malloc 36K re-baselined to the fan-out cost. A real
    // regression still blows well past these.
    Benchmark(
        "animation-regression-static-convert-80cols",
        configuration: animationBenchmarkConfiguration(wallBudgetMilliseconds: 8, cpuBudgetMilliseconds: 26, mallocCountBudget: 36_000)
    ) { benchmark in
        let image = makeGradient(width: 800, height: 600)
        let converter = DefaultConverter()

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(converter.convert(image, columns: 80))
        }
        benchmark.stopMeasurement()
    }

    Benchmark("animation-build-gradient-80cols-k6", configuration: animationBenchmarkConfiguration(wallBudgetMilliseconds: 170, mallocCountBudget: 450_000)) { benchmark in
        let image = makeGradient(width: 800, height: 600)
        let converter = DefaultConverter()
        let options = AnimationOptions(duration: 5, seed: 1, cycling: CyclingOptions(k: 6, speed: 1, intensity: 0.6, randomness: 0.5))

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(converter.animate(image, columns: 80, options: options))
        }
        benchmark.stopMeasurement()
    }

    Benchmark("animation-grid-at-80cols", configuration: animationBenchmarkConfiguration(wallBudgetMilliseconds: 1, mallocCountBudget: 10_000)) { benchmark in
        let image = makeGradient(width: 800, height: 600)
        let animated = DefaultConverter().animate(
            image,
            columns: 80,
            options: AnimationOptions(duration: 5, seed: 1, cycling: CyclingOptions(k: 6, speed: 1, intensity: 1, randomness: 0.5))
        )

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(animated.grid(at: 2.5))
        }
        benchmark.stopMeasurement()
    }

    Benchmark("animation-materialize-80cols-5s-60fps", configuration: animationBenchmarkConfiguration(wallBudgetMilliseconds: 60, mallocCountBudget: 3_000_000)) { benchmark in
        let image = makeGradient(width: 800, height: 600)
        let animated = DefaultConverter().animate(
            image,
            columns: 80,
            options: AnimationOptions(duration: 5, seed: 1, cycling: CyclingOptions(k: 6, speed: 1, intensity: 1, randomness: 0.5))
        )

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(animated.materialize(frameRate: 60))
        }
        benchmark.stopMeasurement()
    }
}

// Workloads that call `convert`/`animate` on >1200-cell grids take the parallel
// row walk (ASTSK-51), where total CPU fans out to ~2.4x wall. Those pass an
// explicit `cpuBudgetMilliseconds`; serial workloads leave it nil and reuse the
// wall budget (cpuTotal ~= wallClock). See ASTSK-58.
private func animationBenchmarkConfiguration(
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
