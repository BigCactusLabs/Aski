import Foundation

public enum GitSHA {
    /// Returns the override if non-nil, otherwise probes git in the current working directory.
    public static func resolve(override: String?) -> String {
        if let override { return override }
        return probe(workingDirectory: FileManager.default.currentDirectoryPath)
    }

    /// Runs `git rev-parse HEAD` in `workingDirectory`. Returns the trimmed SHA
    /// on success, or "unknown" if git is unavailable, the directory is not a
    /// repo, or the command exits non-zero.
    public static func probe(workingDirectory: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "rev-parse", "HEAD"]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "unknown"
        }

        guard process.terminationStatus == 0 else {
            return "unknown"
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }
}
