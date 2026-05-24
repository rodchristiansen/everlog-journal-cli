"""SQLite reader for the Hummingbird (Everlog) database.

All operations are read-only. The live DB is copied to /tmp/ before querying
to avoid WAL/lock conflicts with the running Everlog.app.
"""

from __future__ import annotations

import os
import shutil
import sqlite3
from datetime import datetime
from pathlib import Path

# Cocoa reference date offset to Unix epoch (seconds from 2001-01-01 to 1970-01-01)
COCOA_EPOCH = 978_307_200

# Allow override via environment for testing
_DEFAULT_GROUP = Path.home() / "Library/Group Containers/group.hummingbird"
SRC_DIR = Path(os.environ.get("EVERLOG_GROUP_CONTAINER", _DEFAULT_GROUP))
TMP_DB = Path(os.environ.get("EVERLOG_DB", "/tmp/everlog-ro.sqlite"))


class SchemaError(Exception):
    """Raised when the Hummingbird schema doesn't match expectations."""


def snapshot() -> Path:
    """Copy the live SQLite (+ WAL/SHM) to a /tmp/ working copy. Returns the path."""
    src = SRC_DIR / "Hummingbird.sqlite"
    if not src.exists():
        raise FileNotFoundError(
            f"Everlog database not found at {src}. "
            "Is Everlog installed and synced on this Mac?"
        )
    shutil.copy2(src, TMP_DB)
    for ext in ("-wal", "-shm"):
        side = src.with_suffix(f".sqlite{ext}")
        if side.exists():
            shutil.copy2(side, TMP_DB.with_suffix(f".sqlite{ext}"))
    # Tighten perms — entries can be sensitive
    try:
        TMP_DB.chmod(0o600)
    except OSError:
        pass
    return TMP_DB


