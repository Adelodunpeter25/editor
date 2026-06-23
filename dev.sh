#!/bin/bash
# Rebuild and run the DEV app ("Editor Dev") — installs to /Applications and waits for launch.
set -e
cd "$(dirname "$0")"
CONFIG="${1:-debug}"

if [ "$CONFIG" = "debug" ]; then APP="Editor Dev.app"; else APP="Editor.app"; fi
NAME="${APP%.app}"

ERR=$(swift build -c "$CONFIG" 2>&1 | grep -E "error:" | head -20 || true)
if [ -n "$ERR" ]; then echo "BUILD ERRORS:"; echo "$ERR"; exit 1; fi
./build.sh "$CONFIG" >/dev/null 2>&1

osascript -e "quit app \"$NAME\"" 2>/dev/null || true
pkill -f "$APP/Contents/MacOS/Editor" 2>/dev/null || true
sleep 1
rm -rf "/Applications/$APP"
cp -R "$APP" "/Applications/$APP"
open "/Applications/$APP"
for i in $(seq 1 25); do pgrep -f "/Applications/$APP/Contents/MacOS/Editor" >/dev/null 2>&1&& break; sleep 1; done
sleep 3
pgrep -f "/Applications/$APP/Contents/MacOS/Editor" >/dev/null && echo "OK running ($APP)" || {
  echo "CRASHED"; ls -t ~/Library/Logs/DiagnosticReports/Editor-*.ips 2>/dev/null | head -1; }
