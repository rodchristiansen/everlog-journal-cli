"""Dataclasses for the typed API (used by tests; CLI works with dicts for now)."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class Journal:
    name: str
    count: int


@dataclass
class Tag:
    name: str
    count: int


@dataclass
class Entry:
    identifier: str
    date: str  # ISO 8601 with trailing Z
    journal: str
    wordcount: int | None = None
    preview: str | None = None
    text: str | None = None
    tags: list[str] = field(default_factory=list)
    location: dict | None = None  # {"lat": float, "lng": float}
    bookmarked: bool = False
