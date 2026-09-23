import CoreGraphics
import Testing

@_spi(AskiResearch) @testable import Aski
@testable import AskiColorLab

/// The target-width verdict is fixed before the decisive fixture run. These
/// synthetic rows make each branch executable without reading the consumer
/// input or treating a measured result as a new test expectation.
@Suite(.serialized) struct TargetWidthGateTests {
    @Test func referenceBandingAboveTheBoundIsInvalid() {
        let verdict = TargetWidthGate.verdict(Self.makeReport(referenceBanding: 0.021))

        #expect(verdict.outcome == "INVALID")
        #expect(verdict.reason.contains("reference banding"))
    }

    @Test func negativeControlDriftAboveTheBoundIsInvalid() {
        let verdict = TargetWidthGate.verdict(Self.makeReport(aSwappedDelta: 0.021))

        #expect(verdict.outcome == "INVALID")
        #expect(verdict.reason.contains("negative-control drift"))
    }

    @Test func neitherArmClearingTheBandingBoundIsInconclusive() {
        let verdict = TargetWidthGate.verdict(Self.makeReport(aBanding: 0.11, bBanding: 0.11))

        #expect(verdict.outcome == "INCONCLUSIVE")
        #expect(verdict.reason.contains("banding"))
        #expect(verdict.reason.contains("canyon-384@1166"))
    }

    @Test func gmsdVetoMakesAConfidentMAEWinInconclusive() {
        let verdict = TargetWidthGate.verdict(
            Self.makeReport(aMAE: 0.8, bMAE: 1, aGMSD: 0.9, bGMSD: 0.8)
        )

        #expect(verdict.outcome == "INCONCLUSIVE")
        #expect(verdict.reason.contains("GMSD veto"))
    }

    @Test func closeMAEAndGMSDMeansShipTheSimplerArmA() {
        let verdict = TargetWidthGate.verdict(
            Self.makeReport(aMAE: 0.99, bMAE: 1, aGMSD: 1, bGMSD: 1)
        )

        #expect(verdict.outcome == "SHIP-A")
        #expect(verdict.reason.contains("below their tie thresholds"))
    }

    @Test func aClearMAEWinShipsArmB() {
        let verdict = TargetWidthGate.verdict(
            Self.makeReport(aMAE: 1, bMAE: 0.8, aGMSD: 1, bGMSD: 1)
        )

        #expect(verdict.outcome == "SHIP-B")
        #expect(verdict.reason.contains("MAE decides"))
    }

    @Test func cheapIfCloseConvertsAShipBToShipA() {
        let verdict = TargetWidthGate.verdict(
            Self.makeReport(aMAE: 1, bMAE: 0.97, aCost: 1, bCost: 5)
        )

        #expect(verdict.outcome == "SHIP-A")
        #expect(verdict.reason.contains("cheap-if-close"))
    }

    @Test func oneEligibleArmShipsWithoutTheMAEComparison() {
        let verdict = TargetWidthGate.verdict(Self.makeReport(aBanding: 0.11, bBanding: 0.05))

        #expect(verdict.outcome == "SHIP-B")
        #expect(verdict.reason.contains("only B clears B_max"))
    }

    @Test func bandingCoefficientIsZeroForAUniformFractionalAdvance() throws {
        let uniform = try #require(
            TargetWidthGate.bandingCoefficient(
                // The old floor-based estimator measured about one third here.
                luma: Array(repeating: 0.3, count: 97),
                width: 97,
                height: 1,
                columns: 32,
                useInkMass: true
            )
        )

