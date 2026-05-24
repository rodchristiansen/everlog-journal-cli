# Everlog Shortcuts catalog

Observed Shortcuts actions Everlog ships with. Use these as the underlying primitives for the CLI's write bridge (Phase 2).

To inspect these on your own machine, open Shortcuts.app → new shortcut → search for "Everlog" or "Journal" in the action library.

## Action inventory (observed 2026-05-24)

| Action name (in Shortcuts.app) | Bundle ID (action identifier) | Inputs (observed) | Outputs |
|---|---|---|---|
| **Create Entry** | `co.wonderbit.Hummingbird.CreateEntryIntent` | text, journal, tags, attachments, date, location | entry identifier |
| **Write Entry** | (likely duplicate of Create Entry) | TBD | TBD |
| **Append Text to Entry** | `co.wonderbit.Hummingbird.AppendTextIntent` (likely) | identifier, text | — |
| **Update Journal** | TBD | journal id, properties | — |
| **Delete Journal Entries** | TBD | identifiers | — |
| **Create Journal** | TBD | name, icon, color | journal identifier |
| **Get Journal** | TBD | name or id | journal metadata |
| **Find Entries** | TBD | filters (date, journal, tag) | list of entries |
| **Search Entries** | TBD | query | list of entries |
| **Open Entry** | TBD | identifier | (opens app, no data return) |
| **Open Bookmarks** | TBD | — | (opens app) |
| **Open Tag** | TBD | tag name | (opens app) |
| **Open On This Day** | TBD | — | (opens app) |
| **Set Bookmark of Entry** | TBD | identifier, on/off | — |
| **Set Everlog Focus Filter** | TBD | filter spec | — |
| **Add Comment to Entry** | TBD | identifier, comment text | — |
| **Record Audio** | TBD | (interactive) | audio attachment |
| **Search in Everlog** | TBD | query | (opens app to results) |

## How to decode an action's exact shape

Author a tiny shortcut in Shortcuts.app that uses the action (e.g. drag in "Create Entry" with sample inputs). Save, then export as a `.shortcut` file (Share → Save as File).

Decode the signed file with the chain documented in [Personal repo's `apps/shortcuts.md`](https://github.com/rodchristiansen/dotfiles-personal/blob/main/apps/shortcuts.md) (or the equivalent here once we factor out a generic decoder):

```bash
# Strip AEA wrapper using the leaf cert's pubkey
python3 -c "..."  # extract auth-data cert, derive pubkey, run aea decrypt
aa extract -i payload.aar -d out/
plutil -convert xml1 out/Shortcut.wflow -o decoded.xml
```

The `WFWorkflowActions` array contains each action with its `WFWorkflowActionParameters`. The Everlog action's `AppIntentDescriptor` reveals the exact `AppIntentIdentifier` and parameter shape.

## Helper Shortcuts the CLI installs (Phase 2)

Rather than calling Everlog's actions directly (each call would require building a complete plist), the CLI ships pre-authored helper Shortcuts that accept JSON input:

| Helper | Wraps | Input shape |
|---|---|---|
| `Everlog CLI: New Entry` | Create Entry | `{"journal": "Mindset", "text": "...", "tags": ["wins"], "date": "2026-05-24T18:00:00Z", "lat": 49.28, "lng": -123.12}` |
| `Everlog CLI: Append` | Append Text to Entry | `{"identifier": "ABCD-...", "text": "..."}` |
| `Everlog CLI: Find` | Find Entries | `{"journal": "Mindset", "tag": "wins", "limit": 20}` returns identifiers |
| `Everlog CLI: Bookmark` | Set Bookmark of Entry | `{"identifier": "ABCD-...", "on": true}` |

The CLI's first run detects missing helpers and offers `everlog install-shortcuts` to import them from the bundled `shortcuts_bundle/`.

## Why wrap, instead of calling Everlog actions directly

1. **Stable contract** — our helpers' input/output shape stays fixed even if Wonderbit changes their action's internals.
2. **Single point of update** — schema changes mean editing one helper, not regenerating shortcut plists from CLI code.
3. **User auditability** — helpers are visible in the user's Shortcuts library; users can inspect what the CLI does on their behalf.
4. **No plist generation in code** — the CLI's write path is `serialize(args) → shortcuts run helper → parse response`. Clean and testable.
