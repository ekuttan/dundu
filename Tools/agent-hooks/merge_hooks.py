#!/usr/bin/env python3
"""Merge Dundu's hook entries into a Claude Code settings file.

Kept apart from install.sh so it can be run against a throwaway settings file
and checked, rather than only ever being tried on the real one.

Reads TARGET, SETTINGS and MODE from the environment.
"""
import json
import os

# Which moment maps to which state. Notification is what fires when Claude
# wants permission or has asked a question — the one actually worth looking
# up for. Stop is the turn finishing.
MAPPING = {
    "UserPromptSubmit": "working",
    "PreToolUse": "working",
    "Notification": "waiting",
    "Stop": "done",
    "SessionEnd": "end",
}


def is_ours(entry):
    """Only entries this installer wrote. Another tool's hooks are not ours
    to remove, even from an event we also use."""
    for inner in entry.get("hooks", []):
        if "dundu" in str(inner.get("command", "")):
            return True
    return False


def merge(settings, hook_path, mode):
    hooks = settings.get("hooks") or {}

    # Clear any previous Dundu entries first, so installing twice does not
    # stack duplicates and --remove is just an install that adds nothing.
    for event in list(hooks):
        hooks[event] = [e for e in hooks[event] if not is_ours(e)]
        if not hooks[event]:
            del hooks[event]

    if mode == "install":
        for event, state in MAPPING.items():
            hooks.setdefault(event, []).append({
                "matcher": "*",
                "hooks": [{
                    "type": "command",
                    "command": f"/usr/bin/python3 {hook_path} {state}",
                }],
            })

    if hooks:
        settings["hooks"] = hooks
    else:
        settings.pop("hooks", None)
    return settings


def main():
    settings_path = os.environ["SETTINGS"]
    hook_path = os.path.join(os.environ["TARGET"], "hook.py")
    mode = os.environ.get("MODE", "install")

    try:
        with open(settings_path) as handle:
            settings = json.load(handle)
    except Exception:
        settings = {}

    settings = merge(settings, hook_path, mode)

    with open(settings_path, "w") as handle:
        json.dump(settings, handle, indent=2)
        handle.write("\n")

    print(f"{'Installed' if mode == 'install' else 'Removed'} Dundu hooks in {settings_path}")
    if mode == "install":
        print("Events:", ", ".join(MAPPING))


if __name__ == "__main__":
    main()
