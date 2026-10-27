import Aski
import Benchmark
import CoreGraphics

/// ASKI-91/94: instruments only. No existing thresholds or production paths
/// change. Fixture/schedule construction is outside the measured frame/render.
func addRenderingGroundworkBenchmarks() {
    let configuration = Benchmark.Configuration(
        metrics: [.wallClock, .cpuTotal, .mallocCountTotal, .peakMemoryResident],
        warmupIterations: 1, scalingFactor: .one, maxDuration: .seconds(3), maxIterations: 6
    )
    let overlays: [(String, OngoingPattern)] = [
        ("pulse", .pulse(period: 1, depth: 0.8)),
        ("wave-horizontal", .wave(amplitude: 0.4, frequency: 1, direction: .horizontal)),
        ("wave-diagonal", .wave(amplitude: 0.4, frequency: 1, direction: .diagonal)),
        ("neutral-pulse", .pulse(period: 1, depth: 0)),
        ("neutral-wave", .wave(amplitude: 0, frequency: 1)),
    ]
    // 15 overlay + 9 animation-frame workloads = 24 ASKI-91 identities.
    for columns in [80, 192, 288] {
        for (name, pattern) in overlays {
            Benchmark("aski91-overlay-\(name)-\(columns)cols", configuration: configuration) { benchmark in
                let grid = groundworkGrid(columns: columns)
                benchmark.startMeasurement()
                for _ in benchmark.scaledIterations {
                    blackHole(grid.applyingOngoingPattern(pattern, at: 0.375))
                }
                benchmark.stopMeasurement()
            }
        }
        for name in ["radial-active", "radial-complete", "no-pattern"] {
            Benchmark("aski91-frame-\(name)-\(columns)cols", configuration: configuration) { benchmark in
                let image = makeGradient(width: 800, height: 600)
                let entrance: EntrancePattern? = name == "no-pattern" ? nil : .reveal(origin: .init(x: -0.25, y: 0.5))
                let animated = DefaultConverter().animate(
                    image, columns: columns,
                    options: AnimationOptions(duration: 5, seed: 1, cycling: nil, entrance: entrance)
                )
                let time = name == "radial-complete" ? 5.0 : 2.5
                benchmark.startMeasurement()
                for _ in benchmark.scaledIterations { blackHole(animated.grid(at: time)) }
                benchmark.stopMeasurement()
            }
        }
    }

    let sizingCases: [(String, BackgroundSizing)] = [("fill", .fill), ("fit", .fit), ("stretch", .stretch)]
    // 18 original-image + 9 other-fallback controls = 27 ASKI-94 identities.
    for columns in [80, 160, 320] {
        for (name, sizing) in sizingCases {
            for grounded in [false, true] {
                let branch = grounded ? "grounded" : "overlay"
                Benchmark("aski94-original-\(name)-\(branch)-\(columns)cols", configuration: configuration) { benchmark in
                    let source = makeGradient(width: 800, height: 600)
                    let grid = groundworkGrid(columns: columns, fallback: .originalImage(source, sizing: sizing), grounded: grounded)
                    let font = ASCIIFont.system(size: 10)
                    let background = CGColor(gray: 0, alpha: 0)
                    benchmark.startMeasurement()
                    for _ in benchmark.scaledIterations {
                        blackHole(grid.renderImage(font: font, backgroundColor: background, scale: 1))
                    }
                    benchmark.stopMeasurement()
                }
            }
        }
        for name in ["transparent", "solid", "character"] {
            Benchmark("aski94-control-\(name)-\(columns)cols", configuration: configuration) { benchmark in
                let fallback: MaskFallback
                switch name {
                case "solid": fallback = .solid(CGColor(gray: 0.4, alpha: 1))
                case "character": fallback = .character(".", color: nil)
                default: fallback = .transparent
                }
                let grid = groundworkGrid(columns: columns, fallback: fallback)
                let font = ASCIIFont.system(size: 10)
                let background = CGColor(gray: 0, alpha: 0)
                benchmark.startMeasurement()
                for _ in benchmark.scaledIterations {
                    blackHole(grid.renderImage(font: font, backgroundColor: background, scale: 1))
                }
                benchmark.stopMeasurement()
            }
        }
    }
}

/// A deterministic rectangular frame. Coverage includes 0, 1/4, 3/4 and 1:
/// the overlay path skips the last quarter; the grounded completed branch
/// still draws every existing cell. That is a source-level count, not a GPU
/// raster-work measurement. Ragged geometry is covered by native contracts.
private func groundworkGrid(columns: Int, fallback: MaskFallback? = nil, grounded: Bool = false) -> ASCIIGrid {
    let coverage: [Float] = [0, 0.25, 0.75, 1]
    let cells = (0..<(columns / 4)).map { row in
        (0..<columns).map { column in
            ASCIICell(
                character: (row + column).isMultiple(of: 2) ? "#" : "+",
                displayColor: SIMD3<Float>(0.2, 0.5, 0.8), alpha: 0.8,
                brightness: 0.5, coverage: coverage[(row + column) % 4])
        }
    }
    return ASCIIGrid(
        cells: cells, colorSpace: .sRGB, maskFallback: fallback,
        maskGroundColor: grounded ? CGColor(gray: 0.1, alpha: 1) : nil)
}
