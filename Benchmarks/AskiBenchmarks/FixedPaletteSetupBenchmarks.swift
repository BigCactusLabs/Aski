import Aski
import Benchmark

/// Isolate matching-coordinate and display-table preparation from image and
/// glyph work. Each operation resolves a fresh palette from the same content
/// as conversion. The scalar control prepares matching coordinates only.
func addFixedPaletteSetupBenchmarks() {
    let configuration = Benchmark.Configuration(
        metrics: [.wallClock, .cpuTotal, .mallocCountTotal],
        units: [.mallocCountTotal: .count],
        warmupIterations: 1, scalingFactor: .kilo,
        maxDuration: .seconds(2), maxIterations: 10)
    let palettes: [(String, BuiltInPalette)] = [
        ("ansi16", .ansi16), ("mono", .monochrome), ("passthrough", .fullColor),
    ]
    let spaces: [(String, RenderColorSpace)] = [("srgb", .sRGB), ("p3", .displayP3)]
    let policies: [(String, PaletteMatchingPolicy, GamutMappingPolicy)] = [
        ("default", .oklabEuclidean, .rayTrace),
        ("hyab", .oklabHyAB, .rayTrace),
        ("helmlab", .helmlabEuclidean, .rayTrace),
        ("helmlab-compressed", .helmlabCompressed, .rayTrace),
        ("clip", .oklabEuclidean, .clip),
        ("adaptive", .oklabEuclidean, .adaptiveL0),
    ]

    for (paletteName, palette) in palettes {
        let content = palette.content
        for (spaceName, space) in spaces {
            for (policyName, matching, gamut) in policies {
                Benchmark("aski90-setup-\(paletteName)-\(spaceName)-\(policyName)", configuration: configuration) { benchmark in
                    benchmark.startMeasurement()
                    for _ in benchmark.scaledIterations {
                        let palette = ResolvedPalette(content: content, matching: matching)
                        let displayColors = palette.prepareDisplayColors(colorSpace: space, policy: gamut)
                        blackHole((palette, displayColors))
                    }
                    benchmark.stopMeasurement()
                }
            }
        }
    }
}
