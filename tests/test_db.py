"""Tests for the db layer. Run only on a Mac with Everlog installed.

These are integration-style smoke tests — they hit the real Hummingbird
SQLite via the snapshot mechanism. Skip silently if the DB is missing
(e.g. on CI without a real Everlog install).
"""

from __future__ import annotations

import pytest

from everlog import db


@pytest.fixture
def conn():
    try:
        with db.connect() as c:
            yield c
    except FileNotFoundError:
        pytest.skip("Hummingbird DB not present on this machine.")


def test_journals_returns_at_least_one(conn):
    rows = db.list_journals(conn)
    assert isinstance(rows, list)
    if rows:
        assert "name" in rows[0]
        assert "count" in rows[0]


def test_tags_returns_list(conn):
    rows = db.list_tags(conn)
    assert isinstance(rows, list)


def test_cocoa_to_iso_handles_none():
    assert db.cocoa_to_iso(None) is None


def test_cocoa_to_iso_converts_epoch():
    # Cocoa epoch == 2001-01-01 UTC
    assert db.cocoa_to_iso(0).startswith("2001-01-01")
