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

// MARK: - Write subcommands (Phase 2 — stubs)

struct New: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Create a new entry (Phase 2 — not yet implemented)."
    )

    @Argument var journal: String
    @Argument var text: String

    func run() throws {
        throw ValidationError(
            "Write bridge (Phase 2) not yet implemented. " +
            "Will wrap `shortcuts run 'Create Entry'` or call AppIntents directly. " +
            "See PROJECT_PLAN.md."
        )
    }
}

struct Append: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "append",
        abstract: "Append text to an existing entry (Phase 2 — not yet implemented)."
    )

    @Argument var identifier: String
    @Argument var text: String

    func run() throws {
        throw ValidationError(
            "Write bridge (Phase 2) not yet implemented. " +
            "Will wrap `shortcuts run 'Append Text to Entry'`. See PROJECT_PLAN.md."
        )
    }
}
