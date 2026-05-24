# Contributing to everlog

Thanks for being interested. This is an early-stage project — every contribution moves it forward.

## What kind of help is most useful right now

In rough priority order:

1. **Schema annotation.** The Hummingbird SQLite schema is reverse-engineered. [docs/schema.md](docs/schema.md) documents what we've figured out, but many columns are unannotated. If you know what `ZTOUCH`, `ZAPP`, or any `ZMIGRATEDCONTENT` field does, file an issue or PR.

2. **Cross-version testing.** Run the CLI against your Everlog database and report the `Z_METADATA.Z_VERSION` value with any schema errors. This fills out the compatibility matrix in [ARCHITECTURE.md](ARCHITECTURE.md).

3. **Shortcuts action decoding.** Everlog's Shortcuts actions are AppIntent-backed. Use the [Shortcuts Playground plugin](https://github.com/viticci/shortcuts-playground-plugin) to decode signed `.shortcut` files and document each action's input/output shape. Needed for Phase 2 (write bridge).

4. **AppIntents direct-binding research.** Phase 3 wants to skip the `shortcuts` CLI and invoke `co.wonderbit.Hummingbird.CreateEntryIntent` directly via the `AppIntents` framework. Open question: what entitlements does a third-party binary need? Are Wonderbit's intents `AppIntent` or `OpenIntent`?

5. **Output format additions.** CSV, JSON Lines, Markdown bundles. The `Output.swift` module is where these go.

6. **Issue triage** — reading existing issues, reproducing, narrowing scope.

## Setting up a dev environment

Requires the Xcode Command Line Tools (which ship Swift):

```bash
xcode-select --install   # if not already installed
git clone <fork-url> everlog-journal-cli
cd everlog-journal-cli
swift build
```

Run the binary:

```bash
.build/debug/everlog journals
```

Run the test suite:

```bash
swift test
```

For an editable system-wide install during development:

```bash
swift build -c release
ln -sf "$(pwd)/.build/release/everlog" /usr/local/bin/everlog
```

`/usr/local/bin/everlog` will now point at your release build. Rebuild with `swift build -c release` to update.

## Running against your own data

The CLI reads from `~/Library/Group Containers/group.hummingbird/Hummingbird.sqlite`. As long as you have Everlog installed and synced once on this Mac, every command "just works":

```bash
.build/debug/everlog journals
```

For testing against a known-state database (e.g. a copy you've prepared with synthetic data), point `EVERLOG_DB` and `EVERLOG_GROUP_CONTAINER` at it:

```bash
EVERLOG_GROUP_CONTAINER=/path/to/test/dir .build/debug/everlog journals
```

## Code style

- Follow the existing Swift style — see `Sources/everlog/*.swift` for the patterns.
- Prefer `struct` over `class` unless reference semantics are needed (currently only `Statement` for resource cleanup).
- Use `Codable` for all output types (`Models.swift`).
- Keep dependencies minimal — Apple-first packages only.

Run `swift build` cleanly and `swift test` passing before opening a PR.

## Commit conventions

Conventional-ish, low ceremony:

- `feat:` — new subcommand or feature
- `fix:` — bug fix
- `docs:` — docs only
- `refactor:` — internal change with no user-visible effect
- `test:` — adding or fixing tests
- `chore:` — tooling, dependency bumps

Commit body: explain *why*, not *what*. The diff shows what.

## PR checklist

- [ ] `swift build` succeeds cleanly.
- [ ] `swift test` passes.
- [ ] If you touched the schema layer, manually verified against a real Everlog database.
- [ ] If you added a subcommand, updated `README.md` and `PROJECT_PLAN.md`.
- [ ] If you touched Shortcuts integration, documented the action's input/output in [docs/shortcuts.md](docs/shortcuts.md).

## Code of conduct

Be kind. Don't be a jerk in issues or PRs. We're all here because we journal and we want better tools.

## Licensing

By contributing you agree your contributions are licensed under [MIT](LICENSE), same as the rest of the project.

## Related projects

- [Everlog](https://everlog.app/) — the app this CLI integrates with.
- [Shortcuts Playground](https://github.com/viticci/shortcuts-playground-plugin) — for building/debugging the Shortcuts we wrap.
- [keith/reminders-cli](https://github.com/keith/reminders-cli) — same pattern (Swift CLI over Apple-app data). Good architectural reference.
