import Foundation
import Testing

@Suite struct DocCValidationModeTests {
    @Test func localGatesRunValidationWithoutGeneratingMarkdownSidecars() throws {
        let root = try Self.packageRoot()
        let justfile = try String(
            contentsOf: root.appending(path: "justfile"),
            encoding: .utf8
        )
        let doctor = try String(
            contentsOf: root.appending(path: "Scripts/repo-doctor.sh"),
            encoding: .utf8
        )

        #expect(justfile.contains("./Scripts/validate-docc.sh"))
        #expect(!justfile.contains("validate-docc.sh --emit-markdown"))
        #expect(doctor.contains("./Scripts/validate-docc.sh"))
        #expect(!doctor.contains("validate-docc.sh --emit-markdown"))
    }

    @Test func validatorDefaultsToOneConversionAndGatesTheSecondBehindAFlag() throws {
        let root = try Self.packageRoot()
        let script = try String(
            contentsOf: root.appending(path: "Scripts/validate-docc.sh"),
            encoding: .utf8
        )

        #expect(script.contains("emit_markdown=0"))
        #expect(script.contains("--emit-markdown)"))
        #expect(script.contains("emit_markdown=1"))
        #expect(script.contains("if [ \"$emit_markdown\" -eq 1 ]; then"))
        #expect(script.contains("Markdown output was requested"))
    }

    private static func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appending(path: "Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
