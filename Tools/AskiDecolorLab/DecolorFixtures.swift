import Aski
import CoreGraphics
import Foundation
import simd

public enum DecolorFixtureError: Error, CustomStringConvertible {
    case nonSRGBGrid(RenderColorSpace)
    case emptyGrid(String)
    case unknownCharacter(Character)
    case converterWouldDownscale(fixtureID: String, maxPixelSize: Int, fixtureLongestSide: Int)

    public var description: String {
        switch self {
        case .nonSRGBGrid(let colorSpace):
            "DecolorLab rendered-grid scoring requires .sRGB, got \(colorSpace)"
        case .emptyGrid(let fixtureID):
            "fixture \(fixtureID) produced an empty ASCII grid"
        case .unknownCharacter(let character):
            "character \(character) is not in StandardCharacterSet.standard"
        case .converterWouldDownscale(let fixtureID, let maxPixelSize, let fixtureLongestSide):
            """
            fixture \(fixtureID): converter would downscale \
            (maxPixelSize \(maxPixelSize) < longest side \(fixtureLongestSide)). \
            The oracle measures recompositing fidelity, not ImageIO downscale loss, \
            so the lab's source-cell ground truth must be sampled at the same \
            resolution the converter sampled. Raise columns or oversample (or \
            shrink the fixture) so max(cols, rows) * oversample >= the fixture's \
            longest side and no downscale occurs.
            """
        }
    }
}

/// Which per-glyph ink fraction the oracle composites with.
///
/// `relativeRamp` is the Phase 0 first-cut (`brightnessValues`, normalized to
/// the densest glyph): monotonic with true coverage — valid for the
/// discrimination gate, biased for absolute fidelity. `absoluteDensity` is the
/// physical coverage from `.bin` v2 `rawDensityValues` (Thread C). The Phase 0
/// `evaluate`/`check` gate stays on `relativeRamp` so its calibration holds.
public enum DecolorInkModel: String, Sendable {
    case relativeRamp = "relative_ramp"
    case absoluteDensity = "absolute_density"
}

/// Deterministic source CGImages plus per-cell oracle sample assembly.
///
/// Each fixture carries its own pixel generator (`colorAt`) so the lab can
/// recompute the **source-cell aggregate** by averaging its own pixels over each
/// cell block, then decoding to linear and matrixing to OKLab — without relying
/// on the converter's private sampling path.
public enum DecolorFixtures {
    /// A fixture: a stable id, dimensions, and the deterministic pixel generator.
    public struct Fixture: Sendable {
        public let id: String
        public let width: Int
        public let height: Int
        public let colorAt: @Sendable (Int, Int) -> SIMD3<UInt8>
    }

    /// All Phase 0 fixtures. Sizes divide evenly by typical col/row counts.
    public static let all: [Fixture] = [
        hueStripes(),
        neutralRamp(),
        edgeContrast(),
        isoluminantSwatch(),
        lowInkSparse(),
    ]

    // MARK: - Per-cell sample assembly

