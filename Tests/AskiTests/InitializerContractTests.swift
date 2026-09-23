import CoreGraphics
import Foundation
import Testing

@testable import Aski

/// ASKI-35 — contract regressions for the public initializers that accept an
/// unvalidated floating-point parameter. Each test asserts the BEHAVIOUR the
/// classification doc comments promise, not the text of the guard.
@Suite struct InitializerContractTests {
    // MARK: - AnimationAnchor

    private func revealAlphas(origin: AnimationAnchor, columns: Int, rows: Int, time: Double) -> [Double] {
        var out: [Double] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let coord = AnimationCellCoordinate(column: column, row: row, columns: columns, rows: rows)
                out.append(
                    PatternEvaluator.entranceAlpha(
                        .reveal(origin: origin), coord: coord, time: time, duration: 1))
            }
        }
        return out
    }

    /// A finite anchor outside 0...1 is SUPPORTED: the reveal normalizes the
    /// distance field against the anchor itself, so an off-grid origin gives a
    /// well-defined wavefront sweeping in from that side. Asserted as behaviour:
    /// cells nearer the off-grid origin reveal no later than cells further away.
    @Test func offGridAnchorProducesAMonotoneWavefront() {
        let alphas = revealAlphas(origin: AnimationAnchor(x: -1, y: 0.5), columns: 8, rows: 1, time: 0.5)
        for index in 1..<alphas.count {
            #expect(alphas[index] <= alphas[index - 1] + 1e-12)
        }
        #expect(alphas.first! > alphas.last!)  // a real gradient, not a flat field
    }

    /// A far-off-grid anchor stays inside the unit alpha range — the
    /// normalization keeps the field well-defined however far out the origin is.
    @Test func farOffGridAnchorStaysInUnitRange() {
        let alphas = revealAlphas(origin: AnimationAnchor(x: -500, y: 900), columns: 6, rows: 4, time: 0.6)
        #expect(alphas.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    /// A non-finite coordinate is not a supported geometry: it resolves to the
    /// centre (0.5) at the single consumption point, so a NaN/infinite anchor
    /// reveals exactly like `.center` instead of degenerating into a flat field.
    @Test func nonFiniteAnchorRevealsLikeCenter() {
        let expected = revealAlphas(origin: .center, columns: 7, rows: 5, time: 0.5)
        for bad in [Double.nan, .infinity, -.infinity] {
            #expect(revealAlphas(origin: AnimationAnchor(x: bad, y: bad), columns: 7, rows: 5, time: 0.5) == expected)
            #expect(revealAlphas(origin: AnimationAnchor(x: bad, y: 0.5), columns: 7, rows: 5, time: 0.5) == expected)
        }
    }

    /// A finite coordinate so large that the corner `hypot` overflows has no
    /// finite geometry either: `inf / inf` progress is NaN, which hid every
    /// cell until the endpoint (PR #28 review). It takes the same centre
    /// fallback as a non-finite coordinate.
    @Test func overflowingFiniteAnchorRevealsLikeCenter() {
        let expected = revealAlphas(origin: .center, columns: 7, rows: 5, time: 0.5)
        for huge in [Double.greatestFiniteMagnitude, -.greatestFiniteMagnitude] {
            #expect(revealAlphas(origin: AnimationAnchor(x: huge, y: huge), columns: 7, rows: 5, time: 0.5) == expected)
            #expect(revealAlphas(origin: AnimationAnchor(x: huge, y: 0.5), columns: 7, rows: 5, time: 0.5) == expected)
        }
    }

    /// In-range anchors are untouched by the non-finite rule.
    @Test func inRangeAnchorsAreUnchanged() {
        let alphas = revealAlphas(origin: AnimationAnchor(x: 0, y: 0), columns: 4, rows: 4, time: 0.5)
        #expect(alphas.first! > alphas.last!)
        #expect(alphas.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    // MARK: - GIF frame delay

    private func gifStream(_ delays: [Double]) -> AsyncThrowingStream<ASCIIGIFFrame, Error> {
        AsyncThrowingStream { continuation in
            for delay in delays {
                continuation.yield(ASCIIGIFFrame(grid: ASCIIGrid(cells: [], colorSpace: .sRGB), delay: delay))
            }
            continuation.finish()
        }
    }

    private func resampledDelays(_ delays: [Double], targetFPS: Int, sourceDuration: Double) async throws -> [Double] {
        let stats = ResampleStats()
        let stream = try resampledGIFFrames(
            gifStream(delays), targetFPS: targetFPS, sourceDuration: sourceDuration, into: stats)
        var out: [Double] = []
        for try await frame in stream { out.append(frame.delay) }
        return out
    }

    /// A frame carrying a non-finite or absurdly large delay must degrade, not
    /// trap: the derived output slot is bounded, so such a frame simply lands
    /// past the end of the schedule and the stream still finishes.
    @Test func outOfRangeFrameDelaysDoNotTrapTheResampler() async throws {
        for bad in [Double.infinity, .greatestFiniteMagnitude, 1e30, .nan] {
            let out = try await resampledDelays([0.1, bad, 0.1], targetFPS: 10, sourceDuration: 0.3)
            #expect(out.count == 3)
            #expect(out.allSatisfy { abs($0 - 0.1) < 1e-9 })
        }
    }

    /// A negative delay is out of domain too and must not push the schedule
    /// backwards into a trapping slot.
    @Test func negativeFrameDelayDoesNotTrapTheResampler() async throws {
        let out = try await resampledDelays([0.1, -1e300, 0.1], targetFPS: 10, sourceDuration: 0.3)
        #expect(out.count == 3)
    }

    /// Valid delays keep their exact existing selection behaviour.
    @Test func validFrameDelaysAreUnaffected() async throws {
        let out = try await resampledDelays([0.1, 0.1, 0.1], targetFPS: 20, sourceDuration: 0.3)
        #expect(out.count == 6)
        #expect(out.allSatisfy { abs($0 - 0.05) < 1e-9 })
    }

    /// The one stated rule for a bad delay AT WRITE TIME is the encoder's
    /// normalization to 0.1s; valid values (including sub-floor) pass through raw.
    @Test func writeTimeRuleNormalizesOnlyOutOfDomainDelays() {
        #expect(ASCIIGIFEncoder.normalizedDelay(.nan) == 0.1)
        #expect(ASCIIGIFEncoder.normalizedDelay(.infinity) == 0.1)
        #expect(ASCIIGIFEncoder.normalizedDelay(0) == 0.1)
        #expect(ASCIIGIFEncoder.normalizedDelay(-1) == 0.1)
        #expect(ASCIIGIFEncoder.normalizedDelay(0.005) == 0.005)
        #expect(ASCIIGIFEncoder.normalizedDelay(2) == 2)
    }

    // MARK: - ASCIIFont / frozen preset (ASKI-17 derived-geometry bound)

    /// The font point size stays unvalidated at construction; the bound lives on
    /// the derived raster geometry, which returns the empty-image fallback.
    @Test func extremeFontSizeDegradesAtTheRenderBound() {
        let cell = ASCIICell(character: "A", displayColor: SIMD3<Float>(1, 1, 1), alpha: 1, brightness: 1)
        let grid = ASCIIGrid(cells: [[cell]], colorSpace: .sRGB)
        let background = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        for size in [CGFloat.infinity, .greatestFiniteMagnitude, 1e30] {
            let font = ASCIIFont(name: "Menlo", size: size)
            let image = grid.renderImage(font: font, backgroundColor: background, scale: 1)
            #expect(image.width >= 1)  // degraded fallback, not a trap
        }
    }
}
