import AppKit
import CoreGraphics
import SnapshotTesting
import Testing
import simd

import Aski
import AskiToolSupport

/// Pins the ASTSK-47 rendering reference and its original raster snapshot.
@MainActor
@Suite(.serialized) struct FrozenRenderReferenceTests {

    @Test func canonicalFreezesTheSettledKnobs() {
        #expect(FrozenRenderReference.columns == 76)
        #expect(FrozenRenderReference.contrast == 0.15)
        #expect(FrozenRenderReference.colorSpace == .displayP3)
        #expect(FrozenRenderReference.oversample == 2)
        #expect(FrozenRenderReference.fontSize == 14)
        #expect(FrozenRenderReference.scale == 2)
    }

    // The duotone: bone (sRGB) figure + oxblood (Display P3) ground, in that order.
    @Test func canonicalPaletteIsBoneOxbloodDuotone() {
        #expect(FrozenRenderReference.ink.colorSpace == .sRGB)
        #expect(approx(FrozenRenderReference.ink.components, SIMD3(Float(0xE8) / 255, Float(0xE2) / 255, Float(0xD2) / 255)))
        #expect(FrozenRenderReference.accent.colorSpace == .displayP3)
        #expect(approx(FrozenRenderReference.accent.components, SIMD3(Float(0x5E) / 255, Float(0x1B) / 255, Float(0x18) / 255)))

        let colors = FrozenRenderReference.makeConverter().palette.content.colors
        #expect(colors?.count == 2)
        #expect(colors?.first == FrozenRenderReference.ink)
        #expect(colors?.last == FrozenRenderReference.accent)
    }

    @Test func canonicalRenderProducesAspectFaithfulImage() {
        let source = Self.fixture()
        let rendered = FrozenRenderReference.render(source)
        #expect(rendered.width > 0)
        #expect(rendered.height > 0)
        // preserveSourceAspect: a portrait source ⇒ a taller-than-wide render.
        #expect(rendered.height > rendered.width)
    }

    @Test func canonicalRenderIsDeterministic() {
        let source = Self.fixture()
        let first = TestImages.deviceRGBBytes(FrozenRenderReference.render(source))
        let second = TestImages.deviceRGBBytes(FrozenRenderReference.render(source))
        #expect(first == second)
    }

    // Guards the raster snapshot against the blank-render trap: on a synthetic fixture
    // logPolar+blocks can collapse to the space glyph everywhere, leaving a byte lock
    // that locks nothing. The golden is only a real lock if the fixture paints a
    // substantial share of cells, uses only blocks glyphs, and hits BOTH duotone colors.
    @Test func fixtureExercisesTheDuotone() {
        let grid = FrozenRenderReference.makeConverter().convert(Self.fixture(), columns: FrozenRenderReference.columns)
        let cells = grid.cells.flatMap { $0 }
        let painted = cells.filter { $0.character != " " }
        #expect(painted.count > cells.count / 4)

        let blocksGlyphs = Set(StandardCharacterSet.blocks.characters)
        #expect(painted.allSatisfy { blocksGlyphs.contains($0.character) })

        let paintedColors = Set(painted.map(\.displayColor))
        #expect(paintedColors.count == 2)
    }

    // Regression: portrait-aspect sources once rendered fully blank (1px-wide cells
    // zero out the log-polar descriptor, which exact-matches the space glyph). The
    // tall case additionally locks the aspect-aware thumbnail cap for rows > cols,
    // where scaling the row-derived budget by height/width would double-apply the
    // aspect ratio.
    @Test func portraitAndTallSourcesPaintGlyphs() {
        for (width, height) in [(240, 320), (200, 500)] {
            let source = TestImages.structuredPortraitProxy(width: width, height: height)
            let cells = FrozenRenderReference.makeConverter().convert(source, columns: FrozenRenderReference.columns)
                .cells.flatMap { $0 }
            let painted = cells.filter { $0.character != " " }
            #expect(painted.count > cells.count / 4, "\(width)x\(height) should paint glyphs")
        }
    }

    @Test func canonicalRenderMatchesGoldenSnapshot() {
        let source = Self.fixture()
        let rendered = FrozenRenderReference.render(source)
        assertSnapshot(of: nsImage(from: rendered), as: .image, named: "frozen-render-reference")
    }

    /// A fixed, deterministic portrait-proxy (structured, full tonal range) so the
    /// golden exercises the whole bone→oxblood→charcoal duotone, not blank cells.
    private static func fixture() -> CGImage {
        TestImages.structuredPortraitProxy(width: 240, height: 320)
    }

    private func approx(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>, _ tolerance: Float = 1e-4) -> Bool {
        simd_length(lhs - rhs) < tolerance
    }

    private func nsImage(from image: CGImage) -> NSImage {
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
