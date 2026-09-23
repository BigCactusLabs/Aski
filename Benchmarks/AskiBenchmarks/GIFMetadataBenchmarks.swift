import Aski
import Benchmark
import CoreGraphics
import Foundation

private let gifMetadataFrameCount = 120

func addGIFMetadataBenchmarks() {
    addGIFMetadataBenchmark(name: "gif-metadata-one-delay-scan-120frames", scanCount: 1)
    addGIFMetadataBenchmark(name: "gif-metadata-two-delay-scans-120frames", scanCount: 2)

    let name = "gif-decode-noop-120frames"
    let root = gifBenchmarkRoot(name)
    Benchmark(
        name,
        configuration: gifBenchmarkConfiguration(),
        closure: { benchmark, source in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                var count = 0
                for try await _ in ASCIIGIFDecoder().grids(
                    fromGIFAt: source,
                    transform: { _ in ASCIIGrid(cells: [], colorSpace: .sRGB) }
                ) {
                    count += 1
                }
                if count != gifMetadataFrameCount {
                    benchmark.error("GIF decode produced \(count) frames; expected \(gifMetadataFrameCount)")
                }
                blackHole(count)
            }
            benchmark.stopMeasurement()
        },
        setup: { try makeGIFBenchmarkFixture(at: root) },
        teardown: { try? FileManager.default.removeItem(at: root) }
    )
}

private func addGIFMetadataBenchmark(name: String, scanCount: Int) {
    let root = gifBenchmarkRoot(name)
    Benchmark(
        name,
        configuration: gifBenchmarkConfiguration(),
        closure: { benchmark, source in
            let decoder = ASCIIGIFDecoder()
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                for _ in 0..<scanCount {
                    let info = try decoder.containerInfo(ofGIFAt: source)
                    if info.frameCount != gifMetadataFrameCount {
                        benchmark.error(
                            "GIF metadata reported \(info.frameCount) frames; expected \(gifMetadataFrameCount)"
                        )
                    }
                    blackHole(info.frameDelays)
                }
            }
            benchmark.stopMeasurement()
        },
        setup: { try makeGIFBenchmarkFixture(at: root) },
        teardown: { try? FileManager.default.removeItem(at: root) }
    )
}

private func gifBenchmarkConfiguration() -> Benchmark.Configuration {
    .init(
        metrics: [.wallClock, .throughput, .cpuTotal, .mallocCountTotal],
        warmupIterations: 1,
        maxDuration: .seconds(2),
        maxIterations: 5
    )
}

private func gifBenchmarkRoot(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("AskiGIFBenchmarks", isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
}

private func makeGIFBenchmarkFixture(at root: URL) throws -> URL {
    try? FileManager.default.removeItem(at: root)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("source.gif")
    let image = gifBenchmarkImage()
    let frames = (0..<gifMetadataFrameCount).map { index in
        RenderedGIFFrame(
            image: image,
            delay: index.isMultiple(of: 3) ? 0.04 : 0.08
        )
    }
    try ASCIIGIFEncoder().write(frames, loopCount: 0, to: source)
    return source
}

private func gifBenchmarkImage() -> CGImage {
    let width = 32
    let height = 32
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1)
    context.fill(CGRect(x: 8, y: 8, width: 16, height: 16))
    return context.makeImage()!
}
