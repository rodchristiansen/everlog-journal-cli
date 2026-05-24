"""Output formatters: human-readable (with rich if available) and JSON."""

from __future__ import annotations

import json
from typing import Any

try:
    from rich.console import Console
    from rich.table import Table

    _console = Console()
    _HAS_RICH = True
except ImportError:
    Console = None  # type: ignore[assignment, misc]
    Table = None  # type: ignore[assignment, misc]
    _console = None
    _HAS_RICH = False


def _has_rich() -> bool:
    return _HAS_RICH


def emit(data: Any, *, kind: str, as_json: bool) -> None:
    if as_json:
        print(json.dumps(data, indent=2, default=str))
        return
    if data is None:
        print("(no result)")
        return
    if kind == "journals":
        _print_journals(data)
    elif kind == "tags":
        _print_tags(data)
    elif kind in ("show", "search", "on-this-day"):
        _print_entries(data)
    elif kind == "read":
        _print_entry(data)
    elif kind == "random":
        _print_entries([data])


def _print_journals(rows: list[dict]) -> None:
    if _has_rich():
        assert _console is not None and Table is not None
        table = Table(show_header=True, header_style="bold")
        table.add_column("Journal")
        table.add_column("Entries", justify="right")
        for r in rows:
            table.add_row(r["name"], str(r["count"]))
        _console.print(table)
    else:
        for r in rows:
            print(f"  {r['name']:14s} {r['count']:5d}")


def _print_tags(rows: list[dict]) -> None:
    if _has_rich():
        assert _console is not None and Table is not None
        table = Table(show_header=True, header_style="bold")
        table.add_column("Tag")
        table.add_column("Uses", justify="right")
        for r in rows:
            table.add_row(f"#{r['name']}", str(r["count"]))
        _console.print(table)
    else:
        for r in rows:
            print(f"  #{r['name']:14s} {r['count']:5d}")


def _print_entries(rows: list[dict]) -> None:
    for r in rows:
        wc = f" · {r['wordcount']}w" if r.get("wordcount") else ""
        if _has_rich():
            assert _console is not None
            _console.print(
                f"\n[bold cyan]{r['date'][:10]}[/]  "
                f"[green]{r['journal']}[/]{wc}  "
                f"[dim]({r['identifier'][:8]})[/]"
            )
        else:
            print(f"\n  {r['date'][:10]} · {r['journal']}{wc}  ({r['identifier'][:8]})")
        preview = (r.get("preview") or "").replace("\n", " ")[:160]
        print(f"  {preview}")


def _print_entry(entry: dict) -> None:
    if _has_rich():
        assert _console is not None
        _console.rule(entry["date"][:19])
    else:
        print(f"=== {entry['date'][:19]} ===")
    print(f"Journal:   {entry['journal']}")
    print(f"Tags:      {', '.join(entry['tags']) if entry['tags'] else '(none)'}")
    print(f"Wordcount: {entry['wordcount']}")
    if entry.get("location"):
        print(f"Location:  {entry['location']['lat']:.4f}, {entry['location']['lng']:.4f}")
    print()
    print(entry["text"] or "(empty)")
