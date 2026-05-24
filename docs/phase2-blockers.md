# Phase 2 blockers — Shortcuts dispatch

**Status (2026-05-24):** The Swift CLI side of Phase 2 is implemented (`everlog new`, `install-shortcuts`, Resources bundling, helper-shortcut machinery). The actual entry-creation dispatch path is **not reliably working** at the time of this writing. This document records what we tried, what we learned, and the platform constraints that need a different angle than the original Phase 2 plan assumed.

## What we learned about Everlog's AppIntents

From `/Applications/Everlog.app/Contents/Resources/Metadata.appintents/extract.actionsdata`:

- Everlog declares 20 AppIntents. 11 are background-capable (`openAppWhenRun=false`).
- The two write-side candidates for "create entry" are:
  - **`CreateEntryIntent`** — plain `String` for `text` parameter. Declared with `deprecationMetadata` set, even though still functional. Wonderbit clearly intends to remove it.
  - **`AICreateEntryIntent`** — the non-deprecated replacement. `message` parameter is typed `primitive.wrapper.typeIdentifier: 12` (an IntentsTransferable rather than plain String) and declares `assistantDefinedSchemas: [{name: CreateJournalEntryIntent, version: 1.0.0, domain: journal}]` — part of Apple's `journal` assistant-domain schema family.
- `EverlogIntents.appex` is the App Extension that hosts the background intent handlers.

## What works

- Manual invocation in Shortcuts.app via the "play" button creates entries successfully — the user can type text directly into the Message field and it lands as a real entry.
- The Swift CLI bundling: `swift build` packages the helper `.shortcut` into the resource bundle, `install-shortcuts` extracts and opens it for import, `Bundle.module.resourceURL` correctly resolves the bundled shortcut at runtime.
- `shortcuts list` and `shortcuts sign -m anyone` work as expected for the agent-authored helpers.

## What doesn't

Every CLI-driven invocation we tried produced **exit 0 with no entry created**, regardless of mechanism:

- `shortcuts run "Everlog CLI- New Entry" --input-path -` with JSON on stdin
- `shortcuts run ... --input-path FILE` with the JSON in a `.json` or `.txt` file under `~/`
- `open "shortcuts://run-shortcut?name=...&input=text&text=<urlencoded JSON>"`
- A simplified helper that takes plain text Shortcut Input directly
- A file-bridge helper that reads `~/.everlog-cli/message.txt`

Console logs (`log show --predicate 'process == "shortcuts"'`) confirm the shortcut workflow runs to completion (`workflow did finish running`), and Everlog's process log emits `Finished Processing History. There are 0 cloud inserts, 0 deletes pending` at the exact moment the shortcut completes — indicating the AppIntent was invoked but with an empty/nil `message` parameter, so no entry was committed.

## Hypothesis

`AICreateEntryIntent.message` is typed as an `IntentsTransferable` (type-12) tied to Apple's journal assistant schema. The Shortcuts.app editor coerces typed-in text to the right transferable form before invoking. When `shortcuts run` passes raw bytes via stdin or a file path, the resulting variable doesn't satisfy the transferable type, and the AppIntent silently rejects the call (no error, no log, no entry). The deprecated `CreateEntryIntent` accepts plain `String` and may be the only intent that works from third-party CLI invocations today — but the user-visible path forward is unclear (it WILL be removed by Wonderbit eventually).

## What would unblock this

In rough order of effort:

1. **Empirical verification with CreateEntryIntent (deprecated).** Build a helper that targets the deprecated intent (plain String message), test end-to-end. If that works, the IntentsTransferable hypothesis is confirmed and we have a stop-gap.
2. **File a feature request with Wonderbit** for write-capable `everlog://` URLs (e.g. `everlog://new?journal=X&text=...`). Avoids Shortcuts entirely. See [docs/phase3-research.md](phase3-research.md).
3. **Wait for or research a Shortcuts mechanism to coerce String → IntentsTransferable.** There may be an explicit "Set Variable" type-coercion or an action that wraps the string into the right transferable wrapper — but we didn't find it in this session.
4. **Replace the Shortcuts bridge with a direct AppIntents binding** — blocked at the platform level for cross-process invocation, see [docs/phase3-research.md](phase3-research.md).

## Files in this state

- `Sources/everlog/Resources/Shortcuts/Everlog CLI- New Entry.{xml,shortcut}` — agent-authored helper targeting `AICreateEntryIntent` via the file-bridge approach (reads `~/.everlog-cli/message.txt`). Installed in Shortcuts.app but dispatch is unreliable.
- `Sources/everlog/Shortcuts.swift` — `Shortcuts.runNewEntry(helper:message:)` writes the message to the bridge file and runs the helper. No stdin piping.
- `Sources/everlog/Commands.swift` — `New` is wired but its abstract notes the experimental status and points readers at this document.

## Reproducing the failure

```bash
mkdir -p ~/.everlog-cli
printf '%s' "test entry from CLI" > ~/.everlog-cli/message.txt
shortcuts run "Everlog CLI- New Entry"
echo "exit=$?"
everlog show Leisure 1
```

If the test entry doesn't appear in the `show` output, you're hitting the same wall we hit.

## Next session recommendations

- Start with the **deprecated CreateEntryIntent** to validate that the rest of the pipeline (Swift CLI, helper install, bridge file) is sound. Live with the deprecation warning until a better path opens up.
- Look at `EverlogFocusFilter` and `BookmarkEntryAppIntent` — both are background-capable and use simpler parameter types. If they work via `shortcuts run`, that confirms the issue is specifically the AI-flavored intents.
- Try a known-third-party AppIntent on this machine that's verified to work via `shortcuts run`. If none do, the issue is broader than Everlog.
