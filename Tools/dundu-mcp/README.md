# dundu-mcp

An MCP server that lets Claude put reminders on your devices.

## What it writes to, and why

Apple Reminders, through EventKit — **not** Dundu's own store.

Reminders is the substrate Dundu already shares: iCloud carries it to the
iPhone, and Dundu ingests from EventKit on its next sync pass. So a reminder
Claude adds arrives everywhere through the ordinary path, including routing
and the push/ingest pairing. Writing into Dundu's SwiftData container from a
second process would mean concurrent access to a sandboxed store owned by a
running app, which is a good way to lose data.

## Tools

| Tool | Does |
|---|---|
| `add_reminder` | title, plus optional notes, due date, list, priority |
| `list_reminders` | soonest due first; optionally one list, optionally completed |
| `list_lists` | the lists, and which is the default |
| `complete_reminder` | marks one done by id |

Due dates accept ISO 8601 (`2026-08-17T09:00:00Z`), `2026-08-17 09:00`, or
`2026-08-17` for a whole day. List names are matched case-insensitively, so
"hoomans" finds "Hoomans".

## Build and install

```bash
cd Tools/dundu-mcp
swift build -c release
codesign -s - --force .build/release/dundu-mcp
cp .build/release/dundu-mcp ~/.local/bin/dundu-mcp
codesign -s - --force ~/.local/bin/dundu-mcp
claude mcp add dundu --scope user -- "$HOME/.local/bin/dundu-mcp"
```

The ad-hoc signature matters: TCC keys a permission grant to the binary's
identity, and an unsigned one can lose its grant on rebuild.

## Granting Reminders access

A command line tool has no app bundle, so the usage string is embedded into
`__TEXT,__info_plist` by the linker flags in `Package.swift`. Without that,
the access request fails with no prompt at all.

macOS only shows the prompt to a process with a user session attached, which
an MCP server started by Claude Code does not have. So grant it once by hand:

```bash
~/.local/bin/dundu-mcp <<< '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_lists","arguments":{}}}'
```

Run that in Terminal.app, allow the prompt, and every later run inherits the
grant. If no prompt appears, add the binary under System Settings › Privacy &
Security › Reminders.

`"Reminders access was refused"` coming back from a tool call means this step
hasn't happened yet.
