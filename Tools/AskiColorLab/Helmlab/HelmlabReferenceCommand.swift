@_spi(AskiResearch) import Aski
import AskiToolSupport
import CoreGraphics
import Foundation
import simd

/// `helmlab-reference` — writes a pinned Helmlab MetricSpace reference CSV
/// (material primaries + strided gamut grid, MetricSpace-Lab coords, per-row
/// round-trip error) and the perturbation-recovery oracle CSV (small-ΔE
/// ground truth: each source is a known small perturbation of a palette entry;
/// recovery = nearest match returns the un-perturbed entry). Mirrors
/// `CAM16HCTReferenceCommand`.
///
/// It also emits the large-ΔE *visual-review* HTML artifacts — a synthetic
/// saturation-stress set (always) and, with `--review-corpus <dir>`, a
/// real-image corpus — rendering actual converter output under the
/// `.helmlabEuclidean` / `.helmlabCompressed` policies (the large-ΔE regime has
/// no objective oracle, so the spec requires a visual record). These render to
/// self-contained colored-HTML grids, keeping the command synchronous and
/// Metal-free.
public enum HelmlabReferenceCommand {
    public static let commandName = "helmlab-reference"
    public static let referenceOutputFileName = "helmlab-metricspace-reference.csv"

    public static let referenceMetricColumns: [String] = [
        "reference_kind",
        "metric_l", "metric_a", "metric_b",
        "roundtrip_max_abs_error",
        "helmlab_param_version", "helmlab_source_sha",
    ]

    public static let recoveryOutputFileName = "helmlab-recovery-oracle.csv"
    public static let recoveryColumns: [String] = [
        "palette_id", "expected_index", "selected_index", "recovered",
    ]

    public static func run(
        arguments: LabArguments,
        standardError: (String) -> Void
    ) -> LabExitCode {
        let directory = URL(fileURLWithPath: arguments.outputDirectory)
        let gitSHA = GitSHA.resolve(override: arguments.gitShaOverride)

        switch writeReferenceCSV(directory: directory, gitSHA: gitSHA, seed: arguments.seed) {
        case .success:
            break
        case .failure(let error):
            standardError("error: \(error)\n")
            return .ioError
        }

        switch writeRecoveryCSV(directory: directory, gitSHA: gitSHA, seed: arguments.seed) {
        case .success:
            break
        case .failure(let error):
            standardError("error: \(error)\n")
            return .ioError
        }

        switch writeVisualReview(directory: directory) {
        case .success:
            break
        case .failure(let error):
            standardError("error: \(error)\n")
            return .ioError
        }

        let corpusDir = arguments.reviewCorpusDirectory.map { URL(fileURLWithPath: $0) }
        switch writeCorpusReview(directory: directory, corpusDir: corpusDir) {
        case .success:
            return .success
        case .failure(let error):
            standardError("error: \(error)\n")
            return .ioError
        }
    }

    private static func writeReferenceCSV(
        directory: URL,
        gitSHA: String,
        seed: UInt64
    ) -> Result<Void, Error> {
        Result {
            let writer = try CSVWriter(
                url: directory.appendingPathComponent(referenceOutputFileName),
                columns: CSVSchema.sharedPrefixColumns + referenceMetricColumns
            )
            defer { try? writer.close() }

            var sampleID = 0
            for primary in HelmlabReferenceFixtures.materialPrimaries {
                try writer.writeRow(
                    referenceRow(
                        referenceKind: "material_primary",
                        fixtureID: primary.id,
                        rgb: primary.rgb,
                        sampleID: sampleID,
                        gitSHA: gitSHA,
                        seed: seed
                    ))
                sampleID += 1
            }
            for (i, rgb) in HelmlabReferenceFixtures.grid().enumerated() {
                try writer.writeRow(
                    referenceRow(
                        referenceKind: "gamut_grid",
                        fixtureID: "grid_\(String(format: "%04d", i))",
                        rgb: rgb,
                        sampleID: sampleID,
                        gitSHA: gitSHA,
                        seed: seed
                    ))
                sampleID += 1
            }
        }
    }

