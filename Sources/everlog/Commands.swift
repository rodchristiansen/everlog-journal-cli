import ArgumentParser
import Foundation

// MARK: - Read subcommands

struct Journals: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List journals with entry counts."
    )

    @Flag(name: .long, help: "Emit JSON instead of formatted output.")
    var json = false

    func run() throws {
        let db = try DB.open()
        defer { DB.close(db) }
        let rows = try DB.listJournals(db)
        if json { Output.emitJSON(rows) } else { Output.emitJournals(rows) }
    }
}

struct Tags: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List tags with usage counts."
    )

    @Flag(name: .long, help: "Emit JSON instead of formatted output.")
    var json = false

    func run() throws {
        let db = try DB.open()
        defer { DB.close(db) }
        let rows = try DB.listTags(db)
        if json { Output.emitJSON(rows) } else { Output.emitTags(rows) }
    }
}

struct Show: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show recent entries in a journal."
    )

    @Argument(help: "Journal name (e.g. Mindset).")
    var journal: String

    @Argument(help: "Number of entries to return (default 10).")
    var limit: Int = 10

    @Flag(name: .long, help: "Emit JSON instead of formatted output.")
    var json = false

    func run() throws {
        let db = try DB.open()
        defer { DB.close(db) }
        let rows = try DB.showJournal(db, journal: journal, limit: limit)
        if json { Output.emitJSON(rows) } else { Output.emitEntries(rows) }
    }
}

struct Search: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Full-text search across entries."
    )

    @Argument(help: "Search query (matched against entry text).")
    var query: String

    @Option(name: .long, help: "Restrict to one journal.")
    var journal: String?

    @Option(name: .long, help: "Restrict to entries with this tag.")
    var tag: String?

    @Argument(help: "Max results (default 20).")
    var limit: Int = 20

    @Flag(name: .long, help: "Emit JSON instead of formatted output.")
    var json = false

    func run() throws {
        let db = try DB.open()
        defer { DB.close(db) }
        let rows = try DB.search(db, query: query, journal: journal, tag: tag, limit: limit)
        if json { Output.emitJSON(rows) } else { Output.emitEntries(rows) }
    }
}

struct Read: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Read the full text of one entry by identifier (UUID prefix is OK)."
    )

    @Argument(help: "Entry identifier or prefix (e.g. 1BD3C6DF).")
    var identifier: String

    @Flag(name: .long, help: "Emit JSON instead of formatted output.")
    var json = false

    func run() throws {
        let db = try DB.open()
        defer { DB.close(db) }
        let entry = try DB.readEntry(db, identifierPrefix: identifier)
        if json {
            // Encode as nullable for JSON callers
            Output.emitJSON(entry)
        } else {
            Output.emitEntry(entry)
        }
    }
}

struct OnThisDay: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "on-this-day",
        abstract: "Entries from this day-of-year across all years."
    )

    @Flag(name: .long, help: "Emit JSON instead of formatted output.")
    var json = false

    func run() throws {
        let db = try DB.open()
        defer { DB.close(db) }
        let rows = try DB.onThisDay(db)
        if json { Output.emitJSON(rows) } else { Output.emitEntries(rows) }
    }
}

struct Random: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Return one random entry, useful for reflection."
    )

    @Option(name: .long, help: "Restrict to one journal.")
    var journal: String?

    @Flag(name: .long, help: "Emit JSON instead of formatted output.")
    var json = false

    func run() throws {
        let db = try DB.open()
        defer { DB.close(db) }
        let entry = try DB.randomEntry(db, journal: journal)
        if json {
            Output.emitJSON(entry)
        } else if let e = entry {
            Output.emitEntries([e])
        } else {
            print("(no entries match)")
        }
    }
}

