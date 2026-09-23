import Foundation
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif
import Testing
@testable import Aski

@Suite struct AttributedStringRendererTests {
    @Test func preservesCharacters() {
        let cells = [
            [
                ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5),
                ASCIICell(character: "B", displayColor: .one, alpha: 1, brightness: 0.5),
            ]
        ]
        let grid = ASCIIGrid(cells: cells, colorSpace: .sRGB)
        let attributed = grid.renderAttributedString()
        #expect(String(attributed.characters) == "AB")
    }

    @Test func batchesIdenticalColorsIntoOneRun() {
        let redCells = (0..<5).map {
            ASCIICell(
                character: Character(String($0)),
                displayColor: .init(1, 0, 0),
                alpha: 1,
                brightness: 0.5
            )
        }
        let grid = ASCIIGrid(cells: [redCells], colorSpace: .sRGB)
        let attributed = grid.renderAttributedString()

        var runs = 0
        for run in attributed.runs {
            #if canImport(UIKit)
                if run.uiKit.foregroundColor != nil {
                    runs += 1
                }
            #elseif canImport(AppKit)
                if run.appKit.foregroundColor != nil {
                    runs += 1
                }
            #endif
        }
        #expect(runs == 1)
    }

    @Test func visibleCellForegroundAlphaUsesCellAlphaTimesCoverage() {
        let cell = ASCIICell(
            character: "A",
            displayColor: .init(1, 0, 0),
            alpha: 0.25,
            brightness: 0.5,
            coverage: 0.5
        )
        let grid = ASCIIGrid(cells: [[cell]], colorSpace: .sRGB)
        let attributed = grid.renderAttributedString()

        #if canImport(UIKit)
            let alpha = attributed.runs.first?.uiKit.foregroundColor?.cgColor.alpha
        #elseif canImport(AppKit)
            let alpha = attributed.runs.first?.appKit.foregroundColor?.usingColorSpace(.sRGB)?.alphaComponent
        #endif
        #expect(abs((alpha ?? 0) - 0.125) < 0.001)
    }

    @Test func fallbackCellForegroundAlphaScalesWithInverseCoverage() {
        let cell = ASCIICell(
            character: "A",
            displayColor: .init(1, 0, 0),
            alpha: 1,
            brightness: 0.5,
            coverage: 0.25
        )
        let grid = ASCIIGrid(
            cells: [[cell]],
            colorSpace: .sRGB,
            maskFallback: .character("*", color: CGColor(red: 0, green: 1, blue: 0, alpha: 0.8))
        )
        let attributed = grid.renderAttributedString()

        #if canImport(UIKit)
            let alpha = attributed.runs.first?.uiKit.foregroundColor?.cgColor.alpha
        #elseif canImport(AppKit)
            let alpha = attributed.runs.first?.appKit.foregroundColor?.usingColorSpace(.sRGB)?.alphaComponent
        #endif
        #expect(abs((alpha ?? 0) - 0.6) < 0.001)
    }

    #if canImport(UIKit)
        @Test func displayP3GridUsesDisplayP3UIColor() {
            let cell = ASCIICell(
                character: "P",
                displayColor: .init(1, 0, 0),
                alpha: 1,
                brightness: 0.5
            )
            let grid = ASCIIGrid(cells: [[cell]], colorSpace: .displayP3)
            let attributed = grid.renderAttributedString()

            let foregroundColor = attributed.runs.first?.uiKit.foregroundColor
            #expect(foregroundColor?.cgColor.colorSpace?.name == CGColorSpace.displayP3)
        }
    #endif

    #if canImport(AppKit)
        @Test func characterMaskFallbackUsesFallbackColor() {
            let grid = ASCIIGrid(
                cells: [
                    [
                        ASCIICell(character: "A", displayColor: SIMD3<Float>(1, 0, 0), alpha: 1, brightness: 1, coverage: 0),
                        ASCIICell(character: "B", displayColor: SIMD3<Float>(1, 0, 0), alpha: 1, brightness: 1, coverage: 1),
                    ]
                ],
                colorSpace: .sRGB,
                maskFallback: .character("*", color: CGColor(red: 0, green: 1, blue: 0, alpha: 1))
            )

            let attributed = grid.renderAttributedString()
            let coloredRuns = attributed.runs.compactMap { run -> (text: String, color: NSColor)? in
                guard let color = run.appKit.foregroundColor?.usingColorSpace(.sRGB) else { return nil }
                return (String(attributed[run.range].characters), color)
            }

            #expect(coloredRuns.count == 2)
            #expect(coloredRuns.first?.text == "*")
            #expect((coloredRuns.first?.color.greenComponent ?? 0) > 0.9)
            #expect(coloredRuns.last?.text == "B")
            #expect((coloredRuns.last?.color.redComponent ?? 0) > 0.9)
        }
    #endif
}
