// Tests/AskiTests/DefaultPathExactGoldenTests.swift
import CoreGraphics
import Testing
import simd
@testable import Aski

/// Bit-exact freeze of the public default conversion path (ASTSK-29 AC #1).
/// Captured BEFORE the cellStats split; Tasks 2–4 must keep this grid
/// bit-identical. No ε — Float.bitPattern equality. Re-recorded for ASKI-1,
/// when sources larger than the conversion budget moved from the ImageIO
/// thumbnail to direct resampling.
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
        GoldenCell(character: ".", color: [1031195550, 1031195536, 1031195538], alpha: 1065353216, brightness: 1043214388, coverage: 1065353216),
        GoldenCell(character: "-", color: [1044254014, 1044254016, 1044254014], alpha: 1065353216, brightness: 1050471833, coverage: 1065353216),
        GoldenCell(character: "*", color: [1050645818, 1050645823, 1050645819], alpha: 1065353216, brightness: 1054594702, coverage: 1065353216),
        GoldenCell(character: "t", color: [1054840493, 1054840493, 1054840488], alpha: 1065353216, brightness: 1057685102, coverage: 1065353216),
        GoldenCell(character: "z", color: [1058068820, 1058068820, 1058068818], alpha: 1065353216, brightness: 1059553119, coverage: 1065353216),
        GoldenCell(character: "e", color: [1060171058, 1060171068, 1060171062], alpha: 1065353216, brightness: 1061292417, coverage: 1065353216),
        GoldenCell(character: "m", color: [1062308790, 1062308779, 1062308786], alpha: 1065353216, brightness: 1063001911, coverage: 1065353216),
        GoldenCell(character: "#", color: [1064443665, 1064443665, 1064443665], alpha: 1065353216, brightness: 1064659891, coverage: 1065353216),
        GoldenCell(character: ".", color: [1031195550, 1031195536, 1031195538], alpha: 1065353216, brightness: 1043214388, coverage: 1065353216),
        GoldenCell(character: "-", color: [1044254014, 1044254016, 1044254014], alpha: 1065353216, brightness: 1050471833, coverage: 1065353216),
        GoldenCell(character: "*", color: [1050645818, 1050645823, 1050645819], alpha: 1065353216, brightness: 1054594702, coverage: 1065353216),
        GoldenCell(character: "t", color: [1054840493, 1054840493, 1054840488], alpha: 1065353216, brightness: 1057685102, coverage: 1065353216),
        GoldenCell(character: "z", color: [1058068820, 1058068820, 1058068818], alpha: 1065353216, brightness: 1059553119, coverage: 1065353216),
        GoldenCell(character: "e", color: [1060171058, 1060171068, 1060171062], alpha: 1065353216, brightness: 1061292417, coverage: 1065353216),
        GoldenCell(character: "m", color: [1062308790, 1062308779, 1062308786], alpha: 1065353216, brightness: 1063001911, coverage: 1065353216),
        GoldenCell(character: "#", color: [1064443665, 1064443665, 1064443665], alpha: 1065353216, brightness: 1064659891, coverage: 1065353216),
        GoldenCell(character: ".", color: [1031195550, 1031195536, 1031195538], alpha: 1065353216, brightness: 1043214388, coverage: 1065353216),
        GoldenCell(character: "-", color: [1044254014, 1044254016, 1044254014], alpha: 1065353216, brightness: 1050471833, coverage: 1065353216),
        GoldenCell(character: "*", color: [1050645818, 1050645823, 1050645819], alpha: 1065353216, brightness: 1054594702, coverage: 1065353216),
        GoldenCell(character: "t", color: [1054840493, 1054840493, 1054840488], alpha: 1065353216, brightness: 1057685102, coverage: 1065353216),
        GoldenCell(character: "z", color: [1058068820, 1058068820, 1058068818], alpha: 1065353216, brightness: 1059553119, coverage: 1065353216),
        GoldenCell(character: "e", color: [1060171058, 1060171068, 1060171062], alpha: 1065353216, brightness: 1061292417, coverage: 1065353216),
        GoldenCell(character: "m", color: [1062308790, 1062308779, 1062308786], alpha: 1065353216, brightness: 1063001911, coverage: 1065353216),
        GoldenCell(character: "#", color: [1064443665, 1064443665, 1064443665], alpha: 1065353216, brightness: 1064659891, coverage: 1065353216),
    ]
}