struct Watch: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Tail new entries as they're added to Everlog. Emits NDJSON to stdout.",
        discussion: """
        Polls the live Everlog SQLite store at a configurable interval and emits \
        one JSON line per new entry (same Entry shape as `show --json`). Use \
        --exec to run a shell command per entry — the entry identifier is passed \
        as $1.

        By default the first tick emits the full backfill of existing entries \
        oldest-first. Use --from-now to skip the backfill and only emit entries \
        created after the watcher starts.

        Stop with Ctrl+C.
        """
    )

    @Option(name: .long, help: "Poll interval in seconds (default 2).")
    var pollInterval: Double = 2.0

    @Option(name: .long, help: "Restrict to one journal.")
    var journal: String?

    @Flag(name: .long, help: "Skip historical backfill — only emit new entries created after watch starts.")
    var fromNow = false

    @Option(name: .long, help: "Shell command to run per new entry. The entry identifier is passed as $1.")
    var exec: String?

    func run() throws {
        let db = try DB.openLive()
        defer { DB.close(db) }

        var lastPK: Int64 = 0
        if fromNow {
            lastPK = try DB.maxEntryPK(db)
        }

        let banner: String = {
            var parts = ["watching everlog"]
            if let j = journal { parts.append("(journal=\(j))") }
            if fromNow { parts.append("(from-now)") } else { parts.append("(backfill + tail)") }
            parts.append("— Ctrl+C to stop")
            return parts.joined(separator: " ") + "\n"
        }()
        FileHandle.standardError.write(Data(banner.utf8))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        while true {
            let pairs = try DB.entriesAfterWithPKs(db, pk: lastPK, journal: journal)
            for (entry, pk) in pairs {
                if let data = try? encoder.encode(entry),
                   let line = String(data: data, encoding: .utf8) {
                    print(line)
                    fflush(stdout)
                }
                if let cmd = exec {
                    runExec(cmd, identifier: entry.identifier)
                }
                if pk > lastPK { lastPK = pk }
            }
            if pollInterval > 0 {
                Thread.sleep(forTimeInterval: pollInterval)
            }
        }
    }

    private func runExec(_ cmd: String, identifier: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", cmd, "_", identifier]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            FileHandle.standardError.write(Data("exec failed: \(error.localizedDescription)\n".utf8))
        }
    }
}

// MARK: - Write subcommands

struct New: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Create a new entry — fully headless, no Shortcuts involved.",
        discussion: """
        Writes through Everlog's own compiled CoreData model against the live \
        store, with persistent-history tracking so the app's CloudKit sync \
        picks the entry up like any other local edit. A backup of the store is \
        taken to ~/.everlog-cli/backups/ before every write session.

        Body text comes from the argument, or from stdin when the argument is \
        omitted or is `-`.
        """
    )

    @Argument(help: "Entry body text. Omit (or pass -) to read from stdin.")
    var text: String?

    @Option(name: [.customShort("j"), .long], help: "Journal name (e.g. Mindset).")
    var journal: String = "Journal"

    @Option(name: .long, help: "Entry title — becomes a markdown heading above the body.")
    var title: String?

    @Option(name: .long, help: "Entry date, ISO-8601 (e.g. 2026-08-08 or 2026-08-08T21:30:00). Defaults to now.")
    var date: String?

    @Option(name: [.customShort("t"), .customLong("tag")], help: "Tag to attach (repeatable).")
    var tags: [String] = []

    @Flag(name: .long, help: "Bookmark the entry.")
    var bookmark = false

    @Option(name: [.customShort("i"), .customLong("image")], help: "Image file to attach (repeatable).")
    var images: [String] = []

    @Flag(name: .long, help: "Emit the created entry as JSON.")
    var json = false

    func run() throws {
        var body: String
        if let text, text != "-" {
            body = text
        } else {
            body = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
        }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            throw ValidationError("Entry body is empty.")
        }
        if let title, !title.isEmpty {
            body = "# \(title)\n\(body)"
        }

        let entryDate: Date
        if let date {
            guard let parsed = Self.parseDate(date) else {
                throw ValidationError("Could not parse date: \(date). Use ISO-8601 (2026-08-08 or 2026-08-08T21:30:00).")
            }
            entryDate = parsed
        } else {
            entryDate = Date()
        }

        let created = try Store.createEntry(
            body: body, journalName: journal, date: entryDate,
            tags: tags, bookmarked: bookmark, imagePaths: images)

        if json {
            Output.emitJSON(created)
        } else {
            let suffix = created.images > 0 ? ", \(created.images) image\(created.images == 1 ? "" : "s")" : ""
            print("Created \(created.identifier.prefix(8)) in \(created.journal) (\(created.wordCount) words\(suffix))")
        }
    }

    static func parseDate(_ s: String) -> Date? {
        let formats = ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"]
        for format in formats {
            let f = DateFormatter()
            f.dateFormat = format
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            if let d = f.date(from: s) { return d }
        }
        return ISO8601DateFormatter().date(from: s)
    }
}

