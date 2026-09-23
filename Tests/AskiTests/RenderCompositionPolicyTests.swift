import CoreGraphics
import Testing
import simd
@testable import Aski

@Suite struct RenderCompositionPolicyTests {

    /// The default policy must produce a CGImage tagged with the target gamut's
    /// encoded color space — v0.2.0 behavior.
    @Test func encodedDisplay8BitTagsEncodedColorSpace() {
        let grid = ASCIIGrid(cells: [[Self.gray50Cell]], colorSpace: .sRGB)
        let img = grid.renderImage(
            font: .system(size: 20),
            backgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            scale: 1
        )
        let imgSpaceName = img.colorSpace?.name as String?
        let sRGBName = CGColorSpace.sRGB as String
        #expect(
            imgSpaceName == sRGBName,
            "default policy on sRGB grid expected sRGB-tagged image, got \(imgSpaceName ?? "nil")")
    }

    @Test func encodedDisplay8BitTagsDisplayP3ForP3Grid() {
        let grid = ASCIIGrid(cells: [[Self.gray50Cell]], colorSpace: .displayP3)
        let img = grid.renderImage(
            font: .system(size: 20),
            backgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            scale: 1
        )
        let imgSpaceName = img.colorSpace?.name as String?
        let p3Name = CGColorSpace.displayP3 as String
        #expect(
            imgSpaceName == p3Name,
            "default policy on P3 grid expected Display-P3-tagged image, got \(imgSpaceName ?? "nil")")
    }

    @Test func extendedLinearPerGamutTagsLinearSRGBForSRGBGrid() {
        let grid = ASCIIGrid(cells: [[Self.gray50Cell]], colorSpace: .sRGB, composition: .extendedLinearPerGamut)
        let img = grid.renderImage(
            font: .system(size: 20),
            backgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            scale: 1
        )
        let imgSpaceName = img.colorSpace?.name as String?
        let linearSRGBName = CGColorSpace.linearSRGB as String
        #expect(
            imgSpaceName == linearSRGBName,
            "opt-in policy on sRGB grid expected linearSRGB-tagged image, got \(imgSpaceName ?? "nil")")
    }

    @Test func extendedLinearPerGamutTagsLinearDisplayP3ForP3Grid() {
        let grid = ASCIIGrid(cells: [[Self.gray50Cell]], colorSpace: .displayP3, composition: .extendedLinearPerGamut)
        let img = grid.renderImage(
            font: .system(size: 20),
            backgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            scale: 1
        )
        let imgSpaceName = img.colorSpace?.name as String?
        let linearP3Name = CGColorSpace.linearDisplayP3 as String
        #expect(
            imgSpaceName == linearP3Name,
            "opt-in policy on P3 grid expected linearDisplayP3-tagged image, got \(imgSpaceName ?? "nil")")
    }

    /// Discriminator fixture: edge_gray50_over_white_alpha050 — gray50 cell at
    /// α≈0.5 over a white background. The two policies must diverge, with the
    /// opt-in linear-light path producing a *brighter* result than the default
    /// encoded path (per lab evidence: linear-light alpha blending preserves
    /// more brightness on dark-over-light than encoded 8-bit blending).
    ///
    /// Note on absolute byte values: the lab's `encoded8bit` byte 191 and
    /// `linear8bit` byte 204 come from pure-software 8-bit blending math
    /// (`Tools/AskiColorLab/LinearComposite/LinearCompositePolicies.swift`).
    /// `renderImage()` goes through Core Text glyph rendering, which already
    /// applies some linear-light alpha correction inside CGContext, so the
    /// observed bytes (≈ 200 default, ≈ 210 opt-in) shift relative to the
    /// lab's reference but the *direction* and *materiality* of divergence
    /// match. This test pins those two properties.
    ///
    /// Ported from
    /// `Tools/AskiColorLab/LinearComposite/LinearCompositeFixtures.swift:57-63`
    /// per addendum §2.
    @Test func extendedLinearPerGamutDivergesAndBrightensOnGray50OverWhite() {
        let cells = [[Self.gray50Cell]]
        let backgroundWhite = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let font = ASCIIFont.system(size: 40)

        let gridDefault = ASCIIGrid(cells: cells, colorSpace: .sRGB)
        let gridLinear = ASCIIGrid(cells: cells, colorSpace: .sRGB, composition: .extendedLinearPerGamut)

        let imgDefault = gridDefault.renderImage(font: font, backgroundColor: backgroundWhite, scale: 1)
        let imgLinear = gridLinear.renderImage(font: font, backgroundColor: backgroundWhite, scale: 1)

        let centerDefault = sampleCenterPixelCanonicalizedToSRGB(imgDefault)
        let centerLinear = sampleCenterPixelCanonicalizedToSRGB(imgLinear)

        // Direction: linear-light blending preserves more brightness on
        // dark-over-light, so opt-in byte > default byte.
        #expect(
            centerLinear.x > centerDefault.x,
            "opt-in must be brighter than default on gray50-over-white (default=\(centerDefault.x), opt-in=\(centerLinear.x))")
        // Materiality: divergence must exceed at least 5 bytes per channel so a
        // future regression that silently revert opt-in is detectable.
        let perChannelDelta = Int(centerLinear.x) - Int(centerDefault.x)
        #expect(
            perChannelDelta >= 5,
            "policies must diverge by ≥5 bytes/channel on this discriminator (got \(perChannelDelta), default=\(centerDefault), opt-in=\(centerLinear))")
    }

    /// Analogous P3-target discriminator: edge_p3_green_over_white_alpha050.
    /// fg = displayP3 (0, 1, 0) at α=0.502, over white background. Pins that
    /// the P3 path uses `linearDisplayP3` (not `linearSRGB`) under opt-in.
    @Test func extendedLinearPerGamutDivergesOnP3GreenOverWhite() {
        let cells = [
            [
                ASCIICell(
                    character: "█",
                    displayColor: SIMD3<Float>(0, 1, 0),
                    alpha: 128.0 / 255.0,
                    brightness: 0.5,
                    coverage: 1.0
                )
            ]
        ]
        let backgroundWhite = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let font = ASCIIFont.system(size: 40)

        let gridDefault = ASCIIGrid(cells: cells, colorSpace: .displayP3)
        let gridLinear = ASCIIGrid(cells: cells, colorSpace: .displayP3, composition: .extendedLinearPerGamut)

        let imgDefault = gridDefault.renderImage(font: font, backgroundColor: backgroundWhite, scale: 1)
        let imgLinear = gridLinear.renderImage(font: font, backgroundColor: backgroundWhite, scale: 1)

        let centerDefault = sampleCenterPixelCanonicalizedToSRGB(imgDefault)
        let centerLinear = sampleCenterPixelCanonicalizedToSRGB(imgLinear)

        // The two policies must produce materially different output on this
        // discriminator (encoded vs linear-light compositing of a saturated
        // primary over white at α=0.5). Lab's per-channel divergence ≈ 60+
        // bytes on R/B channels.
        let pairwise = simd_distance(
            SIMD3<Float>(Float(centerDefault.x), Float(centerDefault.y), Float(centerDefault.z)) / 255,
            SIMD3<Float>(Float(centerLinear.x), Float(centerLinear.y), Float(centerLinear.z)) / 255
        )
        #expect(
            pairwise > 0.05,
            "policies must diverge on P3-green-over-white discriminator (got distance \(pairwise), default=\(centerDefault), linear=\(centerLinear))")
    }

    // MARK: - Fixtures

    private static let gray50Cell = ASCIICell(
        character: "█",
        displayColor: SIMD3<Float>(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0),
        alpha: 128.0 / 255.0,
        brightness: 0.5,
        coverage: 1.0
    )
}

