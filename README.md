# everlog

An unofficial command-line interface for [Everlog](https://everlog.app/) (Hummingbird, by Wonderbit) — the macOS / iOS / iPadOS journaling app.

> Everlog has no official CLI. This project fills that gap with a fast, native Swift tool: read your entries from the terminal, query them like a database, pipe them through other tools, and (in Phase 2) write new entries from any script.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE) ![Swift 5.10+](https://img.shields.io/badge/swift-5.10+-orange.svg) ![macOS 13+](https://img.shields.io/badge/macOS-13+-lightgrey.svg)

## What works today (read MVP)

```bash
everlog journals                              # list journals with entry counts
everlog tags                                  # list tags with usage counts
everlog show Mindset                          # 10 most recent entries in a journal
everlog show Mindset 50                       # last 50 entries
everlog search "vancouver"                    # full-text search
everlog search "win" --tag wins               # search restricted to a tag
everlog search "morning" --journal Mindset    # search restricted to a journal
everlog read <identifier>                     # full text of one entry (UUID prefix OK)
everlog on-this-day                           # this day-of-year across all years
everlog random                                # one random entry, for reflection
everlog random --journal Fitness              # random scoped to a journal
```

Every subcommand accepts `--json` for machine-readable output.

## What's planned

| Phase | Feature | Status |
|---|---|---|
| **1. Read MVP** | journals · tags · show · search · read · on-this-day · random · `--json` everywhere | ✅ |
| **2. Writes** | `new` (journal, title, date, tags, bookmark, stdin) · `append` · `attach` · `bookmark` · `trash` — headless CoreData, no Shortcuts | ✅ |
| **3. Image attachments** | `-i/--image` on `new`, `attach` for existing entries; blobs land in the AttachmentData store with thumbnails | ✅ |
| **4. Statistics** | `everlog stats` — word counts, streaks, frequency by tag/journal; date-range filters | ⬜ |
| **5. Export** | `everlog export --format markdown`; JSON | ✅ |
| **6. Distribution** | Homebrew tap, signed + notarized binary via Developer ID, GitHub Releases | ⬜ |
| **7. Watch mode** | `everlog watch` — tail new entries as NDJSON | ✅ |

See [PROJECT_PLAN.md](PROJECT_PLAN.md) for the full roadmap.

## Writing entries

```bash
everlog new "Grateful for the quiet morning" -j Mindset --tag wins
everlog new -j Cashflow --title "August books" --date 2026-08-01 - < notes.md
everlog new "Sunset at the seawall" -j Leisure -i sunset.jpg -i seawall.jpg
everlog append 8556DCCA "One more thought before bed."
everlog attach 8556DCCA screenshot.png
everlog bookmark 8556DCCA
everlog bookmark 8556DCCA 4B006A86 --off
everlog trash 8556DCCA
```

Everything is headless — no Shortcuts, no app activation, no prompts. A
timestamped backup of both stores is written to `~/.everlog-cli/backups/`
before every write session (newest five kept).

## How it works

Everlog stores its data in a SQLite database inside the app group container:

```
~/Library/Group Containers/group.hummingbird/Hummingbird.sqlite
```

**Reads:** the CLI copies this file to `/tmp/everlog-ro.sqlite` (to avoid WAL conflicts with the running app) and queries it read-only. No private APIs, no app activation, no permission prompts — entirely transparent to Everlog itself.

**Writes:** the CLI loads Everlog's own compiled CoreData model (`Hummingbird.momd`) straight out of the app bundle and saves through `NSPersistentStoreCoordinator` with persistent-history tracking — the same multi-process pattern Everlog's widget and share extensions use. Each save is recorded as a history transaction (author `everlog-cli`) that the app's CloudKit mirror exports like any other local edit, so sync stays intact. Writes never touch the SQLite directly, and the CLI refuses to open a store whose schema doesn't match the installed app (no auto-migration — that's the app's job).

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full schema reference and design decisions.

## Install

**Not yet published.** Install from source during development:

```bash
git clone https://github.com/rodchristiansen/everlog-journal-cli ~/Developer/GitHub/tools/everlog-journal-cli
cd ~/Developer/GitHub/tools/everlog-journal-cli
swift build -c release
ln -sf "$(pwd)/.build/release/everlog" /usr/local/bin/everlog
```

Then `everlog journals` from anywhere.

Planned for v1.0 (Phase 6):

```bash
brew tap rodchristiansen/tools
brew install everlog
```

## Requirements

- **macOS 13+** (Everlog itself is macOS / iOS only — iCloud-synced data is accessible on any Mac that has Everlog installed and signed in).
- **Swift 5.10+** toolchain for building from source. Xcode Command Line Tools provide this:
  ```bash
  xcode-select --install
  ```
- **Everlog installed at least once**, with iCloud sync completed (so the local SQLite exists).

No third-party language runtimes, no Python, no Node. Single signed binary in the release distribution.

## Status

🟢 **Functional.** Reads and writes are implemented and tested against a 3000+-entry production database (reads via snapshot SQLite, writes via the app's own CoreData model — see above). Distribution channel (Phase 6) is not yet set up — install from source.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and PRs welcome — particularly for:

- Schema column annotation (which `Z*` fields mean what — see [docs/schema.md](docs/schema.md))
- Cross-version compatibility (testing against older Everlog versions; reporting `Z_METADATA.Z_VERSION`)
- Write-path hardening across Everlog updates (see [docs/write-path.md](docs/write-path.md))

## License

[MIT](LICENSE). Unofficial — not affiliated with Wonderbit.
