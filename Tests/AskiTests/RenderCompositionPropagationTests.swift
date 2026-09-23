import CoreGraphics
import CoreImage
import Testing
@testable import Aski

/// Pin that `RenderCompositionPolicy` flows through every code path that
/// rebuilds an ``ASCIIGrid`` from a configured source. Addresses the silent-
/// drop regressions Codex flagged on PR #17: animation frames had been
/// reconstructing grids without `composition:`, and the effects raster path
/// was hardcoding encoded sRGB/P3 regardless of policy.
@Suite struct RenderCompositionPropagationTests {

    // MARK: - Animation

    @Test func animatedGridPreservesCompositionPerFrame() {
        let animated = makeAnimatedGrid(composition: .extendedLinearPerGamut)
        #expect(animated.baseGrid.composition == .extendedLinearPerGamut)
        #expect(animated.grid(at: 0).composition == .extendedLinearPerGamut)
        #expect(animated.grid(at: 0.5).composition == .extendedLinearPerGamut)
        #expect(animated.grid(at: 1.0).composition == .extendedLinearPerGamut)
    }

    @Test func materializedFramesPreserveComposition() {
        let animated = makeAnimatedGrid(composition: .extendedLinearPerGamut)
        let frames = animated.materialize(frameRate: 4)
        #expect(!frames.isEmpty)
        for frame in frames {
            #expect(frame.composition == .extendedLinearPerGamut)
        }
    }

    @Test func animatedGridDefaultsToEncodedDisplay8Bit() {
        // Base grid built without specifying composition → default propagates
        // through frames unchanged.
        let animated = makeAnimatedGrid(composition: .encodedDisplay8Bit)
        #expect(animated.grid(at: 0).composition == .encodedDisplay8Bit)
    }

    // MARK: - Effects raster path

    @Test func cellRasterBuilderUsesEncodedColorSpaceUnderDefault() {
        let grid = makeOneCellGrid(colorSpace: .sRGB, composition: .encodedDisplay8Bit)
        let raster = CellRasterBuilder.makeASCIIRaster(grid: grid, font: .system(size: 20), scale: 1)
        let cgImage = raster.image.cgImage
        #expect(cgImage != nil)
        let name = cgImage?.colorSpace?.name as String?
        #expect(
            name == (CGColorSpace.sRGB as String),
            "default policy → effects raster CGImage should be sRGB-tagged, got \(name ?? "nil")")
    }

    @Test func cellRasterBuilderUsesLinearSRGBUnderOptIn() {
        let grid = makeOneCellGrid(colorSpace: .sRGB, composition: .extendedLinearPerGamut)
        let raster = CellRasterBuilder.makeASCIIRaster(grid: grid, font: .system(size: 20), scale: 1)
        let cgImage = raster.image.cgImage
        #expect(cgImage != nil)
        let name = cgImage?.colorSpace?.name as String?
        #expect(
            name == (CGColorSpace.linearSRGB as String),
            "opt-in policy → effects raster CGImage should be linearSRGB-tagged, got \(name ?? "nil")")
    }

    @Test func cellRasterBuilderUsesDisplayP3UnderDefaultForP3Grid() {
        let grid = makeOneCellGrid(colorSpace: .displayP3, composition: .encodedDisplay8Bit)
        let raster = CellRasterBuilder.makeASCIIRaster(grid: grid, font: .system(size: 20), scale: 1)
        let cgImage = raster.image.cgImage
        #expect(cgImage != nil)
        let name = cgImage?.colorSpace?.name as String?
        #expect(
            name == (CGColorSpace.displayP3 as String),
            "default policy on P3 grid → effects raster should be displayP3-tagged, got \(name ?? "nil")")
    }

    @Test func cellRasterBuilderUsesLinearDisplayP3UnderOptInForP3Grid() {
        let grid = makeOneCellGrid(colorSpace: .displayP3, composition: .extendedLinearPerGamut)
        let raster = CellRasterBuilder.makeASCIIRaster(grid: grid, font: .system(size: 20), scale: 1)
        let cgImage = raster.image.cgImage
        #expect(cgImage != nil)
        let name = cgImage?.colorSpace?.name as String?
        #expect(
            name == (CGColorSpace.linearDisplayP3 as String),
            "opt-in policy on P3 grid → effects raster should be linearDisplayP3-tagged, got \(name ?? "nil")")
    }

    // MARK: - Fixtures

    private func makeOneCellGrid(colorSpace: RenderColorSpace, composition: RenderCompositionPolicy) -> ASCIIGrid {
        let cell = ASCIICell(
            character: "A",
            displayColor: SIMD3<Float>(1, 0, 0),
            alpha: 1,
            brightness: 0.5,
            coverage: 1
        )
        return ASCIIGrid(cells: [[cell]], colorSpace: colorSpace, composition: composition)
    }

    private func makeAnimatedGrid(composition: RenderCompositionPolicy) -> AnimatedASCIIGrid {
        let base = ASCIIGrid(
            cells: [[ASCIICell(character: "A", displayColor: .one, alpha: 1, brightness: 0.5, coverage: 1)]],
            colorSpace: .sRGB,
            composition: composition
        )
        let snapshot = CharacterSetSnapshot(characters: ["A", "B", "C"])
        let schedule = ScheduleBuilder.build(
            baseGrid: base,
            candidates: [0, 1, 2],
            candidateStride: 3,
            candidateCounts: [3],
            characterSet: snapshot,
            options: AnimationOptions(duration: 1, cycling: CyclingOptions(k: 3, speed: 1, intensity: 1, randomness: 0))
        )
        return AnimatedASCIIGrid(baseGrid: base, duration: 1, seed: 0, schedule: schedule, characterSet: snapshot)
    }
}
