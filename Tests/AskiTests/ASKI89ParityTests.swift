import CoreGraphics
import CryptoKit
import Foundation
import Testing
@_spi(AskiResearch) @testable import Aski

struct ASKI89ParityTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ASKI89_PARITY_DIR"] != nil))
    func exportNativeParity() throws {
        let output = try #require(ProcessInfo.processInfo.environment["ASKI89_PARITY_DIR"])
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)

        let image = TestImages.horizontalGradient(width: 2400, height: 1800)
        let reversed = try makeImage(like: image, flat: false)
        let flat = try makeImage(like: image, flat: true)
        let regimes = [(80, 2, 0), (120, 2, 0), (240, 2, 0), (120, 8, 50)]
        let modes: [(String, GridRowWalk.Mode)] = [("serial", .forcedSerial), ("parallel", .forcedParallel)]
        for (columns, oversample, edge) in regimes {
            for (modeName, mode) in modes {
                let id = "aski89-convert-\(columns)cols-os\(oversample)-e\(edge)-\(modeName)"
                var converter = DefaultConverter()
                converter.rowWalkMode = mode
                converter.oversample = oversample
                converter.options.edgeEmphasis = Float(edge) / 100
                var record = ParityRecord(id: id)
                try capturePaths(converter, image: image, reversed: reversed, columns: columns, record: &record)
                try record.write(id: id, to: directory)
            }
        }

        for (id, columns, algorithm) in [
            ("aski89-convert-1cols-os2-e0-serial", 1, ASCIIAlgorithm.logPolar),
            ("aski89-convert-8cols-os2-e0-serial", 8, .logPolar),
            ("aski89-dotmatrix-control-8cols", 8, .dotMatrix),
            ("aski89-dotmatrix-control-120cols", 120, .dotMatrix),
        ] {
            var converter = DefaultConverter()
            converter.algorithm = algorithm
            converter.rowWalkMode = .forcedSerial
            let grid = converter.convert(image, columns: columns)
            try #require(grid.columns == columns && grid.rows > 0)
            var record = ParityRecord(id: id)
            record.append(grid)
            try record.write(id: id, to: directory)
        }

        var emphasized = DefaultConverter()
        emphasized.oversample = 8
        let noEdge = try #require(emphasized.cellQueryDescriptors(flat, columns: 120))
        emphasized.options.edgeEmphasis = 0.5
        let withEdge = try #require(emphasized.cellQueryDescriptors(flat, columns: 120))
        try #require(withEdge.supportsShapeDescriptor)
        try #require(withEdge.lanes.contains { $0 != .zero })
        let id = "aski89-flat-120cols-os8"
        var unweighted = ParityRecord(id: id)
        var weighted = ParityRecord(id: id)
        unweighted.append(noEdge)
        weighted.append(withEdge)
        try #require(unweighted.bytes == weighted.bytes)
        try weighted.write(id: id, to: directory)

        try captureDegenerateQuery(to: directory)
        try captureTexturedQuery(to: directory)
    }

    private func captureDegenerateQuery(to directory: URL) throws {
        let id = "aski89-degenerate-8cols-os2"
        let image = TestImages.horizontalGradient(width: 8, height: 16)
        let columns = 8
        var converter = DefaultConverter()
        converter.rowWalkMode = .forcedSerial
        let geometry = try #require(converter.samplingGeometry(image, columns: columns))
        try #require(geometry.columns == columns && geometry.rows > 0)
        try #require(geometry.cellWidth == 1 && geometry.cellHeight > 1)
        let query = try #require(converter.cellQueryDescriptors(image, columns: columns))
        try #require(!query.supportsShapeDescriptor)
        try #require(query.columns == columns && query.rows == geometry.rows)
        try #require(query.lanesPerCell == 15 && query.lanes.count == columns * geometry.rows * 15)
        try #require(
            query.lanes.allSatisfy { lane in
                lane.x.bitPattern == 0 && lane.y.bitPattern == 0 && lane.z.bitPattern == 0 && lane.w.bitPattern == 0
            })
        var record = ParityRecord(id: id)
        record.append(geometry.cellWidth)
        record.append(geometry.cellHeight)
        record.append(query)
        try record.write(id: id, to: directory)
    }

    private func captureTexturedQuery(to directory: URL) throws {
        let id = "aski89-texture-40cols-os8-e50-serial"
        let width = 320
        let height = 240
        let columns = 40
        let pixels = (0..<(width * height)).map { index in
            UInt8(truncatingIfNeeded: SplitMix64.hash(seed: 89, row: index / width, column: index % width, salt: .phase))
        }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(
            CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))

        var converter = DefaultConverter()
        converter.rowWalkMode = .forcedSerial
        converter.oversample = 8
        converter.options.edgeEmphasis = 0.5
        let geometry = try #require(converter.samplingGeometry(image, columns: columns))
        try #require(geometry.columns == columns && geometry.rows > 0)
        try #require(geometry.cellWidth >= 3 && geometry.cellHeight >= 3)
        let query = try #require(converter.cellQueryDescriptors(image, columns: columns))
        try #require(query.supportsShapeDescriptor)
        try #require(query.columns == columns && query.rows == geometry.rows)
        try #require(query.lanesPerCell == 15 && query.lanes.count == columns * geometry.rows * 15)
        try #require(query.lanes.contains { $0 != .zero })
        var record = ParityRecord(id: id)
        record.append(geometry.cellWidth)
        record.append(geometry.cellHeight)
        record.append(query)
        try record.write(id: id, to: directory)
    }

    private func capturePaths(
        _ converter: DefaultConverter, image: CGImage, reversed: CGImage, columns: Int, record: inout ParityRecord
    ) throws {
        let geometry = try #require(converter.samplingGeometry(image, columns: columns))
        try #require(geometry.columns == columns && geometry.rows > 1)
        try #require(geometry.cellWidth > 1 && geometry.cellHeight > 1)
        try #require(
            GridRowWalk.resolvesParallel(rows: geometry.rows, columns: columns, mode: converter.rowWalkMode)
                == (converter.rowWalkMode == .forcedParallel))
        record.append(geometry.cellWidth)
        record.append(geometry.cellHeight)
        record.append(geometry.thumbnailWidth)
        record.append(geometry.thumbnailHeight)

        let ordinary = converter.convert(image, columns: columns)
        let count = geometry.rows * columns
        try #require(ordinary.columns == columns && ordinary.rows == geometry.rows)
        record.append(ordinary)

        let ranked = converter.convertWithRankedCandidates(image, columns: columns, candidateStride: 6)
        try #require(ranked.candidateStride == 6)
        try #require(ranked.candidateCounts.count == count)
        try #require(ranked.candidates.count == count * 6)
        record.append(ranked.grid)
        record.append(ranked.candidateStride)
        record.append(ranked.candidateCounts.map(Int.init))
        record.append(ranked.candidates.map(Int.init))
        let animation = AnimationOptions(duration: 5, seed: 1, cycling: CyclingOptions(k: 6, speed: 1, intensity: 0.6, randomness: 0.5))
        let animated = converter.animate(image, columns: columns, options: animation)
        record.append(animated.baseGrid)
        record.append(animated.grid(at: 2.5))

        let residual = converter.convertWithResidual(image, columns: columns)
        try #require(residual.residual.count == count)
        record.append(residual.grid)
        record.append(residual.residual)

        let first = converter.convertTemporalFrame(image, columns: columns, prior: nil, alpha: 0.5, tau: 0.1, sourceTetherRho: 0.2)
        let second = converter.convertTemporalFrame(reversed, columns: columns, prior: first.state, alpha: 0.5, tau: 0.1, sourceTetherRho: 0.2)
        for frame in [first, second] {
            try #require(frame.state.columns == columns && frame.state.rows == geometry.rows)
            try #require(frame.state.emaOKLab.count == count)
            try #require(frame.state.emaAdjustedL.count == count)
            try #require(frame.state.emaAlpha.count == count)
            try #require(frame.state.heldGlyphIndex.count == count)
            try #require(frame.state.lockDistance.count == count)
            record.append(frame.grid)
            record.append(frame.state)
        }

        let query = try #require(converter.cellQueryDescriptors(image, columns: columns))
        try #require(query.supportsShapeDescriptor)
        try #require(query.lanesPerCell == 15 && query.lanes.count == count * 15)
        try #require(query.adjustedL.count == count)
        try #require(query.lanes.contains { $0 != .zero })
        let heldCell = query.lanes(row: geometry.rows / 2, column: columns / 4)
        var retained = ParityRecord(id: "retained")
        retained.append(query)
        retained.append(heldCell)
        let next = try #require(converter.cellQueryDescriptors(reversed, columns: columns))
        try #require(next.lanes != query.lanes)
        var after = ParityRecord(id: "retained")
        after.append(query)
        after.append(heldCell)
        try #require(retained.bytes == after.bytes)
        record.append(query)
        record.append(heldCell)
        record.append(next)

        if converter.options.edgeEmphasis > 0 {
            try #require(geometry.cellWidth >= 3 && geometry.cellHeight >= 3)
            var noEdge = converter
            noEdge.options.edgeEmphasis = 0
            let plain = try #require(noEdge.cellQueryDescriptors(image, columns: columns))
            try #require(query.lanes != plain.lanes)
        }
    }

    private func makeImage(like source: CGImage, flat: Bool) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: source.width, height: source.height, bitsPerComponent: 8, bytesPerRow: source.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let bounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        if flat {
            // Opaque black maps to exact unit ink, so the Sobel sum cancels exactly.
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            context.fill(bounds)
        } else {
            context.interpolationQuality = .none
            context.translateBy(x: CGFloat(source.width), y: 0)
            context.scaleBy(x: -1, y: 1)
            context.draw(source, in: bounds)
        }
        return try #require(context.makeImage())
    }
}

