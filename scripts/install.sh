#!/usr/bin/env bash
# Usage: ./scripts/install.sh
# Builds Timi (Release) from this checkout, installs it in /Applications (or ~/Applications),
# launches it and installs the Claude Code hooks. Safe to run again to update.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { echo "error: $*" >&2; exit 1; }

# 1. Requirements: macOS 26 and a full Xcode 26 (the Command Line Tools alone cannot build an app).
macos="$(sw_vers -productVersion)"
(( ${macos%%.*} >= 26 )) || die "Timi needs macOS 26 or later (this Mac runs $macos)"
[[ "$(xcode-select -p 2>/dev/null)" == *.app/Contents/Developer ]] \
  || die "Xcode 26 is required: install it from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"
xcode="$(xcodebuild -version 2>/dev/null | awk 'NR == 1 { print $2 }')"
(( ${xcode%%.*} >= 26 )) || die "Xcode 26 or later is required (found ${xcode:-none})"
xcodebuild -checkFirstLaunchStatus \
  || die "finish the Xcode setup first: sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch"

# 2. Release build. Signed with the stable identity of scripts/release.conf when this Mac has it
# (macOS permissions then survive reinstalls), ad hoc otherwise: no Apple account needed.
# shellcheck source=release.conf
source scripts/release.conf
identity="-"
security find-identity -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\"" && identity="$SIGN_IDENTITY"
echo "Building Timi (Release, signing identity: $identity)…"
xcodebuild -quiet -project Timi.xcodeproj -scheme Timi -configuration Release \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM= build
built="build/Build/Products/Release/Timi.app"

# 3. Install, replacing a previous copy wherever it was.
destination_dir="/Applications"
[[ -w "$destination_dir" ]] || { destination_dir="$HOME/Applications"; mkdir -p "$destination_dir"; }
app="$destination_dir/Timi.app"
if pkill -x Timi; then
  for _ in {1..30}; do pgrep -x Timi >/dev/null || break; sleep 0.1; done
  pkill -9 -x Timi || true
fi
rm -rf "$app"
ditto "$built" "$app"
echo "Installed $app"

# 4. Launch, then wait for the Claude Code hook socket.
open "$app"
socket="$HOME/Library/Application Support/Timi/claude-hooks.sock"
for _ in {1..50}; do [[ -S "$socket" ]] && break; sleep 0.1; done
if [[ -S "$socket" ]]; then
  echo "Timi is running and listening on $socket"
else
  echo "warning: Timi is open but its socket is missing: check Settings > Sessions Claude Code" >&2
fi

# 5. Claude Code hooks.
./scripts/claude-hooks.sh install
