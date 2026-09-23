import CoreGraphics
import Foundation
import Testing
import simd
@testable import Aski

// ASKI-24. `cgColorToOKLAB`'s fallback path guards `components.count >= 3`
// before subscripting; the sRGB/linearSRGB and displayP3 fast paths did not, so
// a colour tagged with an RGB-named space but carrying fewer than three
// components trapped instead of returning the documented OKLAB black.
//
// CoreGraphics will not hand out an RGB-tagged colour with a short component
// list — `CGColor(colorSpace:components:)` always normalizes to the space's
// component count. The fast-path component read is therefore exercised through
// the `ColorConversion.rgbTriple(from:)` seam all three paths now share; a
// pattern colour (one component, conversion to sRGB fails) covers the same
// degeneracy end to end on the fallback path.

private func srgbColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, 1])!
}

private func linearSRGBColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!, components: [r, g, b, 1])!
}

private func displayP3Color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!, components: [r, g, b, 1])!
}

/// A colour that misses both fast paths and takes the `converted(to:)` fallback.
private func cmykColor(_ c: CGFloat, _ m: CGFloat, _ y: CGFloat, _ k: CGFloat) -> CGColor {
    CGColor(
        colorSpace: CGColorSpace(name: CGColorSpace.genericCMYK)!, components: [c, m, y, k, 1])!
}

/// A real CGColor carrying a single component: a coloured pattern. It reports
/// `components == [1.0]` and cannot be converted to sRGB, so it is the
/// constructible stand-in for the malformed input the guard exists for.
private func shortComponentColor() -> CGColor {
    var callbacks = CGPatternCallbacks(version: 0, drawPattern: { _, _ in }, releaseInfo: nil)
    let space = CGColorSpace(patternBaseSpace: nil)!
    let pattern = CGPattern(
        info: nil, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), matrix: .identity,
        xStep: 1, yStep: 1, tiling: .constantSpacing, isColored: true, callbacks: &callbacks)!
    var alpha: CGFloat = 1
    return CGColor(patternSpace: space, pattern: pattern, components: &alpha)!
}

@Suite struct ColorConversionShortComponentTests {

    // MARK: - AC#1 / AC#2: the guard the fast paths were missing

    @Test func shortComponentListYieldsNoTriple() {
        #expect(ColorConversion.rgbTriple(from: [0.5, 1.0]) == nil)
        #expect(ColorConversion.rgbTriple(from: [0.5]) == nil)
        #expect(ColorConversion.rgbTriple(from: []) == nil)
        #expect(ColorConversion.rgbTriple(from: nil) == nil)
    }

