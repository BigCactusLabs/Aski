import Testing
import CoreGraphics
@testable import Aski

@Suite struct AskiRenderEngineTests {
    @Test func defaultInitUsesSRGBColorSpace() async {
        let engine = AskiRenderEngine()
        let cap = await engine.deviceCapability
        switch cap {
        case .full, .reducedQuality:
            break
        }
    }

    @Test func renderASCIIGridProducesCGImage() async throws {
        let cell = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
        let grid = ASCIIGrid(cells: Array(repeating: Array(repeating: cell, count: 8), count: 8), colorSpace: .sRGB)
        let engine = AskiRenderEngine()
        let img = try await engine.render(
            grid,
            font: ASCIIFont.system(size: 12),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )
        #expect(img.width > 0)
    }

    @Test func renderASCIIGridUsesEngineColorSpace() async throws {
        let cell = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 0, 0), alpha: 1, brightness: 0.5)
        let grid = ASCIIGrid(cells: Array(repeating: Array(repeating: cell, count: 8), count: 8), colorSpace: .sRGB)
        let engine = AskiRenderEngine(colorSpace: .displayP3)
        let img = try await engine.render(
            grid,
            font: ASCIIFont.system(size: 12),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )
        #expect(img.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func renderTileGridUsesEngineColorSpace() async throws {
        let cell = TileCell(displayColor: SIMD3<Float>(1, 0, 0), alpha: 1, brightness: 0.5)
        let grid = TileGrid(cells: Array(repeating: Array(repeating: cell, count: 8), count: 8), colorSpace: .sRGB)
        let engine = AskiRenderEngine(colorSpace: .displayP3)
        let img = try await engine.render(grid, mode: .pixelArt, cellShape: .square, scale: 4)
        #expect(img.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func renderASCIIGridColorSpaceAdaptationPreservesMaskFallback() async throws {
        let fallback = CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        let ground = CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.75)
        let cell = ASCIICell(
            character: "#",
            displayColor: SIMD3<Float>(1, 1, 1),
            alpha: 1,
            brightness: 0.5,
            coverage: 0
        )
        let cells = Array(repeating: Array(repeating: cell, count: 3), count: 3)
        let directGrid = ASCIIGrid(
            cells: cells,
            colorSpace: .displayP3,
            maskFallback: .solid(fallback),
            maskGroundColor: ground,
            maskUsesHardEdges: true
        )
        let adaptedGrid = ASCIIGrid(
            cells: cells,
            colorSpace: .sRGB,
            maskFallback: .solid(fallback),
            maskGroundColor: ground,
            maskUsesHardEdges: true
        )
        let font = ASCIIFont.system(size: 12)
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let engine = AskiRenderEngine(colorSpace: .displayP3)
        let expected = try await engine.render(
            directGrid,
            font: font,
            backgroundColor: background,
            scale: 1
        )
        let actual = try await engine.render(
            adaptedGrid,
            font: font,
            backgroundColor: background,
            scale: 1
        )

        #expect(TestImages.deviceRGBBytes(actual) == TestImages.deviceRGBBytes(expected))
    }

    @Test func renderTileGridColorSpaceAdaptationPreservesMaskFallback() async throws {
        let fallback = CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        let ground = CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.75)
        let cell = TileCell(
            displayColor: SIMD3<Float>(1, 1, 1),
            alpha: 1,
            brightness: 0.5,
            coverage: 0
        )
        let cells = Array(repeating: Array(repeating: cell, count: 3), count: 3)
        let directGrid = TileGrid(
            cells: cells,
            colorSpace: .displayP3,
            maskFallback: .solid(fallback),
            maskGroundColor: ground,
            maskUsesHardEdges: true
        )
        let adaptedGrid = TileGrid(
            cells: cells,
            colorSpace: .sRGB,
            maskFallback: .solid(fallback),
            maskGroundColor: ground,
            maskUsesHardEdges: true
        )
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let engine = AskiRenderEngine(colorSpace: .displayP3)
        let expected = try await engine.render(
            directGrid,
            mode: .mosaic,
            cellShape: .square,
            scale: 4,
            backgroundColor: background
        )
        let actual = try await engine.render(
            adaptedGrid,
            mode: .mosaic,
            cellShape: .square,
            scale: 4,
            backgroundColor: background
        )

        #expect(TestImages.deviceRGBBytes(actual) == TestImages.deviceRGBBytes(expected))
    }

    @Test func flushCachesDoesNotCorruptSubsequentRender() async throws {
        let cell = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
        let grid = ASCIIGrid(cells: Array(repeating: Array(repeating: cell, count: 8), count: 8), colorSpace: .sRGB)
        let engine = AskiRenderEngine()
        _ = try await engine.render(
            grid,
            font: ASCIIFont.system(size: 12),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )
        await engine.flushCaches()
        let img = try await engine.render(
            grid,
            font: ASCIIFont.system(size: 12),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )
        #expect(img.width > 0)
    }

    @Test func parallelRendersReturnIdenticalDimensions() async throws {
        let cell = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
        let grid = ASCIIGrid(cells: Array(repeating: Array(repeating: cell, count: 8), count: 8), colorSpace: .sRGB)
        let engine = AskiRenderEngine()
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        async let a = engine.render(grid, font: ASCIIFont.system(size: 12), backgroundColor: bg, scale: 1)
        async let b = engine.render(grid, font: ASCIIFont.system(size: 12), backgroundColor: bg, scale: 1)
        async let c = engine.render(grid, font: ASCIIFont.system(size: 12), backgroundColor: bg, scale: 1)
        let images = try await [a, b, c]
        #expect(images.allSatisfy { $0.width == images[0].width && $0.height == images[0].height })
    }
}

@Suite struct AskiRenderEngineConcurrencyTests {
    @Test func parallelRendersOnSameEngineSucceed() async throws {
        let cell = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
        let grid = ASCIIGrid(cells: Array(repeating: Array(repeating: cell, count: 16), count: 16), colorSpace: .sRGB)
        let engine = AskiRenderEngine()
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

        try await withThrowingTaskGroup(of: CGImage.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await engine.render(grid, font: ASCIIFont.system(size: 12), backgroundColor: bg, scale: 1)
                }
            }

            var count = 0
            for try await img in group {
                #expect(img.width > 0)
                count += 1
            }
            #expect(count == 8)
        }
    }

    @Test func flushCachesDuringRendersDoesNotCrash() async throws {
        let cell = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
        let grid = ASCIIGrid(cells: Array(repeating: Array(repeating: cell, count: 8), count: 8), colorSpace: .sRGB)
        let engine = AskiRenderEngine()
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

        async let render1 = engine.render(grid, font: ASCIIFont.system(size: 12), backgroundColor: bg, scale: 1)
        await engine.flushCaches()
        async let render2 = engine.render(grid, font: ASCIIFont.system(size: 12), backgroundColor: bg, scale: 1)
        let imgs = try await [render1, render2]
        #expect(imgs.allSatisfy { $0.width > 0 })
    }
}
