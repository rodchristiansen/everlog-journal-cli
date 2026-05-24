"""Click-based CLI entry point.

`--json` is available on every subcommand for ergonomic use:

    everlog journals --json
    everlog show Mindset 5 --json
"""

from __future__ import annotations

import click

from everlog import __version__, db, output


def json_flag(f):
    """Reusable --json option decorator."""
    return click.option("--json", "as_json", is_flag=True, help="Emit JSON output.")(f)


@click.group()
@click.version_option(__version__, prog_name="everlog")
def main() -> None:
    """Unofficial CLI for the Everlog (Hummingbird) journaling app."""


@main.command()
@json_flag
def journals(as_json: bool) -> None:
    """List journals with entry counts."""
    with db.connect() as conn:
        rows = db.list_journals(conn)
    output.emit(rows, kind="journals", as_json=as_json)


@main.command()
@json_flag
def tags(as_json: bool) -> None:
    """List tags with usage counts."""
    with db.connect() as conn:
        rows = db.list_tags(conn)
    output.emit(rows, kind="tags", as_json=as_json)


@main.command()
@click.argument("journal")
@click.argument("limit", type=int, default=10, required=False)
@json_flag
def show(journal: str, limit: int, as_json: bool) -> None:
    """Show recent entries in a journal (default 10)."""
    with db.connect() as conn:
        rows = db.show_journal(conn, journal, limit)
    output.emit(rows, kind="show", as_json=as_json)


@main.command()
@click.argument("query")
@click.option("--journal", "journal", default=None, help="Restrict to one journal.")
@click.option("--tag", "tag", default=None, help="Restrict to entries with this tag.")
@click.argument("limit", type=int, default=20, required=False)
@json_flag
def search(
    query: str,
    journal: str | None,
    tag: str | None,
    limit: int,
    as_json: bool,
) -> None:
    """Full-text search across entries."""
    with db.connect() as conn:
        rows = db.search_entries(conn, query, journal=journal, tag=tag, limit=limit)
    output.emit(rows, kind="search", as_json=as_json)


@main.command()
@click.argument("identifier")
@json_flag
def read(identifier: str, as_json: bool) -> None:
    """Read the full text of one entry by identifier (UUID prefix OK)."""
    with db.connect() as conn:
        entry = db.read_entry(conn, identifier)
    if not entry:
        raise click.ClickException(f"no entry with identifier {identifier}")
    output.emit(entry, kind="read", as_json=as_json)


@main.command(name="on-this-day")
@json_flag
def on_this_day(as_json: bool) -> None:
    """Entries from this day-of-year across all years."""
    with db.connect() as conn:
        rows = db.on_this_day(conn)
    output.emit(rows, kind="on-this-day", as_json=as_json)


@main.command()
@click.option("--journal", "journal", default=None, help="Restrict to one journal.")
@json_flag
def random(journal: str | None, as_json: bool) -> None:
    """Return one random entry, useful for reflection."""
    with db.connect() as conn:
        entry = db.random_entry(conn, journal)
    output.emit(entry, kind="random", as_json=as_json)


# ---- write-bridge subcommands (Phase 2 — stubs) ----------------------------


@main.command(name="new")
@click.argument("journal_name")
@click.argument("text")
def new_entry(journal_name: str, text: str) -> None:
    """Create a new entry via Everlog Shortcuts (Phase 2 — not yet implemented)."""
    raise click.ClickException(
        "Write bridge (Phase 2) not yet implemented. "
        "Will wrap `shortcuts run 'Create Entry'`. See PROJECT_PLAN.md."
    )


@main.command(name="append")
@click.argument("identifier")
@click.argument("text")
def append_entry(identifier: str, text: str) -> None:
    """Append text to an existing entry (Phase 2 — not yet implemented)."""
    raise click.ClickException(
        "Write bridge (Phase 2) not yet implemented. "
        "Will wrap `shortcuts run 'Append Text to Entry'`. See PROJECT_PLAN.md."
    )


if __name__ == "__main__":
    main()