    @Test func threeOrMoreComponentsYieldTheLeadingTriple() {
        #expect(ColorConversion.rgbTriple(from: [0.25, 0.5, 0.75]) == SIMD3<Float>(0.25, 0.5, 0.75))
        #expect(
            ColorConversion.rgbTriple(from: [0.25, 0.5, 0.75, 0.5])
                == SIMD3<Float>(0.25, 0.5, 0.75))
    }

    /// The degenerate result is OKLAB black on every path — the fallback branch
    /// already returned it, and a missing triple must not diverge from that.
    @Test func aShortComponentColourReturnsOKLABBlack() {
        #expect(ColorConversion.cgColorToOKLAB(shortComponentColor()) == SIMD3<Float>(0, 0, 0))
    }

    // MARK: - AC#3: well-formed colours are byte-identical

    @Test func wellFormedColoursConvertToTheRecordedValues() {
        for (label, color, expected) in wellFormedAnchors {
            let actual = ColorConversion.cgColorToOKLAB(color)
            #expect(actual.x.bitPattern == expected.x.bitPattern, "\(label) L")
            #expect(actual.y.bitPattern == expected.y.bitPattern, "\(label) a")
            #expect(actual.z.bitPattern == expected.z.bitPattern, "\(label) b")
        }
    }

    /// The linearSRGB branch must stay the no-decode branch: the linear value
    /// fed to the linear-tagged colour and the encoded value fed to the
    /// sRGB-tagged colour have to land on the same OKLAB.
    @Test func linearSRGBBranchSkipsTheDecode() {
        let encoded: CGFloat = 0.5
        let linear = CGFloat(ColorConversion.sRGBDecode(Float(encoded)))
        let viaEncoded = ColorConversion.cgColorToOKLAB(srgbColor(encoded, encoded, encoded))
        let viaLinear = ColorConversion.cgColorToOKLAB(linearSRGBColor(linear, linear, linear))
        #expect(abs(viaEncoded.x - viaLinear.x) < 1e-5)
        #expect(abs(viaEncoded.y - viaLinear.y) < 1e-5)
        #expect(abs(viaEncoded.z - viaLinear.z) < 1e-5)
    }

    /// The P3 branch must keep using the P3 matrix: a saturated P3 green is
    /// outside sRGB, so it may not agree with the same components read as sRGB.
    @Test func displayP3BranchUsesTheP3Matrix() {
        let asP3 = ColorConversion.cgColorToOKLAB(displayP3Color(0, 1, 0))
        let asSRGB = ColorConversion.cgColorToOKLAB(srgbColor(0, 1, 0))
        #expect(asP3 != asSRGB)
    }

    // MARK: - AC#4: driven through the public entry point

    @Test func tilePaletteFixedConvertsEachPathToTheRecordedValues() {
        let colors = wellFormedAnchors.map(\.1)
        let palette = TilePalette.fixed(colors)
        guard case .fixedOKLAB(let oklab) = palette.strategy else {
            Issue.record("TilePalette.fixed did not produce a fixed OKLAB palette")
            return
        }
        #expect(oklab.count == colors.count)
        for (index, anchor) in wellFormedAnchors.enumerated() where index < oklab.count {
            #expect(oklab[index].x.bitPattern == anchor.2.x.bitPattern, "\(anchor.0) via palette L")
            #expect(oklab[index].y.bitPattern == anchor.2.y.bitPattern, "\(anchor.0) via palette a")
            #expect(oklab[index].z.bitPattern == anchor.2.z.bitPattern, "\(anchor.0) via palette b")
        }
    }

    /// A colour that cannot supply a triple must not take the whole palette
    /// down; it degenerates to OKLAB black and its neighbours are unaffected.
    @Test func tilePaletteFixedSurvivesAShortComponentColour() {
        let palette = TilePalette.fixed([srgbColor(1, 0, 0), shortComponentColor()])
        guard case .fixedOKLAB(let oklab) = palette.strategy else {
            Issue.record("TilePalette.fixed did not produce a fixed OKLAB palette")
            return
        }
        #expect(oklab.count == 2)
        #expect(oklab[0] == ColorConversion.cgColorToOKLAB(srgbColor(1, 0, 0)))
        #expect(oklab[1] == SIMD3<Float>(0, 0, 0))
    }
}

/// `(label, colour, recorded OKLAB)`. Recorded from the pre-ASKI-24
/// implementation: byte-identity anchors for AC#3, not to be re-recorded.
/// The list covers the sRGB fast path, the linearSRGB no-decode branch, the
/// displayP3 branch and the `converted(to:)` fallback.
private let wellFormedAnchors: [(String, CGColor, SIMD3<Float>)] = [
    ("sRGB mid gray", srgbColor(0.5, 0.5, 0.5), oklab(1_058_611_807, 864_097_330, 857_096_544)),
    ("sRGB red", srgbColor(1, 0, 0), oklab(1_059_111_343, 1_046_889_081, 1_040_244_185)),
    (
        "linearSRGB mid", linearSRGBColor(0.5, 0.25, 0.75),
        oklab(1_060_516_027, 1_034_971_777, 3_184_752_721)
    ),
    (
        "displayP3 green", displayP3Color(0, 1, 0),
        oklab(1_062_816_992, 3_197_879_660, 1_045_755_242)
    ),
    (
        "CMYK fallback", cmykColor(0.2, 0.4, 0.6, 0.1),
        oklab(1_059_631_060, 1_022_924_865, 1_032_004_834)
    ),
]

private func oklab(_ l: UInt32, _ a: UInt32, _ b: UInt32) -> SIMD3<Float> {
    SIMD3<Float>(Float(bitPattern: l), Float(bitPattern: a), Float(bitPattern: b))
}
