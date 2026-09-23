import AskiToolSupport
import CoreGraphics
import Foundation

// MARK: - Natural-content fixture loader (ASTSK-31 Phase 5)

/// Loads the committed NASA photo corpus into the shared `ResidualFixture` shape:
/// each asset decoded at NATIVE size (no resampling — the no-downscale invariant
/// applies unchanged; the 2048px corpus supports the full column sweep at ≥24px
/// native blocks), id = file stem, tagged the `.natural` pool. Deterministic:
/// the same committed bytes decode to the same luma every run.
enum RealFixture {
    /// Default corpus location, resolved by walking up to the package root.
    static let defaultCorpusRelativePath = "docs/Research/Corpus/nasa-structure-v1/assets"

    /// Asset extensions this loader accepts.
    ///
    /// PNG alone was the original rule, and it made the JPEG-only
    /// `nasa-occupancy-v1` and `nasa-isoluminant-v1` corpora unreachable from
    /// every Tools-side battery that routes through here — a gap that already
    /// forced a published correction (`2026-08-19-sampling-lattice-support-
    /// collapse.md` §3/§5, which had to retract two fixtures a reader could not
    /// load). JPEG is accepted so those corpora can be measured; the compression
    /// artifacts in them are then part of the measurement, and any result quoted
    /// from a lossy corpus has to say so.
    static let assetExtensions: Set<String> = ["png", "jpg", "jpeg"]

    /// Loads every asset in `corpusDirectory` (or the default corpus when nil)
    /// whose extension is in ``assetExtensions``, sorted by filename for a
    /// deterministic battery order.
    ///
    /// - Throws: `ShapeResidualError.corpusAssetUnreadable` if the directory is
    ///   missing/unlistable, contains no loadable assets, or any asset fails to
    ///   decode — so a `--battery real|all` run fails loudly rather than
    ///   silently dropping the natural pool.
    static func load(corpusDirectory: String?) throws -> [ResidualFixture] {
        let dir = try corpusDirectory.map { URL(fileURLWithPath: $0) } ?? defaultCorpusURL()

        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)
        } catch {
            throw ShapeResidualError.corpusAssetUnreadable(path: dir.path)
        }
        let assets =
            entries
            .filter { assetExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !assets.isEmpty else {
            throw ShapeResidualError.corpusAssetUnreadable(path: dir.path)
        }

        return try assets.map { url in
            guard let image = try? DemoImageIO.loadImage(at: url.path) else {
                throw ShapeResidualError.corpusAssetUnreadable(path: url.path)
            }
            return try fixture(from: image, id: url.deletingPathExtension().lastPathComponent)
        }
    }

    /// Renders a decoded image into a native-size DeviceGray context (no
    /// interpolation, no resampling) and reads the gray bytes, so `image`↔`luma`
    /// match through the shared `fromGrayBytes` constructor.
    private static func fixture(from image: CGImage, id: String) throws -> ResidualFixture {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { throw ShapeResidualError.corpusAssetUnreadable(path: id) }
        guard let ctx = ResidualFixture.makeGrayContext(width: w, height: h) else {
            throw ShapeResidualError.corpusAssetUnreadable(path: id)
        }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let gray = ResidualFixture.grayBytes(from: ctx, width: w, height: h) else {
            throw ShapeResidualError.corpusAssetUnreadable(path: id)
        }
        return ResidualFixture.fromGrayBytes(id: id, width: w, height: h, pool: .natural, gray: gray)
    }

    /// Walks up from the current working directory to the package root (the dir
    /// holding `Package.swift`) and appends the default corpus path. Mirrors the
    /// research-registry walk-up used by the tests.
    private static func defaultCorpusURL() throws -> URL {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appending(path: "Package.swift").path) {
                return url.appending(path: defaultCorpusRelativePath)
            }
            url.deleteLastPathComponent()
        }
        throw ShapeResidualError.corpusAssetUnreadable(path: defaultCorpusRelativePath)
    }
}
