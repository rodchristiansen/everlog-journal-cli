import ArgumentParser
import Foundation

enum ExportFormat: String, CaseIterable, ExpressibleByArgument {
    case markdown
    case json
    case dayone
}

enum ExportError: Error, CustomStringConvertible {
    case missingDestination
    case notADirectory(String)
    case writeFailed(String, underlying: Error)

    var description: String {
        switch self {
        case .missingDestination:
            return "An output destination is required: pass --to <path>."
        case .notADirectory(let path):
            return "Markdown export expects --to to be a directory. \(path) is not."
        case .writeFailed(let path, let err):
            return "Failed to write \(path): \(err.localizedDescription)"
        }
    }
}

enum Export {
    /// Write entries as one Markdown file per entry under `dir/<journal>/<filename>.md`.
    static func writeMarkdown(_ entries: [Entry], to dir: URL) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var written = 0
        for entry in entries {
            let journalDir = dir.appendingPathComponent(sanitize(entry.journal), isDirectory: true)
            try fm.createDirectory(at: journalDir, withIntermediateDirectories: true)
            let file = journalDir.appendingPathComponent(filename(for: entry))
            let body = renderMarkdown(entry)
            do {
                try body.write(to: file, atomically: true, encoding: .utf8)
            } catch {
                throw ExportError.writeFailed(file.path, underlying: error)
            }
            written += 1
        }
        return written
    }

    /// Write all entries to a single JSON file (or stdout if `to` is `-`).
    static func writeJSON(_ entries: [Entry], toPath path: String) throws -> Int {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(entries)
        try emit(data, toPath: path)
        return entries.count
    }

    /// Write entries as a Day One-compatible JSON document.
    ///
    /// Day One's import format (verified against the documented export shape) is a
    /// single top-level object `{ "metadata": { "version": "1.0" }, "entries": [...] }`.
    /// Each entry has `uuid` (32-char hex, no hyphens), `creationDate`, `text`, `tags`,
    /// `starred`, and an optional nested `location: { latitude, longitude }`.
    static func writeDayOne(_ entries: [Entry], toPath path: String) throws -> Int {
        let doc = DayOneExport(
            metadata: .init(version: "1.0"),
            entries: entries.map { e in
                DayOneEntry(
                    uuid: e.identifier.replacingOccurrences(of: "-", with: ""),
                    creationDate: e.date,
                    text: e.text ?? "",
                    tags: e.tags,
                    starred: e.bookmarked,
                    location: e.location.map { .init(latitude: $0.lat, longitude: $0.lng) }
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(doc)
        try emit(data, toPath: path)
        return entries.count
    }

    private static func emit(_ data: Data, toPath path: String) throws {
        if path == "-" {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0A]))
        } else {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                throw ExportError.writeFailed(url.path, underlying: error)
            }
        }
    }

    // MARK: - Day One schema

    private struct DayOneExport: Codable {
        let metadata: Metadata
        let entries: [DayOneEntry]
        struct Metadata: Codable { let version: String }
    }

    private struct DayOneEntry: Codable {
        let uuid: String
        let creationDate: String
        let text: String
        let tags: [String]
        let starred: Bool
        let location: Location?
        struct Location: Codable {
            let latitude: Double
            let longitude: Double
        }
    }

    // MARK: - Markdown body

    private static func renderMarkdown(_ e: Entry) -> String {
        var frontmatter = "---\n"
        frontmatter += "identifier: \(e.identifier)\n"
        frontmatter += "date: \(e.date)\n"
        frontmatter += "journal: \(yamlString(e.journal))\n"
        frontmatter += "wordcount: \(e.wordcount)\n"
        frontmatter += "bookmarked: \(e.bookmarked)\n"
        if !e.tags.isEmpty {
            frontmatter += "tags: [\(e.tags.map(yamlString).joined(separator: ", "))]\n"
        }
        if let loc = e.location {
            frontmatter += "location: [\(loc.lat), \(loc.lng)]\n"
        }
        frontmatter += "---\n\n"
        let body = e.text ?? ""
        return frontmatter + body + (body.hasSuffix("\n") ? "" : "\n")
    }

    /// Minimal YAML string escaping: quote if the value contains special chars, otherwise emit bare.
    private static func yamlString(_ s: String) -> String {
        let needsQuote = s.contains(":") || s.contains("#") || s.contains("[") || s.contains("]")
            || s.contains(",") || s.contains("\n") || s.contains("\"") || s.isEmpty
            || s.hasPrefix(" ") || s.hasSuffix(" ")
        guard needsQuote else { return s }
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    // MARK: - Filename

    private static func filename(for e: Entry) -> String {
        // e.date is ISO 8601 like "2026-05-24T14:30:00Z"
        let datePart: String
        if let idx = e.date.firstIndex(of: "T") {
            datePart = String(e.date[..<idx])
        } else {
            datePart = e.date
        }
        let timePart: String
        if let t = e.date.firstIndex(of: "T") {
            let after = e.date.index(after: t)
            let end = e.date.firstIndex(of: "Z") ?? e.date.endIndex
            timePart = String(e.date[after..<end]).replacingOccurrences(of: ":", with: "")
        } else {
            timePart = "000000"
        }
        let shortID = String(e.identifier.prefix(8))
        return "\(datePart)T\(timePart)-\(shortID).md"
    }

    private static func sanitize(_ name: String) -> String {
        // Strip path separators + leading dots; preserve otherwise-safe filename chars.
        var s = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        while s.hasPrefix(".") { s.removeFirst() }
        if s.isEmpty { s = "Untitled" }
        return s
    }
}
