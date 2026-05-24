"""Write bridge — wraps Everlog Shortcuts via the macOS `shortcuts` CLI.

PHASE 2 — STUB.

When implemented this module will:

1. Detect whether the helper Shortcuts (`Everlog CLI: New Entry`, etc.) are
   installed in the user's Shortcuts library. If not, offer to install them
   (signed .shortcut files shipped alongside this package).
2. Provide functions like `create_entry(journal, text, tags, ...)` that
   serialize arguments to JSON and call `shortcuts run "<name>" --input <json>`.
3. Parse stdout from the helper Shortcut to return the created entry's
   identifier so the caller can chain operations.

See PROJECT_PLAN.md Phase 2 and ARCHITECTURE.md "Write side (Phase 2)" for
the full design.
"""

from __future__ import annotations


class NotImplementedYetError(NotImplementedError):
    """Raised by write-bridge stubs until Phase 2 lands."""


def create_entry(
    journal: str,
    text: str,
    *,
    tags: list[str] | None = None,
    date: str | None = None,
    location: tuple[float, float] | None = None,
) -> str:
    raise NotImplementedYetError(
        "everlog.shortcuts.create_entry: Phase 2 — wraps `shortcuts run 'Create Entry'`."
    )


def append_to_entry(identifier: str, text: str) -> None:
    raise NotImplementedYetError(
        "everlog.shortcuts.append_to_entry: Phase 2 — wraps `shortcuts run 'Append Text to Entry'`."
    )


def set_bookmark(identifier: str, *, bookmarked: bool) -> None:
    raise NotImplementedYetError(
        "everlog.shortcuts.set_bookmark: Phase 2 — wraps `shortcuts run 'Set Bookmark of Entry'`."
    )
