# Project plan — everlog CLI

## Why this exists

Everlog is the journaling app of record for users who outgrew Apple Journal (no custom dates, no read API, no tags, no multi-journal organization). It has:

- A rich Shortcuts catalog (read + write actions).
- Custom dates, tags, locations, weather, attachments, templates, prompts.
- 11+ journals per user, mapping cleanly to life-category structures.
- iCloud sync that puts the same data on every Mac/iPad/iPhone.
- A queryable local SQLite database (read access without going through the app).

It does **not** have an official command-line interface. Power users who script their lives want one for:

- "What did I write about X in Year Y?"
- Cron jobs that capture daily data into Everlog.
- Bulk operations (re-tagging, exports, statistics).
- Cross-tool integration (write a journal entry from any script).
- LLM agents that can read journal context to inform decisions.

The macOS Shortcuts CLI is one path but clunky for query-heavy work (each call is a separate app invocation; no piping). Direct SQLite is faster, scriptable, and pure-CLI-ergonomic.

## Why Swift

Native to the platform Everlog runs on. Single signed binary distribution via Homebrew. No language runtime dependency for end users. Direct interop with macOS frameworks (AppIntents, EventKit, etc.) for future native-write integration. Matches the rest of Rod's Apple-ecosystem tooling (`fsutil`, signing infrastructure, hardened runtime).

The system `sqlite3` library is linked directly — no third-party DB wrapper. `swift-argument-parser` is the only dependency, and it's first-party Apple.

## Design principles

1. **SQLite for read, Shortcuts/AppIntents for write.** Read is fast, local, and synchronous. Write goes through Everlog's supported integration so we never corrupt the user's data.
2. **Read-only safe.** Always snapshot the live DB to `/tmp/` (with WAL + SHM sidecars) before querying — avoids lock contention with the running app.
3. **No app activation.** Read operations must never bring Everlog.app to the foreground. Write operations may briefly, only if the underlying integration requires it.
4. **Stable output for piping.** `--json` on every subcommand. Output formats are versioned in `Models.swift`.
5. **macOS-only is fine.** Everlog is macOS/iOS only — no cross-platform burden.
6. **Small surface, deep operations.** A dozen well-chosen subcommands beat fifty wrappers.
7. **Schema is internal but documented.** Treat Wonderbit's schema as semi-stable; pin to versions we've tested; document the assumed shape in [docs/schema.md](docs/schema.md).
8. **Single binary distribution.** No language runtime install required for users. Build once, distribute via brew.

## Phases

### Phase 1 — Read MVP ✅

Subcommands: `journals`, `tags`, `show <journal> [N]`, `search <query> [--journal] [--tag] [N]`, `read <identifier>`, `on-this-day`, `random [--journal]`. `--json` on all.

Verified against a 3060-entry production database. UUID-prefix matching on `read` (like git short SHAs).

Implementation in `Sources/everlog/Commands.swift` (CLI surfaces), `DB.swift` (SQLite layer), `Models.swift` (`Codable` structs), `Output.swift` (plain + JSON formatters).

### Phase 2 — Write bridge via `shortcuts` CLI

Subcommands:

- `everlog new <journal> "text" [--tags a,b,c] [--date ISO] [--lat X --lng Y]`
- `everlog append <identifier> "text"`
- `everlog tag-add <identifier> <tag>` / `tag-remove <identifier> <tag>`
- `everlog bookmark <identifier> [--unset]`
- `everlog import --from <file>` — bulk import from Day One JSON / Markdown / Everlog's own export ZIP

Implementation:

- Ship pre-authored helper Shortcuts (`Everlog CLI: New Entry`, etc.) as `.shortcut` files in `Sources/everlog/Resources/`.
- First-run install: `everlog install-shortcuts` imports them via `open` on each .shortcut file.
- Each write call serializes args to JSON and runs `shortcuts run "<helper>" --input <json>`.
- Helper Shortcuts call Everlog's underlying AppIntents (`co.wonderbit.Hummingbird.CreateEntryIntent`, etc.).

### Phase 3 — Make the write path feel native

The original Phase 3 plan was "skip the `shortcuts` CLI by calling Wonderbit's `AppIntent` types directly." Empirical inspection of `Everlog.app` (see [docs/phase3-research.md](docs/phase3-research.md)) confirms that path is blocked at the macOS platform level: Apple's public API has no cross-process AppIntents invocation entry point, and ExtensionKit doesn't expose a way to connect to `EverlogIntents.appex` directly. The good news is that Wonderbit's write intents (`CreateEntryIntent`, `AddCommentIntent`, `AddToEntryAppIntent`, `BookmarkEntryAppIntent`, `TrashEntryAppIntent`) are all background-capable (`openAppWhenRun=false`), so they dispatch through the intents extension without bringing the app forward.

Revised scope:

