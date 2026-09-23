import ArgumentParser
import Aski
import CoreGraphics
import Testing
@testable import AskiToolSupport

@Suite struct ToolSupportTests {
    @Test func charsetMapsEveryCaseToABuiltIn() {
        // Smoke-check that each case resolves a StandardCharacterSet without trapping.
        for charset in Charset.allCases {
            _ = charset.characterSet
        }
        #expect(Charset(argument: "blocks") == .blocks)
        #expect(Charset(argument: "braille") == .braille)
    }

    @Test func charsetRejectsUnknownName() {
        #expect(Charset(argument: "rainbow") == nil)
    }

    @Test func backgroundColorParsesHex() {
        let red = BackgroundColor(argument: "#FF0000")
        #expect(red?.red == 1)
        #expect(red?.green == 0)
        #expect(red?.blue == 0)
        #expect(red?.alpha == 1)
    }

    @Test func backgroundColorParsesNamed() {
        #expect(BackgroundColor(argument: "white") == BackgroundColor(red: 1, green: 1, blue: 1, alpha: 1))
        #expect(BackgroundColor(argument: "BLACK") == .black)
    }

    @Test func backgroundColorParsesTransparentNames() {
        #expect(BackgroundColor(argument: "clear") == .clear)
        #expect(BackgroundColor(argument: "TRANSPARENT") == .clear)
        #expect(BackgroundColor(argument: "clear")?.alpha == 0)
        #expect(BackgroundColor(argument: "clear")?.cgColor.alpha == 0)
    }

    @Test func backgroundColorHasCanonicalRGBAHex() {
        #expect(BackgroundColor(argument: "#112233")?.canonicalRGBAHex == "#112233FF")
        #expect(BackgroundColor(argument: "white")?.canonicalRGBAHex == "#FFFFFFFF")
        #expect(BackgroundColor(argument: "gray")?.canonicalRGBAHex == "#808080FF")
        #expect(BackgroundColor(argument: "clear")?.canonicalRGBAHex == "#00000000")
    }

    @Test func backgroundColorRejectsBadInput() {
        #expect(BackgroundColor(argument: "#GGGGGG") == nil)
        #expect(BackgroundColor(argument: "notacolor") == nil)
        #expect(BackgroundColor(argument: "#FFF") == nil)
    }

    @Test func validatorsRejectOutOfRange() {
        #expect(throws: (any Error).self) { try ToolValidation.requireColumns(0) }
        #expect(throws: (any Error).self) { try ToolValidation.requireColumns(513) }
        #expect(throws: (any Error).self) { try ToolValidation.requireFontSize(.infinity) }
        #expect(throws: (any Error).self) { try ToolValidation.requireFontSize(97) }
        #expect(throws: (any Error).self) { try ToolValidation.requireTargetPixelWidth(0) }
        #expect(throws: (any Error).self) {
            try ToolValidation.requireTargetPixelWidth(ASCIIGrid.maxTargetPixelWidth + 1)
        }
        #expect(throws: (any Error).self) { try ToolValidation.requireSafeGitSHA("a,b") }
        #expect(throws: (any Error).self) { try ToolValidation.requireSafeGitSHA("a\nb") }
    }

    @Test func validatorsAcceptInRange() throws {
        try ToolValidation.requireColumns(512)
        try ToolValidation.requireFontSize(10)
        try ToolValidation.requireTargetPixelWidth(ASCIIGrid.maxTargetPixelWidth)
        try ToolValidation.requireSafeGitSHA("deadbeef")
        try ToolValidation.requireSafeGitSHA(nil)
    }

    @Test func toolVersionIsResolvedOnce() {
        #expect(!ToolVersion.current.isEmpty)
    }
}
