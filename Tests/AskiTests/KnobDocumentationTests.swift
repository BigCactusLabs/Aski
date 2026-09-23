import Foundation
import Testing

@testable import Aski

/// Guards the ASTSK-59 / PR #62 drift class D: a public `RenderingOptions` knob
/// added in code but never documented. This test reflects over the struct's
/// stored properties and asserts each public knob is named — as a `` `code span` ``
/// — in the DocC *Algorithms* article, where the product-knob table and the
/// research-only polarity prose both live. It is a tripwire for *presence*, not a judge of
/// documentation quality.
@Suite struct KnobDocumentationTests {
    /// `Sources/Aski/Aski.docc/Algorithms.md`, resolved from this test's own path
    /// so it works regardless of the process working directory.
    static var algorithmsDocURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/AskiTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Sources/Aski/Aski.docc/Algorithms.md")
    }

    @Test func everyRenderingOptionsKnobIsDocumented() throws {
        let doc = try String(contentsOf: Self.algorithmsDocURL, encoding: .utf8)

        let knobs = Mirror(reflecting: RenderingOptions())
            .children
            .compactMap(\.label)

        #expect(
            !knobs.isEmpty,
            "Mirror surfaced no RenderingOptions properties — the reflection assumption broke."
        )

        for knob in knobs {
            #expect(
                doc.contains("`\(knob)`"),
                """
                RenderingOptions.\(knob) is not documented in Algorithms.md. Add it to the product-knob \
                table or the research-knob prose as a `\(knob)` code span.
                """
            )
        }
    }
}
