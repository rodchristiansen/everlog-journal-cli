# Contributing to everlog

Thanks for being interested. This is an early-stage project — every contribution moves it forward.

## What kind of help is most useful right now

In rough priority order:

1. **Schema annotation.** The Hummingbird SQLite schema is reverse-engineered. `docs/schema.md` documents what we've figured out, but many columns are unannotated. If you know what `ZTOUCH` or `ZAPP` or any `ZMIGRATEDCONTENT` field does, please file an issue or PR.

2. **Cross-version testing.** Run the CLI against your Everlog database and report the `Z_METADATA.Z_VERSION` value along with any schema errors. This builds out the compatibility matrix in `ARCHITECTURE.md`.

3. **Shortcuts action decoding.** Everlog's Shortcuts actions are AppIntent-backed. Use [Shortcuts Playground](https://github.com/viticci/shortcuts-playground-plugin) or the `sc-dump` pattern (decode signed `.shortcut` files to plist) to document each action's input/output shape. We need this for Phase 2 (write bridge).

4. **Output format additions.** CSV, JSON Lines, Markdown bundles. The `output.py` module is where these go.

5. **Issue triage.** Reading existing issues, reproducing, narrowing scope.

## Setting up a dev environment

```bash
git clone <fork-url> everlog-journal-cli
cd everlog-journal-cli
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

Run the test suite:

```bash
pytest tests/
```

Run linters:

```bash
ruff check src/ tests/
```

## Running against your own data

The CLI reads from `~/Library/Group Containers/group.hummingbird/Hummingbird.sqlite`. As long as you have Everlog installed and synced once on this Mac, every command "just works":

```bash
python -m everlog journals
```

For testing against a known-state database, point `EVERLOG_DB` to a copy:

```bash
EVERLOG_DB=/tmp/test-db.sqlite python -m everlog journals
```

## Commit conventions

Conventional-ish, low ceremony:

- `feat:` — new subcommand or feature.
- `fix:` — bug fix.
- `docs:` — docs only.
- `refactor:` — internal change with no user-visible effect.
- `test:` — adding or fixing tests.
- `chore:` — tooling, dependency bumps, etc.

Body: explain *why*, not *what*. The diff shows what.

## PR checklist

- [ ] Tests pass (`pytest`).
- [ ] Lint clean (`ruff check`).
- [ ] If you touched the schema layer, manually verified against your real Everlog database.
- [ ] If you added a subcommand, updated `README.md` and `PROJECT_PLAN.md`.
- [ ] If you touched Shortcuts integration, documented the action's input/output in `docs/shortcuts.md`.

## Code of conduct

Be kind. Don't be a jerk in issues or PRs. We're all here because we journal and we want better tools.

## Licensing

By contributing you agree your contributions are licensed under [MIT](LICENSE), the same as the rest of the project.

## Related projects

- [Everlog](https://everlog.app/) — the app this CLI integrates with.
- [Shortcuts Playground](https://github.com/viticci/shortcuts-playground-plugin) — for building/debugging the Shortcuts we wrap.
- [reminders-cli](https://github.com/keith/reminders-cli) — similar pattern (CLI over Apple-app data via private/internal access). Good architectural reference.
