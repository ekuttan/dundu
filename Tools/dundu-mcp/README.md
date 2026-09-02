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
Tools/dundu-mcp/make-app.sh
claude mcp add dundu --scope user -- \
  "$HOME/Applications/Dundu MCP.app/Contents/MacOS/dundu-mcp"
```

## Why it is an .app and not a bare binary

A command line tool is not an application as far as TCC is concerned. It has
no registered identity, so a Reminders request is attributed to whatever
launched it — Terminal, or Claude Code — and no prompt is ever shown for the
tool itself. `tccutil reset Reminders app.scoop.dundu.mcp` answered plainly:
*No such bundle identifier*. TCC had never heard of it.

Wrapping the same executable in a bundle gives it an identity LaunchServices
registers and TCC remembers; after that, the same `tccutil` command reports
success. The MCP server is still the executable inside the bundle, launched
directly over stdio — the bundle exists purely so the permission has
something to attach to.

The usage string is in the bundle's `Info.plist`. It is also linked into
`__TEXT,__info_plist` by `Package.swift`, which is what a bare build needs;
harmless here, and it keeps `swift run` usable for protocol work.

## Granting Reminders access

macOS shows a permission prompt only to a process with a user session, which
an MCP server started by Claude Code does not have. Grant it once, by hand,
**from Terminal.app**:

```bash
"$HOME/Applications/Dundu MCP.app/Contents/MacOS/dundu-mcp" <<< '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_lists","arguments":{}}}'
```

Allow the prompt. Every later run inherits the grant, including the one
Claude Code launches. If the lists come back as JSON, it is working.

`"Reminders access was refused"` means this step has not happened yet. If no
prompt appears at all, run `tccutil reset Reminders app.scoop.dundu.mcp`
first — a previous refusal is remembered.
