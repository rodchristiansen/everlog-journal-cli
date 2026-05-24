# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`everlog-journal-cli` is an unofficial Swift CLI for the Everlog (Hummingbird) journaling app by Wonderbit. It reads the local SQLite database directly and (eventually) writes via Everlog's Shortcuts actions or AppIntents.

This is an open-source project — written for both Rod's personal use and community contribution. MIT licensed. Not affiliated with Wonderbit.

## First move when a task arrives

1. **Read [`PROJECT_PLAN.md`](PROJECT_PLAN.md)** for the 8-phase roadmap and where we are now.
2. **Read [`ARCHITECTURE.md`](ARCHITECTURE.md)** for storage layout, schema overview, write-side design.
3. **Read [`docs/schema.md`](docs/schema.md)** before touching any DB query.

## Layout

```
Sources/everlog/
├── EverlogCLI.swift     @main, top-level command, subcommand list
├── Commands.swift       each subcommand as a ParsableCommand struct
├── DB.swift             SQLite snapshot + open + per-query functions
├── Models.swift         Codable structs (Journal, Tag, Entry)
└── Output.swift         plain + JSON formatters, ANSI helpers

Tests/everlogTests/
└── DBTests.swift        integration-style; skips on machines without Everlog

Package.swift            SwiftPM. macOS 13+. swift-argument-parser. Links system sqlite3.

docs/
├── schema.md            Hummingbird SQLite schema column-by-column reference
├── shortcuts.md         Everlog Shortcuts catalog + helper-shortcut design
└── examples.md          common usage patterns
```

## Build / run / test

```bash
swift build                                 # debug build → .build/debug/everlog
swift build -c release                      # release build → .build/release/everlog
swift test                                  # run XCTest suite
.build/debug/everlog journals               # smoke test
```

For editable system install:

```bash
ln -sf "$(pwd)/.build/release/everlog" /usr/local/bin/everlog
```

## Architecture rules

1. **Read = SQLite, Write = Shortcuts/AppIntents.** Never mutate the SQLite directly — that bypasses Wonderbit's CloudKit sync.
2. **Always snapshot-before-query.** Copy live DB + WAL + SHM to `/tmp/everlog-ro.sqlite` (chmod 600), then open `SQLITE_OPEN_READONLY`.
3. **No app activation.** Read operations must stay headless. Write operations may briefly activate Everlog/Shortcuts but only when invoking the underlying integration.
4. **`--json` is a public API.** Output schemas in `Models.swift` are `Codable` and versioned. Breaking changes to JSON shape require a major version bump.
5. **Schema is documented but not enforced — yet.** [docs/schema.md](docs/schema.md) is the source of truth; the CLI should eventually check `Z_METADATA.Z_VERSION` against a known-compatible list (TODO).
6. **No third-party deps beyond Apple's.** Only `swift-argument-parser` and the system `sqlite3`. Adding a dep needs an issue + discussion.

## Patterns

### Adding a new subcommand

1. Define a `ParsableCommand` struct in `Commands.swift`:
   ```swift
   struct Foo: ParsableCommand {
       static let configuration = CommandConfiguration(abstract: "…")
       @Argument var something: String
       @Flag(name: .long) var json = false
       func run() throws {
           let db = try DB.open()
           defer { DB.close(db) }
           let rows = try DB.foo(db, something: something)
           if json { Output.emitJSON(rows) } else { Output.emitWhatever(rows) }
       }
   }
   ```
2. Add the corresponding query function in `DB.swift`.
3. Add an output formatter in `Output.swift` if the shape is new.
4. Register the subcommand in `EverlogCLI.swift`'s `subcommands:` array.
5. Document the subcommand in `README.md`, examples in `docs/examples.md`.

### SQLite query pattern

```swift
let stmt = try Statement(db, """
    SELECT col1, col2 FROM ZTABLE WHERE col3 = ?1 LIMIT ?2
""").bind(1, "value").bind(2, 10)

var out: [Something] = []
while stmt.step() {
    out.append(Something(
        field1: stmt.text(0) ?? "",
        field2: Int(stmt.int(1))
    ))
}
return out
```

`Statement` handles `sqlite3_finalize` automatically (`deinit`). Don't manually free.

### Cocoa timestamps

Swift's `Date(timeIntervalSinceReferenceDate:)` already uses the Cocoa epoch (2001-01-01) — same units as Hummingbird's `ZDATE` columns. **No offset arithmetic needed** in Swift code:

```swift
let date = Date(timeIntervalSinceReferenceDate: stmt.double(0))
```

For SQLite's `strftime` (which uses Unix epoch), we still add 978307200 inside the SQL:

```sql
datetime(e.ZDATE + 978307200, 'unixepoch')
```

## When you should ask before acting

- Before adding any third-party dependency to `Package.swift`.
- Before modifying `Models.swift` in a way that changes JSON output shape.
- Before mutating the user's Everlog data (writing entries, modifying tags, etc. — Phase 2+).
- Before pushing to a GitHub remote (this is a public OSS repo).
- Before tagging a release.

## When to extend

- **New read query?** Add to `DB.swift` + new `ParsableCommand` in `Commands.swift`.
- **New output format?** Add to `Output.swift`. JSON shape is in `Models.swift`.
- **New Phase 2 write operation?** First decode the Everlog Shortcut action (see `docs/shortcuts.md`); then implement in `Sources/everlog/` (probably a new `WriteBridge.swift`).
- **New docs?** Drop in `docs/`. Major design changes go in `ARCHITECTURE.md` or new dedicated docs.

## Related repos

- `~/Developer/Personal` — Rod's personal life-system repo. Has its own `bin/everlog` (predates this) that this OSS project will eventually supersede. Don't modify it from here.
- `~/Documents/Create/Setup/cmux/workspace-set.yaml` — has a workspace entry pointing here under "GitHub Tools" section.

## What's NOT in scope

- Cross-platform support (Linux/Windows). Everlog is macOS/iOS only.
- A GUI. This is a CLI; the app already has a GUI.
- Mirroring entries to Markdown/Notion/Obsidian as a sync target. That'd be Phase 5 export, one-shot only.
- Replacing the Everlog app or its sync.
