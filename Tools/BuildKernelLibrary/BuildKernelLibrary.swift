import Foundation

@main
struct BuildKernelLibrary {
    static func main() throws {
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let kernelDir = projectRoot.appendingPathComponent("Sources/Aski/Effects/Kernels")
        let outputDir = projectRoot.appendingPathComponent("Sources/Aski/Resources/Kernels")
        let outputURL = outputDir.appendingPathComponent("default.metallib")

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let kernelSources =
            (try? FileManager.default.contentsOfDirectory(
                at: kernelDir,
                includingPropertiesForKeys: nil
            ))?
            .filter { $0.pathExtension == "metal" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        let headerSources =
            (try? FileManager.default.contentsOfDirectory(
                at: kernelDir,
                includingPropertiesForKeys: nil
            ))?
            .filter { $0.pathExtension == "h" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        guard !kernelSources.isEmpty else {
            FileHandle.standardError.write(Data("BuildKernelLibrary: no .metal sources found in \(kernelDir.path); writing empty metallib\n".utf8))
            if FileManager.default.fileExists(atPath: outputURL.path) {
                let handle = try FileHandle(forWritingTo: outputURL)
                try handle.truncate(atOffset: 0)
                try handle.close()
            } else {
                try Data().write(to: outputURL)
            }
            print("Wrote \(outputURL.path)")
            return
        }

        let temp = URL(fileURLWithPath: "/private/tmp/aski-kernel-build", isDirectory: true)
        try? FileManager.default.removeItem(at: temp)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        for header in headerSources {
            let destination = temp.appendingPathComponent(header.lastPathComponent)
            try Data(contentsOf: header).write(to: destination, options: .atomic)
        }

        let combinedSource = temp.appendingPathComponent("combined.ci.metal")
        var combined = Data()
        for source in kernelSources {
            combined.append(Data("// \(source.lastPathComponent)\n".utf8))
            combined.append(try Data(contentsOf: source))
            combined.append(Data("\n\n".utf8))
        }
        try combined.write(to: combinedSource)

        let air = temp.appendingPathComponent("combined.air")
        runMetalTool(
            "metal",
            arguments: ["-fcikernel", "-c", combinedSource.path, "-o", air.path],
            failureMessage: "BuildKernelLibrary: metal compile failed"
        )

        runMetalTool(
            "metallib",
            arguments: ["--cikernel", air.path, "-o", outputURL.path],
            failureMessage: "BuildKernelLibrary: metallib link failed"
        )
        print("Wrote \(outputURL.path)")
    }

    private static func runMetalTool(_ tool: String, arguments: [String], failureMessage: String) {
        let command = resolveMetalTool(named: tool)
        let result = runProcess(executable: command.executable, arguments: command.arguments + arguments)
        if !result.output.isEmpty {
            writeError(result.output)
        }
        guard result.status == 0 else {
            writeError("\(failureMessage)\n")
            printToolchainDiagnostics()
            Foundation.exit(result.status == 0 ? 1 : result.status)
        }
    }

    private static func resolveMetalTool(named tool: String) -> (executable: String, arguments: [String]) {
        let xcrunResult = runProcess(
            executable: "/usr/bin/xcrun",
            arguments: ["--find", tool],
            environment: ["TOOLCHAINS": "com.apple.dt.toolchain.Metal"]
        )
        if xcrunResult.status == 0 {
            let path = xcrunResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return (path, [])
            }
        }

        if let fallback = mountedMetalToolchainPath(named: tool) {
            writeError("BuildKernelLibrary: xcrun --find \(tool) failed; using mounted Metal toolchain path \(fallback)\n")
            return (fallback, [])
        }

        return ("/usr/bin/xcrun", [tool])
    }

    private static func mountedMetalToolchainPath(named tool: String) -> String? {
        let versionResult = runProcess(
            executable: "/usr/bin/xcrun",
            arguments: ["metal", "-v"],
            environment: ["TOOLCHAINS": "com.apple.dt.toolchain.Metal"]
        )
        let installedDir = versionResult.output
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard line.hasPrefix("InstalledDir: ") else { return nil }
                return String(line.dropFirst("InstalledDir: ".count))
            }
            .first
        guard let installedDir else { return nil }

        let installedDirURL = URL(fileURLWithPath: installedDir)
        let currentBinCandidate = installedDirURL.appending(path: tool).path
        if FileManager.default.isExecutableFile(atPath: currentBinCandidate) {
            return currentBinCandidate
        }

        let currentBinSuffix = "/usr/metal/current/bin"
        if installedDir.hasSuffix(currentBinSuffix) {
            let toolchainRoot = String(installedDir.dropLast(currentBinSuffix.count))
            let usrBinCandidate = URL(fileURLWithPath: toolchainRoot)
                .appending(path: "usr/bin")
                .appending(path: tool)
                .path
            if FileManager.default.isExecutableFile(atPath: usrBinCandidate) {
                return usrBinCandidate
            }
        }

        return nil
    }

    private static func printToolchainDiagnostics() {
        writeError("BuildKernelLibrary: toolchain diagnostics\n")
        printDiagnostic("xcodebuild -version", executable: "/usr/bin/xcodebuild", arguments: ["-version"])
        printDiagnostic("swift --version", executable: "/usr/bin/xcrun", arguments: ["swift", "--version"])
        printDiagnostic(
            "xcrun --find metal",
            executable: "/usr/bin/xcrun",
            arguments: ["--find", "metal"],
            environment: ["TOOLCHAINS": "com.apple.dt.toolchain.Metal"]
        )
        printDiagnostic(
            "xcrun --find metallib",
            executable: "/usr/bin/xcrun",
            arguments: ["--find", "metallib"],
            environment: ["TOOLCHAINS": "com.apple.dt.toolchain.Metal"]
        )
        writeError("Install the Metal toolchain with: xcodebuild -downloadComponent MetalToolchain\n")
    }

    private static func printDiagnostic(
        _ label: String,
        executable: String,
        arguments: [String],
        environment: [String: String] = [:]
    ) {
        let result = runProcess(executable: executable, arguments: arguments, environment: environment)
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty {
            writeError("\(label): exit \(result.status)\n")
        } else {
            writeError("\(label):\n\(output)\n")
        }
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        environment: [String: String] = [:]
    ) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (127, "failed to run \(executable) \(arguments.joined(separator: " ")): \(error)\n")
        }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data(message.utf8))
    }
}
