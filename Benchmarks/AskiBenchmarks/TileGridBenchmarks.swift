import Aski
import Benchmark
import CoreGraphics

/// Register TileGrid conversion and raster benchmarks. The conversion matrix
/// holds image dimensions and grid density constant while varying adaptive
/// palette cardinality, so the palette work is measured separately from the
/// fixed-palette path. Raster fixtures use a finite 16-colour palette and
/// cover the square/circle fast-path candidates with opaque and soft-masked
/// alpha output.
internal func addTileGridBenchmarks() {
    let quantizationCases: [(name: String, maxColors: Int)] = [
        ("tile-quantize-rich-512x512-256cols-adaptive8", 8),
        ("tile-quantize-rich-512x512-256cols-adaptive16", 16),
        ("tile-quantize-rich-512x512-256cols-adaptive64", 64),
    ]
    for benchmarkCase in quantizationCases {
        Benchmark(benchmarkCase.name) { benchmark in
            let image = makeTileFixture(width: 512, height: 512)
            let converter = TileGridConverter(palette: .adaptive(maxColors: benchmarkCase.maxColors))
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                blackHole(converter.convert(image, columns: 256))
            }
            benchmark.stopMeasurement()
        }
    }

    Benchmark("tile-quantize-rich-512x512-256cols-adaptive16-masked") { benchmark in
        let image = makeTileFixture(width: 512, height: 512)
        let mask = makeCircularMask(width: 512, height: 512)
        let converter = TileGridConverter(palette: .adaptive(maxColors: 16))
        let options = MaskOptions(image: mask, fallback: .transparent)
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(converter.convert(image, columns: 256, mask: options))
        }
        benchmark.stopMeasurement()
    }

    let rasterCases: [(name: String, shape: TileCellShape, masked: Bool)] = [
        ("tile-render-finite16-128x128-pixelart-square-scale8-unmasked", .square, false),
        ("tile-render-finite16-128x128-pixelart-circle-scale8-unmasked", .circle, false),
        ("tile-render-finite16-128x128-pixelart-square-scale8-masked", .square, true),
        ("tile-render-finite16-128x128-pixelart-circle-scale8-masked", .circle, true),
        ("tile-render-finite16-128x128-brick-square-scale8-unmasked", .square, false),
        ("tile-render-finite16-128x128-brick-circle-scale8-unmasked", .circle, false),
    ]
    for benchmarkCase in rasterCases {
        Benchmark(benchmarkCase.name) { benchmark in
            let grid = makeFinitePaletteTileGrid(columns: 128, rows: 128, masked: benchmarkCase.masked)
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                blackHole(
                    grid.renderImage(
                        mode: benchmarkCase.name.contains("brick") ? .brick : .pixelArt,
                        cellShape: benchmarkCase.shape,
                        scale: 8
                    ))
            }
            benchmark.stopMeasurement()
        }
    }

    let modes: [(String, TileGridMode)] = [
        ("pixelArt", .pixelArt),
        ("brick", .brick),
        ("mosaic", .mosaic),
    ]
    let shapes: [(String, TileCellShape)] = [
        ("square", .square),
        ("hex", .hex),
        ("triangle", .triangle),
        ("diamond", .diamond),
        ("circle", .circle),
    ]
    for (modeName, mode) in modes {
        for (shapeName, shape) in shapes {
            Benchmark("tile-render-64x64-\(modeName)-\(shapeName)-scale8") { benchmark in
                let grid = makeFinitePaletteTileGrid(columns: 64, rows: 64, masked: false)
                benchmark.startMeasurement()
                for _ in benchmark.scaledIterations {
                    blackHole(grid.renderImage(mode: mode, cellShape: shape, scale: 8))
                }
                benchmark.stopMeasurement()
            }
        }
    }

    Benchmark("tile-render-256x256-pixelart-square-scale32") { benchmark in
        let grid = makeFinitePaletteTileGrid(columns: 256, rows: 256, masked: false)
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(grid.renderImage(mode: .pixelArt, cellShape: .square, scale: 32))
        }
        benchmark.stopMeasurement()
    }
}

private func makeTileFixture(width: Int, height: Int) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * 4
            pixels[offset] = UInt8((x * 13 + y * 7) & 0xFF)
            pixels[offset + 1] = UInt8((x * 3 + y * 19) & 0xFF)
            pixels[offset + 2] = UInt8(((x ^ y) * 11) & 0xFF)
            pixels[offset + 3] = 255
        }
    }
    return context.makeImage()!
}

private func makeFinitePaletteTileGrid(columns: Int, rows: Int, masked: Bool) -> TileGrid {
    let colors: [SIMD3<Float>] = [
        .init(0.12, 0.18, 0.28), .init(0.22, 0.38, 0.56),
        .init(0.28, 0.58, 0.62), .init(0.40, 0.72, 0.52),
        .init(0.72, 0.78, 0.38), .init(0.94, 0.68, 0.24),
        .init(0.86, 0.38, 0.26), .init(0.66, 0.18, 0.34),
        .init(0.20, 0.24, 0.36), .init(0.34, 0.46, 0.68),
        .init(0.48, 0.70, 0.72), .init(0.62, 0.82, 0.64),
        .init(0.84, 0.84, 0.54), .init(0.98, 0.76, 0.38),
        .init(0.94, 0.50, 0.34), .init(0.78, 0.30, 0.48),
    ]
    let coverage: [Float] = [1, 0.75, 0.5, 0.25]
    let cells = (0..<rows).map { row in
        (0..<columns).map { column in
            let index = (row * 5 + column * 3) % colors.count
            return TileCell(
                displayColor: colors[index],
                alpha: 1,
                brightness: Float(index) / Float(colors.count - 1),
                coverage: masked ? coverage[(row + column) % coverage.count] : 1
            )
        }
    }
    return TileGrid(
        cells: cells,
        colorSpace: .sRGB,
        maskFallback: masked ? .transparent : nil,
        maskUsesHardEdges: false
    )
}