    private static func referenceRow(
        referenceKind: String,
        fixtureID: String,
        rgb: SIMD3<Double>,
        sampleID: Int,
        gitSHA: String,
        seed: UInt64
    ) -> [String] {
        let xyz = ColorConversion.linearSRGBToXYZ(rgb)
        let lab = HelmlabMetric.xyzToHelmlabMetric(xyz)
        let back = HelmlabMetric.helmlabMetricToXYZ(lab)
        let rtError = simd_reduce_max(abs(back - xyz))
        return [
            CSVSchema.schemaVersion,
            commandName,
            gitSHA,
            String(seed),
            String(sampleID),
            fixtureID,
            "helmlab-metric",
            "sRGB",
            CSVSchema.formatComponents([Float(rgb.x), Float(rgb.y), Float(rgb.z)]),
            "helmlab-metric",
            formatDoubleTriplet(lab),
            referenceKind,
            String(format: "%.6f", lab.x),
            String(format: "%.6f", lab.y),
            String(format: "%.6f", lab.z),
            String(format: "%.2e", rtError),
            HelmlabMetric.Provenance.declaredParamVersion,
            HelmlabMetric.Provenance.sourceSHA,
        ]
    }

    private static func formatDoubleTriplet(_ v: SIMD3<Double>) -> String {
        [v.x, v.y, v.z].map { String(format: "%.6f", $0) }.joined(separator: ";")
    }

    // MARK: - Recovery oracle (small-ΔE ground truth)

    /// Policies scored by the recovery oracle. A `func` (not a `static let`) so
    /// the non-`Sendable` closure tuple isn't held as global state under Swift 6
    /// strict concurrency.
    private static func recoveryPolicies() -> [(
        name: String,
        resolve: (PaletteColor) -> SIMD3<Double>,
        distance: (SIMD3<Double>, SIMD3<Double>) -> Double
    )] {
        [
            ("oklabEuclidean", { SIMD3<Double>(PaletteMatchPolicies.resolveToOKLab($0)) }, { simd_length($0 - $1) }),
            ("helmlabEuclidean", PaletteMatchPolicies.resolveToHelmlab, HelmlabMetric.euclideanDistance),
            ("helmlabCompressed", PaletteMatchPolicies.resolveToHelmlab, HelmlabMetric.compressedDeltaE),
        ]
    }

    /// One row per recovery case × policy: the prefix `input_*`/`output_*`
    /// columns carry the perturbed source and the matched palette entry, and
    /// `recovered` is the objective small-ΔE ground truth (selected == expected).
    private static func writeRecoveryCSV(
        directory: URL, gitSHA: String, seed: UInt64
    ) -> Result<Void, Error> {
        Result {
            let writer = try CSVWriter(
                url: directory.appendingPathComponent(recoveryOutputFileName),
                columns: CSVSchema.sharedPrefixColumns + recoveryColumns
            )
            defer { try? writer.close() }

            let policies = recoveryPolicies()
            var sampleID = 0
            for c in HelmlabRecoveryFixtures.all {
                for policy in policies {
                    let selected = selectedIndex(
                        palette: c.palette, source: c.source,
                        resolve: policy.resolve, distance: policy.distance
                    )
                    let chosen = c.palette[selected]
                    try writer.writeRow([
                        CSVSchema.schemaVersion, commandName, gitSHA, String(seed), String(sampleID),
                        c.id,  // fixture_id
                        policy.name,  // policy
                        spaceName(c.source.colorSpace),  // input_space
                        CSVSchema.formatSIMD3(c.source.components),  // input_components
                        spaceName(chosen.colorSpace),  // output_space
                        CSVSchema.formatSIMD3(chosen.components),  // output_components
                        c.paletteID,
                        String(c.expectedIndex),
                        String(selected),
                        selected == c.expectedIndex ? "true" : "false",
                    ])
                    sampleID += 1
                }
            }
        }
    }

