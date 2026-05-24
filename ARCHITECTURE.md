# Architecture

## Storage layout

Everlog (Hummingbird) stores all data in the macOS App Group container shared across the main app, widget, share extension, and Intents host. Verified locations:

```
~/Library/Group Containers/group.hummingbird/
├── Hummingbird.sqlite               main CoreData store (135 MB on a 3060-entry production DB)
├── Hummingbird.sqlite-wal           write-ahead log
├── Hummingbird.sqlite-shm           shared memory
├── AttachmentData.sqlite            binary attachment data (26 MB on the same DB)
├── AttachmentData.sqlite-wal
├── AttachmentData.sqlite-shm
├── Backups/                         widget-extension local backups (zips)
├── CoreDataHistory/                 CoreData persistent history tracking
└── Hummingbird_ckAssets/            CloudKit asset cache
```

```
~/Library/Mobile Documents/iCloud~co~wonderbit~hummingbird/Documents/Backups/
└── Everlog Backup YYYY-MM-DD_HH-MM-SS.zip    app-generated full backups (iCloud-synced)
```

```
~/Library/Containers/co.wonderbit.Hummingbird/                main app container
~/Library/Containers/co.wonderbit.Hummingbird.HummingbirdWidget/      widget
~/Library/Containers/co.wonderbit.Hummingbird.HummingbirdIntents/     shortcut intents host
~/Library/Containers/co.wonderbit.Hummingbird.EverlogShareExtension/  share extension
```

The CLI only touches the **Group Containers** path. Per-target containers are app-internal and we don't read or write them.

`EVERLOG_GROUP_CONTAINER` and `EVERLOG_DB` env vars override the default paths for testing.

## Why copy-before-query

SQLite has aggressive WAL behavior under CoreData's settings. Reading the live file while Everlog or its widget is writing produces inconsistent reads — sometimes empty result sets, sometimes "database is locked" errors.

