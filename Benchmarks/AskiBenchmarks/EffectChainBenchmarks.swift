import Aski
import Benchmark
import CoreGraphics

let perfSpikeBenchmarks: @Sendable () -> Void = {
    Benchmark("perf-spike-ascii-192x108-no-effects", configuration: effectBenchmarkConfiguration(budgetMilliseconds: 142, mallocCountBudget: 410_000)) { benchmark in
        let grid = makeASCIIGrid(columns: 192, rows: 108)
        let font = ASCIIFont.system(size: 8)
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(grid.renderImage(font: font, backgroundColor: bg, scale: 1))
        }
        benchmark.stopMeasurement()
    }

    Benchmark("perf-spike-ascii-192x108-3-stock-effects", configuration: effectBenchmarkConfiguration(budgetMilliseconds: 145, mallocCountBudget: 410_000)) { benchmark in
        let grid = makeASCIIGrid(columns: 192, rows: 108)
        let font = ASCIIFont.system(size: 8)
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let composition = stockComposition(background: bg)
        let chain = EffectChain([.vignette(intensity: 0.4), .bloom(intensity: 0.5, radius: 8)])

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(grid.renderImage(font: font, backgroundColor: bg, scale: 1, composition: composition, effects: chain))
        }
        benchmark.stopMeasurement()
    }

    Benchmark("perf-spike-ascii-192x108-1-metallib-effect", configuration: effectBenchmarkConfiguration(budgetMilliseconds: 145, mallocCountBudget: 410_000)) { benchmark in
        let grid = makeASCIIGrid(columns: 192, rows: 108)
        let font = ASCIIFont.system(size: 8)
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let chain = EffectChain([.scanLines(intensity: 0.6, frequency: 4)])

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(grid.renderImage(font: font, backgroundColor: bg, scale: 1, effects: chain))
        }
        benchmark.stopMeasurement()
    }

    Benchmark("perf-spike-ascii-192x108-full-metallib-chain", configuration: effectBenchmarkConfiguration(budgetMilliseconds: 147, mallocCountBudget: 410_000)) { benchmark in
        let grid = makeASCIIGrid(columns: 192, rows: 108)
        let font = ASCIIFont.system(size: 8)
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let chain = fullMetallibChain()

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(grid.renderImage(font: font, backgroundColor: bg, scale: 1, effects: chain))
        }
        benchmark.stopMeasurement()
    }

    Benchmark(
        "perf-spike-aski-render-engine-192x108-warm-cache-3-effects",
        configuration: effectBenchmarkConfiguration(budgetMilliseconds: 148, mallocCountBudget: 412_000)
    ) { (benchmark: Benchmark, state: ActorBenchmarkState) in
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(
                try await state.engine.render(
                    state.grid,
                    font: state.font,
                    backgroundColor: state.background,
                    scale: 1,
                    composition: state.composition,
                    effects: state.effects
                ))
        }
        benchmark.stopMeasurement()
    } setup: {
        let grid = makeASCIIGrid(columns: 192, rows: 108)
        let font = ASCIIFont.system(size: 8)
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let composition = stockComposition(background: background)
        let effects = EffectChain([.vignette(intensity: 0.4), .bloom(intensity: 0.5, radius: 8)])
        let engine = AskiRenderEngine()
        _ = try await engine.render(
            grid,
            font: font,
            backgroundColor: background,
            scale: 1,
            composition: composition,
            effects: effects
        )
        return ActorBenchmarkState(
            grid: grid,
            font: font,
            background: background,
            composition: composition,
            effects: effects,
            engine: engine
        )
    }

    Benchmark("perf-spike-tilegrid-64x64-3-effects", configuration: effectBenchmarkConfiguration(budgetMilliseconds: 10, mallocCountBudget: 42_000)) { benchmark in
        let grid = makeTileGrid(columns: 64, rows: 64)
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let composition = stockComposition(background: bg)
        let chain = EffectChain([.vignette(intensity: 0.4), .bloom(intensity: 0.5, radius: 8)])

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(grid.renderImage(mode: .pixelArt, cellShape: .square, scale: 1, backgroundColor: bg, composition: composition, effects: chain))
        }
        benchmark.stopMeasurement()
    }
}

func addEffectChainBenchmarks() {
    perfSpikeBenchmarks()
}

private struct ActorBenchmarkState {
    let grid: ASCIIGrid
    let font: ASCIIFont
    let background: CGColor
    let composition: CompositionOptions
    let effects: EffectChain
    let engine: AskiRenderEngine
}

private func effectBenchmarkConfiguration(
    budgetMilliseconds: Int,
    mallocCountBudget: Int
) -> Benchmark.Configuration {
    let timeBudget = BenchmarkThresholds(
        absolute: [
            .p50: .milliseconds(budgetMilliseconds),
            .p90: .milliseconds(budgetMilliseconds),
        ]
    )

    return Benchmark.Configuration(
        metrics: [.wallClock, .cpuTotal, .mallocCountTotal],
        warmupIterations: 1,
        scalingFactor: .one,
        maxDuration: .seconds(3),
        maxIterations: 6,
        thresholds: [
            .wallClock: timeBudget,
            .cpuTotal: timeBudget,
            .mallocCountTotal: BenchmarkThresholds(absolute: [
                .p50: .count(mallocCountBudget),
                .p90: .count(mallocCountBudget),
            ]),
        ]
    )
}

private func stockComposition(background: CGColor) -> CompositionOptions {
    CompositionOptions(
        background: .solid(background),
        colorOverlay: ColorOverlay(color: CGColor(red: 1, green: 0.8, blue: 0.6, alpha: 1))
    )
}

private func fullMetallibChain() -> EffectChain {
    EffectChain([
        .scanLines(intensity: 0.6, frequency: 4),
        .crtCurvature(intensity: 0.25),
        .halftone(scale: 8),
        .filmDust(intensity: 0.18, seed: 0x1234_5678_9ABC_DEF0),
        .glitch(intensity: 0.18, seed: 0xFEDC_BA98_7654_3210),
        .rgbSplit(intensity: 0.6),
        .filmGrain(intensity: 0.14, seed: 0x0F0E_0D0C_0B0A_0908),
    ])
}

private func makeASCIIGrid(columns: Int, rows: Int) -> ASCIIGrid {
    let characters = Array("@#S%?*+;:,.")
    let cells = (0..<rows).map { row in
        (0..<columns).map { column in
            let t = Float(column) / Float(max(columns - 1, 1))
            let y = Float(row) / Float(max(rows - 1, 1))
            return ASCIICell(
                character: characters[(row + column) % characters.count],
                displayColor: SIMD3<Float>(max(0.2, t), max(0.2, 1 - y), max(0.2, (t + y) * 0.5)),
                alpha: 1,
                brightness: (t + y) * 0.5
            )
        }
    }
    return ASCIIGrid(cells: cells, colorSpace: .sRGB)
}

private func makeTileGrid(columns: Int, rows: Int) -> TileGrid {
    let cells = (0..<rows).map { row in
        (0..<columns).map { column in
            let t = Float(column) / Float(max(columns - 1, 1))
            let y = Float(row) / Float(max(rows - 1, 1))
            return TileCell(
                displayColor: SIMD3<Float>(max(0.2, 1 - t), max(0.2, y), max(0.2, (t + y) * 0.5)),
                alpha: 1,
                brightness: (t + y) * 0.5
            )
        }
    }
    return TileGrid(cells: cells, colorSpace: .sRGB)
}
