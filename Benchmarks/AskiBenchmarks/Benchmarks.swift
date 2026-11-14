import Aski
import Benchmark
import CoreGraphics
import Darwin
import Foundation
#if canImport(MallocInterposerSwift)
    import MallocInterposerSwift
#endif

let benchmarks: @Sendable () -> Void = {
    reportAllocatorObservation()

    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .mallocCountTotal, .allocatedResidentMemory],
        warmupIterations: 3,
        scalingFactor: .one
    )

    Benchmark("convert-gradient-800x600-80cols") { benchmark in
        let image = makeGradient(width: 800, height: 600)
        let converter = DefaultConverter()

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(converter.convert(image, columns: 80))
        }
        benchmark.stopMeasurement()
    }

    Benchmark("convert-gradient-2400x1800-120cols") { benchmark in
        let image = makeGradient(width: 2400, height: 1800)
        let converter = DefaultConverter()

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(converter.convert(image, columns: 120))
        }
        benchmark.stopMeasurement()
    }

    Benchmark("render-image-gradient-80cols") { benchmark in
        let image = makeGradient(width: 800, height: 600)
        let grid = DefaultConverter().convert(image, columns: 80)
        let font = ASCIIFont.system(size: 10)
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(grid.renderImage(font: font, backgroundColor: background, scale: 1))
        }
        benchmark.stopMeasurement()
    }

    addTileGridBenchmarks()
    addEffectChainBenchmarks()
    addMaskBenchmarks()
    addAnimationBenchmarks()
    addRenderingGroundworkBenchmarks()
    addBrightnessPoolGroundworkBenchmarks()
    addHelmlabBenchmarks()
    addParallelismCrossoverBenchmarks()
    addVideoPipelineBenchmarks()
    addVideoSelectionBenchmarks()
    addGIFMetadataBenchmarks()
    addASTSK55Benchmarks()
    addPreparationBenchmarks()
    addShapeContextFootprintBenchmarks()
}

internal func makeGradient(width: Int, height: Int) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    )!

    for x in 0..<width {
        let t = CGFloat(x) / CGFloat(width - 1)
        context.setFillColor(red: t, green: t, blue: t, alpha: 1)
        context.fill(CGRect(x: x, y: 0, width: 1, height: height))
    }

    return context.makeImage()!
}

// Runs before registration, outside every measured workload. The pinned runner
// enables counting only around measurement and takes fresh counter snapshots.
private func reportAllocatorObservation() {
    var observation: [String: Any] = ["schema_version": 1, "pid": getpid(), "backend": "unavailable"]
    #if canImport(MallocInterposerSwift)
        let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_interposer_get_stats")
        var info = Dl_info()
        if let symbol, dladdr(symbol, &info) != 0, let image = info.dli_fname {
            observation["image"] = String(cString: image)
        }
        MallocInterposerSwift.hook()
        let before = MallocInterposerSwift.getStatistics()
        // A real libc allocation, escaped through blackHole so release optimization
        // cannot remove the call. No counter reset changes upstream state.
        let pointer = malloc(4096)
        blackHole(pointer)
        free(pointer)
        let after = MallocInterposerSwift.getStatistics()
        MallocInterposerSwift.unhook()
        observation["backend"] = "malloc-interposer"
        observation["malloc_delta"] = after.mallocCount - before.mallocCount
        observation["free_delta"] = after.freeCount - before.freeCount
        observation["allocated"] = pointer != nil
    #endif
    if let data = try? JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys]),
        let json = String(data: data, encoding: .utf8)
    {
        FileHandle.standardError.write(Data(("ASKI_ALLOCATOR_OBSERVATION " + json + "\n").utf8))
    }
}