private struct ParityRecord {
    private(set) var bytes: Data

    init(id: String) {
        bytes = Data("aski89-parity-v1 \(id)\n".utf8)
    }

    mutating func append(_ grid: ASCIIGrid) {
        append(grid.rows)
        append(grid.columns)
        append(String(describing: grid.colorSpace))
        append(String(describing: grid.composition))
        append(grid.maskFallback == nil ? 0 : 1)
        append(grid.maskGroundColor == nil ? 0 : 1)
        append(grid.maskUsesHardEdges ? 1 : 0)
        for row in grid.cells {
            append(row.count)
            for cell in row {
                append(String(cell.character))
                append(cell.displayColor)
                append(cell.alpha)
                append(cell.brightness)
                append(cell.coverage)
            }
        }
    }

    mutating func append(_ query: CellQueryDescriptors) {
        append(query.grid)
        append(query.rows)
        append(query.columns)
        append(query.lanesPerCell)
        append(query.lanes)
        append(query.adjustedL)
        append(query.supportsShapeDescriptor ? 1 : 0)
    }

    mutating func append(_ state: TemporalPriorState) {
        append(state.rows)
        append(state.columns)
        append(state.emaOKLab.count)
        for value in state.emaOKLab { append(value) }
        append(state.emaAdjustedL)
        append(state.emaAlpha)
        append(state.heldGlyphIndex)
        append(state.lockDistance)
    }