        #expect(abs(uniform) < 0.000_000_001)
    }

    @Test func bandingCoefficientMatchesTheIntegerAdvanceEstimator() throws {
        let alternating = try #require(
            TargetWidthGate.bandingCoefficient(
                luma: (0..<96).map { ($0 / 3).isMultiple(of: 2) ? 0 : 1 },
                width: 96,
                height: 1,
                columns: 32,
                useInkMass: true
            )
        )

        #expect(abs(alternating - 2) < 0.000_000_1)
    }

    @Test func bandingCoefficientIgnoresPerfectlyPlacedFractionalPeriodicBars() throws {
        let width = 97
        let columns = 32
        let advance = Double(width) / Double(columns)
        let luma = (0..<width).map { x -> Float in
            let cell = min(columns - 1, Int(floor((Double(x) + 0.5) / advance)))
            let inkStart = Double(cell) * advance + 1
            let inkEnd = Double(cell) * advance + 2
            let coverage = max(0, min(Double(x + 1), inkEnd) - max(Double(x), inkStart))
            return Float(1 - coverage)
        }
        let coefficient = try #require(
            TargetWidthGate.bandingCoefficient(
                luma: luma,
                width: width,
                height: 1,
                columns: columns,
                useInkMass: true
            )
        )

        #expect(coefficient < 0.01)
    }

    @Test func straddlingDeviceColumnSplitsAndConservesMass() throws {
        let luma = (0..<11).map { $0 == 2 ? Float(0) : Float(1) }
        let masses = try #require(
            TargetWidthGate.bandingMasses(
                luma: luma,
                width: 11,
                height: 1,
                columns: 5,
                useInkMass: true
            )
        )
        let expectedMass = luma.reduce(0.0) { partial, sample in
            partial + (1 - Double(sample))
        }

        #expect(abs(masses[0] - 0.2) < 0.000_001)
        #expect(abs(masses[1] - 0.8) < 0.000_001)
        #expect(abs(masses.reduce(0, +) - expectedMass) < 0.000_001)
    }

    @Test func tinyGridRunsAllThreeRendersAtTheExactTargetWidth() throws {
        let grid = ASCIIGrid(
            cells: (0..<3).map { row in
                (0..<8).map { column in
                    let tint = Float(row * 8 + column) / Float(3 * 8)
                    return ASCIICell(
                        character: "#",
                        displayColor: SIMD3(tint, 1 - tint, 0.5),
                        alpha: 1,
                        brightness: tint
                    )
                }
            },
            colorSpace: .sRGB
        )
        let configuration = TargetWidthGate.FixtureConfiguration(
            id: "tiny",
            source: "test",
            columns: 8,
            widths: [25],
            font: .system(size: 10),
            backgroundRGB: .zero,
            backgroundHex: "#000000",
            preserveSourceAspect: true
        )

        let evaluation = try TargetWidthGate.evaluate(
            grid: grid,
            configuration: configuration,
            repeats: 1
        )
        let reference = try #require(evaluation.referenceRows.first)

        #expect(evaluation.armRows.count == 2)
        #expect(evaluation.referenceRows.count == 1)
        #expect(reference.width == 25)
        #expect(reference.height > 0)
        for row in evaluation.armRows {
            #expect(row.width == 25)
            #expect(row.height == reference.height)
            #expect(row.dimensionsMatchReference)
            #expect(row.mae != nil)
            #expect(row.gmsd != nil)
            #expect(row.banding != nil)
        }
    }

    private static func makeReport(
        aMAE: Double = 1,
        bMAE: Double = 1,
        aGMSD: Double = 1,
        bGMSD: Double = 1,
        aBanding: Double = 0.05,
        bBanding: Double = 0.05,
        referenceBanding: Double = 0.01,
        aSwappedDelta: Double = 0,
        bSwappedDelta: Double = 0,
        aCost: Double = 1,
        bCost: Double = 2
    ) -> TargetWidthGate.Report {
        let fixtures = Self.fixtures
        var armRows: [TargetWidthGate.ArmRow] = []
        var referenceRows: [TargetWidthGate.ReferenceRow] = []

        for fixture in fixtures {
            for targetPixelWidth in fixture.widths {
                let height = max(1, targetPixelWidth / 2)
                armRows.append(
                    TargetWidthGate.ArmRow(
                        fixtureID: fixture.id,
                        arm: .a,
                        targetPixelWidth: targetPixelWidth,
                        width: targetPixelWidth,
                        height: height,
                        mae: aMAE,
                        gmsd: aGMSD,
                        banding: aBanding,
                        bandingSwappedDelta: aSwappedDelta,
                        costMs: aCost,
                        dimensionsMatchReference: true,
                        renderPNG: nil,
                        probePNG: nil
                    )
                )
                armRows.append(
                    TargetWidthGate.ArmRow(
                        fixtureID: fixture.id,
                        arm: .b,
                        targetPixelWidth: targetPixelWidth,
                        width: targetPixelWidth,
                        height: height,
                        mae: bMAE,
                        gmsd: bGMSD,
                        banding: bBanding,
                        bandingSwappedDelta: bSwappedDelta,
                        costMs: bCost,
                        dimensionsMatchReference: true,
                        renderPNG: nil,
                        probePNG: nil
                    )
                )
                referenceRows.append(
                    TargetWidthGate.ReferenceRow(
                        fixtureID: fixture.id,
                        targetPixelWidth: targetPixelWidth,
                        width: targetPixelWidth,
                        height: height,
                        banding: referenceBanding,
                        costMs: 4,
                        renderPNG: nil,
                        probePNG: nil
                    )
                )
            }
        }

        return TargetWidthGate.Report(
            fixtures: fixtures,
            armRows: armRows,
            referenceRows: referenceRows
        )
    }

    private static var fixtures: [TargetWidthGate.FixtureMetadata] {
        [
            TargetWidthGate.FixtureMetadata(
                configuration: TargetWidthGate.FixtureConfiguration(
                    id: "canyon-384",
                    source: "consumer",
                    columns: 384,
                    widths: [1166, 2332],
                    font: .system(size: 13.333333),
                    backgroundRGB: SIMD3<Float>(
                        Float(0x23) / 255,
                        Float(0x23) / 255,
                        Float(0x23) / 255
                    ),
                    backgroundHex: "#232323",
                    preserveSourceAspect: true
                )
            ),
            TargetWidthGate.FixtureMetadata(
                configuration: TargetWidthGate.FixtureConfiguration(
                    id: "earth-limb-80",
                    source: "corpus",
                    columns: 80,
                    widths: [243, 600, 960],
                    font: .system(size: 12),
                    backgroundRGB: .zero,
                    backgroundHex: "#000000",
                    preserveSourceAspect: true
                )
            ),
        ]
    }
}
