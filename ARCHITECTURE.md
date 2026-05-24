# Architecture

## Storage layout

Everlog (Hummingbird) stores all data in the macOS App Group container shared across the main app, widget, and share extension. Verified locations:

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

## Why copy-before-query

SQLite has aggressive WAL behavior under CoreData's settings. Reading the live file while Everlog or its widget is writing produces inconsistent reads — sometimes empty result sets, sometimes "database is locked" errors.

The pattern (taken from the `bin/sc-dump-all` Shortcuts tool in `~/Developer/Personal`):

```python
shutil.copy2(SRC / "Hummingbird.sqlite", "/tmp/everlog-ro.sqlite")
shutil.copy2(SRC / "Hummingbird.sqlite-wal", "/tmp/everlog-ro.sqlite-wal")
shutil.copy2(SRC / "Hummingbird.sqlite-shm", "/tmp/everlog-ro.sqlite-shm")
```

The WAL/SHM sidecars are copied alongside so SQLite reconstructs a coherent point-in-time view. Then queries open the `/tmp` copy read-only.

## Schema overview (CoreData-generated)

Hummingbird's CoreData store uses the standard `Z<ENTITY>` naming. Key tables documented in `docs/schema.md`. Highlights:

| Table | Role |
|---|---|
| `ZENTRY` | One row per journal entry. `ZTEXT` is the markdown body. `ZDATE` is a Cocoa timestamp (add 978307200 for Unix epoch). |
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

The UUID resolves against `ZATTACHMENT.ZIDENTIFIER` (or similar — needs verification).

## Cocoa timestamps

`ZDATE`, `ZDATECREATED`, `ZDATEMODIFIED`, `ZDATETRASHED`, `ZSORTDATE`, `ZTEXTMODIFIEDDATE` are all stored as seconds-since-2001-01-01 (Cocoa epoch). Convert with:

```python
unix_ts = cocoa_ts + 978307200
```

## Trashed entries

`ZISTRASHED = 1` indicates a trashed entry. The CLI filters these out by default. Pass `--include-trashed` (Phase 3+) to include them.

## Encrypted columns

Some columns suffixed `ZENCRYPTED*` (e.g. `ZENCRYPTEDLATITUDE`, `ZENCRYPTEDLONGITUDE`, `ZENCRYPTEDNAME`) exist alongside their plaintext counterparts. These appear to be filled for journals/entries marked as encrypted. The plaintext versions remain populated for non-encrypted entries.

**Handling of encrypted entries is an open question** (see PROJECT_PLAN.md Open design questions). For Phase 1, the CLI reads plaintext columns; encrypted entries may appear empty in results until we implement decryption.

## Write side (Phase 2)

Everlog's Shortcuts actions provide the only safe write path. Direct SQLite mutations would (a) bypass Wonderbit's CloudKit sync logic and (b) risk CoreData consistency rules.

Observed Shortcuts actions (in Shortcuts.app's catalog when searching "Everlog" or "Hummingbird"):

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
| `Write Entry` | (Duplicate of `Create Entry`? — needs decode.) |
| `Record Audio` | Record audio attachment. |

These are AppIntent-backed (`co.wonderbit.Hummingbird.*Intent` action identifiers). The CLI wraps them via:

```bash
shortcuts run "Create Entry" --input <json>
```

The CLI ships a set of pre-authored wrapper Shortcuts (`Everlog CLI: New Entry`, etc.) that accept JSON input and call the underlying Everlog actions. First-run install drops these into the user's Shortcuts library.

## Package layout

```
src/everlog/
├── __init__.py
├── __main__.py        enables `python -m everlog`
├── cli.py             click commands, top-level routing
├── db.py              SQLite reader: open, query, return dataclasses
├── shortcuts.py       Phase 2: wraps `shortcuts run`, manages helper-shortcut install
├── models.py          dataclasses: Entry, Journal, Tag, Attachment
├── output.py          formatters: human (text + colors) + JSON
└── shortcuts_bundle/  pre-authored .shortcut files for the write bridge (Phase 2)
```

Tests in `tests/`. Schema docs in `docs/schema.md`. Examples in `docs/examples.md`.

## Compatibility matrix (to be verified)

| Everlog version | Hummingbird.sqlite schema version | CLI tested? |
|---|---|---|
| 2025.x (production at scaffold time) | (unknown — needs `Z_METADATA.Z_VERSION` probe) | ✅ |
| 2024.x | TBD | ⬜ |
| 2023.x | TBD | ⬜ |

The CLI should refuse to run against an untested schema version with a clear error pointing at this matrix. Issue template for adding new versions: "report your `Z_VERSION` + your Everlog version + any errors."

## Dependencies

Minimal:

- Python 3.10+ (stdlib `sqlite3`, `pathlib`, `datetime`, `json`, `shutil`)
- `click` for CLI parsing
- `rich` for terminal formatting (optional — fallback to plain text)

Phase 2+ adds:

- `pyyaml` for config files
- Possibly a wrapper around `shortcuts` CLI

No CoreData library dependency — we read raw SQLite.

## Security & privacy

- The CLI reads journal entries from local storage. Entries can contain sensitive personal content. Never log entry text to stdout *unless the user explicitly requested it via the `read` subcommand*. Never send entries over the network without explicit opt-in.
- `--exec` in Phase 6's `watch` mode is a foot-gun — entry text is piped to user-supplied commands. Document the trust model clearly.
- The `/tmp/` copies are world-readable on default macOS settings. We should `chmod 600` them after copy. (TODO.)
