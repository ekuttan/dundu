#!/bin/bash
# Install Dundu's Claude Code status hooks.
#
# Adds hook entries to ~/.claude/settings.json and copies the reporter script
# next to them. Existing settings are merged, never replaced, and backed up to
# settings.json.backup-dundu first. Hooks belonging to other tools are left
# alone; only entries whose command mentions dundu are touched.
#
# Undo with:  Tools/agent-hooks/install.sh --remove
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/.claude/dundu"
SETTINGS="$HOME/.claude/settings.json"

mkdir -p "$TARGET/sessions"
cp "$ROOT/hook.py" "$TARGET/hook.py"
chmod +x "$TARGET/hook.py"

[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.backup-dundu"

MODE="install"
[ "${1:-}" = "--remove" ] && MODE="remove"

TARGET="$TARGET" SETTINGS="$SETTINGS" MODE="$MODE" /usr/bin/python3 "$ROOT/merge_hooks.py"

echo
echo "Status files: $HOME/.claude/dundu/sessions"
echo "Restart any running Claude Code session for the hooks to take effect."
