import Testing
import CoreGraphics
@testable import Aski

@Suite struct AsyncRenderTests {
    @Test func asyncRenderProducesOutput() async throws {
        let cell = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
        let grid = ASCIIGrid(
            cells: Array(repeating: Array(repeating: cell, count: 8), count: 8),
            colorSpace: .sRGB
        )
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let image = try await grid.renderImage(
            font: ASCIIFont.system(size: 12),
            backgroundColor: background,
            scale: 1,
            composition: CompositionOptions(background: .solid(background)),
            effects: EffectChain([.vignette(intensity: 0.5)])
        )
        #expect(image.width > 0)
    }

    @Test func asyncRenderUsesDefaultsForOptionalArgs() async throws {
        let cell = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
        let grid = ASCIIGrid(
            cells: Array(repeating: Array(repeating: cell, count: 8), count: 8),
            colorSpace: .sRGB
        )
        let image = try await grid.renderImage(
            font: ASCIIFont.system(size: 12),
            backgroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            scale: 1
        )
        #expect(image.width > 0)
    }

    @Test func asyncRenderTileGridUsesDefaultsForOptionalArgs() async throws {
        let cell = TileCell(displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
        let grid = TileGrid(
            cells: Array(repeating: Array(repeating: cell, count: 8), count: 8),
            colorSpace: .sRGB
        )
        let image = try await grid.renderImage()
        #expect(image.width > 0)
    }

    @Test func cancelledTaskThrowsCancellationError() async {
        let cell = ASCIICell(character: "#", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 0.5)
        let grid = ASCIIGrid(
            cells: Array(repeating: Array(repeating: cell, count: 64), count: 64),
            colorSpace: .sRGB
        )
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let task = Task {
            try await grid.renderImage(
                font: ASCIIFont.system(size: 12),
                backgroundColor: background,
                scale: 2,
                composition: CompositionOptions(background: .solid(background)),
                effects: EffectChain([
                    .blur(radius: 8),
                    .bloom(intensity: 0.5, radius: 8),
                    .vignette(intensity: 0.5),
                ])
            )
        }
        task.cancel()
        do {
            _ = try await task.value
        } catch is CancellationError {
            return
        } catch {
            Issue.record("expected CancellationError, got \(error)")
        }
    }
}
