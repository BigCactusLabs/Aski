import Foundation
import CoreText
import CoreGraphics

/// CTFont is a reference-counted CoreFoundation type documented by Apple as
/// thread-safe for reads. All stored state of `ASCIIFont` is immutable `let`,
/// so the struct is safe to share across actors. `@unchecked Sendable` is the
/// correct escape hatch — if any property is ever made mutable, this
/// invariant breaks and the conformance must be revisited.
public struct ASCIIFont: @unchecked Sendable {
    public let pointSize: CGFloat
    public let postScriptName: String
    internal let ctFont: CTFont

    /// `size` is deliberately NOT validated (ASKI-35 classification:
    /// intentionally permissive, downstream bound named). ASKI-17 settled that
    /// the bound belongs on the DERIVED raster geometry, not on the point size:
    /// `RenderPixelBounds.pixelExtent` (Renderers/ImageRenderer.swift) rejects
    /// an out-of-range extent at all four raster sites, so a non-finite or
    /// enormous point size takes the renderers' documented empty-image
    /// fallback. Adding a precondition here would make the same input fail in
    /// two different ways; do not add one.
    public init(name: String, size: CGFloat) {
        self.pointSize = size
        self.ctFont = CTFontCreateWithName(name as CFString, size, nil)
        self.postScriptName = CTFontCopyPostScriptName(self.ctFont) as String
    }

    /// `size` is unvalidated for the same reason as `init(name:size:)` — the
    /// bound lives on the derived raster geometry (`RenderPixelBounds`,
    /// ASKI-17), not on the point size.
    public static func system(size: CGFloat, monospaced: Bool = true) -> ASCIIFont {
        let traits: CTFontSymbolicTraits = monospaced ? .traitMonoSpace : []
        let base =
            CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let descriptor = CTFontCopyFontDescriptor(base)
        if let withTraits = CTFontDescriptorCreateCopyWithSymbolicTraits(descriptor, traits, traits) {
            let ct = CTFontCreateWithFontDescriptor(withTraits, size, nil)
            return ASCIIFont(ctFont: ct)
        }
        // Trait descriptor creation can return nil when the current system
        // family doesn't support the requested trait. For monospaced, return
        // a named monospaced font rather than silently handing back the
        // proportional base — downstream cell calibration depends on it.
        // Menlo ships on macOS ≥ 10.6, iOS ≥ 7, visionOS ≥ 1.
        if monospaced {
            return ASCIIFont(ctFont: CTFontCreateWithName("Menlo" as CFString, size, nil))
        }
        return ASCIIFont(ctFont: base)
    }

    internal init(ctFont: CTFont) {
        self.ctFont = ctFont
        self.pointSize = CTFontGetSize(ctFont)
        self.postScriptName = CTFontCopyPostScriptName(ctFont) as String
    }
}

public extension ASCIIFont {
    /// Returns Courier Prime Regular at `size`, loaded from the bundled
    /// `Resources/Fonts/CourierPrime-Regular.ttf`. Falls back to the system
    /// monospaced font if the bundle resource is missing or unreadable.
    static func courierPrime(size: CGFloat) -> ASCIIFont {
        guard
            let url = Bundle.module.url(
                forResource: "CourierPrime-Regular",
                withExtension: "ttf",
                subdirectory: "Fonts"
            )
        else {
            return .system(size: size)
        }
        guard let data = try? Data(contentsOf: url),
            let provider = CGDataProvider(data: data as CFData),
            let cgFont = CGFont(provider)
        else {
            return .system(size: size)
        }
        let ctFont = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
        return ASCIIFont(ctFont: ctFont)
    }
}
