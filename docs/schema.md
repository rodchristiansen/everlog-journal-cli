# Hummingbird SQLite schema reference

Reverse-engineered from a production database (Everlog v[tbd], 3060 entries). **Unofficial** — Wonderbit has not published this. The schema may change with Everlog updates; see the compatibility matrix in [ARCHITECTURE.md](../ARCHITECTURE.md).

The store is CoreData-backed, so all entity tables are prefixed `Z`. Cross-entity joins use either foreign keys (`ZJOURNAL` is the FK to `ZJOURNAL.Z_PK`) or generated join tables (`Z_17TAGS`).

## Tables we use

### `ZENTRY` — journal entries

```sql
CREATE TABLE ZENTRY (
    Z_PK INTEGER PRIMARY KEY,
    Z_ENT INTEGER,
    Z_OPT INTEGER,
    ZAPP INTEGER,
    ZISBOOKMARKED INTEGER,         -- 1 if bookmarked
    ZISTRASHED INTEGER,            -- 1 if in trash; we filter these out
    ZTOUCH INTEGER,                -- (unknown — needs annotation)
    ZWORDCOUNT INTEGER,            -- computed word count
    ZDEVICE INTEGER,               -- FK to ZDEVICE (which device wrote it)
    ZJOURNAL INTEGER,              -- FK to ZJOURNAL.Z_PK
    ZPARENT INTEGER,               -- (for threaded entries? — needs verification)
    ZPLACE INTEGER,                -- FK to ZPLACE
    ZWEATHER INTEGER,              -- FK to ZWEATHER
    ZDATE TIMESTAMP,               -- entry's user-set date (Cocoa timestamp)
    ZDATECREATED TIMESTAMP,        -- DB insert time
    ZDATEMODIFIED TIMESTAMP,       -- last edit time
    ZDATETRASHED TIMESTAMP,        -- when trashed (NULL if not)
    ZDAY TIMESTAMP,                -- start of day (for daily grouping)
    ZLATITUDE FLOAT,
    ZLONGITUDE FLOAT,
    ZMONTH TIMESTAMP,
    ZSORTDATE TIMESTAMP,           -- the date used for app-level sorting
    ZTIMETYPING FLOAT,             -- seconds spent typing this entry
    ZCONTENT VARCHAR,              -- formatted content (HTML?) — needs annotation
    ZIDENTIFIER VARCHAR,           -- stable UUID; the public handle for entries
    ZTIMEZONE INTEGER,
    ZTEXTMODIFIEDDATE TIMESTAMP,
    ZTEXT VARCHAR,                 -- the markdown body (primary read field)
    ZYEARMONTHDAYID INTEGER,       -- packed integer key for date queries
    ZENCRYPTEDLATITUDE FLOAT,      -- encrypted variant; populated for encrypted entries
    ZYEARID INTEGER,
    ZMONTHID INTEGER,
    ZENCRYPTEDLONGITUDE FLOAT,
    ZDAYID INTEGER,
    ZYEARMONTHID INTEGER,
    ZMIGRATEDCONTENT INTEGER,      -- (unknown — migration marker?)
    ZPROMPT INTEGER,               -- FK to ZPROMPT
    ZPINNED INTEGER                -- 1 if pinned
);
```

**Read primary key**: `ZIDENTIFIER` (the UUID). Don't expose `Z_PK` to users — it's a CoreData internal.

**Filter by default**: `ZISTRASHED = 0`.

**Time conversion**: any `TIMESTAMP` column is seconds-since-2001-01-01 (Cocoa epoch). Add `978307200` to get Unix epoch.

### `ZJOURNAL` — journals (categories)

