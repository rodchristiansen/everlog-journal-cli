# Project plan — everlog CLI

## Why this exists

Everlog is the journaling app of record for power users who outgrew Apple Journal (no custom dates, no read API, no tags, no multi-journal organization). It has:

- A rich Shortcuts catalog (read + write actions).
- Custom dates, tags, locations, weather, attachments, templates, prompts.
- 11+ journals per user, mapping cleanly to life-category structures.
- iCloud sync that puts the same data on every Mac/iPad/iPhone.
- A queryable local SQLite database.

It does **not** have an official command-line interface. Power users who script their lives (rod, this is you) want one:

- "What did I write about X in Year Y?"
- Cron jobs that capture daily data into Everlog.
- Bulk operations (re-tagging, exports, statistics).
- Cross-tool integration (write a journal entry from any script).
- LLM agents that can read journal context to inform decisions.

The macOS Shortcuts CLI is one path but it's clunky for query-heavy work (every call is a separate app invocation; no piping). Direct SQLite is faster, scriptable, and pure-CLI-ergonomic.

## Design principles

1. **SQLite for read, Shortcuts for write.** Read is fast and local; write goes through the supported integration so we never corrupt the user's data.
2. **Read-only safe.** Always copy the live DB to `/tmp/` before querying to avoid WAL/lock conflicts with the running app.
3. **No app activation.** Read operations should never bring Everlog.app to the foreground. Write operations may, briefly, only if the underlying Shortcut requires it.
4. **Stable output for piping.** `--json` on every subcommand. Newline-delimited JSON (NDJSON) for streaming where useful.
5. **macOS-only is fine.** Everlog is macOS/iOS only — no cross-platform burden. Use macOS-specific facilities (Shortcuts CLI, `mdfind`, AppleScript fallbacks) where they help.
6. **Small surface, deep operations.** A dozen well-chosen subcommands beat fifty wrappers.
7. **Schema is internal but documented.** Treat Wonderbit's schema as semi-stable; pin to versions we've tested; document the assumed shape in `docs/schema.md`.

## Phases

### Phase 1 — Read MVP ✅ (initial)

Subcommands:

- `everlog journals` — list journals with entry counts. Sort by count descending.
- `everlog tags` — list tags with usage counts.
- `everlog show <journal> [N]` — last N entries in a journal (default 10).
- `everlog search <query> [--journal X] [--tag Y] [N]` — text search with optional filters.
- `everlog read <identifier>` — full text of one entry, including tags, location, weather.
- `everlog on-this-day` — entries from this day-of-year across all years.
- `everlog random [--journal X]` — one random entry for reflection.
- `--json` flag on all.

Done? Verified against Rod's 3060-entry database. Initial Python implementation in `src/everlog/`.

### Phase 2 — Write bridge

Subcommands:

- `everlog new <journal> "text" [--tags a,b,c] [--date ISO] [--location lat,lng]` — create entry via Everlog's `Create Entry` Shortcut.
- `everlog append <identifier> "text"` — append to an existing entry via `Append Text to Entry`.
- `everlog tag add <identifier> <tag>` / `everlog tag remove <identifier> <tag>`.
- `everlog bookmark <identifier> [--unset]` — toggle bookmark via `Set Bookmark of Entry`.
- `everlog import --from <file>` — bulk import from Day One JSON / Markdown / Everlog's own export ZIP.

Implementation notes:
- Wrap `shortcuts run "<name>" --input <json>` for each operation.
- The CLI should detect missing required Shortcuts on first run and offer to install them (ship signed `.shortcut` files in `everlog/shortcuts/`).
- Audit Everlog's Shortcuts catalog (decode the actual action plists) to confirm input/output shapes.

### Phase 3 — Statistics & date filtering

- `everlog stats` — overall stats (entries, words, days written, streaks).
- `everlog stats --journal X` / `everlog stats --tag Y`.
- `everlog stats --year 2025` — date-range filtering.
- `everlog streak` — current writing streak.
- Add `--from DATE --to DATE` to all read commands.

### Phase 4 — Export

- `everlog export --format markdown` — one .md file per entry (Day-One-style).
- `everlog export --format json` — single JSON file with all entries.
- `everlog export --format dayone` — Day One-compatible JSON (for migrators going the other way).
- `everlog export --bundle <dir>` — directory tree organized by journal/year/month.
- Attachments resolved and copied alongside the export.

### Phase 5 — Distribution

- **Homebrew tap** at `rodchristiansen/tools/everlog`.
- **pipx** install path documented and tested.
- **GitHub Releases** with versioned tarballs.
- Optional: **PyInstaller** signed binary for users who don't want Python.
- CI: GitHub Actions running tests on every PR, build on tag.

### Phase 6 — iCloud follow mode

- `everlog watch` — tail-like mode that polls the SQLite WAL and emits NDJSON events on new entries.
- `--exec "<command>"` — run a command per new entry (for webhooks, LLM ingestion, etc.).
- Useful for: piping daily entries into a vector DB, triggering automations on certain tags, mirroring to Markdown.

### Phase 7 — Read-side Shortcuts compatibility

Some users may prefer to read via the supported Everlog Shortcuts (`Find Entries`, `Search Entries`) instead of direct SQLite — for example if Wonderbit changes the schema or if iCloud sync hasn't completed locally.

- `--use-shortcuts` flag falls back to invoking Everlog's actions via `shortcuts run`.
- Slower but officially supported.

## Open design questions

1. **Schema versioning** — how to detect Hummingbird DB schema changes between Everlog updates and warn the user before queries fail.
2. **Attachment access** — `ZATTACHMENTDATA` is in a separate SQLite (`AttachmentData.sqlite`). How to expose binary blobs? Write to temp files? Stream to stdout?
3. **iCloud not-yet-synced state** — what does the local SQLite look like before sync completes? Document the failure mode.
4. **Encrypted entries** — Everlog supports per-journal encryption (`ZENCRYPTEDNAME`, `ZENCRYPTEDLATITUDE` columns visible). How to handle entries the user has encrypted at rest?
5. **Templates and prompts** — `ZTEMPLATE` and `ZPROMPT` are user-authored structures. Are they worth exposing for read or scriptable write?
6. **Performance at scale** — 3060 entries queries fast. What about 30,000? Index strategy?

## Non-goals

- Cross-platform support (Linux/Windows). Everlog is macOS/iOS only.
- Write-side direct SQLite mutations. Always go through Shortcuts to keep Everlog as the source of truth.
- Replacing the Everlog app. This is a complementary CLI for power-users and automation, not a replacement UI.
- iOS Shortcuts integration. Mac-only CLI; iOS users already have the rich Shortcuts catalog inside the Everlog app.

## Source of truth for schema

The schema is reverse-engineered from a production database. Wonderbit has not published an official schema. See `docs/schema.md` for column-by-column annotations.

The CLI should fail gracefully (not silently) when schema assumptions don't hold — preferable to detect a missing column at startup and prompt the user to file an issue than to return wrong data.

## Versioning

[Semver](https://semver.org/):

- 0.x while the schema is still being verified across Everlog versions.
- 1.0 when Phase 1–3 are complete and stable across at least 3 Everlog releases.

## Contribution invitations

When the read MVP is solid, open issues for:

- "Everlog Shortcuts catalog audit" — decode and document each Shortcut action.
- "Schema annotation contributions" — column-by-column meaning, especially for the CloudKit sync tables we currently ignore.
- "Day One JSON importer" — for users migrating *into* Everlog.
- "Vector DB / LLM ingest examples" — sample integrations.
