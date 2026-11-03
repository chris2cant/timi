#!/usr/bin/env bash
# Usage: ./scripts/run.sh
# Builds Timi in Debug and relaunches it, like ⌘R in Xcode but without opening Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

app="build/Build/Products/Debug/Timi.app"

# -quiet prints only warnings and errors.
xcodebuild -quiet -project Timi.xcodeproj -scheme Timi -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build build

# Only one Timi at a time: the latest one launched takes over the Claude Code hook socket.
if pkill -x Timi; then
  for _ in {1..30}; do
    pgrep -x Timi >/dev/null || break
    sleep 0.1
  done
  pkill -9 -x Timi || true
  sleep 0.2
  # Xcode's debugger holds a Timi it launched, even against SIGKILL.
  if pgrep -x Timi >/dev/null; then
    echo "warning: a Timi run from Xcode is still alive: stop it in Xcode (⌘.)" >&2
  fi
fi

open "$app"
echo "Timi relaunched from $app"
