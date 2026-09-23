import CoreGraphics
import CoreImage
import Testing

@testable import Aski

/// ASKI-34 regression. CoreImage reports `CGRectInfinite` for generator and
/// tiled filters. Its components are finite floats but astronomical
/// (1.797e308), so `value.isFinite` does not catch them and
/// `Int(ceil(extent.width))` traps. Both raster sites must degrade
/// deliberately instead: clamp to the finite reference rect the call site
/// already knows, and only fall back to an empty image when no such rect
/// exists.
@Suite struct InfiniteExtentDegradationTests {

    /// A genuinely infinite-extent CIImage, produced the way CoreImage
    /// produces one in the wild: a generator filter with no crop.
    private static func infiniteGeneratorImage() -> CIImage {
        CIFilter(name: "CICheckerboardGenerator")!.outputImage!
    }

    @Test func generatorFixtureIsGenuinelyInfinite() {
        let extent = Self.infiniteGeneratorImage().extent
        #expect(extent.isInfinite)
        #expect(!extent.isEmpty)
    }

    // MARK: - Shared rule

    @Test func finiteExtentPassesFiniteRectsThroughUnchanged() {
        let rect = CGRect(x: 2, y: 3, width: 4, height: 5)
        let reference = CGRect(x: 0, y: 0, width: 9, height: 9)
        #expect(RenderPixelBounds.finiteExtent(rect, clampedTo: reference) == rect)
        #expect(RenderPixelBounds.finiteExtent(.zero, clampedTo: reference) == .zero)
    }

    @Test func finiteExtentClampsUnboundedRectsToTheReference() {
        let reference = CGRect(x: 0, y: 0, width: 9, height: 9)
        #expect(RenderPixelBounds.finiteExtent(.infinite, clampedTo: reference) == reference)
        #expect(RenderPixelBounds.finiteExtent(.null, clampedTo: reference) == reference)
        let nonFinite = CGRect(x: 0, y: 0, width: CGFloat.nan, height: 9)
        #expect(RenderPixelBounds.finiteExtent(nonFinite, clampedTo: reference) == reference)
    }

    @Test func finiteExtentReportsNoUsableRectWhenTheReferenceIsUnusable() {
        #expect(RenderPixelBounds.finiteExtent(.infinite, clampedTo: .zero) == nil)
        #expect(RenderPixelBounds.finiteExtent(.infinite, clampedTo: .infinite) == nil)
        #expect(RenderPixelBounds.finiteExtent(.infinite, clampedTo: .null) == nil)
    }

    // MARK: - Coverage path

