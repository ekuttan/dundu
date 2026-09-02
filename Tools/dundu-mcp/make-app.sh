#!/bin/bash
# Wrap the server in a real .app bundle.
#
# A bare executable is not an application as far as TCC is concerned: it has
# no registered identity, so the Reminders request is attributed to whatever
# launched it and no prompt is ever shown for the tool itself. A bundle gives
# it a durable identity that LaunchServices registers and TCC can remember.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-$HOME/Applications/Dundu MCP.app}"

swift build -c release --package-path "$ROOT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/release/dundu-mcp" "$APP/Contents/MacOS/dundu-mcp"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>dundu-mcp</string>
    <key>CFBundleIdentifier</key><string>app.scoop.dundu.mcp</string>
    <key>CFBundleName</key><string>Dundu MCP</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSUIElement</key><true/>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>Dundu's MCP server adds and reads reminders when you ask Claude to.</string>
</dict>
</plist>
PLIST

codesign -s - --force --deep "$APP"
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f "$APP"

echo "built: $APP"
echo "exec:  $APP/Contents/MacOS/dundu-mcp"
