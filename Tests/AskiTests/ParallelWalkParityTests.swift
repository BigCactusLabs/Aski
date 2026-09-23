import CoreGraphics
import Foundation
import Testing
@_spi(AskiResearch) @testable import Aski

struct ParallelWalkParityTests {
    private func bitIdentical(_ a: ASCIIGrid, _ b: ASCIIGrid) -> Bool {
        guard a.cells.count == b.cells.count else { return false }
        for (rowA, rowB) in zip(a.cells, b.cells) {
            guard rowA.count == rowB.count else { return false }
            for (cellA, cellB) in zip(rowA, rowB) {
                guard cellA.character == cellB.character,
                    cellA.displayColor.x.bitPattern == cellB.displayColor.x.bitPattern,
                    cellA.displayColor.y.bitPattern == cellB.displayColor.y.bitPattern,
                    cellA.displayColor.z.bitPattern == cellB.displayColor.z.bitPattern,
                    cellA.alpha.bitPattern == cellB.alpha.bitPattern,
                    cellA.brightness.bitPattern == cellB.brightness.bitPattern,
                    cellA.coverage.bitPattern == cellB.coverage.bitPattern
                else { return false }
            }
        }
        return true
    }

    // AC#3 matrix: both aspects × grid sizes spanning small/typical/large.
    // Portrait-aspect regression coverage: ASTSK-47.
    private static let fixtures: [(String, CGImage)] = [
        ("landscape", TestImages.horizontalGradient(width: 640, height: 480)),
        ("portrait", TestImages.structuredPortraitProxy(width: 240, height: 320)),
    ]

    @Test(arguments: [ASCIIAlgorithm.logPolar], [16, 32, 76, 80, 120])
    func parallelMatchesSerialByteForByte(algorithm: ASCIIAlgorithm, columns: Int) {
        for (_, image) in Self.fixtures {
            var serial = makeConverter(algorithm: algorithm)
            serial.rowWalkMode = .forcedSerial
            var parallel = makeConverter(algorithm: algorithm)
            parallel.rowWalkMode = .forcedParallel
            let a = serial.convert(image, columns: columns)
            let b = parallel.convert(image, columns: columns)
            #expect(bitIdentical(a, b))
        }
    }

    @Test(arguments: [ASCIIAlgorithm.logPolar, .dotMatrix])
    func repeatedParallelRunsAreDeterministic(algorithm: ASCIIAlgorithm) {
        for (_, image) in Self.fixtures {
            var converter = makeConverter(algorithm: algorithm)
            converter.rowWalkMode = .forcedParallel
            let first = converter.convert(image, columns: 80)
            for _ in 0..<4 {
                #expect(bitIdentical(first, converter.convert(image, columns: 80)))
            }
        }
    }

