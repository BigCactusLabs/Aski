import CoreGraphics
import Foundation
import Testing

// Deliberately NOT `@testable`: this suite is the ASKI-9 proof that a host app
// can drive the whole beat with the public module interface only. Any symbol it
// needs that is `internal` or `@_spi` would fail to compile here, which is the
// point of the file.
import Aski

/// ASKI-9 — the host-app seam contract: photo → canonical duotone render →
/// `EntrancePattern` reveal → `CGImage` frames.
///
/// An integrating app drives the beat in five steps, all public API:
///
/// 1. **Photo in.** Obtain the source as a `CGImage` (PhotosPicker /
///    `CGImageSourceCreateImageAtIndex` / camera buffer). No Aski call yet.
/// 2. **Take the frozen preset.** `let preset = VesperPreset.canonical` — the
///    one settled look (blocks charset, 76 columns, bone-on-oxblood duotone on
///    charcoal). Never re-derive its knobs; read them off the preset so the app
///    cannot drift from the library.
/// 3. **Build the converter once.** `let converter = preset.makeConverter()`.
///    It is `Sendable` and reusable; build it once per look, not per frame.
/// 4. **Animate instead of convert.** `converter.animate(photo, columns:
///    preset.columns, options:)` where `options` carries the reveal, e.g.
///    `AnimationOptions(duration: 1, seed: 0, cycling: nil, entrance:
///    .reveal(origin: .center))`. Pass `cycling: nil` for a clean reveal with
///    stable glyphs; keep `.default` to let glyphs churn underneath it. The
///    result, `AnimatedASCIIGrid`, is a *closed form* — it holds no timer and
///    no state.
/// 5. **Pull frames.** Either sample on the app's own clock
///    (`animated.grid(at: t)`) for a `CADisplayLink`/`TimelineView` reveal, or
///    materialize a fixed cadence up front
///    (`animated.materialize(frameRate: 12)`) for an export. Render each grid
///    with the preset's own render parameters:
///    `grid.renderImage(font: preset.font, backgroundColor:
///    preset.backgroundColor, scale: preset.scale, preserveSourceAspect: true)`.
///
/// Seam caveat (step 5): render through `grid(at:)`/`materialize(frameRate:)`
/// plus `ASCIIGrid.renderImage`, **not** through the
/// `AnimatedASCIIGrid.renderImage(at:...)` convenience, which has no
/// `preserveSourceAspect` parameter and therefore cannot reproduce the
/// preset's aspect-faithful geometry. `frameGeometryMatchesStaticPresetRender`
/// below locks that the documented route agrees with `VesperPreset.render`.
@Suite struct VesperRevealIntegrationTests {

    private static let frameRate = 12
    private static let duration: TimeInterval = 1

    private static func photo() -> CGImage {
        TestImages.structuredPortraitProxy(width: 240, height: 320)
    }

    private static func revealOptions() -> AnimationOptions {
        AnimationOptions(
            duration: duration,
            seed: 0,
            cycling: nil,
            entrance: .reveal(origin: .center)
        )
    }

    private static func revealFrames() -> [CGImage] {
        let preset = VesperPreset.canonical
        let animated = preset.makeConverter()
            .animate(photo(), columns: preset.columns, options: revealOptions())
        return animated.materialize(frameRate: frameRate).map { grid in
            grid.renderImage(
                font: preset.font,
                backgroundColor: preset.backgroundColor,
                scale: preset.scale,
                preserveSourceAspect: true
            )
        }
    }

    /// Count pixels of `image` that differ from the same pixel of `reference`.
    /// With `cycling: nil` the glyphs are fixed, so the only thing that can
    /// change between frames is how much of the art the reveal has uncovered.
    private static func changedPixelCount(_ image: CGImage, from reference: CGImage) -> Int {
        let lhs = TestImages.deviceRGBBytes(image)
        let rhs = TestImages.deviceRGBBytes(reference)
        #expect(lhs.count == rhs.count)
        var changed = 0
        for pixel in stride(from: 0, to: min(lhs.count, rhs.count), by: 4)
        where lhs[pixel] != rhs[pixel] || lhs[pixel + 1] != rhs[pixel + 1] || lhs[pixel + 2] != rhs[pixel + 2] {
            changed += 1
        }
        return changed
    }

    private static func meanAlpha(_ grid: ASCIIGrid) -> Float {
        let alphas = grid.cells.flatMap { $0 }.map(\.alpha)
        guard !alphas.isEmpty else { return 0 }
        return alphas.reduce(0, +) / Float(alphas.count)
    }

    // AC#1: the whole beat runs, and the frames it yields are real images at the
    // cadence the host asked for.
    @Test func photoRendersToRevealFrames() {
        let frames = Self.revealFrames()

        // duration * frameRate lands on a whole frame, so the endpoint is the
        // last cadence step: 12 steps + frame zero.
        #expect(frames.count == Self.frameRate * Int(Self.duration) + 1)
        #expect(frames.allSatisfy { $0.width > 0 && $0.height > 0 })
        // Every frame is the same canvas — a host can hand them straight to an
        // encoder or a cross-fade without re-laying out.
        #expect(Set(frames.map { $0.width }).count == 1)
        #expect(Set(frames.map { $0.height }).count == 1)
        // Portrait source ⇒ aspect-faithful portrait frames.
        #expect(frames[0].height > frames[0].width)
    }

    // AC#1: the frames actually *reveal* — pixel coverage grows over the beat
    // and the last frame differs from the first.
    @Test func revealUncoversMorePixelsOverTime() {
        let frames = Self.revealFrames()
        let first = frames[0]
        let middle = frames[frames.count / 2]
        let last = frames[frames.count - 1]

        let midChanged = Self.changedPixelCount(middle, from: first)
        let lastChanged = Self.changedPixelCount(last, from: first)

        #expect(midChanged > 0)
        #expect(lastChanged > midChanged)
    }

    // AC#1: the reveal envelope itself — hidden at t=0, fully open at t=duration,
    // read through the public `grid(at:)` sampling seam a live host would use.
    @Test func revealAlphaProgressesFromHiddenToFullyOpen() {
        let preset = VesperPreset.canonical
        let animated = preset.makeConverter()
            .animate(Self.photo(), columns: preset.columns, options: Self.revealOptions())

        let samples = [0, 0.25, 0.5, 0.75, 1.0].map { Self.meanAlpha(animated.grid(at: $0 * Self.duration)) }
        for (earlier, later) in zip(samples, samples.dropFirst()) {
            #expect(later >= earlier)
        }
        #expect(samples[0] < samples[samples.count - 1])

        // At and past the duration the reveal is transparent: every cell carries
        // its converted alpha, exactly as a static render would.
        let settled = animated.grid(at: Self.duration)
        let base = animated.baseGrid
        #expect(settled.rows == base.rows && settled.columns == base.columns)
        for row in 0..<base.rows {
            for column in 0..<base.columns {
                #expect(settled.cells[row][column].alpha == base.cells[row][column].alpha)
            }
        }
    }

    // AC#3 lock: the documented step-5 route reproduces the frozen preset's
    // geometry, so a host can cross-fade the reveal's last frame into
    // `VesperPreset.render`'s still without a resize.
    @Test func frameGeometryMatchesStaticPresetRender() {
        let still = VesperPreset.canonical.render(Self.photo())
        let frames = Self.revealFrames()
        #expect(frames[0].width == still.width)
        #expect(frames[0].height == still.height)
    }
}
