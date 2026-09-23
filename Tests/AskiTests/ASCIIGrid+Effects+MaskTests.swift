import CoreGraphics
import CoreImage
import Testing
@testable import Aski

@Suite struct ASCIIGridEffectsMaskTests {
    @Test func activeOnlyEffectsDoNotChangeInactiveFallback() {
        let grid = Self.groupedGrid(coverages: [0])
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let composition = CompositionOptions(
            background: .solid(background),
            colorOverlay: ColorOverlay(
                color: CGColor(red: 1, green: 0, blue: 0, alpha: 1),
                blendMode: .normal,
                opacity: 1
            ),
            perCharacter: PerCharacterEffects(
                bloom: BloomOptions(intensity: 1, radius: 8),
                chromaticAberration: AberrationOptions(intensity: 8)
            )
        )

        let image = grid.renderImage(
            font: .system(size: 24),
            backgroundColor: background,
            scale: 1,
            composition: composition
        )
        let pixel = Self.pixels(image)[0]

        #expect(pixel.b > 200)
        #expect(pixel.r < 60)
        #expect(pixel.g < 60)
    }

    @Test func lightingAndWholeImageEffectsRunAfterGroupedBranchBlend() throws {
        let grid = Self.groupedGrid(coverages: [0, 1])
        let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let composition = CompositionOptions(background: .solid(background))
        let font = ASCIIFont.system(size: 24)
        let base = grid.renderCIImage(
            font: font,
            backgroundColor: background,
            scale: 1,
            composition: composition
        )
        let effectContext = EffectContext(
            workingColorSpace: WorkingColorSpace.extendedLinearSRGB,
            outputExtent: base.extent,
            renderColorSpace: .sRGB,
            deviceCapability: .full
        )

        let effectExpected = try StockCIEffectKernel(kind: .blur(radius: 3)).apply(
            to: base,
            in: effectContext
        )
        let effectActual = grid.renderCIImage(
            font: font,
            backgroundColor: background,
            scale: 1,
            composition: composition,
            effects: EffectChain([.blur(radius: 3)])
        )
        #expect(Self.bytes(effectActual) == Self.bytes(effectExpected))

        let lighting = LightingOptions(
            lights: [
                PointLight(
                    position: CGPoint(x: 0.25, y: 0.5),
                    radius: 1,
                    intensity: 1,
                    color: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
                )
            ],
            ambient: 0.2
        )
        let lightingExpected = LightingApplicator().apply(lighting, to: base, in: effectContext)
        let lightingActual = grid.renderCIImage(
            font: font,
            backgroundColor: background,
            scale: 1,
            composition: composition,
            lighting: lighting
        )
        #expect(Self.bytes(lightingActual) == Self.bytes(lightingExpected))
    }

    @Test func groupedSyncAsyncCGAndCIPathsAgree() async throws {
        let grid = Self.groupedGrid(coverages: [0, 0.5, 1])
        let background = CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        let composition = CompositionOptions(background: .solid(background))
        let font = ASCIIFont.system(size: 18)

        let syncCG = Self.renderSyncCG(
            grid,
            font: font,
            background: background,
            composition: composition
        )
        let asyncCG = try await grid.renderImage(
            font: font,
            backgroundColor: background,
            scale: 1,
            composition: composition
        )
        #expect(TestImages.deviceRGBBytes(syncCG) == TestImages.deviceRGBBytes(asyncCG))

        let syncCI = Self.renderSyncCI(
            grid,
            font: font,
            background: background,
            composition: composition
        )
        let asyncCI = try await grid.renderCIImage(
            font: font,
            backgroundColor: background,
            scale: 1,
            composition: composition
        )
        #expect(Self.bytes(syncCI) == Self.bytes(asyncCI))

        let ciCG = EffectsRenderEngine.shared.context.createCGImage(
            syncCI,
            from: syncCI.extent,
            format: .RGBA8,
            colorSpace: EffectsRenderEngine.renderColorSpaceCG(.sRGB)
        )!
        #expect(TestImages.deviceRGBBytes(syncCG) == TestImages.deviceRGBBytes(ciCG))
    }

    @Test func allWhiteMaskEffectsRenderMatchesUnmaskedBytes() {
        let cell = ASCIICell(character: "█", displayColor: SIMD3<Float>(1, 0, 0), alpha: 1, brightness: 1)
        let unmasked = ASCIIGrid(cells: [[cell]], colorSpace: .sRGB)
        let masked = ASCIIGrid(
            cells: [[ASCIICell(character: "█", displayColor: SIMD3<Float>(1, 0, 0), alpha: 1, brightness: 1, coverage: 1)]],
            colorSpace: .sRGB,
            maskFallback: .solid(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        )
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let composition = CompositionOptions(background: .solid(bg))

        let a = unmasked.renderImage(font: .system(size: 24), backgroundColor: bg, scale: 1, composition: composition)
        let b = masked.renderImage(font: .system(size: 24), backgroundColor: bg, scale: 1, composition: composition)

        #expect(Self.bytes(a) == Self.bytes(b))
    }

    @Test func zeroCoverageEffectsRenderShowsFallbackBehindMissingCell() {
        let grid = ASCIIGrid(
            cells: [[ASCIICell(character: "█", displayColor: SIMD3<Float>(1, 0, 0), alpha: 1, brightness: 1, coverage: 0)]],
            colorSpace: .sRGB,
            maskFallback: .solid(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        )
        let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let image = grid.renderImage(
            font: .system(size: 24),
            backgroundColor: bg,
            scale: 1,
            composition: CompositionOptions(background: .solid(bg))
        )

        let pixels = Self.pixels(image)
        #expect(pixels.contains { $0.b > 200 && $0.r < 50 })
    }

    private static func bytes(_ image: CGImage) -> [UInt8] {
        pixels(image).flatMap { [$0.r, $0.g, $0.b, $0.a] }
    }

    private static func bytes(_ image: CIImage) -> [UInt8] {
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        EffectsRenderEngine.shared.context.render(
            image,
            toBitmap: &bytes,
            rowBytes: width * 4,
            bounds: image.extent,
            format: .RGBA8,
            colorSpace: EffectsRenderEngine.renderColorSpaceCG(.sRGB)
        )
        return bytes
    }

    private static func groupedGrid(coverages: [Float]) -> ASCIIGrid {
        ASCIIGrid(
            cells: [
                coverages.map { coverage in
                    ASCIICell(
                        character: "█",
                        displayColor: SIMD3<Float>(0, 1, 0),
                        alpha: 1,
                        brightness: 1,
                        coverage: coverage
                    )
                }
            ],
            colorSpace: .sRGB,
            maskFallback: .solid(CGColor(red: 0, green: 0, blue: 1, alpha: 1)),
            maskGroundColor: CGColor(red: 0.2, green: 0.02, blue: 0.02, alpha: 1),
            maskUsesHardEdges: true
        )
    }

    private static func renderSyncCG(
        _ grid: ASCIIGrid,
        font: ASCIIFont,
        background: CGColor,
        composition: CompositionOptions
    ) -> CGImage {
        grid.renderImage(
            font: font,
            backgroundColor: background,
            scale: 1,
            composition: composition
        )
    }

    private static func renderSyncCI(
        _ grid: ASCIIGrid,
        font: ASCIIFont,
        background: CGColor,
        composition: CompositionOptions
    ) -> CIImage {
        grid.renderCIImage(
            font: font,
            backgroundColor: background,
            scale: 1,
            composition: composition
        )
    }

    private static func pixels(_ image: CGImage) -> [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &bytes,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 0, to: bytes.count, by: 4).map { index in
            (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
        }
    }
}
