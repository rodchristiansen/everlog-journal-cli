# The write path

How `everlog new` / `append` / `attach` / `trash` actually write, what fields
they maintain, and why two earlier approaches were abandoned.

## Design

`Sources/everlog/Store.swift` loads Everlog's compiled CoreData model from the
app bundle and opens the two group-container stores with their model
configurations:

| Configuration | Store file | Holds |
|---|---|---|
| `Main` | `Hummingbird.sqlite` | Entries, journals, tags, attachments (metadata + thumbnail) |
| `AttachmentData` | `AttachmentData.sqlite` | Attachment blobs (externalized to `_EXTERNAL_DATA` by CoreData) |

Both open with `NSPersistentHistoryTrackingKey: true`; every save carries
`transactionAuthor = "everlog-cli"`. The app's CloudKit mirror exports those
history transactions on its next activity, so entries written by the CLI sync
to other devices without the app being told anything.

Auto-migration is disabled on purpose. If Everlog updated and the store hasn't
been migrated yet, the CLI errors out and asks you to launch the app once.

## Derived fields the CLI maintains

Everlog's queries group by pre-computed date buckets, so an entry is invisible
to the app's day/month/year views unless these are filled exactly like the
app fills them. `Store.applyDerivedFields` sets, from `(body, date)`:

| Field | Value |
|---|---|
| `text`, `content` | The body (kept identical, matching app-written rows) |
| `date`, `sortDate` | The entry timestamp |
| `day` | Local start-of-day |
| `month` | Local start-of-month |
| `dayId`, `monthId`, `yearId` | Calendar components |
| `yearMonthId` | `yyyyMM` as integer |
| `yearMonthDayId` | `yyyyMMdd` as integer |
| `wordCount` | Whitespace-split count |
| `timeZone` | UTC offset in minutes |

## Image attachments

`new -i photo.jpg` (or `attach <id> photo.jpg`) creates:

1. An `ImageAttachment` row (entity inherits `Attachment`): identifier =
   uppercase UUID hex without dashes, width/height from ImageIO, byte size,
   file extension, and a 400px JPEG thumbnail.
2. An `AttachmentData` row in the attachment store with the same identifier
   and the full file bytes. CoreData externalizes the blob into
   `.AttachmentData_SUPPORT/_EXTERNAL_DATA/` — one of several reasons raw SQL
   writes were never on the table.
3. The markdown reference `![attachment](<identifier>)` appended to the entry
   text, which is how the app renders inline images.

Note: CoreData maps same-named attributes of sibling `Attachment` subclasses
to suffixed columns (`ZSIZE2`, `ZFILEEXTENSION2`, …). Only CoreData knows the
mapping — another reason raw SQL was rejected.

## Why not Shortcuts or AppIntents (the graveyard)

Two earlier designs are preserved in git history (`docs/shortcuts.md`,
`docs/phase2-blockers.md`, `docs/phase3-research.md`, removed alongside this
file's introduction):

1. **Helper Shortcuts wrapping Everlog's actions** (`shortcuts run …`).
   Blocked in practice: `--input-path -` does not deliver stdin to AppIntent
   parameters, which forced a clipboard workaround whose failure mode was
   silently journaling whatever was on the clipboard. Parameters beyond
   `message` (journal, date, images) were never reliably wireable from
   pre-authored plists, and the whole path added a Shortcuts.app dependency
   to what should be a headless tool.
2. **Direct AppIntents invocation** from our own process. There is no public
   API for one process to execute another app's `AppIntent`; Apple routes
   third-party intents exclusively through Shortcuts/Siri/Spotlight.

The CoreData path replaced both: fully headless, all parameters, and the same
write mechanism the app's own extensions use.

## Verifying a write

```bash
everlog new "verification" -j Mindset --json
everlog show Mindset 1
```

The read side goes through the independent snapshot-SQLite path, so a
successful `show` proves the write is durably in the store, not just in a
CoreData cache. For sync verification, check the entry appears on a second
device (or in the app after relaunch) — CloudKit export happens on the app's
schedule, not the CLI's.
