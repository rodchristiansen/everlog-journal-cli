# Phase 3 research — direct AppIntents binding

**Status:** Empirical findings from inspecting `Everlog.app` v3.0 (Hummingbird, `co.wonderbit.Hummingbird`). Conclusion: the original Phase 3 plan ("skip the `shortcuts` CLI by calling Wonderbit's `AppIntent` types directly from our binary") is blocked at the macOS platform level, not at our implementation. Below are the findings and the revised path forward.

## What Everlog exposes

Inspected via `/usr/libexec/PlistBuddy`, `strings`, `codesign -d --entitlements -`, and `plutil -p` on `Contents/Resources/Metadata.appintents/extract.actionsdata`.

**20 declared AppIntents.** Of those, 11 are background-capable (`openAppWhenRun=false`) — meaning Apple's intent dispatcher can run them without bringing Everlog to the foreground:

| Intent | Type | Notes |
|---|---|---|
| `CreateEntryIntent` | `Everlog.CreateEntryAppIntent` | Primary write |
| `AICreateEntryIntent` | `Everlog.AICreateEntryIntent` | AI surface variant |
| `AddCommentIntent` | `Everlog.AddCommentAppIntent` | Comment on entry |
| `AddToEntryAppIntent` | `Everlog.AddToEntryAppIntent` | Append text |
| `AIUpdateEntryIntent` | `Everlog.AIUpdateEntryIntent` | Update entry |
| `BookmarkEntryAppIntent` | `Everlog.BookmarkEntryAppIntent` | Toggle bookmark |
| `TrashEntryAppIntent` | `Everlog.TrashEntryAppIntent` | Move to trash |
| `AIDeleteEntryIntent` | `Everlog.AIDeleteEntryIntent` | Delete |
| `FindEntriesIntent` | `Everlog.FindEntriesAppIntent` | Read |
| `EverlogFocusFilter` | `Everlog.EverlogFocusFilter` | Focus integration |

The remaining 9 are foreground-only (`openAppWhenRun=true`) — `WriteEntryIntent`, `OpenJournalIntent`, `OpenEntryIntent`, `OpenTagAppIntent`, `OpenBookmarksAppIntent`, `OnThisDayIntent`, `SearchAppIntent`, `AISearchEntryIntent`, `RecordAudioAppIntent`. These will activate the app regardless of dispatch path.

**Intent host:** `Contents/PlugIns/EverlogIntents.appex` — an App Extension that runs the background intent handlers out-of-process from the main app. When `shortcuts run` invokes a background intent, it dispatches into this extension via the system, not into `Everlog.app` itself.

**App is sandboxed** (`com.apple.security.app-sandbox`). No `NSAppleEventsUsageDescription` — no AppleScript bridge.

**URL scheme:** `everlog://entry/<id>` and `everlog://journal/<name>`. Navigation only, not write-capable.

## What blocks direct binding

Apple's public AppIntents API has no cross-process invocation entry point. There is no public Swift call along the lines of:

```swift
AppIntents.invoke(
    bundleID: "co.wonderbit.Hummingbird",
    intentName: "CreateEntryIntent",
    parameters: [...]
)
```

The system-blessed invokers of another app's intents are: **Shortcuts.app, Siri, Spotlight, Focus filters, and the system "Use with…" surface.** All of them route through Apple's private `LNExtensionManager` / `AppIntents` distributor that locates and launches `EverlogIntents.appex`. Third-party processes don't get that hook.

Routes considered and ruled out:

- **Direct `XPC` to `EverlogIntents.appex`** — ExtensionKit doesn't expose a public API to enumerate or connect to arbitrary app extensions by bundle ID.
- **`NSUserActivity` continuation** — works for handoff between *trusted* devices/apps, not arbitrary CLI → app invocation.
- **AppleScript / Apple Events** — Everlog ships no scripting dictionary; no `NSAppleEventsUsageDescription`.
- **URL scheme `everlog://`** — only routes navigation, not entry creation. Would require Wonderbit to add write-capable URL parameters.
- **Loading `EverlogIntents.appex` into our process** — sandboxing + code signing prevents this; even if it worked it'd be brittle and non-distributable.

## Revised Phase 3

Three viable directions, in increasing order of effort:

### 3a — Optimize the `shortcuts run` path (recommended first step)

Stay on Phase 2's `shortcuts run` mechanism but minimize its overhead:

- **Warm-start helper shortcuts**: install lightweight wrapper shortcuts (`Everlog CLI: New Entry`, `Everlog CLI: Append`, etc.) that the system can cache.
- **Batch writes through one shortcut**: a single shortcut that loops over a JSON array of operations cuts the per-call Shortcuts.app spin-up cost.
- **Async invocation**: where the caller doesn't need a return value, fire-and-forget via `shortcuts run` with `&` to avoid blocking.

### 3b — Register `everlog` itself as an AppIntents provider

Our CLI binary can declare *its own* `AppIntent` types that Shortcuts/Siri/Spotlight can invoke. This doesn't replace the write path into Everlog, but it lets users build workflows like:

> "Hey Siri, run my morning journal entry" → Shortcut calls Everlog's `CreateEntryIntent` → then calls our `Everlog CLI: Backup` intent.

Adds value as a peer to Everlog's intent surface rather than as a backdoor into it.

### 3c — Advocate for `everlog://` write URLs (feature request to Wonderbit)

File an issue / contact Wonderbit asking for write-capable URL parameters:

```
everlog://new?journal=Mindset&text=Hello&tags=morning,reflection&date=2026-05-24T08:00:00Z
```

If they ship this, our CLI can `open` the URL and skip the Shortcuts dispatcher entirely for the common write case. Low effort for them, big win for any CLI/automation tool.

## Verification commands

Reproducible from any Mac with Everlog installed:

```bash
plutil -p /Applications/Everlog.app/Contents/Resources/Metadata.appintents/extract.actionsdata \
  | grep -E '"(customIntentClassName|openAppWhenRun|fullyQualifiedTypeName)"'
```

```bash
codesign -d --entitlements - /Applications/Everlog.app/Contents/MacOS/Everlog 2>&1
```

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes' /Applications/Everlog.app/Contents/Info.plist
```

## Recommendation

Implement **Phase 2** (shortcuts CLI bridge) as planned. Treat **Phase 3a** as the actual deliverable for "Phase 3" — make the Phase 2 mechanism feel snappy. Park **Phase 3b** as a follow-up enhancement once write commands have real users. Submit **Phase 3c** as a feature request to Wonderbit independent of our roadmap.
