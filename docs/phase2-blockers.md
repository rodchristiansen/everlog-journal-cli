# Phase 2 blockers — Shortcuts dispatch

**Status (2026-05-24, updated post-retry):** The Swift CLI side of Phase 2 is implemented (`everlog new`, `install-shortcuts`, Resources bundling, helper-shortcut machinery). The actual entry-creation dispatch path is **not reliably working** at the time of this writing. An empirical retry with the deprecated `CreateEntryIntent` (plain String message, hypothesized to bypass the IntentsTransferable type-coercion issue) failed identically — see "Retry findings" below. The blocker is now believed to be in `shortcuts run`'s headless input delivery, not in any specific intent's parameter type.

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

## Retry findings (2026-05-24)

A targeted retry built a minimal helper using the **deprecated `CreateEntryIntent`** (`text` parameter is plain `String`, not IntentsTransferable). Helper signed cleanly, installed cleanly, and `shortcuts run` exited 0 — but **no entry was created**, identical behavior to the AICreateEntryIntent path. The IntentsTransferable hypothesis is **ruled out**.

Reproduction (with the deprecated-intent helper installed):

```
echo "phase2-retry verification body" | shortcuts run "Everlog CLI- New Entry" --input-path -
# exit 0, no stdout, no stderr
everlog search "phase2-retry verification body"
# (no results)
```

This rules out parameter-type coercion as the cause. The remaining candidate explanations:

1. **`shortcuts run --input-path -` doesn't deliver bytes to the ExtensionInput magic variable** when invoked headlessly. The shortcut runs but Shortcut Input is effectively empty, so the AppIntent receives a nil/empty `text` and silently no-ops. Would explain why manual Play-button invocations in Shortcuts.app work (Shortcuts UI injects typed text directly, bypassing input plumbing).
2. **Sandboxing / entitlement gating**. `shortcuts run` launched from Terminal/cmux may lack the entitlement Everlog requires to write to its group container when triggered without an explicitly user-initiated GUI invocation. Manual Play has a user-gesture context that headless dispatch doesn't.
3. **Wonderbit rejects missing-default optional parameters** when the call originates from `shortcuts run`. Passing `journal`/`date` explicitly might flip the silent failure into success or a visible error.

## Original (now-superseded) hypothesis

`AICreateEntryIntent.message` is typed as an `IntentsTransferable` (type-12) tied to Apple's journal assistant schema, so CLI-piped raw bytes can't satisfy it. The retry showed even the plain-String deprecated intent fails identically, so this isn't the cause — the failure is upstream, in how Shortcut Input is (not) propagated under `shortcuts run`.

## What would unblock this

In rough order of effort, post-retry:

1. **Verify Shortcut Input arrives at all under `shortcuts run`.** Build a debug helper whose only action is `Save File` writing the value of Shortcut Input to `~/.everlog-cli/debug-input.txt`. Invoke via the same CLI path and read the file. If it's empty, the input plumbing is the bug and we need a different delivery channel (e.g. clipboard, named pipe, or a long-lived helper process).
2. **Compare entitlements** between Shortcuts.app's foreground runner and the `shortcuts run` background runner — `codesign -d --entitlements - $(which shortcuts)` and the Shortcuts.app binary side by side. If they diverge, headless dispatch may be missing the AppIntent invocation entitlement that Wonderbit gates on.
3. **File a feature request with Wonderbit** for write-capable `everlog://` URLs (e.g. `everlog://new?journal=X&text=...`). Avoids the Shortcuts/AppIntents layer entirely. See [docs/phase3-research.md](phase3-research.md).
4. **Try passing parameters explicitly** rather than relying on AppIntent defaults — author a helper that hardcodes a known journal name in the `journal` parameter to see if the silent failure shifts.
5. **Replace the Shortcuts bridge with a direct AppIntents binding** — blocked at the platform level for cross-process invocation, see [docs/phase3-research.md](phase3-research.md).

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

- **Run the debug-input shortcut first** (unblock #1 above). It's the smallest possible signal — if Shortcut Input is empty under `shortcuts run`, we know to stop tinkering with intents.
- If Shortcut Input does arrive: try `BookmarkEntryAppIntent` (background-capable, takes an EntryEntity + Bool — no String typing). A successful bookmark toggle on a known entry would prove headless AppIntents dispatch works at all on this Mac, narrowing the issue to text-parameter handling.
- If headless dispatch is universally broken: pivot to the `everlog://` URL feature request to Wonderbit and treat Phase 2 as platform-blocked rather than CLI-blocked.