- **3a — Optimize the `shortcuts run` path.** Warm-start helper shortcuts, batch multi-write operations through a single dispatcher shortcut, fire-and-forget for callers that don't need a return value.
- **3b — Register `everlog` itself as an AppIntents provider.** Declare our own `AppIntent` types so Shortcuts/Siri/Spotlight can compose our CLI alongside Everlog's intents.
- **3c — Advocate to Wonderbit for write-capable `everlog://` URLs** (e.g. `everlog://new?journal=X&text=...`). Independent of our roadmap; would let any tool skip the Shortcuts dispatcher.

### Phase 4 — Statistics & date filtering

- `everlog stats` — total entries, words, days written, streak.
- `everlog stats --journal X` / `--tag Y`.
- `everlog stats --year YYYY` / `--from DATE --to DATE`.
- `everlog streak` — current writing streak.
- Add `--from` / `--to` to all read commands.

### Phase 5 — Export

- `everlog export --format markdown --to <dir>` — one .md file per entry, Day-One-style.
- `everlog export --format json --to <file>` — single JSON file.
- `everlog export --format dayone --to <file>` — Day One-compatible JSON.
- Attachments resolved from `AttachmentData.sqlite` and copied alongside the export.

### Phase 6 — Distribution

- Build: `swift build -c release` produces `.build/release/everlog`.
- Sign: `codesign --sign "Developer ID Application: …" --options runtime --entitlements …` for hardened-runtime distribution.
- Notarize via `notarytool` and staple.
- Publish: GitHub Releases with the signed binary attached.
- Homebrew tap: `rodchristiansen/tools/everlog`. Bottle the signed binary.
- CI: GitHub Actions running `swift test` on every PR, building releases on tag.

### Phase 7 — Watch mode

- `everlog watch` — tail-like mode polling the SQLite WAL for new entries; emits NDJSON.
- `everlog watch --exec "<command>"` — run a command per new entry.

Useful for: feeding daily entries into a vector DB, triggering automations on tag matches, mirroring to Markdown.

### Phase 8 — Read-side Shortcuts compatibility

Some users may prefer to read via the supported Everlog Shortcuts (`Find Entries`, `Search Entries`) instead of direct SQLite — for schema-change resilience, or if iCloud sync is incomplete locally.

- `--use-shortcuts` flag on read commands falls back to invoking Everlog's actions via `shortcuts run`.
- Slower (each call spawns Shortcuts.app activity) but officially supported.

## Open design questions

1. **Schema versioning** — how to detect Hummingbird DB schema changes between Everlog updates? `Z_METADATA.Z_VERSION` exists; build a compatibility matrix in [ARCHITECTURE.md](ARCHITECTURE.md).
2. **Attachment access** — `ZATTACHMENTDATA` lives in `AttachmentData.sqlite` (separate file). How to expose binary blobs? Write to temp files? Stream to stdout?
3. **iCloud not-yet-synced state** — what does the local SQLite look like before initial sync completes? Document the failure mode.
4. **Encrypted entries** — Everlog supports per-journal encryption (`ZENCRYPTED*` columns observed). Read access for encrypted entries needs design.
5. **Templates and prompts** — `ZTEMPLATE` and `ZPROMPT` are user-authored structures. Are they worth exposing for read or scriptable write?
6. **Performance at scale** — 3060 entries query fast. What about 30,000? Index strategy if `ZTEXT LIKE` becomes slow?

## Non-goals

- Cross-platform support (Linux/Windows). Everlog is macOS/iOS only.
- Write-side direct SQLite mutations. Always go through the supported integration to keep Everlog as the source of truth.
- Replacing the Everlog app. This is a complementary CLI for power users and automation, not a replacement UI.
- iOS Shortcuts integration. Mac-only CLI; iOS users already have the rich Shortcuts catalog inside the Everlog app.

## Source of truth for schema

The schema is reverse-engineered from a production database. Wonderbit has not published an official schema. See [docs/schema.md](docs/schema.md) for column-by-column annotations.

The CLI should fail loudly (not silently) when schema assumptions don't hold — preferable to detect a missing column at startup and prompt the user to file an issue than to return wrong data.

## Versioning

[Semver](https://semver.org/):

- 0.x while the schema is being verified across Everlog versions.
- 1.0 when Phase 1–3 are complete and stable across at least three Everlog releases.

## Contribution invitations

When the read MVP is published, open issues for:

- **Everlog Shortcuts catalog audit** — decode and document each Shortcut action's parameter shape.
- **Schema annotation contributions** — column-by-column meaning, especially for the CloudKit sync tables we currently ignore.
- **Day One JSON importer** — for users migrating *into* Everlog.
- **Vector DB / LLM ingest examples** — sample integrations.
- **AppIntents direct-binding research** (Phase 3) — what entitlements are required to fire Wonderbit's intents from a third-party binary?