struct Attach: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attach",
        abstract: "Attach image files to an existing entry."
    )

    @Argument(help: "Entry identifier or unique prefix.")
    var identifier: String

    @Argument(help: "Image file path(s).")
    var paths: [String]

    func run() throws {
        guard !paths.isEmpty else { throw ValidationError("No image paths given.") }
        let id = try Store.attachImages(identifierPrefix: identifier, paths: paths)
        print("Attached \(paths.count) image\(paths.count == 1 ? "" : "s") to \(id.prefix(8))")
    }
}

struct Trash: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trash",
        abstract: "Move an entry to Everlog's trash (soft delete, recoverable in-app)."
    )

    @Argument(help: "Entry identifier or unique prefix (from `everlog show --json`).")
    var identifier: String

    func run() throws {
        let id = try Store.trashEntry(identifierPrefix: identifier)
        print("Trashed \(id.prefix(8))")
    }
}

struct ExportCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export entries to Markdown (one file per entry) or JSON (single file).",
        discussion: """
        Markdown output is organized as <to>/<journal>/<YYYY-MM-DDTHHMMSS>-<shortid>.md \
        with YAML frontmatter (identifier, date, journal, tags, location, bookmarked, \
        wordcount) followed by the entry body. JSON output is a single file containing \
        the full Entry array (use --to - to stream to stdout).

        Attachments and Day One-compatible format are not yet supported.
        """
    )

    @Option(name: .long, help: "Output format: markdown or json.")
    var format: ExportFormat = .markdown

    @Option(name: .long, help: "Output destination. Directory for markdown, file path (or - for stdout) for json.")
    var to: String

    @Option(name: .long, help: "Restrict to one journal.")
    var journal: String?

    @Flag(name: .long, help: "Include trashed entries.")
    var includeTrashed = false

    func run() throws {
        let db = try DB.open()
        defer { DB.close(db) }
        let entries = try DB.allEntries(db, journal: journal, includingTrashed: includeTrashed)

        let written: Int
        switch format {
        case .markdown:
            let url = URL(fileURLWithPath: (to as NSString).expandingTildeInPath)
            written = try Export.writeMarkdown(entries, to: url)
            FileHandle.standardError.write(Data("Wrote \(written) entries to \(url.path)\n".utf8))
        case .json:
            let path = (to as NSString).expandingTildeInPath
            written = try Export.writeJSON(entries, toPath: path)
            if path != "-" {
                FileHandle.standardError.write(Data("Wrote \(written) entries to \(path)\n".utf8))
            }
        }
    }
}

struct Append: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "append",
        abstract: "Append text to an existing entry."
    )

    @Argument(help: "Entry identifier or unique prefix.")
    var identifier: String

    @Argument(help: "Text to append (added on a new line).")
    var text: String

    func run() throws {
        let id = try Store.appendText(identifierPrefix: identifier, text: text)
        print("Appended to \(id.prefix(8))")
    }
}
