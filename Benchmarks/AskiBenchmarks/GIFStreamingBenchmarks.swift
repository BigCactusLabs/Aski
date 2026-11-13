import Aski
import Benchmark
import CoreGraphics
import Foundation

/// Each frame is freshly rendered: reusing a single CGImage would hide the
/// retained-array cost. Opt-in sizes are for isolated process RSS captures.
func addGIFStreamingBenchmarks() {
    let counts = ProcessInfo.processInfo.environment["ASKI_GIF_MEMORY_MATRIX"] == "1" ? [24, 240, 1200] : [24]
    for count in counts {
        for retained in [false, true] {
            let mode = retained ? "retained" : "incremental"
            Benchmark(
                "gif-render-encode-\(mode)-\(count)frames",
                configuration: .init(
                    metrics: [.wallClock, .cpuTotal, .mallocCountTotal, .peakMemoryResident],
                    units: [.mallocCountTotal: .count, .peakMemoryResident: .count],
                    warmupIterations: 0, maxDuration: .seconds(10), maxIterations: 1
                )
            ) { benchmark in
                let grid = DefaultConverter().convert(makeGradient(width: 640, height: 360), columns: 80)
                let font = ASCIIFont.system(size: 10)
                let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
                let output = FileManager.default.temporaryDirectory
                    .appendingPathComponent("AskiGIFStreaming-\(UUID().uuidString).gif")
                defer { try? FileManager.default.removeItem(at: output) }
                benchmark.startMeasurement()
                for _ in benchmark.scaledIterations {
                    if retained {
                        let frames = (0..<count).map { _ in
                            RenderedGIFFrame(
                                image: grid.renderImage(font: font, backgroundColor: background, scale: 1), delay: 0.04
                            )
                        }
                        blackHole(try ASCIIGIFEncoder().write(frames, loopCount: 0, to: output))
                    } else {
                        let session = try GIFEncodeSession(frameCount: count, loopCount: 0, to: output)
                        for _ in 0..<count {
                            try autoreleasepool {
                                try session.append(
                                    RenderedGIFFrame(
                                        image: grid.renderImage(font: font, backgroundColor: background, scale: 1), delay: 0.04
                                    ))
                            }
                        }
                        blackHole(try session.finish())
                    }
                }
                benchmark.stopMeasurement()
            }
        }
    }
}