    private static func selectedIndex(
        palette: [PaletteColor],
        source: PaletteColor,
        resolve: (PaletteColor) -> SIMD3<Double>,
        distance: (SIMD3<Double>, SIMD3<Double>) -> Double
    ) -> Int {
        let resolved = palette.map(resolve)
        let src = resolve(source)
        var best = 0
        var bestD = distance(src, resolved[0])
        for i in 1..<resolved.count {
            let d = distance(src, resolved[i])
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    private static func spaceName(_ space: PaletteColorSpace) -> String {
        if space == .sRGB { return "sRGB" }
        if space == .displayP3 { return "displayP3" }
        preconditionFailure("Unsupported PaletteColorSpace: update HelmlabReferenceCommand.spaceName")
    }

    // MARK: - Large-ΔE visual review (no objective oracle → durable HTML record)

    /// The six synthetic saturation-stress HTML artifacts, always emitted (no
    /// inputs). Used by tests for an existence check.
    public static let reviewFileNames: [String] = [
        "helmlab-review-primaries-oklabEuclidean.html",
        "helmlab-review-primaries-helmlabEuclidean.html",
        "helmlab-review-primaries-helmlabCompressed.html",
        "helmlab-review-ramp-oklabEuclidean.html",
        "helmlab-review-ramp-helmlabEuclidean.html",
        "helmlab-review-ramp-helmlabCompressed.html",
    ]

    private static let reviewPolicies: [(name: String, policy: PaletteMatchingPolicy)] = [
        ("oklabEuclidean", .oklabEuclidean),
        ("helmlabEuclidean", .helmlabEuclidean),
        ("helmlabCompressed", .helmlabCompressed),
    ]

    /// Deterministic large-ΔE fixtures: saturated primaries (where
    /// `helmlabCompressed`'s ~0.15 saturation can collapse selections vs
    /// ANSI16) and a black→white lightness ramp.
    private static func reviewFixtures() -> [(name: String, image: CGImage)] {
        [
            (
                "primaries",
                makeBandsImage(
                    [(1, 0, 0), (1, 1, 0), (0, 1, 0), (0, 1, 1), (0, 0, 1), (1, 0, 1)],
                    width: 240, height: 60)
            ),
            ("ramp", makeRampImage(width: 240, height: 60)),
        ]
    }

    /// Synthetic saturation-stress HTML (always run). Each (fixture × policy)
    /// renders ANSI16-matched converter output to a self-contained colored grid.
    private static func writeVisualReview(directory: URL) -> Result<Void, Error> {
        Result {
            for fixture in reviewFixtures() {
                for entry in reviewPolicies {
                    let converter = ASCIIConverter(
                        characterSet: StandardCharacterSet.standard,
                        palette: BuiltInPalette.ansi16,
                        paletteMatching: entry.policy
                    )
                    let grid = converter.convert(fixture.image, columns: 60)
                    let html = renderGridHTML(grid, title: "\(fixture.name) — \(entry.name)")
                    let url = directory.appendingPathComponent(
                        "helmlab-review-\(fixture.name)-\(entry.name).html")
                    try Data(html.utf8).write(to: url)
                }
            }
        }
    }

    /// Real-image visual corpus review (spec § ColorLab harness). Loads every
    /// image in `corpusDir` (sorted by filename for determinism), converts each
    /// under the three policies against ANSI16, and writes
    /// `helmlab-corpus-<stem>-<policy>.html`. No-op if `corpusDir` is nil.
    private static func writeCorpusReview(directory: URL, corpusDir: URL?) -> Result<Void, Error> {
        Result {
            guard let corpusDir else { return }
            let files = try FileManager.default
                .contentsOfDirectory(at: corpusDir, includingPropertiesForKeys: nil)
                .filter { ["png", "jpg", "jpeg", "heic"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for file in files {
                guard let image = try? DemoImageIO.loadImage(at: file.path) else { continue }
                let stem = file.deletingPathExtension().lastPathComponent
                for entry in reviewPolicies {
                    let converter = ASCIIConverter(
                        characterSet: StandardCharacterSet.standard,
                        palette: BuiltInPalette.ansi16,
                        paletteMatching: entry.policy
                    )
                    let grid = converter.convert(image, columns: 80)
                    let html = renderGridHTML(grid, title: "\(stem) — \(entry.name)")
                    let url = directory.appendingPathComponent("helmlab-corpus-\(stem)-\(entry.name).html")
                    try Data(html.utf8).write(to: url)
                }
            }
        }
    }

    private static func renderGridHTML(_ grid: ASCIIGrid, title: String) -> String {
        var body = "<!doctype html><meta charset=utf-8><title>\(title)</title>"
        body += "<pre style='font:14px/1.0 monospace;background:#000;padding:8px'>"
        for row in grid.cells {
            for cell in row {
                let c = cell.displayColor
                let r = Int((c.x * 255).rounded())
                let g = Int((c.y * 255).rounded())
                let b = Int((c.z * 255).rounded())
                body += "<span style='color:rgb(\(r),\(g),\(b))'>\(htmlEscape(cell.character))</span>"
            }
            body += "\n"
        }
        body += "</pre>"
        return body
    }

    private static func htmlEscape(_ ch: Character) -> String {
        switch ch {
        case "<": return "&lt;"
        case ">": return "&gt;"
        case "&": return "&amp;"
        case " ": return "&nbsp;"
        default: return String(ch)
        }
    }

    private static func makeBandsImage(_ colors: [(CGFloat, CGFloat, CGFloat)], width: Int, height: Int) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bandW = max(1, width / colors.count)
        for (i, c) in colors.enumerated() {
            ctx.setFillColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
            ctx.fill(CGRect(x: i * bandW, y: 0, width: bandW, height: height))
        }
        return ctx.makeImage()!
    }

    private static func makeRampImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<width {
            let t = CGFloat(x) / CGFloat(width - 1)
            ctx.setFillColor(red: t, green: t, blue: t, alpha: 1)
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return ctx.makeImage()!
    }
}