    @Test func tileCoverageClampsInfiniteExtentToTheGridExtent() {
        let grid = TileGrid(
            cells: [
                [Self.tileCell(coverage: 0), Self.tileCell(coverage: 1)],
                [Self.tileCell(coverage: 1), Self.tileCell(coverage: 0)],
            ],
            colorSpace: .sRGB
        )
        let gridExtent = CGRect(x: 0, y: 0, width: 20, height: 20)

        let clamped = CoverageImageBuilder.makeTile(
            grid: grid,
            mode: .pixelArt,
            shape: .square,
            scale: 10,
            extent: Self.infiniteGeneratorImage().extent,
            useHardEdges: true
        )
        let reference = CoverageImageBuilder.makeTile(
            grid: grid,
            mode: .pixelArt,
            shape: .square,
            scale: 10,
            extent: gridExtent,
            useHardEdges: true
        )

        #expect(clamped.extent == gridExtent)
        // The clamp must reproduce the coverage mask, not merely avoid the trap.
        for point in [(5, 5), (15, 5), (5, 15), (15, 15)] {
            #expect(
                Self.gray(clamped, x: point.0, y: point.1)
                    == Self.gray(reference, x: point.0, y: point.1)
            )
        }
        // Sanity: the mask actually varies, so the comparison above has content.
        #expect(Self.gray(reference, x: 5, y: 5) != Self.gray(reference, x: 15, y: 5))
    }

    @Test func tileCoverageWithNoFiniteReferenceDegradesToAnEmptyImage() {
        let grid = TileGrid(cells: [], colorSpace: .sRGB)
        let image = CoverageImageBuilder.makeTile(
            grid: grid,
            mode: .pixelArt,
            shape: .square,
            scale: 10,
            extent: Self.infiniteGeneratorImage().extent,
            useHardEdges: true
        )

        #expect(!image.extent.isInfinite)
        #expect(image.extent.isEmpty)
    }

    @Test func tileCoverageIsUnchangedForFiniteExtents() {
        let grid = TileGrid(
            cells: [[Self.tileCell(coverage: 0)]],
            colorSpace: .sRGB
        )
        let image = CoverageImageBuilder.makeTile(
            grid: grid,
            mode: .pixelArt,
            shape: .circle,
            scale: 20,
            extent: CGRect(x: 0, y: 0, width: 20, height: 20),
            useHardEdges: true
        )

        #expect(Self.gray(image, x: 0, y: 0) > 247)
        #expect(Self.gray(image, x: 10, y: 10) < 8)
    }

    // MARK: - Effects path

    @Test func stockEffectClampsInfiniteOutputExtentToTheInputImageExtent() throws {
        let extent = CGRect(x: 0, y: 0, width: 16, height: 16)
        let input = CIImage(color: CIColor(red: 0.5, green: 0.4, blue: 0.3, alpha: 1))
            .cropped(to: extent)
        let kernel = StockCIEffectKernel(kind: .filmGrainApprox(intensity: 0.5, seed: 7))

        let clamped = try kernel.apply(
            to: input,
            in: Self.context(outputExtent: Self.infiniteGeneratorImage().extent)
        )
        let reference = try kernel.apply(to: input, in: Self.context(outputExtent: extent))

        #expect(clamped.extent == extent)
        #expect(Self.rgba(clamped, x: 3, y: 3) == Self.rgba(reference, x: 3, y: 3))
        #expect(Self.rgba(clamped, x: 11, y: 9) == Self.rgba(reference, x: 11, y: 9))
    }

    @Test func stockEffectWithNoFiniteReferenceDegradesToAnEmptyImage() throws {
        let input = Self.infiniteGeneratorImage()
        let kernel = StockCIEffectKernel(kind: .filmDustApprox(intensity: 0.5, seed: 3))

        let output = try kernel.apply(to: input, in: Self.context(outputExtent: input.extent))

        #expect(!output.extent.isInfinite)
        #expect(output.extent.isEmpty)
    }

    @Test func stockEffectAcceptsAnInfiniteInputImageWhenTheOutputExtentIsFinite() throws {
        let extent = CGRect(x: 0, y: 0, width: 16, height: 16)
        let kernel = StockCIEffectKernel(kind: .filmGrainApprox(intensity: 0.5, seed: 11))

        let output = try kernel.apply(
            to: Self.infiniteGeneratorImage(),
            in: Self.context(outputExtent: extent)
        )

        #expect(output.extent == extent)
    }

    // MARK: - Helpers

    private static func tileCell(coverage: Float) -> TileCell {
        TileCell(displayColor: .one, alpha: 1, brightness: 1, coverage: coverage)
    }

    private static func context(outputExtent: CGRect) -> EffectContext {
        EffectContext(
            workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
            outputExtent: outputExtent,
            renderColorSpace: .sRGB,
            deviceCapability: .reducedQuality(.metallibUnsupported)
        )
    }

    private static func rgba(_ image: CIImage, x: Int, y: Int) -> [UInt8] {
        let context = CIContext(options: nil)
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            image,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: x, y: y, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return pixel
    }

    private static func gray(_ image: CIImage, x: Int, y: Int) -> UInt8 {
        rgba(image, x: x, y: y)[0]
    }
}
