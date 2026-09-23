import Testing
import CoreText
@testable import Aski

@Suite struct ASCIIFontTests {
    @Test func initWithNameAndSize() {
        let font = ASCIIFont(name: "Courier", size: 14)
        #expect(font.pointSize == 14)
        #expect(font.postScriptName.hasPrefix("Courier"))
    }

    @Test func systemFactory() {
        let font = ASCIIFont.system(size: 12, monospaced: true)
        #expect(font.pointSize == 12)
        #expect(CTFontGetSymbolicTraits(font.ctFont).contains(.traitMonoSpace))
    }
}
