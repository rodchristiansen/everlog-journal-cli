import Foundation

enum ShortcutsError: Error, CustomStringConvertible {
    case helperNotInstalled(String)
    case shortcutsBinaryMissing
    case runFailed(name: String, exitCode: Int32, stderr: String)
    case invalidPayload(String)

    var description: String {
        switch self {
        case .helperNotInstalled(let name):
            return """
            Helper shortcut '\(name)' is not installed.
            Run `everlog install-shortcuts` to import the helpers, then retry.
            """
        case .shortcutsBinaryMissing:
            return "/usr/bin/shortcuts not found (macOS 12+ required)."
        case .runFailed(let name, let code, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Shortcut '\(name)' exited \(code).\n\(trimmed)"
        case .invalidPayload(let why):
            return "Invalid payload: \(why)"
        }
    }
}

enum Shortcuts {
    static let helperPrefix = "Everlog CLI- "
    static let shortcutsBinary = "/usr/bin/shortcuts"

    static func ensureBinaryAvailable() throws {
        guard FileManager.default.isExecutableFile(atPath: shortcutsBinary) else {
            throw ShortcutsError.shortcutsBinaryMissing
        }
    }

    static func isInstalled(_ helperName: String) -> Bool {
        guard let output = try? runCapturing(shortcutsBinary, ["list"]) else { return false }
        return output.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == helperName }
    }

    /// Path the CLI writes message text to before invoking the new-entry helper.
    /// The helper Shortcut reads this file via "Get Contents of URL" with a file:// URL.
    /// This bridges around macOS's flaky `shortcuts run --input-path` plumbing for
    /// AppIntents whose parameters are typed as IntentsTransferable rather than plain String.
    /// See docs/phase2-blockers.md for the full story.
    static let messageBridgePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".everlog-cli", isDirectory: true)
                   .appendingPathComponent("message.txt").path
    }()

    /// Run a helper shortcut. The message body is written to `messageBridgePath` first,
    /// then the shortcut runs (no input piping needed).
    static func runNewEntry(helper: String, message: String) throws {
        try ensureBinaryAvailable()
        guard isInstalled(helper) else {
            throw ShortcutsError.helperNotInstalled(helper)
        }
        let url = URL(fileURLWithPath: messageBridgePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try message.write(to: url, atomically: true, encoding: .utf8)
        _ = try runCapturing(shortcutsBinary, ["run", helper])
    }

    /// Bundled helper `.shortcut` files copied from `Resources/Shortcuts/`.
    static func bundledHelpers() -> [URL] {
        guard let dir = Bundle.module.resourceURL?.appendingPathComponent("Shortcuts", isDirectory: true) else {
            return []
        }
        let contents: [URL] = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let helpers: [URL] = contents.filter { $0.pathExtension == "shortcut" }
        return helpers.sorted { (a: URL, b: URL) -> Bool in a.lastPathComponent < b.lastPathComponent }
    }

    @discardableResult
    private static func runCapturing(_ path: String, _ args: [String], stdin: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        if let stdin = stdin {
            let inPipe = Pipe()
            process.standardInput = inPipe
            try process.run()
            if let data = stdin.data(using: .utf8) {
                try inPipe.fileHandleForWriting.write(contentsOf: data)
            }
            try inPipe.fileHandleForWriting.close()
        } else {
            try process.run()
        }
        process.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw ShortcutsError.runFailed(name: args.dropFirst().first ?? "(unknown)", exitCode: process.terminationStatus, stderr: stderr)
        }
        return stdout
    }
}
