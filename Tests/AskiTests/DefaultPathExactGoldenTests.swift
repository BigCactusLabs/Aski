// Tests/AskiTests/DefaultPathExactGoldenTests.swift
import CoreGraphics
import Testing
import simd
@testable import Aski

/// Bit-exact freeze of the public default conversion path (ASTSK-29 AC #1).
/// Captured BEFORE the cellStats split; Tasks 2–4 must keep this grid
/// bit-identical. No ε — Float.bitPattern equality.
@Suite struct DefaultPathExactGoldenTests {

    @Test func defaultPathIsBitIdenticalToPreChangeCapture() {
        let image = TestImages.horizontalGradient(width: 64, height: 64)
        let grid = DefaultConverter().convert(image, columns: 8)

        // Grid shape + metadata: byte-identical means the whole ASCIIGrid,
        // not just the cell payload.
        #expect(grid.columns == Self.goldenColumns)
        #expect(grid.rows == Self.goldenRows)
        #expect(grid.cells.count == Self.goldenRows)
        #expect(grid.cells.allSatisfy { $0.count == Self.goldenColumns })
        #expect(grid.colorSpace == .sRGB)
        #expect(grid.composition == .encodedDisplay8Bit)
        #expect(grid.maskFallback == nil)
        #expect(grid.maskUsesHardEdges == false)

        let flat = grid.cells.flatMap { $0 }
        #expect(flat.count == Self.golden.count)
        for (cell, golden) in zip(flat, Self.golden) {
            #expect(String(cell.character) == golden.character)
            #expect(cell.displayColor.x.bitPattern == golden.color[0])
            #expect(cell.displayColor.y.bitPattern == golden.color[1])
            #expect(cell.displayColor.z.bitPattern == golden.color[2])
            #expect(cell.alpha.bitPattern == golden.alpha)
            #expect(cell.brightness.bitPattern == golden.brightness)
            #expect(cell.coverage.bitPattern == golden.coverage)
        }
    }

    private struct GoldenCell {
        let character: String
        let color: [UInt32]
        let alpha: UInt32
        let brightness: UInt32
        let coverage: UInt32
    }

    private static let goldenColumns = 8
    private static let goldenRows = 3

    private static let golden: [GoldenCell] = [
        GoldenCell(character: ".", color: [1027513486, 1027513484, 1027513484], alpha: 1065353216, brightness: 1042113898, coverage: 1065353216),
        GoldenCell(character: "-", color: [1043632424, 1043632424, 1043632424], alpha: 1065353216, brightness: 1050153853, coverage: 1065353216),
        GoldenCell(character: "*", color: [1050457701, 1050457701, 1050457699], alpha: 1065353216, brightness: 1054418207, coverage: 1065353216),
        GoldenCell(character: "t", color: [1054780962, 1054780961, 1054780960], alpha: 1065353216, brightness: 1057658798, coverage: 1065353216),
        GoldenCell(character: "z", color: [1058104048, 1058104049, 1058104046], alpha: 1065353216, brightness: 1059582811, coverage: 1065353216),
        GoldenCell(character: "e", color: [1060271615, 1060271614, 1060271615], alpha: 1065353216, brightness: 1061374067, coverage: 1065353216),
        GoldenCell(character: "m", color: [1062505964, 1062505965, 1062505964], alpha: 1065353216, brightness: 1063156977, coverage: 1065353216),
        GoldenCell(character: "#", color: [1064638237, 1064638237, 1064638233], alpha: 1065353216, brightness: 1064808825, coverage: 1065353216),
        GoldenCell(character: ".", color: [1027513486, 1027513484, 1027513484], alpha: 1065353216, brightness: 1042113898, coverage: 1065353216),
        GoldenCell(character: "-", color: [1043632424, 1043632424, 1043632424], alpha: 1065353216, brightness: 1050153853, coverage: 1065353216),
        GoldenCell(character: "*", color: [1050457701, 1050457701, 1050457699], alpha: 1065353216, brightness: 1054418207, coverage: 1065353216),
        GoldenCell(character: "t", color: [1054780962, 1054780961, 1054780960], alpha: 1065353216, brightness: 1057658798, coverage: 1065353216),
        GoldenCell(character: "z", color: [1058104048, 1058104049, 1058104046], alpha: 1065353216, brightness: 1059582811, coverage: 1065353216),
        GoldenCell(character: "e", color: [1060271615, 1060271614, 1060271615], alpha: 1065353216, brightness: 1061374067, coverage: 1065353216),
        GoldenCell(character: "m", color: [1062505964, 1062505965, 1062505964], alpha: 1065353216, brightness: 1063156977, coverage: 1065353216),
        GoldenCell(character: "#", color: [1064638237, 1064638237, 1064638233], alpha: 1065353216, brightness: 1064808825, coverage: 1065353216),
        GoldenCell(character: ".", color: [1027513486, 1027513484, 1027513484], alpha: 1065353216, brightness: 1042113898, coverage: 1065353216),
        GoldenCell(character: "-", color: [1043632424, 1043632424, 1043632424], alpha: 1065353216, brightness: 1050153853, coverage: 1065353216),
        GoldenCell(character: "*", color: [1050457701, 1050457701, 1050457699], alpha: 1065353216, brightness: 1054418207, coverage: 1065353216),
        GoldenCell(character: "t", color: [1054780962, 1054780961, 1054780960], alpha: 1065353216, brightness: 1057658798, coverage: 1065353216),
        GoldenCell(character: "z", color: [1058104048, 1058104049, 1058104046], alpha: 1065353216, brightness: 1059582811, coverage: 1065353216),
        GoldenCell(character: "e", color: [1060271615, 1060271614, 1060271615], alpha: 1065353216, brightness: 1061374067, coverage: 1065353216),
        GoldenCell(character: "m", color: [1062505964, 1062505965, 1062505964], alpha: 1065353216, brightness: 1063156977, coverage: 1065353216),
        GoldenCell(character: "#", color: [1064638237, 1064638237, 1064638233], alpha: 1065353216, brightness: 1064808825, coverage: 1065353216),
    ]
}
