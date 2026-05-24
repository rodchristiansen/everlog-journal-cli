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
| **2. Write bridge** | `everlog new <journal> "text"` via Everlog Shortcuts (`Create Entry`); attachment support; tag input | 🟡 stub |
| **3. Direct AppIntents** | Skip the `shortcuts` CLI and invoke `co.wonderbit.Hummingbird.CreateEntryIntent` natively from Swift | ⬜ |
| **4. Statistics** | `everlog stats` — word counts, streaks, frequency by tag/journal; date-range filters | ⬜ |
| **5. Export** | `everlog export --format markdown` (Day-One-style); JSON / CSV / NDJSON | ⬜ |
| **6. Distribution** | Homebrew tap, signed + notarized binary via Developer ID, GitHub Releases | ⬜ |
| **7. Watch mode** | `everlog watch --exec "<cmd>"` — tail-like over the SQLite WAL for live events | ⬜ |
| **8. Read-side Shortcuts compatibility** | `--use-shortcuts` flag falls back to Everlog's `Find Entries` / `Search Entries` actions instead of SQLite, for officially-supported reads | ⬜ |

See [PROJECT_PLAN.md](PROJECT_PLAN.md) for the full roadmap.

## How it works

Everlog stores its data in a SQLite database inside the app group container:

```
~/Library/Group Containers/group.hummingbird/Hummingbird.sqlite
```

The CLI copies this file to `/tmp/everlog-ro.sqlite` (to avoid WAL conflicts with the running app) and queries it read-only. No private APIs, no app activation, no permission prompts — entirely transparent to Everlog itself.

For write operations (Phase 2), the CLI will wrap Everlog's existing Shortcuts actions (`Create Entry`, `Append Text to Entry`, etc.) via the macOS `shortcuts` command, then progress (Phase 3) to invoking the underlying AppIntents directly from Swift.

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

🟡 **Early development.** Read MVP is functional and tested against a 3060-entry production database. Write side (Phase 2) is stubbed. Distribution channel (Phase 6) is not yet set up — install from source.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and PRs welcome — particularly for:

- Schema column annotation (which `Z*` fields mean what — see [docs/schema.md](docs/schema.md))
- Everlog Shortcuts action reverse-engineering (for the write bridge — see [docs/shortcuts.md](docs/shortcuts.md))
- Cross-version compatibility (testing against older Everlog versions; reporting `Z_METADATA.Z_VERSION`)
- AppIntents direct-binding research for Phase 3

## License

[MIT](LICENSE). Unofficial — not affiliated with Wonderbit.