    /// Run the real converter over every fixture and build one `OracleRow` per
    /// grid cell: resolve ink fraction `k` from the relative brightness ramp,
    /// FG = `cell.displayColor`, BG = `backgroundEncoded`, source aggregate =
    /// local linear-light block average → OKLab, then the three fidelity metrics.
    ///
    /// ## Recompositing-fidelity rationale
    ///
    /// The oracle scores **recompositing fidelity** — how close the area-toned
    /// composite `k·FG + (1−k)·BG` (in linear light) lands to the source cell's
    /// own appearance. It does *not* measure ImageIO downscale loss. For that
    /// comparison to be valid, the lab's source-cell aggregate must be sampled at
    /// the **same resolution the converter sampled**.
    ///
    /// ## No-downscale invariant (asserted)
    ///
    /// `ASCIIConverter` samples a thumbnail whose longest side is
    /// `max(cols, rows) * oversample`. When that budget is ≥ the fixture's longest
    /// side, ImageIO returns the original (thumbnail == fixture) and the
    /// converter's per-cell sampling reads the same pixels the lab averages below.
    /// If the budget is smaller, the converter silently downscales and the lab's
    /// full-resolution block average no longer aligns with the converter's
    /// per-cell sampling, so the fidelity numbers would conflate recompositing
    /// error with resampling error. We therefore **throw**
    /// `DecolorFixtureError.converterWouldDownscale` rather than emit invalid
    /// rows. Callers (the eval gate) run at columns where this always holds.
    public static func samples(
        palette: DecolorPalette,
        columns: Int,
        backgroundEncoded: SIMD3<Float>,
        gitSHA: String,
        command: String,
        options: RenderingOptions = .default,
        inkModel: DecolorInkModel = .relativeRamp
    ) throws -> [OracleRow] {
        let charSet = StandardCharacterSet.standard
        let converter = ASCIIConverter(
            characterSet: charSet,
            palette: palette,
            options: options,
            colorSpace: .sRGB
        )
        let bgHex = DecolorOracle.hex(encoded: backgroundEncoded)

        var rows: [OracleRow] = []
        for fixture in all {
            let image = makeImage(fixture)
            let grid = converter.convert(image, columns: columns)
            guard grid.colorSpace == .sRGB else {
                throw DecolorFixtureError.nonSRGBGrid(grid.colorSpace)
            }
            guard grid.rows > 0, grid.columns > 0 else {
                throw DecolorFixtureError.emptyGrid(fixture.id)
            }

            // No-downscale invariant: the converter samples a thumbnail whose
            // longest side is max(cols, rows) * oversample. If that is smaller
            // than the fixture's longest side ImageIO downscales, and the lab's
            // full-resolution block average below would no longer line up with
            // the converter's per-cell sampling. Throw instead of scoring loss
            // we don't intend to measure. (See the recompositing-fidelity doc.)
            let maxPixelSize = max(grid.columns, grid.rows) * converter.oversample
            let fixtureLongestSide = max(fixture.width, fixture.height)
            guard maxPixelSize >= fixtureLongestSide else {
                throw DecolorFixtureError.converterWouldDownscale(
                    fixtureID: fixture.id,
                    maxPixelSize: maxPixelSize,
                    fixtureLongestSide: fixtureLongestSide
                )
            }

            // Same truncating cell math the converter uses (thumbnail.width /
            // cols, integer-truncated). With no downscale thumbnail == fixture,
            // so any residual right/bottom edge pixels are dropped identically
            // by both the lab and the converter — alignment is intentional.
            let cellWidth = fixture.width / grid.columns
            let cellHeight = fixture.height / grid.rows

            for rowIndex in 0..<grid.rows {
                let gridRow = grid.cells[rowIndex]
                for columnIndex in 0..<gridRow.count {
                    let cell = gridRow[columnIndex]

                    // Resolve the ink fraction under the requested model.
                    // Assumes distinct graphemes in StandardCharacterSet.standard
                    // (true today), so firstIndex(of:) is unambiguous.
                    guard let idx = charSet.characters.firstIndex(of: cell.character) else {
                        throw DecolorFixtureError.unknownCharacter(cell.character)
                    }
                    let k =
                        inkModel == .relativeRamp
                        ? charSet.brightnessValues[idx]
                        : charSet.rawDensityValues[idx]

                    // Recomposite the cell: k·FG + (1−k)·BG in linear light.
                    let perceivedLinear = DecolorOracle.composite(
                        fgEncoded: cell.displayColor,
                        bgEncoded: backgroundEncoded,
                        inkFraction: k
                    )
                    let perceivedOKLab = DecolorOracle.oklab(linearRGB: perceivedLinear)

                    // Source-cell aggregate: average the fixture's own pixels over
                    // the cell block, decode to linear, matrix to OKLab.
                    let sourceLinear = sourceBlockLinearAverage(
                        fixture: fixture,
                        cellColumn: columnIndex,
                        cellRow: rowIndex,
                        cellWidth: cellWidth,
                        cellHeight: cellHeight
                    )
                    let sourceOKLab = DecolorOracle.oklab(linearRGB: sourceLinear)

                    let fidelity = DecolorOracle.fidelity(
                        perceivedOKLab: perceivedOKLab,
                        sourceOKLab: sourceOKLab
                    )

                    rows.append(
                        OracleRow(
                            schemaVersion: "1",
                            command: command,
                            askiGitSHA: gitSHA,
                            fixtureID: fixture.id,
                            paletteID: palette.id,
                            row: rowIndex,
                            col: columnIndex,
                            character: String(cell.character),
                            inkFraction: k,
                            inkModel: inkModel.rawValue,
                            fgHex: DecolorOracle.hex(encoded: cell.displayColor),
                            bgHex: bgHex,
                            perceivedHex: DecolorOracle.hex(linear: perceivedLinear),
                            sourceHex: DecolorOracle.hex(linear: sourceLinear),
                            deficiency: "none",
                            lFidelity: fidelity.l,
                            chromaFidelity: fidelity.chroma,
                            oklabDelta: fidelity.delta
                        ))
                }
            }
        }
        return rows
    }

