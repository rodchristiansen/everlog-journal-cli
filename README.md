# everlog

An unofficial command-line interface for [Everlog](https://everlog.app/) (Hummingbird, by Wonderbit) — the macOS / iOS / iPadOS journaling app.

> Everlog has no official CLI. This project fills that gap with a fast, scriptable interface to your journal entries: read your entries from the terminal, query them like a database, and (eventually) write new entries from automation pipelines.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE) ![Python 3.10+](https://img.shields.io/badge/python-3.10+-blue.svg) ![macOS](https://img.shields.io/badge/macOS-only-lightgrey.svg)

## What works today (read MVP)

```bash
everlog journals                              # list journals with entry counts
everlog tags                                  # list tags with usage counts
everlog show Mindset                          # 10 most recent entries in a journal
everlog show Mindset 50                       # last 50 entries
everlog search "vancouver"                    # full-text search
everlog search "win" --tag wins               # search restricted to a tag
everlog search "morning" --journal Mindset    # search restricted to a journal
everlog read <identifier>                     # full text of one entry
everlog on-this-day                           # this day-of-year across all years
everlog random                                # one random entry, for reflection
everlog random --journal Fitness              # random scoped to a journal
```

Every command accepts `--json` for machine-readable output.

## What's planned

| Phase | Feature | Status |
|---|---|---|
| **1. Read MVP** | journals · tags · show · search · read · on-this-day · random · JSON output | ✅ initial |
| **2. Write bridge** | `everlog new <journal> "text"` via Everlog Shortcuts (`Create Entry`); attachment support; tag input | 🟡 stub |
| **3. Statistics** | `everlog stats` — word counts, streaks, frequency by tag/journal; date-range filtering everywhere | ⬜ |
| **4. Export** | `everlog export --format markdown` for Day-One-style import elsewhere; `--filter` by date/journal/tag | ⬜ |
| **5. Distribution** | Homebrew tap, pipx, GitHub releases, signed binary (PyInstaller / Briefcase) | ⬜ |
| **6. iCloud follow-mode** | Live-watch the SQLite WAL for new entries; emit events to a webhook/script | ⬜ |
| **7. Read-side Shortcuts compatibility** | `--use-shortcuts` flag to source data via Everlog's `Find Entries`/`Search Entries` actions instead of SQLite, for users who prefer the supported integration | ⬜ |

See [PROJECT_PLAN.md](PROJECT_PLAN.md) for the full roadmap.

## How it works (briefly)

Everlog stores its data in a SQLite database inside the app group container at:

```
~/Library/Group Containers/group.hummingbird/Hummingbird.sqlite
```

The CLI copies this file to `/tmp/` (to avoid WAL conflicts with the running app) and queries it read-only. No private APIs, no app activation, no permission prompts — entirely transparent to Everlog itself.

For write operations (Phase 2), the CLI will wrap Everlog's existing Shortcuts actions (`Create Entry`, `Append Text to Entry`, etc.) via the macOS `shortcuts` command-line tool.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full schema reference and design decisions.

## Install

**Not yet published.** Install from source during development:

```bash
git clone https://github.com/rodchristiansen/everlog-journal-cli ~/Developer/GitHub/tools/everlog-journal-cli
cd ~/Developer/GitHub/tools/everlog-journal-cli
pipx install --editable .
```

Then `everlog journals` from anywhere.

Planned for v1.0:

```bash
brew tap rodchristiansen/tools
brew install everlog
```

## Requirements

- **macOS** (Everlog is macOS / iOS only; iCloud-synced data is accessible on any Mac that has Everlog installed and signed in).
- Python 3.10 or newer.
- Everlog installed at least once, with sync completed (so the local SQLite exists).

## Status

🟡 **Early development.** Read MVP is functional. The schema reference is verified against a 3060-entry production database. Write side is stubbed pending Phase 2.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and PRs welcome — particularly for:

- Schema column documentation (which fields mean what)
- Shortcuts action reverse-engineering (for write bridge)
- Cross-version compatibility (older Everlog versions)
- Output format additions (CSV, JSON Lines, Markdown)

## License

[MIT](LICENSE). Unofficial — not affiliated with Wonderbit.