    @Test func dotMatrixIgnoresForcedParallel() {
        var forced = makeConverter(algorithm: .dotMatrix)
        forced.rowWalkMode = .forcedParallel
        var serial = makeConverter(algorithm: .dotMatrix)
        serial.rowWalkMode = .forcedSerial
        let image = TestImages.horizontalGradient(width: 640, height: 480)
        #expect(
            bitIdentical(
                forced.convert(image, columns: 80),
                serial.convert(image, columns: 80)
            )
        )
    }

    @Test(arguments: [ASCIIAlgorithm.logPolar, .dotMatrix])
    func rankedAndResidualParallelMatchSerial(algorithm: ASCIIAlgorithm) {
        for (_, image) in Self.fixtures {
            var serial = makeConverter(algorithm: algorithm)
            serial.rowWalkMode = .forcedSerial
            var parallel = makeConverter(algorithm: algorithm)
            parallel.rowWalkMode = .forcedParallel
            let rankedA = serial.convertWithRankedCandidates(image, columns: 80, candidateStride: 4)
            let rankedB = parallel.convertWithRankedCandidates(image, columns: 80, candidateStride: 4)
            #expect(rankedA.candidates == rankedB.candidates)
            #expect(rankedA.candidateCounts == rankedB.candidateCounts)
            #expect(bitIdentical(rankedA.grid, rankedB.grid))
            let residualA = serial.convertWithResidual(image, columns: 80)
            let residualB = parallel.convertWithResidual(image, columns: 80)
            #expect(
                residualA.residual.map { $0.bitPattern } == residualB.residual.map { $0.bitPattern }
            )
            #expect(bitIdentical(residualA.grid, residualB.grid))
        }
    }

    // ASTSK-51 Task 6: prove the shipped `.auto` gate (threshold = 1200 cells)
    // is byte-identical to serial on BOTH sides of the crossover. GridRowWalkTests
    // proves the pure gate function; this proves the production `convert` path —
    // the below-threshold grid must resolve serial, the above-threshold grid must
    // resolve parallel, and both must match a forcedSerial baseline exactly.
    @Test(arguments: [ASCIIAlgorithm.logPolar])
    func autoStraddlesThresholdByteIdentical(algorithm: ASCIIAlgorithm) {
        let image = TestImages.horizontalGradient(width: 640, height: 480)
        var serial = makeConverter(algorithm: algorithm)
        serial.rowWalkMode = .forcedSerial
        let auto = makeConverter(algorithm: algorithm)  // default .auto

        // 48 cols on 640×480 → ~768 cells: below 1200, `.auto` stays serial.
        let belowAuto = auto.convert(image, columns: 48)
        #expect(
            !GridRowWalk.resolvesParallel(
                rows: belowAuto.cells.count,
                columns: belowAuto.cells.first?.count ?? 0,
                mode: .auto))
        #expect(bitIdentical(belowAuto, serial.convert(image, columns: 48)))

        // 96 cols on 640×480 → ~3072 cells: above 1200, `.auto` goes parallel.
        let aboveAuto = auto.convert(image, columns: 96)
        #expect(
            GridRowWalk.resolvesParallel(
                rows: aboveAuto.cells.count,
                columns: aboveAuto.cells.first?.count ?? 0,
                mode: .auto))
        #expect(bitIdentical(aboveAuto, serial.convert(image, columns: 96)))
    }

    @Test func temporalParallelMatchesSerialIncludingState() {
        let images = (0..<3).map { temporalRampImage(side: 96, shift: $0 * 3) }

        let configurations: [(alpha: Float, tau: Float, sourceTetherRho: Float?)] = [
            (Float(1), Float(0), Float(2)),
            (Float(0.4), Float(2), Optional<Float>.none),
        ]
        for (alpha, tau, sourceTetherRho) in configurations {
            var serial = makeConverter(algorithm: .logPolar)
            serial.rowWalkMode = .forcedSerial
            var parallel = makeConverter(algorithm: .logPolar)
            parallel.rowWalkMode = .forcedParallel
            var serialPrior: TemporalPriorState?
            var parallelPrior: TemporalPriorState?

            for image in images {
                let serialResult = serial.convertTemporalFrame(
                    image,
                    columns: 16,
                    prior: serialPrior,
                    alpha: alpha,
                    tau: tau,
                    sourceTetherRho: sourceTetherRho
                )
                let parallelResult = parallel.convertTemporalFrame(
                    image,
                    columns: 16,
                    prior: parallelPrior,
                    alpha: alpha,
                    tau: tau,
                    sourceTetherRho: sourceTetherRho
                )

                #expect(bitIdentical(serialResult.grid, parallelResult.grid))
                #expect(serialResult.state.emaOKLab.map { $0.x.bitPattern } == parallelResult.state.emaOKLab.map { $0.x.bitPattern })
                #expect(serialResult.state.emaOKLab.map { $0.y.bitPattern } == parallelResult.state.emaOKLab.map { $0.y.bitPattern })
                #expect(serialResult.state.emaOKLab.map { $0.z.bitPattern } == parallelResult.state.emaOKLab.map { $0.z.bitPattern })
                #expect(serialResult.state.emaAdjustedL.map(\.bitPattern) == parallelResult.state.emaAdjustedL.map(\.bitPattern))
                #expect(serialResult.state.emaAlpha.map(\.bitPattern) == parallelResult.state.emaAlpha.map(\.bitPattern))
                #expect(serialResult.state.heldGlyphIndex == parallelResult.state.heldGlyphIndex)
                #expect(serialResult.state.lockDistance.map(\.bitPattern) == parallelResult.state.lockDistance.map(\.bitPattern))

                serialPrior = serialResult.state
                parallelPrior = parallelResult.state
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func animateParallelMatchesSerialOverRepeatedFrameChain() {
        var serial = makeConverter(algorithm: .logPolar)
        serial.rowWalkMode = .forcedSerial
        var parallel = makeConverter(algorithm: .logPolar)
        parallel.rowWalkMode = .forcedParallel
        let options = AnimationOptions(
            duration: 1,
            seed: 7,
            cycling: CyclingOptions(k: 4, speed: 1, intensity: 1, randomness: 0)
        )

        for frame in 0..<10 {
            let image = temporalRampImage(side: 96, shift: frame)
            let serialFrames = serial.animate(image, columns: 16, options: options).materialize(frameRate: 10)
            let parallelFrames = parallel.animate(image, columns: 16, options: options).materialize(frameRate: 10)

            #expect(serialFrames.count == parallelFrames.count)
            for (serialFrame, parallelFrame) in zip(serialFrames, parallelFrames) {
                #expect(bitIdentical(serialFrame, parallelFrame))
            }
        }
    }

    private func makeConverter(algorithm: ASCIIAlgorithm) -> DefaultConverter {
        ASCIIConverter(
            characterSet: StandardCharacterSet.standard,
            palette: BuiltInPalette.fullColor,
            algorithm: algorithm
        )
    }

    private func temporalRampImage(side: Int, shift: Int) -> CGImage {
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        let span = Double(max(1, side + side - 2))
        for y in 0..<side {
            for x in 0..<side {
                let shiftedX = (x + shift) % side
                let value = UInt8(
                    min(255, max(0, Int((Double(shiftedX + y) / span) * 255))))
                let offset = (y * side + x) * 4
                rgba[offset] = value
                rgba[offset + 1] = value
                rgba[offset + 2] = value
                rgba[offset + 3] = 255
            }
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        return CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}