The pattern (port of the same approach in Rod's `bin/sc-dump-all` for Shortcuts):

```swift
let src = URL(...).appendingPathComponent("Hummingbird.sqlite")
let dst = URL(fileURLWithPath: "/tmp/everlog-ro.sqlite")
try FileManager.default.copyItem(at: src, to: dst)
// WAL/SHM sidecars too
for ext in ["-wal", "-shm"] {
    try? FileManager.default.copyItem(
        at: URL(fileURLWithPath: src.path + ext),
        to: URL(fileURLWithPath: dst.path + ext)
    )
}
try? FileManager.default.setAttributes(
    [.posixPermissions: 0o600],
    ofItemAtPath: dst.path
)
// Then open with SQLITE_OPEN_READONLY
```

The WAL/SHM sidecars are copied alongside so SQLite reconstructs a coherent point-in-time view. The `/tmp` copy is `chmod 600` because entries can be sensitive.

## Schema overview (CoreData-generated)

Hummingbird's CoreData store uses the standard `Z<ENTITY>` naming. Key tables documented in [docs/schema.md](docs/schema.md). Highlights:

| Table | Role |
|---|---|
| `ZENTRY` | One row per journal entry. `ZTEXT` is the markdown body. `ZDATE` is a Cocoa timestamp (same units as Swift's `Date.timeIntervalSinceReferenceDate`). |
| `ZJOURNAL` | The user's journals. `ZNAME` is the display name. |
| `ZTAG` | Tags. `ZTITLE` (not `ZNAME`) is the tag string. |
| `Z_17TAGS` | Entry ↔ tag join. `Z_17ENTRIES1` = entry PK, `Z_22TAGS` = tag PK. |
| `ZATTACHMENT` + `ZATTACHMENTDATA` (in the sibling DB) | Per-entry attachments. |
| `ZIMAGE` | Image-typed attachments. |
| `ZPLACE`, `ZWEATHER` | Location + weather captured at write time. |
| `ZTEMPLATE`, `ZPROMPT` | User-defined entry templates and prompt structures. |
| `ANSCK*` | CloudKit sync metadata. **Ignore unless debugging sync.** |

Entry text is markdown with inline attachment references:

```
![attachment](1BD3C6DF-0325-4AB5-817F-DDF5ED181E33)
```

The UUID resolves against `ZATTACHMENT.ZIDENTIFIER` (or similar — needs verification in Phase 2).

## Cocoa timestamps

`ZDATE`, `ZDATECREATED`, `ZDATEMODIFIED`, `ZDATETRASHED`, `ZSORTDATE`, `ZTEXTMODIFIEDDATE` are seconds-since-2001-01-01 (Cocoa epoch).

**Swift bonus**: `Foundation.Date(timeIntervalSinceReferenceDate:)` uses exactly this epoch — no offset arithmetic needed. The Python port had to add 978307200 to convert; in Swift the value goes straight in.

For SQLite's `strftime` (used in `on-this-day` query), we still need to convert to Unix epoch:

```sql
strftime('%m-%d', datetime(e.ZDATE + 978307200, 'unixepoch')) = ?1
```

## Trashed entries

`ZISTRASHED = 1` indicates a trashed entry. All read queries filter with `ZISTRASHED = 0`. Phase 3+ adds `--include-trashed` for inspection.

## Encrypted columns

Some columns are suffixed `ZENCRYPTED*` (e.g. `ZENCRYPTEDLATITUDE`, `ZENCRYPTEDLONGITUDE`, `ZENCRYPTEDNAME`) alongside their plaintext counterparts. These appear to be filled for entries/journals marked as encrypted. The plaintext versions remain populated for non-encrypted entries.

**Handling of encrypted entries is an open question** (see PROJECT_PLAN.md). For Phase 1 the CLI reads plaintext columns; encrypted entries may appear empty until we implement decryption (likely impossible from outside the app).

## Write side (Phase 2 → Phase 3)

Everlog's Shortcuts actions are the supported write path. Direct SQLite mutations would (a) bypass Wonderbit's CloudKit sync logic and (b) risk CoreData consistency rules.

Observed Shortcuts actions in Shortcuts.app (search for "Everlog" or "Journal"):

| Action | Use |
|---|---|
| `Create Entry` | Create a new entry. Inputs: text, journal, tags, attachments, date, location. |
| `Update Journal` | Modify journal metadata. |
| `Delete Journal Entries` | Bulk delete. |
| `Create Journal` | Create a new top-level journal. |
| `Get Journal` | Fetch journal metadata. |
| `Find Entries` | Filter entries by date/journal/tag. |
| `Search Entries` | Full-text search. |
| `Open Entry` | Open one entry in the Everlog UI. |
| `Open Bookmarks` | Open bookmarks view. |
| `Open Tag` | Open a tag view. |
| `Open On This Day` | Open the On This Day view. |
| `Set Bookmark of Entry` | Toggle bookmark. |
| `Set Everlog Focus Filter` | Restrict app view. |
| `Add Comment to Entry` | Add a comment thread. |
| `Append Text to Entry` | Append text to an existing entry. |
| `Write Entry` | (Possibly duplicate of `Create Entry` — needs decode.) |
| `Record Audio` | Record audio attachment. |

These are AppIntent-backed (`co.wonderbit.Hummingbird.*Intent` action identifiers).

### Phase 2: ship helper shortcuts that wrap Everlog's actions

To avoid building complete plists from CLI code on every write call, the CLI bundles pre-authored helper Shortcuts that take JSON input and call the underlying Everlog actions:

| Helper | Wraps | Input shape |
|---|---|---|
| `Everlog CLI: New Entry` | Create Entry | `{"journal": "Mindset", "text": "...", "tags": ["wins"], "date": "...", "lat": ..., "lng": ...}` |
| `Everlog CLI: Append` | Append Text to Entry | `{"identifier": "ABCD-...", "text": "..."}` |
| `Everlog CLI: Find` | Find Entries | `{"journal": "Mindset", "tag": "wins", "limit": 20}` → identifiers |
| `Everlog CLI: Bookmark` | Set Bookmark of Entry | `{"identifier": "ABCD-...", "on": true}` |

First-run `everlog install-shortcuts` writes the bundled `.shortcut` files to a temp path and opens them, prompting the user to import.

### Phase 3: skip the helper layer with direct AppIntents

Apple's `AppIntents` framework allows a third-party process to invoke another app's `AppIntent` types, given:

1. The target intent is declared as an `AppIntent` (not `OpenIntent`, which requires foreground UI).
2. The calling process has the appropriate entitlements (likely something like `com.apple.developer.intents` or per-bundle-id permission).
3. The user has granted the relevant Privacy permission via a TCC prompt the first time.

If feasible (Wonderbit's intents may be `OpenIntent`-only, in which case we stay on the shortcuts CLI), Phase 3 replaces the helper-shortcut subprocess with direct framework calls:

```swift
import AppIntents

let intent = AnyIntent(identifier: "co.wonderbit.Hummingbird.CreateEntryIntent")
intent["text"] = "..."
intent["journal"] = "Mindset"
let result = try await intent.perform()
```

(Exact API TBD — the dynamic AppIntent invocation API is sparsely documented.)

## Package layout

```
Sources/everlog/
├── EverlogCLI.swift      @main entry, top-level command, version, subcommand list
├── Commands.swift        each subcommand as a ParsableCommand struct
├── DB.swift              SQLite snapshot + open + per-query functions
├── Models.swift          Codable structs: Journal, Tag, Entry, Entry.Location
└── Output.swift          plain + JSON formatters, ANSI helpers

Tests/everlogTests/
└── DBTests.swift         integration-style; skips if Everlog not installed

Package.swift             SwiftPM: macOS 13+, depends on swift-argument-parser,
                          links system sqlite3 via linkedLibrary
```

## Compatibility matrix (to be verified)

| Everlog version | Hummingbird.sqlite schema version | CLI tested? |
|---|---|---|
| 2025.x (scaffold-time production DB) | `Z_METADATA.Z_VERSION` = TBD (needs probe) | ✅ |
| 2024.x | TBD | ⬜ |
| 2023.x | TBD | ⬜ |

The CLI should refuse to run against an untested schema version with a clear error. Issue template for adding new versions: "report `Z_VERSION`, your Everlog version, any errors observed."

## Dependencies

Minimal:

- **System Swift** (5.10+, ships with macOS via Xcode Command Line Tools)
- **`apple/swift-argument-parser`** — only third-party dependency, first-party Apple
- **System `sqlite3`** — linked via `Package.swift`'s `.linkedLibrary("sqlite3")`

No language-runtime dependency for end users (vs Python which would require `python3` + `pip install`). Single signed binary distribution.

## Security & privacy

- The CLI reads journal entries from local storage. Entries can contain sensitive personal content.
- Never log entry text to stdout *unless the user explicitly requested it via the `read` subcommand* (or `--json` was requested as an explicit opt-in).
- Never send entries over the network without explicit opt-in.
- The `/tmp/` snapshot is `chmod 600` after copy so only the current user can read it. Don't store the snapshot anywhere persistent.
- `--exec` in Phase 7's `watch` mode is a foot-gun — entry text is piped to user-supplied commands. Document the trust model clearly.
- The signed binary in Phase 6 will use hardened runtime + Developer ID, and be notarized.
