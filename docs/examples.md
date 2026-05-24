# Examples

## Daily reflection

What did I write on this day in past years?

```bash
everlog on-this-day
```

A random old entry to reflect on:

```bash
everlog random --journal Mindset
```

## Finding things

What did I write about Niguel?

```bash
everlog search "Niguel"
```

When did I have wins around vacationing?

```bash
everlog search "vacation" --tag wins
```

All Mindset entries about a project:

```bash
everlog search "Project Atlas" --journal Mindset 50
```

## Reading

Once you have an identifier (from `show` / `search` / `on-this-day`), read the full entry. UUID prefix is enough — the CLI matches on the full identifier:

```bash
everlog read 1BD3C6DF
```

## Piping into other tools

JSON output everywhere:

```bash
everlog journals --json | jq '.[] | select(.count > 100)'
everlog tags --json | jq -r '.[].name'
everlog search "win" --tag wins --json | jq -r '.[].preview'
```

## Counting

Total entries across all journals (with `jq` math):

```bash
everlog journals --json | jq '[.[].count] | add'
```

How many entries with the "wins" tag?

```bash
everlog tags --json | jq '.[] | select(.name == "wins") | .count'
```

## Agent integration (the killer feature)

Pipe recent entries into an LLM for summarization:

```bash
everlog show Mindset 30 --json | \
  jq -r '.[].preview' | \
  llm "summarize what I've been thinking about lately"
```

Or for retrieval-augmented generation, dump entries for an embedding pipeline:

```bash
everlog show Mindset 5000 --json > /tmp/mindset.json
# ... feed to your embedding pipeline of choice
```

## Cron-friendly

Daily reflection digest at 8am:

```cron
0 8 * * * /usr/local/bin/everlog on-this-day | mail -s "On this day from your journal" you@example.com
```

## Quick verification that the install works

```bash
everlog journals          # should list your journals
everlog tags              # should list your tags
everlog show Mindset 3    # if Mindset exists, recent entries
```

If `everlog journals` returns nothing, either Everlog isn't installed or iCloud hasn't synced yet. The CLI looks for the database at:

```
~/Library/Group Containers/group.hummingbird/Hummingbird.sqlite
```
