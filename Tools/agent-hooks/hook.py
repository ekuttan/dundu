#!/usr/bin/env python3
"""Report a Claude Code session's state to Dundu.

Claude Code runs this on its own at four moments and hands it the event JSON
on stdin. It writes one small file per session; Dundu watches the directory.
Nothing is polled and nothing is sent anywhere — the file never leaves this
Mac, and lives under ~/.claude so Dundu can read it with the folder access it
already has.

Usage, from a hook entry:  hook.py <working|waiting|done|end>
"""
import json
import os
import sys
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
SESSIONS = os.path.join(HOME, ".claude", "dundu", "sessions")


def main() -> int:
    state = sys.argv[1] if len(sys.argv) > 1 else "working"

    try:
        event = json.load(sys.stdin)
    except Exception:
        # A hook that fails must never take the agent down with it.
        return 0

    session_id = event.get("session_id")
    if not session_id:
        return 0

    os.makedirs(SESSIONS, exist_ok=True)
    path = os.path.join(SESSIONS, f"{session_id}.json")

    if state == "end":
        try:
            os.remove(path)
        except OSError:
            pass
        return 0

    # Keep whatever we already knew; only this event's facts are new. The
    # prompt arrives with UserPromptSubmit and nothing later repeats it.
    record = {}
    try:
        with open(path) as handle:
            record = json.load(handle)
    except Exception:
        pass

    prompt = (event.get("prompt") or "").strip()
    if prompt:
        first_line = prompt.splitlines()[0].strip()
        record["task"] = first_line[:80] + ("…" if len(first_line) > 80 else "")

    record["id"] = session_id
    record["tool"] = "claudeCode"
    record["state"] = state
    record["project"] = event.get("cwd") or record.get("project")
    record["updatedAt"] = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")

    # Written whole then moved, so Dundu never reads a half-written file.
    temporary = path + ".tmp"
    with open(temporary, "w") as handle:
        json.dump(record, handle)
    os.replace(temporary, path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
