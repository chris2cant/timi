#!/usr/bin/env bash
# Usage: ./scripts/claude-hooks.sh install|uninstall|status
# Adds (or removes) the Timi entry of every Claude Code hook event in the user settings, and wraps
# the status line (the only place Claude Code sends usage limits) in a Timi script that forwards its
# input to Timi, then runs the user's original status line with the same input and output.
# Idempotent; other hooks are kept; a backup is written before any change.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
backup="$settings.bak-timi"
# macOS 15+ ships jq in /usr/bin.
jq="$(command -v jq || echo /usr/bin/jq)"
[[ -x "$jq" ]] || die "jq not found (it ships with macOS 15 and later)"

support="$HOME/Library/Application Support/Timi"
wrapper="$support/statusline.sh"
original_file="$support/statusline-original"

events='["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "SubagentStart", "SubagentStop", "SessionEnd"]'
# Expanded by the hook shell, not here. Exits 0 in about a second when Timi is not running.
cmd='curl -s -m 1 --unix-socket "$HOME/Library/Application Support/Timi/claude-hooks.sock" -H "X-Timi-Pid: $PPID" -H "X-Timi-Cmux-Workspace: $CMUX_WORKSPACE_ID" -H "X-Timi-Cmux-Surface: $CMUX_SURFACE_ID" -H "X-Timi-Cmux-Socket: $CMUX_SOCKET_PATH" -H "X-Timi-Cmux-Cli: $CMUX_BUNDLED_CLI_PATH" -H "X-Timi-Herdr-Pane: $HERDR_PANE_ID" -H "X-Timi-Herdr-Socket: $HERDR_SOCKET_PATH" -H "X-Timi-Herdr-Cli: $HERDR_BIN_PATH" --data-binary @- http://timi/claude-hook >/dev/null 2>&1 || true'
# Also expanded by Claude Code's shell. "Timi/statusline.sh" identifies the Timi wrapper.
statusline='sh "$HOME/Library/Application Support/Timi/statusline.sh"'
statusline_marker='Timi/statusline.sh'
# Command of the user's status line before Timi wrapped it (set by install and uninstall).
original=""

install_filter='
  .hooks //= {}
  | reduce $events[] as $ev (.;
      .hooks[$ev] = (.hooks[$ev] // [])
      | if any(.hooks[$ev][]?.hooks[]?; (.command // "") | contains("claude-hooks.sock"))
        then .hooks[$ev] |= map(.hooks |= map(if (.command // "") | contains("claude-hooks.sock") then .command = $cmd else . end))
        else .hooks[$ev] += [{"matcher": "", "hooks": [{"type": "command", "command": $cmd, "timeout": 5}]}]
        end)
  | .statusLine = ((.statusLine // {"type": "command"}) + {"command": $statusline})'

uninstall_filter='
  (if .hooks then
    .hooks |= (
      with_entries(.value |= (
        map(.hooks |= map(select((.command // "") | contains("claude-hooks.sock") | not)))
        | map(select((.hooks | length) > 0))
      ))
      | with_entries(select((.value | length) > 0))
    )
  else . end)
  | if ((.statusLine.command? // "") | contains($marker))
    then (if $original == "" then del(.statusLine) else .statusLine.command = $original end)
    else . end'

status_filter='[$events[] as $ev | select(any(.hooks[$ev][]?.hooks[]?; .command == $cmd))] | length'
statusline_command_filter='.statusLine.command? // ""'

# The status line is Claude Code's only source of usage limits: hooks never receive them.
wrapper_script='#!/bin/sh
# Installed by Timi. Do not edit: `claude-hooks.sh uninstall` restores your original status line.
# Sends the status line JSON to Timi (usage limits), then runs the original command unchanged.
dir="$HOME/Library/Application Support/Timi"
input=$(cat; printf x); input=${input%x}
printf '"'"'%s'"'"' "$input" | curl -s -m 1 --unix-socket "$dir/claude-hooks.sock" --data-binary @- http://timi/claude-statusline >/dev/null 2>&1 &
original=$(cat "$dir/statusline-original" 2>/dev/null || true)
[ -n "$original" ] || exit 0
printf '"'"'%s'"'"' "$input" | sh -c "$original"
'

check_settings() {
  [[ -s "$settings" ]] || return 0
  "$jq" empty "$settings" 2>/dev/null || die "$settings is not valid JSON, fix it first"
}

apply() {
  local filter="$1"
  mkdir -p "$(dirname "$settings")"
  [[ -s "$settings" ]] || echo '{}' > "$settings"
  check_settings
  cp "$settings" "$backup"
  local tmp="$settings.tmp-timi"
  "$jq" --arg cmd "$cmd" --argjson events "$events" --arg statusline "$statusline" \
    --arg marker "$statusline_marker" --arg original "$original" "$filter" "$settings" > "$tmp"
  # Rewrite in place rather than mv: keeps a symlinked settings.json (dotfiles) and its mode.
  cat "$tmp" > "$settings"
  rm -f "$tmp"
}

current_statusline() {
  [[ -s "$settings" ]] || return 0
  "$jq" -r "$statusline_command_filter" "$settings"
}

case "${1:-}" in
  install)
    check_settings
    current="$(current_statusline)"
    mkdir -p "$support"
    # Keep the user's command, unless the status line is already the Timi wrapper.
    if [[ "$current" != *"$statusline_marker"* ]]; then
      printf '%s' "$current" > "$original_file"
    elif [[ ! -e "$original_file" ]]; then
      : > "$original_file"
    fi
    printf '%s' "$wrapper_script" > "$wrapper"
    chmod 755 "$wrapper"
    apply "$install_filter"
    echo "Timi hooks and status line wrapper installed in $settings (backup: $backup)."
    echo "Restart running Claude Code sessions so they load them."
    ;;
  uninstall)
    [[ -f "$settings" ]] || { echo "No $settings, nothing to remove."; exit 0; }
    [[ -f "$original_file" ]] && original="$(cat "$original_file")"
    apply "$uninstall_filter"
    rm -f "$wrapper" "$original_file"
    echo "Timi hooks and status line wrapper removed from $settings (backup: $backup)."
    ;;
  status)
    count=0
    [[ -f "$settings" ]] && count="$("$jq" --arg cmd "$cmd" --argjson events "$events" "$status_filter" "$settings")"
    total="$("$jq" -n --argjson events "$events" '$events | length')"
    echo "Timi hooks: $count/$total events up to date in $settings"
    ok=0
    [[ "$count" == "$total" ]] || ok=1
    if [[ "$(current_statusline)" == "$statusline" && -x "$wrapper" ]]; then
      saved=""
      [[ -f "$original_file" ]] && saved="$(cat "$original_file")"
      echo "Timi status line: wrapped (original: ${saved:-none})"
    else
      echo "Timi status line: not installed"
      ok=1
    fi
    exit "$ok"
    ;;
  *)
    die "usage: $0 install|uninstall|status"
    ;;
esac