def connect() -> sqlite3.Connection:
    """Snapshot then open a read-only SQLite connection."""
    snapshot()
    conn = sqlite3.connect(f"file:{TMP_DB}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def cocoa_to_iso(ts: float | None) -> str | None:
    if ts is None:
        return None
    return datetime.utcfromtimestamp(ts + COCOA_EPOCH).isoformat() + "Z"


# ---- queries ----------------------------------------------------------------


def list_journals(conn: sqlite3.Connection) -> list[dict]:
    rows = conn.execute(
        """
        SELECT j.ZNAME AS name, COUNT(e.Z_PK) AS count
        FROM ZJOURNAL j
        LEFT JOIN ZENTRY e ON e.ZJOURNAL = j.Z_PK AND e.ZISTRASHED = 0
        WHERE j.ZISHIDDEN = 0
        GROUP BY j.ZNAME
        ORDER BY count DESC
        """
    ).fetchall()
    return [dict(r) for r in rows]


def list_tags(conn: sqlite3.Connection) -> list[dict]:
    rows = conn.execute(
        """
        SELECT t.ZTITLE AS name, COUNT(j.Z_17ENTRIES1) AS count
        FROM ZTAG t
        LEFT JOIN Z_17TAGS j ON j.Z_22TAGS = t.Z_PK
        GROUP BY t.ZTITLE
        ORDER BY count DESC
        """
    ).fetchall()
    return [dict(r) for r in rows]


def show_journal(conn: sqlite3.Connection, journal: str, limit: int = 10) -> list[dict]:
    rows = conn.execute(
        """
        SELECT e.ZIDENTIFIER AS identifier,
               e.ZDATE AS date,
               j.ZNAME AS journal,
               e.ZWORDCOUNT AS wordcount,
               substr(e.ZTEXT, 1, 200) AS preview
        FROM ZENTRY e
        JOIN ZJOURNAL j ON j.Z_PK = e.ZJOURNAL
        WHERE j.ZNAME = ? AND e.ZISTRASHED = 0
        ORDER BY e.ZDATE DESC
        LIMIT ?
        """,
        (journal, limit),
    ).fetchall()
    return [{**dict(r), "date": cocoa_to_iso(r["date"])} for r in rows]


def search_entries(
    conn: sqlite3.Connection,
    query: str,
    *,
    journal: str | None = None,
    tag: str | None = None,
    limit: int = 20,
) -> list[dict]:
    sql_parts = [
        "SELECT DISTINCT e.ZIDENTIFIER AS identifier,",
        "       e.ZDATE AS date,",
        "       j.ZNAME AS journal,",
        "       e.ZWORDCOUNT AS wordcount,",
        "       substr(e.ZTEXT, 1, 200) AS preview",
        "FROM ZENTRY e",
        "JOIN ZJOURNAL j ON j.Z_PK = e.ZJOURNAL",
    ]
    params: list = []
    if tag:
        sql_parts.append("JOIN Z_17TAGS jt ON jt.Z_17ENTRIES1 = e.Z_PK")
        sql_parts.append("JOIN ZTAG t ON t.Z_PK = jt.Z_22TAGS AND t.ZTITLE = ?")
        params.append(tag)
    sql_parts.append("WHERE e.ZISTRASHED = 0 AND e.ZTEXT LIKE ?")
    params.append(f"%{query}%")
    if journal:
        sql_parts.append("AND j.ZNAME = ?")
        params.append(journal)
    sql_parts.append("ORDER BY e.ZDATE DESC LIMIT ?")
    params.append(limit)

    rows = conn.execute("\n".join(sql_parts), params).fetchall()
    return [{**dict(r), "date": cocoa_to_iso(r["date"])} for r in rows]


def read_entry(conn: sqlite3.Connection, identifier: str) -> dict | None:
    row = conn.execute(
        """
        SELECT e.ZIDENTIFIER AS identifier,
               e.ZDATE AS date,
               j.ZNAME AS journal,
               e.ZWORDCOUNT AS wordcount,
               e.ZTEXT AS text,
               e.ZLATITUDE AS lat,
               e.ZLONGITUDE AS lng,
               e.ZISBOOKMARKED AS bookmarked
        FROM ZENTRY e
        JOIN ZJOURNAL j ON j.Z_PK = e.ZJOURNAL
        WHERE e.ZIDENTIFIER = ? AND e.ZISTRASHED = 0
        """,
        (identifier,),
    ).fetchone()
    if not row:
        return None
    tags = [
        r["t"]
        for r in conn.execute(
            """
            SELECT t.ZTITLE AS t
            FROM Z_17TAGS j
            JOIN ZTAG t ON t.Z_PK = j.Z_22TAGS
            JOIN ZENTRY e ON e.Z_PK = j.Z_17ENTRIES1
            WHERE e.ZIDENTIFIER = ?
            """,
            (identifier,),
        ).fetchall()
    ]
    result = {**dict(row), "date": cocoa_to_iso(row["date"]), "tags": tags}
    result["location"] = (
        {"lat": row["lat"], "lng": row["lng"]} if row["lat"] is not None else None
    )
    return result


def on_this_day(conn: sqlite3.Connection) -> list[dict]:
    today_mmdd = datetime.utcnow().strftime("%m-%d")
    rows = conn.execute(
        """
        SELECT e.ZIDENTIFIER AS identifier,
               e.ZDATE AS date,
               j.ZNAME AS journal,
               substr(e.ZTEXT, 1, 200) AS preview
        FROM ZENTRY e
        JOIN ZJOURNAL j ON j.Z_PK = e.ZJOURNAL
        WHERE e.ZISTRASHED = 0
          AND strftime('%m-%d', datetime(e.ZDATE + ?, 'unixepoch')) = ?
        ORDER BY e.ZDATE DESC
        """,
        (COCOA_EPOCH, today_mmdd),
    ).fetchall()
    return [{**dict(r), "date": cocoa_to_iso(r["date"])} for r in rows]


def random_entry(conn: sqlite3.Connection, journal: str | None = None) -> dict | None:
    sql = [
        "SELECT e.ZIDENTIFIER AS identifier,",
        "       e.ZDATE AS date,",
        "       j.ZNAME AS journal,",
        "       substr(e.ZTEXT, 1, 400) AS preview",
        "FROM ZENTRY e",
        "JOIN ZJOURNAL j ON j.Z_PK = e.ZJOURNAL",
        "WHERE e.ZISTRASHED = 0 AND e.ZTEXT IS NOT NULL AND length(e.ZTEXT) > 50",
    ]
    params: list = []
    if journal:
        sql.append("AND j.ZNAME = ?")
        params.append(journal)
    sql.append("ORDER BY RANDOM() LIMIT 1")
    row = conn.execute("\n".join(sql), params).fetchone()
    if not row:
        return None
    return {**dict(row), "date": cocoa_to_iso(row["date"])}
