import AppKit
import CoreGraphics
import SnapshotTesting
import Testing
import simd

@testable import Aski

/// ASTSK-47: locks the frozen canonical Vesper render preset. The invariant
/// tests pin every settled one-way-door knob; `canonicalRenderMatchesGoldenSnapshot`
/// is the AC#2 byte lock (any drift fails the suite).
@MainActor
@Suite(.serialized) struct VesperPresetTests {

    // AC#1 (reachable via public API) + AC#3 (every knob frozen to its settled value).
    @Test func canonicalFreezesTheSettledKnobs() {
        let preset = VesperPreset.canonical
        #expect(preset.columns == 76)
        #expect(preset.contrast == 0.15)
        #expect(preset.colorSpace == .displayP3)
        #expect(preset.oversample == 2)
        #expect(preset.fontSize == 14)
        #expect(preset.scale == 2)
    }

    // The duotone: bone (sRGB) figure + oxblood (Display P3) ground, in that order.
    @Test func canonicalPaletteIsBoneOxbloodDuotone() {
        let preset = VesperPreset.canonical
        #expect(preset.ink.colorSpace == .sRGB)
        #expect(approx(preset.ink.components, SIMD3(Float(0xE8) / 255, Float(0xE2) / 255, Float(0xD2) / 255)))
        #expect(preset.accent.colorSpace == .displayP3)
        #expect(approx(preset.accent.components, SIMD3(Float(0x5E) / 255, Float(0x1B) / 255, Float(0x18) / 255)))

        let colors = preset.makeConverter().palette.content.colors
        #expect(colors?.count == 2)
        #expect(colors?.first == preset.ink)
        #expect(colors?.last == preset.accent)
    }

    // AC#1: the app's single render entry point produces a real, aspect-faithful image.
    @Test func canonicalRenderProducesAspectFaithfulImage() {
        let source = Self.fixture()
        let rendered = VesperPreset.canonical.render(source)
        #expect(rendered.width > 0)
        #expect(rendered.height > 0)
        // preserveSourceAspect: a portrait source ⇒ a taller-than-wide render.
        #expect(rendered.height > rendered.width)
    }

    // AC#2 foundation: the render is deterministic, so the golden byte-snapshot is a valid lock.
    @Test func canonicalRenderIsDeterministic() {
        let source = Self.fixture()
        let first = TestImages.deviceRGBBytes(VesperPreset.canonical.render(source))
        let second = TestImages.deviceRGBBytes(VesperPreset.canonical.render(source))
        #expect(first == second)
    }

    // Guards the AC#2 golden against the blank-render trap: on a synthetic fixture
    // logPolar+blocks can collapse to the space glyph everywhere, leaving a byte lock
    // that locks nothing. The golden is only a real lock if the fixture paints a
    // substantial share of cells, uses only blocks glyphs, and hits BOTH duotone colors.
    @Test func fixtureExercisesTheDuotone() {
        let preset = VesperPreset.canonical
        let grid = preset.makeConverter().convert(Self.fixture(), columns: preset.columns)
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
        let preset = VesperPreset.canonical
        for (width, height) in [(240, 320), (200, 500)] {
            let source = TestImages.structuredPortraitProxy(width: width, height: height)
            let cells = preset.makeConverter().convert(source, columns: preset.columns)
                .cells.flatMap { $0 }
            let painted = cells.filter { $0.character != " " }
            #expect(painted.count > cells.count / 4, "\(width)x\(height) should paint glyphs")
        }
    }

    // AC#2: lock the rendered output bytes for a fixed image; any drift fails the suite.
    @Test func canonicalRenderMatchesGoldenSnapshot() {
        let source = Self.fixture()
        let rendered = VesperPreset.canonical.render(source)
        assertSnapshot(of: nsImage(from: rendered), as: .image, named: "vesper-canonical")
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
