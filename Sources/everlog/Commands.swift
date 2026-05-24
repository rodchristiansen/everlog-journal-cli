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

// MARK: - Write subcommands (Phase 2)

struct New: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Create a new entry (file-bridge to Everlog's Create Entry AppIntent via Shortcuts).",
        discussion: """
        EXPERIMENTAL. The Shortcuts → AppIntents dispatch path has unresolved \
        platform constraints — see docs/phase2-blockers.md. This command writes \
        the body text to ~/.everlog-cli/message.txt and then invokes the helper \
        Shortcut, which reads the file and calls Everlog's CreateEntry AppIntent. \
        Journal/date/bookmarked are not yet wired through — entries land in \
        Everlog's current default journal.
        """
    )

    @Argument(help: "Entry body text. Wrap multi-word text in quotes.")
    var text: String

    func run() throws {
        try Shortcuts.runNewEntry(helper: "Everlog CLI- New Entry", message: text)
        print("Dispatched to Everlog. Verify with `everlog show <journal>` — if the entry didn't land, see docs/phase2-blockers.md.")
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
        abstract: "Append text to an existing entry (Slice 2 — not yet implemented)."
    )

    @Argument var identifier: String
    @Argument var text: String

    func run() throws {
        throw ValidationError(
            "`append` lands in Phase 2 Slice 2. Use `everlog new` for now."
        )
    }
}

struct InstallShortcuts: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-shortcuts",
        abstract: "Install the helper Shortcuts that bridge the CLI to Everlog's AppIntents."
    )

    @Flag(name: .long, help: "List installed/missing helpers without installing.")
    var check = false

    func run() throws {
        try Shortcuts.ensureBinaryAvailable()
        let helpers = Shortcuts.bundledHelpers()

        if helpers.isEmpty {
            print("(no bundled helper shortcuts found — this build may be missing Resources)")
            return
        }

        for helper in helpers {
            let displayName = helper.deletingPathExtension().lastPathComponent
            let installed = Shortcuts.isInstalled(displayName)
            let mark = installed ? "✓" : "·"
            print("\(mark) \(displayName)")
            if check { continue }
            if installed {
                continue
            }
            // Open the .shortcut in Shortcuts.app for the user to confirm import.
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [helper.path]
            try task.run()
            task.waitUntilExit()
            print("  → opened in Shortcuts.app; confirm 'Add Shortcut' to install.")
        }

        if !check {
            print("\nWhen the import dialogs are done, run `everlog install-shortcuts --check`.")
        }
    }
}