    mutating func append(_ lanes: [SIMD4<Float>]) {
        append(lanes.count)
        for lane in lanes {
            append(lane.x)
            append(lane.y)
            append(lane.z)
            append(lane.w)
        }
    }

    mutating func append(_ value: SIMD3<Float>) {
        append(value.x)
        append(value.y)
        append(value.z)
    }

    mutating func append(_ value: String) {
        append(value.utf8.count)
        bytes.append(contentsOf: value.utf8)
    }

    mutating func append(_ values: [Int]) {
        append(values.count)
        for value in values { append(value) }
    }

    mutating func append(_ values: [Float]) {
        append(values.count)
        for value in values { append(value) }
    }

    mutating func append(_ value: Int) {
        var encoded = Int64(value).littleEndian
        withUnsafeBytes(of: &encoded) { bytes.append(contentsOf: $0) }
    }

    mutating func append(_ value: Float) {
        var encoded = value.bitPattern.littleEndian
        withUnsafeBytes(of: &encoded) { bytes.append(contentsOf: $0) }
    }

    mutating func write(id: String, to directory: URL) throws {
        let digest = SHA256.hash(data: bytes)
        bytes.append(contentsOf: digest)
        try bytes.write(to: directory.appendingPathComponent(id + ".bin"), options: .withoutOverwriting)
    }
}