    /// Average the fixture's own source pixels over one cell block (linear light).
    private static func sourceBlockLinearAverage(
        fixture: Fixture,
        cellColumn: Int,
        cellRow: Int,
        cellWidth: Int,
        cellHeight: Int
    ) -> SIMD3<Float> {
        let x0 = cellColumn * cellWidth
        let y0 = cellRow * cellHeight
        let x1 = min(fixture.width, x0 + max(1, cellWidth))
        let y1 = min(fixture.height, y0 + max(1, cellHeight))

        var sum = SIMD3<Float>(repeating: 0)
        var count = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let pixel = fixture.colorAt(x, y)
                let encoded = SIMD3<Float>(
                    Float(pixel.x) / 255,
                    Float(pixel.y) / 255,
                    Float(pixel.z) / 255
                )
                sum += SIMD3<Float>(
                    ColorConversion.sRGBDecode(encoded.x),
                    ColorConversion.sRGBDecode(encoded.y),
                    ColorConversion.sRGBDecode(encoded.z)
                )
                count += 1
            }
        }
        guard count > 0 else { return .zero }
        return sum / Float(count)
    }

    // MARK: - Fixtures

    static func hueStripes(width: Int = 96, height: Int = 48) -> Fixture {
        let stripes: [SIMD3<UInt8>] = [
            SIMD3<UInt8>(255, 0, 0),
            SIMD3<UInt8>(0, 255, 0),
            SIMD3<UInt8>(0, 0, 255),
            SIMD3<UInt8>(0, 255, 255),
            SIMD3<UInt8>(255, 0, 255),
            SIMD3<UInt8>(255, 255, 0),
        ]
        return Fixture(id: "hue-stripes", width: width, height: height) { x, _ in
            stripes[min(stripes.count - 1, x * stripes.count / width)]
        }
    }

    static func neutralRamp(width: Int = 96, height: Int = 48) -> Fixture {
        Fixture(id: "neutral-ramp", width: width, height: height) { x, _ in
            let value = UInt8((x * 255) / max(1, width - 1))
            return SIMD3<UInt8>(value, value, value)
        }
    }

    static func edgeContrast(width: Int = 96, height: Int = 48) -> Fixture {
        Fixture(id: "edge-contrast", width: width, height: height) { x, y in
            let checker = ((x / 12) + (y / 12)) % 2 == 0
            return checker ? SIMD3<UInt8>(245, 245, 245) : SIMD3<UInt8>(20, 20, 20)
        }
    }

    /// Two regions at roughly constant OKLab L but different hue (red / green),
    /// so luminance contrast is low and hue carries the signal.
    static func isoluminantSwatch(width: Int = 96, height: Int = 48) -> Fixture {
        // Tuned so both halves sit near L ≈ 0.63 in OKLab; hue differs sharply.
        let red = SIMD3<UInt8>(214, 92, 92)
        let green = SIMD3<UInt8>(86, 166, 86)
        return Fixture(id: "isoluminant-swatch", width: width, height: height) { x, _ in
            x < width / 2 ? red : green
        }
    }

    /// A mostly-dark field with sparse bright specks. The matcher picks sparse
    /// low-ink glyphs whose area-tone composite reads muddy — the fixture that
    /// most separates coverage-aware from coverage-blind scoring.
    static func lowInkSparse(width: Int = 96, height: Int = 48) -> Fixture {
        Fixture(id: "low-ink-sparse", width: width, height: height) { x, y in
            // ~1-in-64 pixels is a bright speck on a near-black field.
            let isSpeck = (x % 8 == 3) && (y % 8 == 5)
            return isSpeck ? SIMD3<UInt8>(245, 245, 245) : SIMD3<UInt8>(8, 8, 8)
        }
    }

    // MARK: - CGImage materialization

    private static func makeImage(_ fixture: Fixture) -> CGImage {
        image(width: fixture.width, height: fixture.height, colorAt: fixture.colorAt)
    }

    private static func image(
        width: Int,
        height: Int,
        colorAt: (Int, Int) -> SIMD3<UInt8>
    ) -> CGImage {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let color = colorAt(x, y)
                let offset = (y * width + x) * 4
                buffer[offset + 0] = color.x
                buffer[offset + 1] = color.y
                buffer[offset + 2] = color.z
                buffer[offset + 3] = 255
            }
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data(buffer) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}