/// Render `image` into a fresh sRGB 8-bit context to canonicalize its color
/// space, then sample the center pixel's RGB bytes. Canonicalization is
/// essential because the opt-in policy emits a `linearSRGB`-tagged CGImage,
/// whose stored bytes are linear; comparing them directly to encoded ground
/// truth would be invalid.
private func sampleCenterPixelCanonicalizedToSRGB(_ image: CGImage) -> SIMD3<UInt8> {
    let w = image.width, h = image.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    let didDraw = pixels.withUnsafeMutableBytes { raw -> Bool in
        guard
            let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: space, bitmapInfo: bitmapInfo
            )
        else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    precondition(didDraw, "sampleCenterPixelCanonicalizedToSRGB: CGContext setup failed")
    let offset = (h / 2 * w + w / 2) * 4
    return SIMD3<UInt8>(pixels[offset], pixels[offset + 1], pixels[offset + 2])
}

private func encodedDistance(_ pixel: SIMD3<UInt8>, groundTruthByte: Float) -> Float {
    let pixelUnit = SIMD3<Float>(Float(pixel.x), Float(pixel.y), Float(pixel.z)) / 255
    let groundTruthUnit = SIMD3<Float>(repeating: groundTruthByte / 255)
    return simd_distance(pixelUnit, groundTruthUnit)
}
