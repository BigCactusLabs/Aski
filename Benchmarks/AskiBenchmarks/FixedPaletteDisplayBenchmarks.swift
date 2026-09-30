import Aski
import Benchmark
import CoreGraphics

/// ASKI-90 instruments, not budgets. `convert` includes palette resolution and
/// display-table preparation. Fixtures and converter construction are outside
/// measurement, following the existing conversion suite's convention.
///
/// Compare to a separate worktree with identical instruments and only
/// CellSampling.swift / ResolvedPalette.swift restored from ca5dbaff. Require
/// wall/CPU/malloc samples for every identity; run five alternating complete
/// control/candidate pairs. No adoption from an isolated table-lookup timing.
func addFixedPaletteDisplayBenchmarks() {
    let configuration = Benchmark.Configuration(
        metrics: [.wallClock, .cpuTotal, .mallocCountTotal],
        warmupIterations: 1, scalingFactor: .one,
        maxDuration: .seconds(2), maxIterations: 10)
    let palettes: [(String, BuiltInPalette)] = [
        ("ansi16", .ansi16), ("mono", .monochrome), ("passthrough", .fullColor),
    ]
    let spaces: [(String, RenderColorSpace)] = [("srgb", .sRGB), ("p3", .displayP3)]
    let modes: [(String, GridRowWalk.Mode)] = [("serial", .forcedSerial), ("parallel", .forcedParallel)]

    // 48 small/representative/large conversion cases, including pass-through controls.
    for (paletteName, palette) in palettes {
        for (spaceName, space) in spaces {
            for (modeName, mode) in modes {
                for columns in [1, 8, 80, 512] {
                    Benchmark("aski90-convert-\(paletteName)-\(spaceName)-\(modeName)-\(columns)cols", configuration: configuration) { benchmark in
                        let image = makeFixedPaletteDisplayFixture()
                        var converter = DefaultConverter(characterSet: .standard, palette: palette, colorSpace: space)
                        converter.rowWalkMode = mode
                        benchmark.startMeasurement()
                        for _ in benchmark.scaledIterations { blackHole(converter.convert(image, columns: columns)) }
                        benchmark.stopMeasurement()
                    }
                }
            }

            // Six ranked construction and six repeated-frame cases. Preparation
            // happens once per conversion, not once per benchmark or forever.
            Benchmark("aski90-ranked-\(paletteName)-\(spaceName)-80cols", configuration: configuration) { benchmark in
                let image = makeFixedPaletteDisplayFixture()
                let converter = DefaultConverter(characterSet: .standard, palette: palette, colorSpace: space)
                let options = AnimationOptions(duration: 5, seed: 1, cycling: CyclingOptions(k: 6, speed: 1, intensity: 0.6, randomness: 0.5))
                benchmark.startMeasurement()
                for _ in benchmark.scaledIterations { blackHole(converter.animate(image, columns: 80, options: options)) }
                benchmark.stopMeasurement()
            }
            Benchmark("aski90-repeated-\(paletteName)-\(spaceName)-80cols", configuration: configuration) { benchmark in
                let image = makeFixedPaletteDisplayFixture()
                let converter = DefaultConverter(characterSet: .standard, palette: palette, colorSpace: space)
                benchmark.startMeasurement()
                for _ in benchmark.scaledIterations {
                    for _ in 0..<10 { blackHole(converter.convert(image, columns: 80)) }
                }
                benchmark.stopMeasurement()
            }
        }
    }

    // Ten policy controls: vary one policy at a time rather than burying this
    // focused experiment in a full Cartesian suite. Unit parity covers all pairs.
    let policies: [(String, PaletteMatchingPolicy, GamutMappingPolicy)] = [
        ("hyab", .oklabHyAB, .rayTrace),
        ("helmlab", .helmlabEuclidean, .rayTrace),
        ("helmlab-compressed", .helmlabCompressed, .rayTrace),
        ("clip", .oklabEuclidean, .clip),
        ("adaptive", .oklabEuclidean, .adaptiveL0),
    ]
    for (name, matching, gamut) in policies {
        for (spaceName, space) in spaces {
            Benchmark("aski90-policy-\(name)-\(spaceName)-80cols", configuration: configuration) { benchmark in
                let image = makeFixedPaletteDisplayFixture()
                let converter = DefaultConverter(
                    characterSet: .standard, palette: .ansi16, colorSpace: space,
                    paletteMatching: matching, gamutMapping: gamut)
                benchmark.startMeasurement()
                for _ in benchmark.scaledIterations { blackHole(converter.convert(image, columns: 80)) }
                benchmark.stopMeasurement()
            }
        }
    }
}

/// Redistributable synthetic color/alpha input; unlike a gray gradient this
/// exercises ANSI chroma choices. Large enough for the 512-column lattice.
private func makeFixedPaletteDisplayFixture() -> CGImage {
    let context = CGContext(
        data: nil, width: 1024, height: 768, bitsPerComponent: 8, bytesPerRow: 4096,
        space: CGColorSpace(name: CGColorSpace.displayP3)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for row in 0..<24 {
        for column in 0..<32 {
            let index = row * 32 + column
            context.setFillColor(
                red: CGFloat((index * 37) % 256) / 255,
                green: CGFloat((index * 73) % 256) / 255,
                blue: CGFloat((index * 19) % 256) / 255,
                alpha: [CGFloat(0), 0.25, 0.5, 1][index % 4])
            context.fill(CGRect(x: column * 32, y: row * 32, width: 32, height: 32))
        }
    }
    return context.makeImage()!
}
