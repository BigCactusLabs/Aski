import CoreGraphics

/// Versioned record emitted by `aski render --write-manifest`.
///
/// Version 1 is additive: readers must ignore fields they do not understand.
/// Removing, renaming, or changing the meaning of a field requires a new schema
/// version.
public struct AskiRenderManifest: Codable, Equatable, Sendable {
    public struct Source: Codable, Equatable, Sendable {
        public let path: String
        public let normalizedPixelWidth: Int
        public let normalizedPixelHeight: Int

        public init(path: String, normalizedPixelWidth: Int, normalizedPixelHeight: Int) {
            self.path = path
            self.normalizedPixelWidth = normalizedPixelWidth
            self.normalizedPixelHeight = normalizedPixelHeight
        }
    }

    public struct Conversion: Codable, Equatable, Sendable {
        public let columns: Int
        public let rows: Int
        public let charset: String

        public init(columns: Int, rows: Int, charset: String) {
            self.columns = columns
            self.rows = rows
            self.charset = charset
        }
    }

    public struct RenderSettings: Codable, Equatable, Sendable {
        public let backgroundColor: String
        public let fontSize: Double
        public let preserveSourceAspect: Bool
        public let targetPixelWidth: Int?
        public let derivedScale: Double?
        public let cellAdvancePixels: Double?
        public let resampleSpace: String?

        public init(
            backgroundColor: String,
            fontSize: Double,
            preserveSourceAspect: Bool,
            targetPixelWidth: Int? = nil,
            derivedScale: Double? = nil,
            cellAdvancePixels: Double? = nil,
            resampleSpace: String? = nil
        ) {
            self.backgroundColor = backgroundColor
            self.fontSize = fontSize
            self.preserveSourceAspect = preserveSourceAspect
            self.targetPixelWidth = targetPixelWidth
            self.derivedScale = derivedScale
            self.cellAdvancePixels = cellAdvancePixels
            self.resampleSpace = resampleSpace
        }
    }

    /// Resolved mask choices. This additive v1 block is absent when no mask was
    /// supplied, so existing manifest readers retain their current behavior.
    public struct MaskSettings: Codable, Equatable, Sendable {
        public let path: String
        public let fallback: String
        public let fallbackColor: String?
        public let fallbackSizing: String?
        public let groundColor: String?
        public let hardEdges: Bool
        public let invert: Bool

        public init(
            path: String,
            fallback: String,
            fallbackColor: String?,
            fallbackSizing: String?,
            groundColor: String?,
            hardEdges: Bool,
            invert: Bool
        ) {
            self.path = path
            self.fallback = fallback
            self.fallbackColor = fallbackColor
            self.fallbackSizing = fallbackSizing
            self.groundColor = groundColor
            self.hardEdges = hardEdges
            self.invert = invert
        }
    }

    public struct TextArtifact: Codable, Equatable, Sendable {
        public let destination: String
        public let utf8Bytes: Int

        public init(destination: String, utf8Bytes: Int) {
            self.destination = destination
            self.utf8Bytes = utf8Bytes
        }
    }

    public struct PNGArtifact: Codable, Equatable, Sendable {
        public let path: String
        public let pixelWidth: Int
        public let pixelHeight: Int

        public init(path: String, pixelWidth: Int, pixelHeight: Int) {
            self.path = path
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
        }
    }

    public struct Artifacts: Codable, Equatable, Sendable {
        public let text: TextArtifact
        public let png: PNGArtifact?

        public init(text: TextArtifact, png: PNGArtifact?) {
            self.text = text
            self.png = png
        }
    }

    public let schemaVersion: Int
    public let toolVersion: String
    public let command: String
    public let source: Source
    public let conversion: Conversion
    public let render: RenderSettings
    public let artifacts: Artifacts
    public let mask: MaskSettings?

    public init(
        schemaVersion: Int = 1,
        toolVersion: String,
        command: String,
        source: Source,
        conversion: Conversion,
        render: RenderSettings,
        artifacts: Artifacts,
        mask: MaskSettings? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.toolVersion = toolVersion
        self.command = command
        self.source = source
        self.conversion = conversion
        self.render = render
        self.artifacts = artifacts
        self.mask = mask
    }

    init(
        inputPath: String,
        arguments: RenderArguments,
        result: ToolImageConversion,
        textDestination: String,
        textUTF8Bytes: Int,
        renderedImage: CGImage?
    ) {
        let png: PNGArtifact?
        if let path = arguments.renderPng, let renderedImage {
            png = PNGArtifact(
                path: path,
                pixelWidth: renderedImage.width,
                pixelHeight: renderedImage.height
            )
        } else {
            png = nil
        }

        let mask: MaskSettings?
        if let resolved = arguments.mask.resolvedMask {
            mask = MaskSettings(
                path: resolved.path,
                fallback: resolved.fallback.rawValue,
                fallbackColor: resolved.fallbackColor?.canonicalRGBAHex,
                fallbackSizing: resolved.fallbackSizing?.rawValue,
                groundColor: resolved.ground?.canonicalRGBAHex,
                hardEdges: resolved.hardEdges,
                invert: resolved.invert
            )
        } else {
            mask = nil
        }

        self.init(
            toolVersion: ToolVersion.current,
            command: "render",
            source: Source(
                path: inputPath,
                normalizedPixelWidth: result.normalizedImage.width,
                normalizedPixelHeight: result.normalizedImage.height
            ),
            conversion: Conversion(
                columns: result.grid.columns,
                rows: result.grid.rows,
                charset: arguments.charset.rawValue
            ),
            render: RenderSettings(
                backgroundColor: arguments.background.canonicalRGBAHex,
                fontSize: arguments.fontSize,
                preserveSourceAspect: arguments.preserveAspect,
                targetPixelWidth: arguments.width,
                derivedScale: arguments.width.map {
                    Double($0) / (Double(arguments.columns) * arguments.fontSize * 0.6)
                },
                cellAdvancePixels: arguments.width.map {
                    Double($0) / Double(arguments.columns)
                },
                resampleSpace: arguments.width.map { _ in TargetWidthRenderRecord.resampleSpace }
            ),
            artifacts: Artifacts(
                text: TextArtifact(destination: textDestination, utf8Bytes: textUTF8Bytes),
                png: png
            ),
            mask: mask
        )
    }
}