```sql
CREATE TABLE ZJOURNAL (
    Z_PK INTEGER PRIMARY KEY,
    Z_ENT INTEGER,
    Z_OPT INTEGER,
    ZAPP INTEGER,
    ZCOLORID INTEGER,              -- color theme
    ZISHIDDEN INTEGER,             -- 1 if hidden from sidebar
    ZORDER INTEGER,                -- display order
    ZDEVICE INTEGER,
    ZDATECREATED TIMESTAMP,
    ZCUSTOMCOLOR VARCHAR,          -- hex color override
    ZICON VARCHAR,                 -- emoji or symbol name
    ZID VARCHAR,                   -- (different from ZIDENTIFIER — needs annotation)
    ZIDENTIFIER VARCHAR,           -- stable UUID
    ZNAME VARCHAR,                 -- display name (e.g. "Mindset", "Fitness")
    ZENCRYPTEDNAME VARCHAR,        -- encrypted variant
    ZPINNED INTEGER,
    ZPARENT INTEGER                -- FK to a parent journal (nested journals?)
);
```

### `ZTAG` — tags

```sql
CREATE TABLE ZTAG (
    Z_PK INTEGER PRIMARY KEY,
    Z_ENT INTEGER,
    Z_OPT INTEGER,
    ZAPP INTEGER,
    ZDEVICE INTEGER,
    ZDATECREATED TIMESTAMP,
    ZTITLE VARCHAR,                -- the tag string (e.g. "wins", "moments")
    ZENCRYPTEDTITLE VARCHAR,
    ZPINNED INTEGER,
    ZPARENT INTEGER                -- nested tags?
);
```

**Note**: the column is `ZTITLE`, not `ZNAME`. Easy to get wrong.

### `Z_17TAGS` — entry ↔ tag join

```sql
CREATE TABLE Z_17TAGS (
    Z_17ENTRIES1 INTEGER,          -- entry FK (ZENTRY.Z_PK)
    Z_22TAGS INTEGER,              -- tag FK (ZTAG.Z_PK)
    PRIMARY KEY (Z_17ENTRIES1, Z_22TAGS)
);
```

Naming is CoreData-generated — the `17` and `22` are entity numbers (would differ in other databases). Don't hard-code these; query `Z_PRIMARYKEY` to discover the right join table if writing a generic introspector.

### `ZATTACHMENT` and `AttachmentData.sqlite`

`ZATTACHMENT` (in the main DB) holds per-entry attachment metadata. The actual binary data lives in a separate database (`AttachmentData.sqlite`) in the same group container.

Schema TBD (needs annotation). The migration plan from Personal repo notes that 1364 attachments correspond to the 3060 entries on the production DB.

Entries reference attachments inline in markdown:

```
![attachment](1BD3C6DF-0325-4AB5-817F-DDF5ED181E33)
```

The UUID is `ZATTACHMENT.ZIDENTIFIER` (likely — needs verification).

## Tables we ignore (CloudKit sync metadata)

All `ANSCK*` tables (`ANSCKDATABASEMETADATA`, `ANSCKEVENT`, `ANSCKEXPORTEDOBJECT`, `ANSCKMETADATAENTRY`, `ANSCKRECORDMETADATA`, etc.) are CloudKit sync bookkeeping. The CLI doesn't read or interpret these.

`ATRANSACTION`, `ATRANSACTIONSTRING`, `ACHANGE` — CoreData persistent history tracking.

## Indexes

CoreData generates indexes on most foreign keys (`ZENTRY_ZJOURNAL_INDEX`, etc.). Search performance on `ZTEXT LIKE` is acceptable up to a few thousand entries; for larger histories consider adding an FTS index (Phase 3+).

## Schema version detection

`Z_METADATA` holds the schema version:

```sql
SELECT Z_VERSION FROM Z_METADATA LIMIT 1;
```

The CLI should record observed versions in `ARCHITECTURE.md`'s compatibility matrix and refuse to run against untested versions with a clear error.

## Open annotations needed

These columns are observed but their semantics aren't fully understood:

- `ZAPP` (appears on most tables) — which app component wrote the row?
- `ZTOUCH` on `ZENTRY` — touch / interaction count?
- `ZMIGRATEDCONTENT` on `ZENTRY` — migration marker from an older schema?
- `ZID` vs `ZIDENTIFIER` on `ZJOURNAL` — when does each get used?
- `ZPARENT` on `ZJOURNAL` and `ZTAG` — nested journals/tags? Have you ever seen a non-NULL value?

PRs welcome.
